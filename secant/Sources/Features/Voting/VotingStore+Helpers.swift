import Foundation
import ComposableArchitecture
@preconcurrency import ZcashLightClientKit

// MARK: - Draft & Vote-Record Persistence

extension Voting {
    /// Persisted record of when a round's vote submission fully completed,
    /// the voting weight at that moment, and how many proposals were included.
    /// Survives app termination so the Results screen can render
    /// "Voted Feb 15 - Voting Power X.XXX ZEC" and the polls list can show
    /// the Voted state days after submission, even though the live session
    /// state is per-session.
    ///
    /// At rest, this lives in the per-account encrypted `votingMetadata` file
    /// alongside drafts. In-memory the date stays a `Date` for the UI; the
    /// on-disk form (`PersistedVotingRecord`) stores `votedAt` as a Unix timestamp.
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

    // MARK: - Vote records

    /// Persist a completed-round vote record. Throws so the caller can
    /// surface a failure (toast/alert). On failure the in-memory cache is
    /// rolled back so the next read doesn't lie about what's on disk.
    static func persistVoteRecord(_ record: VoteRecord, roundId: String, account: Account?) throws {
        @Dependency(\.votingMetadata) var votingMetadata
        let previous = votingMetadata.record(roundId)
        votingMetadata.setRecord(record.persisted, roundId)
        if let account {
            do {
                try votingMetadata.store(account)
            } catch {
                if let previous {
                    votingMetadata.setRecord(previous, roundId)
                } else {
                    votingMetadata.clearRecord(roundId)
                }
                throw error
            }
        }
    }

    static func loadVoteRecord(roundId: String) -> VoteRecord? {
        @Dependency(\.votingMetadata) var votingMetadata
        return votingMetadata.record(roundId).map(VoteRecord.init)
    }

    static func clearPersistedVoteRecord(roundId: String, account: Account?) throws {
        @Dependency(\.votingMetadata) var votingMetadata
        let previous = votingMetadata.record(roundId)
        votingMetadata.clearRecord(roundId)
        if let account {
            do {
                try votingMetadata.store(account)
            } catch {
                if let previous {
                    votingMetadata.setRecord(previous, roundId)
                }
                throw error
            }
        }
    }

    /// A round-level vote record is only valid once all drafts are gone.
    /// Older builds wrote it too early, so clear it if there is still
    /// outstanding editable work for the round.
    static func loadCompletedVoteRecord(roundId: String, account: Account?) -> VoteRecord? {
        guard loadDrafts(roundId: roundId).isEmpty else {
            try? clearPersistedVoteRecord(roundId: roundId, account: account)
            return nil
        }
        return loadVoteRecord(roundId: roundId)
    }

    // MARK: - Drafts

    /// Persist draft votes for a round. Optimistically updates the in-memory
    /// cache, then flushes to disk. On persist failure the in-memory cache
    /// is reverted so the UI never displays a draft that didn't actually
    /// survive — and the caller can decide how to surface the failure.
    static func persistDrafts(_ drafts: [UInt32: VoteChoice], roundId: String, account: Account?) throws {
        @Dependency(\.votingMetadata) var votingMetadata
        let previous = votingMetadata.loadDrafts(roundId)
        let encoded = drafts.reduce(into: [String: UInt32]()) { dict, entry in
            dict[String(entry.key)] = entry.value.index
        }
        votingMetadata.setDrafts(encoded, roundId)
        if let account {
            do {
                try votingMetadata.store(account)
            } catch {
                votingMetadata.setDrafts(previous, roundId)
                throw error
            }
        }
    }

    /// Load persisted draft votes for a round.
    static func loadDrafts(roundId: String) -> [UInt32: VoteChoice] {
        @Dependency(\.votingMetadata) var votingMetadata
        return votingMetadata.loadDrafts(roundId).reduce(into: [UInt32: VoteChoice]()) { dict, entry in
            if let proposalId = UInt32(entry.key) {
                dict[proposalId] = .option(entry.value)
            }
        }
    }

    /// Remove all persisted drafts for a round.
    static func clearPersistedDrafts(roundId: String, account: Account?) throws {
        @Dependency(\.votingMetadata) var votingMetadata
        let previous = votingMetadata.loadDrafts(roundId)
        votingMetadata.clearDrafts(roundId)
        if let account {
            do {
                try votingMetadata.store(account)
            } catch {
                votingMetadata.setDrafts(previous, roundId)
                throw error
            }
        }
    }

    // MARK: - Failure surfacing

    /// Logs the failure and surfaces a toast so the user knows their last
    /// action didn't fully take. Use after `try Self.persistDrafts(...)` /
    /// `persistVoteRecord(...)` / `clearPersisted*(...)` in reducer code so
    /// the in-memory rollback (done inside the helper) is paired with a UI
    /// signal.
    static func handlePersistFailure(_ error: Error, state: inout State) {
        LoggerProxy.error("voting metadata persist failed: \(error.localizedDescription)")
        state.$toast.withLock {
            $0 = .top("Your voting changes couldn't be saved. Please try again.")
        }
    }

    // MARK: - Janitorial

    /// One-time sweep of leftover plaintext keys from the previous
    /// `UserDefaults.standard` storage. No real users carry these (the feature
    /// only shipped to internal dev builds before the encrypted file existed),
    /// but the wipe guarantees no internal test device leaves the old shape
    /// behind after upgrade. Safe to keep indefinitely; cheap and idempotent.
    static func sweepLegacyUserDefaultsVotingKeys() {
        let standardDefaults = UserDefaults.standard
        for key in standardDefaults.dictionaryRepresentation().keys
            where key.hasPrefix("voting.voteRecord.") || key.hasPrefix("voting.draftVotes.") {
            standardDefaults.removeObject(forKey: key)
        }
    }
}

// MARK: - Note Bundling

/// Result of value-aware note bundling on the Swift side.
struct BundleResult {
    let bundles: [[NoteInfo]]
    let eligibleWeight: UInt64
    let droppedCount: Int
}

extension Array where Element == NoteInfo {
    /// Value-aware bundling using greedy min-total assignment.
    ///
    /// Mirrors the Rust peer `chunk_notes` (see
    /// `zcash_voting/zcash_voting/src/types.rs` — function `chunk_notes`) for
    /// client-side use. The numbered steps in the body track that function
    /// one-to-one:
    /// 1. Sort notes by value DESC, then position ASC as tiebreaker
    /// 2. Fill bundles sequentially to capacity (5 notes each)
    /// 3. Drop bundles with total < ballotDivisor
    /// 4. Re-sort notes within each surviving bundle by position
    /// 5. Sort surviving bundles by total value DESC (min position as tiebreaker)
    func smartBundles() -> BundleResult {
        guard !isEmpty else {
            return BundleResult(bundles: [], eligibleWeight: 0, droppedCount: 0)
        }

        // Step 1: Sort by value DESC, then position ASC
        let sorted = self.sorted { lhs, rhs in
            if lhs.value != rhs.value { return lhs.value > rhs.value }
            return lhs.position < rhs.position
        }

        // Step 2: Fill bundles sequentially to capacity (5 notes each)
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

        // Step 3: Drop bundles with total < ballotDivisor
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

        // Step 5: Re-sort notes within each surviving bundle by position
        for i in 0..<surviving.count {
            surviving[i].notes.sort { $0.position < $1.position }
        }

        // Step 6: Sort surviving bundles by total value DESC (min position as tiebreaker).
        // This ensures bundle 0 is always the most valuable, enabling users to skip
        // low-value trailing bundles during Keystone signing.
        surviving.sort { lhs, rhs in
            if lhs.total != rhs.total { return lhs.total > rhs.total }
            return (lhs.notes.first?.position ?? .max) < (rhs.notes.first?.position ?? .max)
        }

        return BundleResult(bundles: surviving.map(\.notes), eligibleWeight: eligibleWeight, droppedCount: droppedCount)
    }
}

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

// MARK: - Skip Bundles Alert

extension AlertState where Action == Voting.Action {
    static func confirmSkip(lockedIn: String, givingUp: String) -> AlertState {
        AlertState {
            TextState(String(localizable: .coinVoteDelegationSigningSkipAlertTitle))
        } actions: {
            ButtonState(role: .destructive, action: .skipRemainingKeystoneBundlesConfirmed) {
                TextState(String(localizable: .coinVoteDelegationSigningSkipAlertPrimary))
            }
            ButtonState(role: .cancel, action: .skipBundlesAlert(.dismiss)) {
                TextState(String(localizable: .coinVoteDelegationSigningSkipAlertCancel))
            }
        } message: {
            TextState(String(localizable: .coinVoteDelegationSigningSkipAlertMessage(lockedIn, givingUp)))
        }
    }
}
