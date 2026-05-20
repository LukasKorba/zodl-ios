//
//  VotingCoordFlowStore.swift
//  Zashi
//

import ComposableArchitecture
import Foundation
@preconcurrency import ZcashLightClientKit

@Reducer
struct VotingCoordFlow {
    @Reducer
    enum Path {
        case proposalList(ProposalList)
        case proposalDetail(ProposalDetail)
        case reviewVotes(ReviewVotes)
        case confirmSubmission(ConfirmSubmission)
        case delegationSigning(DelegationSigning)
        case tallying(Tallying)
        case results(Results)
        case ineligible(Ineligible)
        case configSettings(VotingConfigSettings)
    }

    @ObservableState
    struct State {
        /// The root screen shown beneath the NavigationStack. Pushed screens
        /// live in `path`; root replacements happen by mutating this field
        /// (e.g. transitioning from `.loading` to `.pollsList` after rounds
        /// load).
        enum RootScreen: Equatable {
            case loading
            case howToVote
            case noRounds
            case pollsList
            case walletSyncing
            case error(String)
            case configError(String)
        }

        var path = StackState<Path.State>()
        var rootScreen: RootScreen = .loading

        /// Per-round cached session data. Populated on first entry into a
        /// round (witness pipeline, hotkey, weight, etc.) and reused on
        /// re-entry. Evicted on `.dismissFlow`, wallet account switch, or
        /// voting service config change. See `RoundSession`.
        var roundCache: [String: RoundSession] = [:]

        /// Hex-encoded wallet account identifier, used to scope the voting
        /// SQLite DB and the encrypted voting metadata file to this wallet.
        var walletId: String = ""

        /// Whether the currently selected wallet account is a Keystone
        /// hardware wallet. Drives the signing path (Keystone QR flow vs
        /// in-app delegation).
        var isKeystoneUser: Bool = false

        /// Service config loaded from the pinned CDN (or a user override).
        /// Pins voting/PIR endpoints + the bundled round id allow-list.
        var serviceConfig: VotingServiceConfig?

        /// Rounds returned by the voting service, sorted by created_at_height.
        var allRounds: [RoundListItem] = []

        /// Per-round vote summaries persisted in the encrypted voting
        /// metadata file. Hydrated from disk once at `.initialize`; subsequent
        /// reads are O(1). Qualified with `Voting.` to distinguish from the
        /// top-level `VoteRecord` in `VotingModels` (which is the per-proposal
        /// Rust DB record).
        var voteRecords: [String: Voting.VoteRecord] = [:]

        /// True when the most recent rounds fetch failed (network/server).
        /// The polls list overlays a recoverable error sheet; the previously
        /// loaded list (if any) remains visible behind it.
        var pollsLoadError: Bool = false

        /// Round ids endorsed by Zodl (fetched from the bundled service
        /// config). On the default chain, only endorsed rounds are listed
        /// and any non-endorsed entry surfaces an unverified-poll warning.
        var zodlEndorsedRoundIds: Set<String> = []

        /// Whether the user is on the default (Zodl-bundled) voting service
        /// vs a custom override pinned via VotingConfigSettings. Drives the
        /// trust-indicator UI on the polls list cards.
        var isOnDefaultConfig: Bool { votingConfigOverrideURL.isEmpty }

        /// Current wallet scan progress, used by the WalletSyncing root
        /// screen. Updated by the sync-progress polling loop while the user
        /// waits for the wallet to reach a round's snapshot height.
        var walletScannedHeight: UInt64 = 0

        /// The roundId whose pipeline is gated on wallet sync. Restored once
        /// the wallet catches up so we re-trigger the pipeline for the right
        /// round.
        var pendingPipelineRoundId: String?

        // MARK: - Submission flow-wide state (Stage 5)

        /// Signals that batch submission should auto-resume after the
        /// Keystone delegation signing loop finishes. Set when the user
        /// taps Submit on a Keystone account before delegation is ready;
        /// cleared on success, retry, or flow dismiss.
        var pendingBatchSubmission: Bool = false

        /// Round id whose submission alert is currently surfaced. Drives
        /// the alert presentation; nil when no alert.
        var submissionAlertRoundId: String?

        /// Alert state for transient errors during submission setup (e.g.
        /// the not-yet-wired stub placeholder). Real submission errors are
        /// surfaced on the Confirm Submission screen via
        /// `RoundSession.batchSubmissionStatus`.
        @Presents var submissionAlert: AlertState<Never>?

        /// Sheet state for the Keystone QR scan that captures the signed
        /// PCZT from the device. Lifecycle is bound to the delegation
        /// signing screen.
        @Presents var keystoneScan: Scan.State?

        /// Confirmation alert shown when the user taps "Skip remaining
        /// bundles" mid-Keystone-signing-loop. Shows locked-in vs.
        /// giving-up amounts so the decision is informed.
        @Presents var skipBundlesAlert: AlertState<Action>?

        @Shared(.inMemory(.selectedWalletAccount))
        var selectedWalletAccount: WalletAccount?

        @Shared(.appStorage(.hasSeenHowToVote))
        var hasSeenHowToVoteForZashi: Bool = false

        @Shared(.appStorage(.hasSeenHowToVoteKeystone))
        var hasSeenHowToVoteForKeystone: Bool = false

        @Shared(.appStorage(.votingConfigOverrideURL))
        var votingConfigOverrideURL: String = ""

        /// Whether the current wallet account has already seen the
        /// "How to vote" intro. Keystone and Zashi accounts have separate
        /// flags so a user switching wallets sees the intro once per side.
        var hasSeenHowToVoteForCurrentWallet: Bool {
            isKeystoneUser ? hasSeenHowToVoteForKeystone : hasSeenHowToVoteForZashi
        }

        init() {}
    }

    enum Action {
        case path(StackActionOf<Path>)
        case onAppear
        case dismissFlow
        case howToVoteContinueTapped
        case retryLoadRounds
        case openConfigSettings
        case initialize
        case serviceConfigLoaded(VotingServiceConfig)
        case allRoundsLoaded([VotingSession])
        case roundsLoadFailed
        case zodlEndorsementsLoaded(Set<String>)
        case zodlEndorsementsFailed
        case configUnsupported(String)
        case initializeFailed(String)
        case roundTapped(String)
        case ineligibleForRound(roundId: String)
        case refreshActiveRoundsList
        case retryFetchTallyResults(roundId: String)
        case viewMyVotesTapped(roundId: String)
        case proposalTapped(roundId: String, proposalId: UInt32, mode: ProposalDetail.Mode = .voting)
        case startActiveRoundPipeline(roundId: String)
        case walletNotSynced(roundId: String, scannedHeight: UInt64, snapshotHeight: UInt64)
        case walletSyncProgressUpdated(height: UInt64)
        case votingWeightLoaded(roundId: String, weight: UInt64, notes: [NoteInfo])
        case hotkeyLoaded(roundId: String, address: String)
        case pipelineFailed(roundId: String, message: String)
        case draftVoteSet(roundId: String, proposalId: UInt32, choice: VoteChoice)
        case submitTapped(roundId: String)
        case fetchTallyResults(roundId: String)
        case tallyResultsLoaded(roundId: String, results: [UInt32: TallyResult])
        case tallyResultsFailed(roundId: String, message: String)
        case submissionAlert(PresentationAction<Never>)

        // MARK: - Stage 5: submission pipeline

        /// User tapped the Submit button on the Confirm Submission screen.
        /// Routes through local auth (Zashi) or directly into delegation
        /// signing (Keystone). Stage 5A: no-op stub.
        case submitAllDraftsTapped(roundId: String)

        /// User explicitly cleared a draft vote (from the Review screen
        /// edit affordance). Stage 5A: no-op stub; Stage 5B writes through
        /// to the encrypted metadata file.
        case clearDraftVote(roundId: String, proposalId: UInt32)

        /// Biometric / passcode auth gate succeeded; submission can proceed.
        /// For Keystone accounts the auth gate is the device itself, so
        /// `.submitAllDraftsTapped` dispatches this directly.
        case authenticationSucceeded(roundId: String)

        /// Delegation (ZKP #1) pipeline kick-off. Zashi-inline for non-
        /// Keystone users; for Keystone users this starts the per-bundle
        /// PCZT generation that drives the QR signing screen.
        case startDelegationProof(roundId: String)
        case delegationProofProgress(roundId: String, progress: Double)
        case delegationProofCompleted(roundId: String)
        case delegationProofFailed(roundId: String, error: String)

        /// Zashi-only PIR precompute optimization. Runs in the background
        /// while the user is choosing votes so the actual ZKP doesn't
        /// start from cold.
        case maybeStartDelegationPrecompute(roundId: String)
        case delegationPrecomputeCompleted(roundId: String)
        case delegationPrecomputeFailed(roundId: String, error: String)

        // MARK: - Stage 5: per-proposal vote submission loop

        case batchSubmissionProgress(roundId: String, currentIndex: Int, totalCount: Int, proposalId: UInt32)
        case voteSubmissionBundleStarted(roundId: String, bundleIndex: UInt32)
        case voteSubmissionStepUpdated(roundId: String, step: VoteSubmissionStep)
        case batchVoteSubmitted(roundId: String, proposalId: UInt32, choice: VoteChoice)
        case batchVoteFailed(roundId: String, proposalId: UInt32, error: String)
        case batchSubmissionCompleted(roundId: String, successCount: Int, failCount: Int)
        case batchAuthorizationFailed(roundId: String, error: String)
        case batchSubmissionFailed(roundId: String, error: String, submittedCount: Int, totalCount: Int)
        case retryBatchSubmission(roundId: String)
        case dismissBatchResults(roundId: String)

        // MARK: - Stage 5: Keystone delegation signing loop

        case keystoneSigningPrepared(roundId: String, govPczt: VotingPcztResult, unsignedPczt: Pczt)
        case keystoneSigningFailed(roundId: String, error: String)
        case openKeystoneSignatureScan
        case keystoneScan(PresentationAction<Scan.Action>)
        case spendAuthSignatureExtracted(roundId: String, sig: Data, signedPczt: Pczt)
        case keystoneBundleSignatureStored(
            roundId: String,
            signature: KeystoneBundleSignature,
            bundleIndex: UInt32,
            bundleCount: UInt32
        )
        case keystoneAllBundlesSigned(roundId: String)
        case keystoneSignaturesRestored(roundId: String, signatures: [KeystoneBundleSignatureInfo])
        case keystoneShowSigningScreen(roundId: String)
        case skipRemainingKeystoneBundles(roundId: String)
        case skipRemainingKeystoneBundlesConfirmed(roundId: String)
        case skipBundlesAlert(PresentationAction<Action>)
        case delegationRejected(roundId: String)
    }

    @Dependency(\.backgroundTask) var backgroundTask
    @Dependency(\.databaseFiles) var databaseFiles
    @Dependency(\.keystoneHandler) var keystoneHandler
    @Dependency(\.localAuthentication) var localAuthentication
    @Dependency(\.mnemonic) var mnemonic
    @Dependency(\.pasteboard) var pasteboard
    @Dependency(\.sdkSynchronizer) var sdkSynchronizer
    @Dependency(\.votingAPI) var votingAPI
    @Dependency(\.votingCrypto) var votingCrypto
    @Dependency(\.votingMetadata) var votingMetadata
    @Dependency(\.walletStorage) var walletStorage
    @Dependency(\.zcashSDKEnvironment) var zcashSDKEnvironment

    /// Cancellation id for the per-round pipeline (witness verify, hotkey
    /// derivation, voting weight). Phase 4b's `.startActiveRoundPipeline`
    /// effect attaches to this so a new round entry or `.dismissFlow` can
    /// cancel an in-flight pipeline.
    let cancelPipelineId = UUID()

    /// Cancellation id for the batch submission `.run` effect. `.dismissFlow`,
    /// account switch, and config change all cancel this so the submission
    /// loop doesn't outlive the flow.
    let cancelSubmissionId = UUID()

    /// Cancellation id for the delegation proof (ZKP #1) `.run` effect.
    let cancelDelegationProofId = UUID()

    var body: some Reducer<State, Action> {
        coordinatorReduce()
            .forEach(\.path, action: \.path)
            .ifLet(\.$submissionAlert, action: \.submissionAlert)
            .ifLet(\.$keystoneScan, action: \.keystoneScan) {
                Scan()
            }
            .ifLet(\.$skipBundlesAlert, action: \.skipBundlesAlert)
    }
}
