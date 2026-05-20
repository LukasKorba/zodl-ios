//
//  VotingHelpers.swift
//  Zashi
//
//  Stage 5D destination for the static helpers that previously lived on
//  the legacy `Voting` reducer. Keeping the `Voting` namespace lets
//  callers in `VotingCoordFlow` use the same `Voting.persistDrafts(...)`
//  / `Voting.delegateSharesWithFallback(...)` call sites without a
//  rename pass.
//

import Foundation
import ComposableArchitecture
@preconcurrency import ZcashLightClientKit

/// Empty placeholder used as the `senderSeed` parameter when the SDK call
/// path doesn't need it (Keystone signing builds the PCZT externally).
let emptySenderSeed: [UInt8] = []

/// Pull the 32-byte seed fingerprint from a wallet account (Keystone path).
func votingSeedFingerprint(for account: WalletAccount?) -> Data? {
    if let seedFingerprint = account?.seedFingerprint, seedFingerprint.count == 32 {
        return Data(seedFingerprint)
    }
    return nil
}

/// Resolve the ZIP-32 account index for a wallet account; defaults to 0.
func votingAccountIndex(for account: WalletAccount?) -> UInt32 {
    account.flatMap(\.zip32AccountIndex).map { UInt32($0.index) } ?? 0
}

// MARK: - Voting namespace (helpers only — no reducer)

enum Voting {
    // MARK: - Vote record

    /// Persisted record of when a round's vote submission fully completed,
    /// the voting weight at that moment, and how many proposals were included.
    struct VoteRecord: Equatable {
        let votedAt: Date
        let votingWeight: UInt64
        let proposalCount: Int

        init(votedAt: Date, votingWeight: UInt64, proposalCount: Int) {
            self.votedAt = votedAt
            self.votingWeight = votingWeight
            self.proposalCount = proposalCount
        }

        init(_ persisted: PersistedVotingRecord) {
            self.votedAt = Date(timeIntervalSince1970: persisted.votedAt)
            self.votingWeight = persisted.votingWeight
            self.proposalCount = persisted.proposalCount
        }

        var persisted: PersistedVotingRecord {
            PersistedVotingRecord(
                votedAt: votedAt.timeIntervalSince1970,
                votingWeight: votingWeight,
                proposalCount: proposalCount
            )
        }
    }

    // MARK: - Vote-record persistence

    static func persistVoteRecord(_ record: VoteRecord, roundId: String, account: Account?) {
        @Dependency(\.votingMetadata) var votingMetadata
        votingMetadata.setRecord(record.persisted, roundId)
        if let account {
            try? votingMetadata.store(account)
        }
    }

    static func loadVoteRecord(roundId: String) -> VoteRecord? {
        @Dependency(\.votingMetadata) var votingMetadata
        return votingMetadata.record(roundId).map(VoteRecord.init)
    }

    static func clearPersistedVoteRecord(roundId: String, account: Account?) {
        @Dependency(\.votingMetadata) var votingMetadata
        votingMetadata.clearRecord(roundId)
        if let account {
            try? votingMetadata.store(account)
        }
    }

    /// A round-level vote record is only valid once all drafts are gone.
    /// Older builds wrote it too early, so clear it if there is still
    /// outstanding editable work for the round.
    static func loadCompletedVoteRecord(roundId: String, account: Account?) -> VoteRecord? {
        guard loadDrafts(roundId: roundId).isEmpty else {
            clearPersistedVoteRecord(roundId: roundId, account: account)
            return nil
        }
        return loadVoteRecord(roundId: roundId)
    }

    // MARK: - Draft persistence

    static func persistDrafts(_ drafts: [UInt32: VoteChoice], roundId: String, account: Account?) {
        @Dependency(\.votingMetadata) var votingMetadata
        let encoded = drafts.reduce(into: [String: UInt32]()) { dict, entry in
            dict[String(entry.key)] = entry.value.index
        }
        votingMetadata.setDrafts(encoded, roundId)
        if let account {
            try? votingMetadata.store(account)
        }
    }

    static func loadDrafts(roundId: String) -> [UInt32: VoteChoice] {
        @Dependency(\.votingMetadata) var votingMetadata
        return votingMetadata.loadDrafts(roundId).reduce(into: [UInt32: VoteChoice]()) { dict, entry in
            if let proposalId = UInt32(entry.key) {
                dict[proposalId] = .option(entry.value)
            }
        }
    }

    static func clearPersistedDrafts(roundId: String, account: Account?) {
        @Dependency(\.votingMetadata) var votingMetadata
        votingMetadata.clearDrafts(roundId)
        if let account {
            try? votingMetadata.store(account)
        }
    }

    /// One-time sweep of leftover plaintext keys from the previous
    /// UserDefaults storage. Cheap and idempotent — safe to keep on every
    /// boot.
    static func sweepLegacyUserDefaultsVotingKeys() {
        let standardDefaults = UserDefaults.standard
        for key in standardDefaults.dictionaryRepresentation().keys
            where key.hasPrefix("voting.voteRecord.") || key.hasPrefix("voting.draftVotes.") {
            standardDefaults.removeObject(forKey: key)
        }
    }

    // MARK: - Submission helpers

    /// Returns true when the choice is the UI-only synthesized "Abstain"
    /// option (created when a proposal lacks a native abstain), which
    /// has no on-chain submission and should be counted as done.
    static func isSyntheticAbstain(choice: VoteChoice, proposal: VotingProposal?) -> Bool {
        guard let proposal else { return false }
        if proposal.options.contains(where: { $0.index == choice.index }) {
            return false
        }
        guard !proposal.options.contains(where: { $0.label.localizedCaseInsensitiveContains("abstain") }) else {
            return false
        }
        let synthesizedAbstainIndex = (proposal.options.map(\.index).max() ?? 0) + 1
        return choice.index == synthesizedAbstainIndex
    }

    /// Delegate shares to the helper servers with retry on whole-set
    /// exhaustion. Errors other than `noReachableVoteServers` are rethrown
    /// immediately so the per-proposal catch can decide whether to abort
    /// the whole batch.
    @discardableResult
    static func delegateSharesWithFallback(
        _ payloads: [SharePayload],
        roundId: String,
        votingAPI: VotingAPIClient,
        serverURLs: [String],
        retryDelay: Duration = .seconds(2)
    ) async throws -> ShareDelegationResult {
        guard !serverURLs.isEmpty else {
            throw ShareDelegationError.noReachableVoteServers
        }

        var lastExhaustionError: ShareDelegationError?
        for attempt in 1...3 {
            do {
                return try await votingAPI.delegateShares(payloads, roundId, serverURLs)
            } catch let error as ShareDelegationError where error == .noReachableVoteServers {
                lastExhaustionError = error
                LoggerProxy.warn("delegateShares attempt \(attempt)/3 exhausted vote servers")
                if attempt < 3 {
                    try await Task.sleep(for: retryDelay)
                }
            } catch {
                LoggerProxy.warn("delegateShares failed with non-exhaustion error: \(error)")
                throw error
            }
        }

        throw lastExhaustionError ?? ShareDelegationError.noReachableVoteServers
    }
}

// MARK: - Pipeline errors (used by VotingCoordFlow)

enum VotingFlowError: LocalizedError {
    case missingActiveSession
    case missingSigningAccount
    case missingHotkeyAddress
    case missingPendingUnsignedPczt
    case invalidDelegationSignature
    case missingVoteCommitmentBundle
    case delegationTxFailed(code: UInt32, log: String)
    case voteCommitmentTxFailed(code: UInt32, log: String)

    var errorDescription: String? {
        switch self {
        case .missingActiveSession:
            return String(localizable: .coinVoteStoreErrorMissingActiveSession)
        case .missingSigningAccount:
            return String(localizable: .coinVoteStoreErrorMissingSigningAccount)
        case .missingHotkeyAddress:
            return String(localizable: .coinVoteStoreErrorMissingHotkeyAddress)
        case .missingPendingUnsignedPczt:
            return String(localizable: .coinVoteStoreErrorMissingPendingUnsignedPczt)
        case .invalidDelegationSignature:
            return String(localizable: .coinVoteStoreErrorInvalidDelegationSignature)
        case .missingVoteCommitmentBundle:
            return String(localizable: .coinVoteStoreErrorMissingVoteCommitmentBundle)
        case .delegationTxFailed(let code, let log):
            let suffix = log.isEmpty ? "" : ": \(log)"
            return String(localizable: .coinVoteStoreErrorDelegationTxFailed(String(code), suffix))
        case .voteCommitmentTxFailed(let code, let log):
            let suffix = log.isEmpty ? "" : ": \(log)"
            return String(localizable: .coinVoteStoreErrorVoteCommitmentTxFailed(String(code), suffix))
        }
    }
}

/// Maps raw error strings from the voting / SDK layer onto user-friendly
/// messages.
enum VotingErrorMapper {
    static func userFriendlyMessage(from error: Error) -> String {
        if let shareError = error as? ShareDelegationError {
            switch shareError {
            case .noReachableVoteServers:
                return String(localizable: .coinVoteStoreUserErrorNoReachableVoteServers)
            }
        }
        return userFriendlyMessage(from: error.localizedDescription)
    }

    // swiftlint:disable:next cyclomatic_complexity
    static func userFriendlyMessage(from rawError: String) -> String {
        if rawError.contains("nullifier already spent") {
            return String(localizable: .coinVoteStoreUserErrorNullifierAlreadySpent)
        }
        if rawError.contains("vote round is not active") {
            return String(localizable: .coinVoteStoreUserErrorRoundNotActive)
        }
        if rawError.contains("vote round not found") {
            return String(localizable: .coinVoteStoreUserErrorRoundNotFound)
        }
        if rawError.contains("No active voting round") {
            return String(localizable: .coinVoteStoreUserErrorRoundNotActive)
        }
        if rawError.contains("PIR proof root mismatch") {
            return String(localizable: .coinVoteStoreUserErrorPirSnapshotMismatch)
        }
        if rawError.contains("PIR proof verification failed") {
            return String(localizable: .coinVoteStoreUserErrorPirInvalidProofData)
        }
        if rawError.contains("PIR server connect failed") || rawError.contains("PIR parallel fetch failed") {
            return String(localizable: .coinVoteStoreUserErrorPirUnavailable)
        }
        if rawError.contains("No PIR server matches") {
            return String(localizable: .coinVoteStoreUserErrorPirSnapshotMismatch)
        }
        if rawError.contains("No PIR endpoints are configured") {
            return String(localizable: .coinVoteStoreUserErrorPirEndpointsMissing)
        }
        if rawError.contains("Commitment tree did not grow") {
            return String(localizable: .coinVoteStoreUserErrorCommitmentTreeNotGrown)
        }
        if rawError.contains("invalid commitment tree anchor height") {
            return String(localizable: .coinVoteStoreUserErrorInvalidAnchorHeight)
        }
        if rawError.contains("invalid zero-knowledge proof") {
            return String(localizable: .coinVoteStoreUserErrorInvalidProof)
        }
        if rawError.contains("delegation bundle build failed") || rawError.contains("create_proof failed") {
            return String(localizable: .coinVoteStoreUserErrorProofGenerationFailed)
        }
        if rawError.contains("NoTreeState") || rawError.contains("no tree state") {
            return String(localizable: .coinVoteStoreUserErrorNoTreeState)
        }
        if rawError.contains("HTTP 5") {
            return String(localizable: .coinVoteStoreUserErrorHttp5)
        }
        if rawError.contains("GRPCStatus") || rawError.contains("RPC timed out") || rawError.contains("Transport became inactive") {
            return String(localizable: .coinVoteStoreUserErrorLightwalletdUnavailable)
        }
        return rawError
    }
}

// MARK: - Note bundling (Swift mirror of zcash_voting::chunk_notes)

struct BundleResult {
    let bundles: [[NoteInfo]]
    let eligibleWeight: UInt64
    let droppedCount: Int
}

extension Array where Element == NoteInfo {
    /// See the legacy comment on the original definition for rationale; this
    /// is a 1:1 move out of `VotingStore+Helpers.swift`.
    func smartBundles() -> BundleResult {
        guard !isEmpty else {
            return BundleResult(bundles: [], eligibleWeight: 0, droppedCount: 0)
        }

        let sorted = self.sorted { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value > rhs.value }
            return lhs.position < rhs.position
        }

        var bundleNotes: [[NoteInfo]] = []
        var bundleTotals: [UInt64] = []

        for note in sorted {
            if bundleNotes.isEmpty || (bundleNotes.last?.count ?? 0) >= 5 {
                bundleNotes.append([])
                bundleTotals.append(0)
            }
            let last = bundleNotes.count - 1
            bundleTotals[last] += note.value
            bundleNotes[last].append(note)
        }

        let numBundles = bundleNotes.count
        var surviving: [(total: UInt64, notes: [NoteInfo])] = []
        var eligibleWeight: UInt64 = 0
        var survivingNoteCount = 0

        for i in 0..<numBundles where bundleTotals[i] >= ballotDivisor {
            surviving.append((bundleTotals[i], bundleNotes[i]))
            eligibleWeight += quantizeWeight(bundleTotals[i])
            survivingNoteCount += bundleNotes[i].count
        }
        let droppedCount = count - survivingNoteCount

        for i in 0..<surviving.count {
            surviving[i].notes.sort { $0.position < $1.position }
        }

        surviving.sort { lhs, rhs in
            if lhs.total != rhs.total { return lhs.total > rhs.total }
            return (lhs.notes.first?.position ?? .max) < (rhs.notes.first?.position ?? .max)
        }

        return BundleResult(bundles: surviving.map(\.notes), eligibleWeight: eligibleWeight, droppedCount: droppedCount)
    }
}

// MARK: - libzcashlc `network_id` (mirror of `parse_network` in the SDK Rust)

extension NetworkType {
    /// `network_id` for voting FFI: `0` = testnet, `1` = mainnet.
    var votingRustNetworkId: UInt32 {
        switch self {
        case .mainnet: 1
        case .testnet: 0
        }
    }
}

// MARK: - Hex helpers

/// Convert hex string to Data (used for share confirmation polling and API parsing).
func votingDataFromHex(_ hex: String) -> Data {
    var data = Data()
    var idx = hex.startIndex
    while idx < hex.endIndex {
        let next = hex.index(idx, offsetBy: 2, limitedBy: hex.endIndex) ?? hex.endIndex
        if let byte = UInt8(hex[idx..<next], radix: 16) {
            data.append(byte)
        }
        idx = next
    }
    return data
}
