import ComposableArchitecture
import Foundation
import XCTest
@testable import zashi_internal

final class VotingCoordFlowCoordinatorTests: XCTestCase {
    func testBatchVoteSubmittedMovesDraftIntoSubmittedVotes() {
        let metadata = VotingMetadataBox()
        var state = VotingCoordFlow.State()
        state.roundCache[roundId] = roundSession(
            drafts: [
                1: .option(0),
                2: .option(1)
            ]
        )

        withDependencies {
            $0.votingMetadata = votingMetadataClient(metadata)
        } operation: {
            _ = VotingCoordFlow().reduceBatchVoteSubmitted(
                &state,
                roundId: roundId,
                proposalId: 1,
                choice: .option(0)
            )
        }

        let session = tryUnwrap(state.roundCache[roundId])
        XCTAssertEqual(session.draftVotes, [2: .option(1)])
        XCTAssertEqual(session.votes, [1: .option(0)])
        XCTAssertEqual(metadata.drafts[roundId], ["2": 1])
        XCTAssertEqual(metadata.submittedVotes[roundId], ["1": 0])
    }

    func testBatchSubmissionCompletedAcceptsPartialBallotWhenDraftsAreDrained() {
        let metadata = VotingMetadataBox()
        var state = VotingCoordFlow.State()
        state.roundCache[roundId] = roundSession(
            votingWeight: 50_000_000,
            votes: [
                1: .option(0),
                3: .option(1)
            ]
        )

        withDependencies {
            $0.votingMetadata = votingMetadataClient(metadata)
        } operation: {
            _ = VotingCoordFlow().reduceBatchSubmissionCompleted(
                &state,
                roundId: roundId,
                successCount: 2,
                failCount: 0
            )
        }

        let session = tryUnwrap(state.roundCache[roundId])
        XCTAssertEqual(session.batchSubmissionStatus, .completed(successCount: 2))
        XCTAssertEqual(session.voteRecord?.votingWeight, 50_000_000)
        XCTAssertEqual(session.voteRecord?.proposalCount, 2)
        XCTAssertEqual(state.voteRecords[roundId]?.proposalCount, 2)
        XCTAssertEqual(metadata.records[roundId]?.proposalCount, 2)
    }

    func testBatchSubmissionCompletedFailsWhenDraftsRemain() {
        var state = VotingCoordFlow.State()
        state.roundCache[roundId] = roundSession(
            drafts: [2: .option(1)],
            votes: [1: .option(0)]
        )

        _ = VotingCoordFlow().reduceBatchSubmissionCompleted(
            &state,
            roundId: roundId,
            successCount: 1,
            failCount: 0
        )

        let session = tryUnwrap(state.roundCache[roundId])
        XCTAssertEqual(
            session.batchSubmissionStatus,
            .submissionFailed(
                error: String(localizable: .coinVoteSubmissionGenericBatchFailure),
                submittedCount: 1,
                totalCount: 2
            )
        )
        XCTAssertNil(session.voteRecord)
    }

    func testBatchSubmissionCompletedFailsWhenVoteErrorsExist() {
        var session = roundSession(votes: [1: .option(0)])
        session.batchVoteErrors = [2: "server unavailable"]
        var state = VotingCoordFlow.State()
        state.roundCache[roundId] = session

        _ = VotingCoordFlow().reduceBatchSubmissionCompleted(
            &state,
            roundId: roundId,
            successCount: 1,
            failCount: 0
        )

        let updated = tryUnwrap(state.roundCache[roundId])
        XCTAssertEqual(
            updated.batchSubmissionStatus,
            .submissionFailed(
                error: "server unavailable",
                submittedCount: 1,
                totalCount: 1
            )
        )
        XCTAssertNil(updated.voteRecord)
    }

    func testBatchSubmissionProgressClearsPreviousSubmissionStep() {
        var session = roundSession()
        session.voteSubmissionStep = .sendingShares
        session.currentVoteBundleIndex = 0
        var state = VotingCoordFlow.State()
        state.roundCache[roundId] = session

        _ = VotingCoordFlow().reduceBatchSubmissionProgress(
            &state,
            roundId: roundId,
            currentIndex: 0,
            totalCount: 1,
            proposalId: 1
        )

        let updated = tryUnwrap(state.roundCache[roundId])
        XCTAssertEqual(updated.batchSubmissionStatus, .submitting(currentIndex: 0, totalCount: 1, currentProposalId: 1))
        XCTAssertEqual(updated.submittingProposalId, 1)
        XCTAssertTrue(updated.isSubmittingVote)
        XCTAssertNil(updated.voteSubmissionStep)
        XCTAssertNil(updated.currentVoteBundleIndex)
    }

    func testAuthenticationSucceededStartsSoftwareDelegationAtSubmitTime() {
        var session = RoundSession(roundId: activeRoundId)
        session.bundleCount = 1
        session.draftVotes = [1: .option(0)]
        var state = VotingCoordFlow.State()
        state.roundCache[activeRoundId] = session
        state.allRounds = [RoundListItem(roundNumber: 1, session: votingSession())]

        _ = VotingCoordFlow().reduceAuthenticationSucceeded(&state, roundId: activeRoundId)

        let updated = tryUnwrap(state.roundCache[activeRoundId])
        XCTAssertFalse(state.pendingBatchSubmission)
        XCTAssertEqual(updated.batchSubmissionStatus, .authorizing)
        XCTAssertEqual(updated.voteSubmissionStep, .authorizingVote)
        XCTAssertEqual(updated.delegationProofStatus, .generating(progress: 0))
    }

    func testDelegationFailureDuringBatchAuthorizationShowsAuthorizationFailure() {
        var session = roundSession()
        session.bundleCount = 2
        session.currentKeystoneBundleIndex = 1
        session.keystoneBundleSignatures = [signature(byte: 1)]
        session.keystoneSigningStatus = .awaitingSignature
        session.delegationProofStatus = .generating(progress: 0.5)
        session.isDelegationProofInFlight = true
        session.batchSubmissionStatus = .authorizing
        session.voteSubmissionStep = .authorizingVote
        session.currentVoteBundleIndex = 0
        var state = VotingCoordFlow.State()
        state.isKeystoneUser = true
        state.pendingBatchSubmission = true
        state.path.append(.delegationSigning(DelegationSigning.State(roundId: roundId)))
        state.roundCache[roundId] = session

        _ = VotingCoordFlow().reduceDelegationProofFailed(
            &state,
            roundId: roundId,
            error: "nullifier already spent"
        )

        let updated = tryUnwrap(state.roundCache[roundId])
        XCTAssertEqual(updated.delegationProofStatus, .failed("nullifier already spent"))
        XCTAssertFalse(updated.isDelegationProofInFlight)
        XCTAssertFalse(state.pendingBatchSubmission)
        XCTAssertEqual(updated.batchSubmissionStatus, .authorizationFailed(error: "nullifier already spent"))
        XCTAssertNil(updated.voteSubmissionStep)
        XCTAssertNil(updated.currentVoteBundleIndex)
        XCTAssertEqual(updated.currentKeystoneBundleIndex, 0)
        XCTAssertTrue(updated.keystoneBundleSignatures.isEmpty)
        XCTAssertEqual(updated.keystoneSigningStatus, .failed("nullifier already spent"))
    }

    func testIntermediateKeystoneSignatureAdvancesToNextBundle() {
        var session = roundSession()
        session.bundleCount = 2
        session.currentKeystoneBundleIndex = 0
        session.keystoneSigningStatus = .awaitingSignature
        var state = VotingCoordFlow.State()
        state.roundCache[roundId] = session

        _ = VotingCoordFlow().reduceKeystoneBundleSignatureStored(
            &state,
            roundId: roundId,
            signature: signature(byte: 1),
            bundleIndex: 0,
            bundleCount: 2
        )

        let updated = tryUnwrap(state.roundCache[roundId])
        XCTAssertEqual(updated.currentKeystoneBundleIndex, 1)
        XCTAssertEqual(updated.keystoneBundleSignatures, [signature(byte: 1)])
        XCTAssertEqual(updated.keystoneSigningStatus, .idle)
        XCTAssertFalse(updated.isDelegationProofInFlight)
        XCTAssertNil(updated.pendingVotingPczt)
        XCTAssertNil(updated.pendingUnsignedDelegationPczt)
    }

    func testFinalKeystoneSignatureMovesToFinalizingAuthorization() {
        var session = roundSession()
        session.bundleCount = 2
        session.currentKeystoneBundleIndex = 1
        session.keystoneSigningStatus = .awaitingSignature
        var state = VotingCoordFlow.State()
        state.path.append(.delegationSigning(DelegationSigning.State(roundId: roundId)))
        state.roundCache[roundId] = session

        _ = VotingCoordFlow().reduceKeystoneBundleSignatureStored(
            &state,
            roundId: roundId,
            signature: signature(byte: 2),
            bundleIndex: 1,
            bundleCount: 2
        )

        let updated = tryUnwrap(state.roundCache[roundId])
        XCTAssertEqual(updated.keystoneBundleSignatures, [signature(byte: 2)])
        XCTAssertEqual(updated.keystoneSigningStatus, .finalizingAuthorization)
        XCTAssertEqual(updated.delegationProofStatus, .generating(progress: 0))
        XCTAssertTrue(updated.isDelegationProofInFlight)
        XCTAssertEqual(updated.batchSubmissionStatus, .authorizing)
        XCTAssertEqual(updated.voteSubmissionStep, .authorizingVote)
        XCTAssertFalse(isDelegationSigningTop(state))
    }

    func testSkippingRemainingKeystoneBundlesKeepsOnlySignedWeight() {
        var session = roundSession(
            votingWeight: 100_000_000,
            notes: [
                note(value: 31_568_000, position: 0),
                note(value: 26_000_000, position: 1),
                note(value: 13_000_000, position: 2),
                note(value: 12_500_000, position: 3),
                note(value: 5_000_000, position: 4),
                note(value: 4_000_000, position: 5),
                note(value: 3_000_000, position: 6),
                note(value: 3_000_000, position: 7),
                note(value: 2_000_000, position: 8),
                note(value: 1_000_000, position: 9)
            ]
        )
        session.bundleCount = 2
        session.keystoneBundleSignatures = [signature(byte: 1)]
        var state = VotingCoordFlow.State()
        state.path.append(.delegationSigning(DelegationSigning.State(roundId: roundId)))
        state.roundCache[roundId] = session

        _ = VotingCoordFlow().reduceSkipRemainingKeystoneBundles(&state, roundId: roundId)

        let updated = tryUnwrap(state.roundCache[roundId])
        XCTAssertEqual(updated.bundleCount, 1)
        XCTAssertEqual(updated.votingWeight, 87_500_000)
        XCTAssertEqual(updated.eligibleBundleCount, 2)
        XCTAssertEqual(updated.eligibleVotingWeight, 100_000_000)
        XCTAssertEqual(updated.keystoneSigningStatus, .finalizingAuthorization)
        XCTAssertEqual(updated.batchSubmissionStatus, .authorizing)
        XCTAssertEqual(updated.voteSubmissionStep, .authorizingVote)
        XCTAssertFalse(isDelegationSigningTop(state))
    }

    func testDelegationRejectedResetsKeystoneLoopButPreservesVotes() {
        var session = roundSession(
            drafts: [2: .option(1)],
            votes: [1: .option(0)]
        )
        session.bundleCount = 2
        session.currentKeystoneBundleIndex = 1
        session.keystoneBundleSignatures = [signature(byte: 1)]
        session.keystoneSigningStatus = .awaitingSignature
        session.batchSubmissionStatus = .authorizing
        var state = VotingCoordFlow.State()
        state.pendingBatchSubmission = true
        state.path.append(.delegationSigning(DelegationSigning.State(roundId: roundId)))
        state.roundCache[roundId] = session

        _ = VotingCoordFlow().coordinatorReduce().reduce(
            into: &state,
            action: .delegationRejected(roundId: roundId)
        )

        let updated = tryUnwrap(state.roundCache[roundId])
        XCTAssertEqual(updated.currentKeystoneBundleIndex, 0)
        XCTAssertTrue(updated.keystoneBundleSignatures.isEmpty)
        XCTAssertEqual(updated.keystoneSigningStatus, .idle)
        XCTAssertEqual(updated.batchSubmissionStatus, .idle)
        XCTAssertEqual(updated.draftVotes, [2: .option(1)])
        XCTAssertEqual(updated.votes, [1: .option(0)])
        XCTAssertFalse(state.pendingBatchSubmission)
        XCTAssertFalse(isDelegationSigningTop(state))
    }

    func testDelegationPipelineRecoversConfirmedCachedTxBeforeSkippingBundle() async throws {
        let recorder = RecoveryOrderRecorder()
        var votingCrypto = VotingCryptoClient()
        votingCrypto.getDelegationTxHash = { _, _ in .present("cached-tx") }
        votingCrypto.storeVanPosition = { _, bundleIndex, position in
            await recorder.record("van:\(bundleIndex):\(position)")
        }

        var votingAPI = VotingAPIClient()
        votingAPI.fetchTxConfirmation = { txHash in
            await recorder.record("fetch:\(txHash)")
            return Self.makeDelegationConfirmation(position: 42)
        }
        votingAPI.submitDelegation = { _ in
            await recorder.record("submit")
            return TxResult(txHash: "new-tx", code: 0)
        }

        try await VotingCoordFlow.runDelegationPipeline(
            roundId: "aabb",
            cachedNotes: [note(value: ballotDivisor, position: 0)],
            senderSeed: [],
            hotkeySeed: [],
            networkId: 1,
            accountIndex: 0,
            roundName: "Round",
            pirEndpoints: ["https://pir.example.com"],
            expectedSnapshotHeight: 1,
            votingCrypto: votingCrypto,
            votingAPI: votingAPI,
            send: Send<VotingCoordFlow.Action>(send: { _ in }),
            delegationConfirmationTimeout: 0,
            delegationConfirmationRetryDelay: .zero
        )

        let events = await recorder.events()
        XCTAssertEqual(events, ["fetch:cached-tx", "van:0:42"])
    }

    func testDelegationPipelineDoesNotSkipCachedTxWithoutConfirmedVanPosition() async throws {
        let recorder = RecoveryOrderRecorder()
        var votingCrypto = VotingCryptoClient()
        votingCrypto.getDelegationTxHash = { _, _ in .present("cached-tx") }
        votingCrypto.buildVotingPczt = { _, _, _, _, _, _, _, _, _, _ in
            Self.makeVotingPcztResult()
        }
        votingCrypto.getDelegationSubmission = { _, _, _, _, _ in
            await recorder.record("registration")
            return Self.makeDelegationRegistration()
        }
        votingCrypto.storeDelegationTxHash = { _, _, txHash in
            await recorder.record("store-tx:\(txHash)")
        }
        votingCrypto.storeVanPosition = { _, bundleIndex, position in
            await recorder.record("van:\(bundleIndex):\(position)")
        }

        var votingAPI = VotingAPIClient()
        votingAPI.fetchTxConfirmation = { txHash in
            await recorder.record("fetch:\(txHash)")
            if txHash == "cached-tx" {
                return nil
            }
            return Self.makeDelegationConfirmation(position: 9)
        }
        votingAPI.submitDelegation = { _ in
            await recorder.record("submit")
            return TxResult(txHash: "new-tx", code: 0)
        }

        try await VotingCoordFlow.runDelegationPipeline(
            roundId: "aabb",
            cachedNotes: [note(value: ballotDivisor, position: 0)],
            senderSeed: [],
            hotkeySeed: [],
            networkId: 1,
            accountIndex: 0,
            roundName: "Round",
            pirEndpoints: ["https://pir.example.com"],
            expectedSnapshotHeight: 1,
            votingCrypto: votingCrypto,
            votingAPI: votingAPI,
            send: Send<VotingCoordFlow.Action>(send: { _ in }),
            delegationConfirmationTimeout: 0,
            delegationConfirmationRetryDelay: .zero
        )

        let events = await recorder.events()
        XCTAssertEqual(events, [
            "fetch:cached-tx",
            "registration",
            "submit",
            "store-tx:new-tx",
            "fetch:new-tx",
            "van:0:9"
        ])
    }

    private let roundId = "round-1"
    private let activeRoundId = String(repeating: "aa", count: 32)

    private func roundSession(
        votingWeight: UInt64 = 0,
        drafts: [UInt32: VoteChoice] = [:],
        votes: [UInt32: VoteChoice] = [:],
        notes: [NoteInfo] = []
    ) -> RoundSession {
        var session = RoundSession(roundId: roundId)
        session.votingWeight = votingWeight
        session.draftVotes = drafts
        session.votes = votes
        session.walletNotes = notes
        return session
    }

    private func votingSession() -> VotingSession {
        VotingSession(
            voteRoundId: Data(repeating: 0xAA, count: 32),
            snapshotHeight: 123,
            snapshotBlockhash: Data(repeating: 0x01, count: 32),
            proposalsHash: Data(repeating: 0x02, count: 32),
            voteEndTime: .now.addingTimeInterval(60),
            ceremonyStart: .now.addingTimeInterval(-60),
            eaPK: Data(repeating: 0x03, count: 32),
            vkZkp1: Data(repeating: 0x04, count: 32),
            vkZkp2: Data(repeating: 0x05, count: 32),
            vkZkp3: Data(repeating: 0x06, count: 32),
            ncRoot: Data(repeating: 0x07, count: 32),
            nullifierIMTRoot: Data(repeating: 0x08, count: 32),
            creator: "creator",
            description: "Round description",
            proposals: [
                VotingProposal(
                    id: 1,
                    title: "Proposal 1",
                    description: "Description 1",
                    options: [
                        VoteOption(index: 0, label: "Support"),
                        VoteOption(index: 1, label: "Oppose")
                    ]
                )
            ],
            status: .active,
            createdAtHeight: 123,
            title: "Round"
        )
    }

    private func signature(byte: UInt8) -> KeystoneBundleSignature {
        KeystoneBundleSignature(
            sig: Data(repeating: byte, count: 64),
            sighash: Data(repeating: byte + 1, count: 32),
            rk: Data(repeating: byte + 2, count: 32)
        )
    }

    private func note(value: UInt64, position: UInt64) -> NoteInfo {
        let byte = UInt8(position % UInt64(UInt8.max))
        return NoteInfo(
            commitment: Data(repeating: byte, count: 32),
            nullifier: Data(repeating: byte, count: 32),
            value: value,
            position: position,
            diversifier: Data(repeating: byte, count: 11),
            rho: Data(repeating: byte, count: 32),
            rseed: Data(repeating: byte, count: 32),
            scope: 0,
            ufvkStr: "ufvk-\(position)"
        )
    }

    private static func makeVotingPcztResult() -> VotingPcztResult {
        VotingPcztResult(
            pcztBytes: Data([0x01]),
            rk: Data(repeating: 0x01, count: 32),
            alpha: Data(repeating: 0x02, count: 32),
            nfSigned: Data(repeating: 0x03, count: 32),
            cmxNew: Data(repeating: 0x04, count: 32),
            govNullifiers: [Data(repeating: 0x05, count: 32)],
            van: Data(repeating: 0x06, count: 32),
            vanCommRand: Data(repeating: 0x07, count: 32),
            dummyNullifiers: [],
            rhoSigned: Data(repeating: 0x08, count: 32),
            paddedCmx: [],
            rseedSigned: Data(repeating: 0x09, count: 32),
            rseedOutput: Data(repeating: 0x0A, count: 32),
            actionBytes: Data([0x0B]),
            actionIndex: 0
        )
    }

    private static func makeDelegationRegistration() -> DelegationRegistration {
        DelegationRegistration(
            rk: Data(repeating: 0x01, count: 32),
            spendAuthSig: Data(repeating: 0x02, count: 64),
            signedNoteNullifier: Data(repeating: 0x03, count: 32),
            cmxNew: Data(repeating: 0x04, count: 32),
            vanCmx: Data(repeating: 0x05, count: 32),
            govNullifiers: [Data(repeating: 0x06, count: 32)],
            proof: Data(repeating: 0x07, count: 32),
            voteRoundId: Data([0xAA, 0xBB]),
            sighash: Data(repeating: 0x08, count: 32)
        )
    }

    private static func makeDelegationConfirmation(position: UInt32) -> TxConfirmation {
        TxConfirmation(
            height: 1,
            code: 0,
            events: [
                TxEvent(
                    type: "delegate_vote",
                    attributes: [.init(key: "leaf_index", value: "\(position)")]
                )
            ]
        )
    }

    private func isDelegationSigningTop(_ state: VotingCoordFlow.State) -> Bool {
        guard case .delegationSigning = state.path.last else {
            return false
        }
        return true
    }

    private func tryUnwrap<T>(
        _ value: T?,
        file: StaticString = #filePath,
        line: UInt = #line
    ) -> T {
        do {
            return try XCTUnwrap(value, file: file, line: line)
        } catch {
            fatalError("XCTUnwrap failed")
        }
    }

    private func votingMetadataClient(
        _ box: VotingMetadataBox
    ) -> VotingMetadataProviderClient {
        var client = VotingMetadataProviderClient()
        client.load = { _ in }
        client.store = { _ in }
        client.resetAccount = { _ in }
        client.reset = {}
        client.loadDrafts = { box.drafts[$0] ?? [:] }
        client.setDrafts = { drafts, roundId in box.drafts[roundId] = drafts }
        client.clearDrafts = { roundId in box.drafts[roundId] = [:] }
        client.loadSubmittedVotes = { box.submittedVotes[$0] ?? [:] }
        client.setSubmittedVotes = { votes, roundId in
            box.submittedVotes[roundId] = votes
        }
        client.clearSubmittedVotes = { roundId in box.submittedVotes[roundId] = [:] }
        client.record = { box.records[$0] }
        client.allRecords = { box.records }
        client.setRecord = { record, roundId in box.records[roundId] = record }
        client.clearRecord = { roundId in box.records.removeValue(forKey: roundId) }
        return client
    }
}

private final class VotingMetadataBox: @unchecked Sendable {
    var drafts: [String: [String: UInt32]] = [:]
    var submittedVotes: [String: [String: UInt32]] = [:]
    var records: [String: PersistedVotingRecord] = [:]
}

private actor RecoveryOrderRecorder {
    private var recordedEvents: [String] = []

    func record(_ event: String) {
        recordedEvents.append(event)
    }

    func events() -> [String] {
        recordedEvents
    }
}
