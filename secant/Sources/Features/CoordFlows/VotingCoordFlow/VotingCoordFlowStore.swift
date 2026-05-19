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

        /// Alert surfaced when the user taps Submit but the new flow's
        /// submission pipeline is not yet wired (Phase 5). Production users
        /// should use the legacy Coinholder Polling entry until Phase 5
        /// ships; this alert exists so the DEBUG entry doesn't silently
        /// swallow the Submit tap.
        @Presents var submissionAlert: AlertState<Never>?

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
        case configUnsupported(String)
        case initializeFailed(String)
        case roundTapped(String)
        case viewMyVotesTapped(roundId: String)
        case proposalTapped(roundId: String, proposalId: UInt32)
        case startActiveRoundPipeline(roundId: String)
        case walletNotSynced(roundId: String, scannedHeight: UInt64, snapshotHeight: UInt64)
        case walletSyncProgressUpdated(height: UInt64)
        case votingWeightLoaded(roundId: String, weight: UInt64, notes: [NoteInfo])
        case hotkeyLoaded(roundId: String, address: String)
        case pipelineFailed(roundId: String, message: String)
        case draftVoteSet(roundId: String, proposalId: UInt32, choice: VoteChoice)
        case submitTapped(roundId: String)
        case submitAllDraftsTapped(roundId: String)
        case fetchTallyResults(roundId: String)
        case tallyResultsLoaded(roundId: String, results: [UInt32: TallyResult])
        case tallyResultsFailed(roundId: String, message: String)
        case submissionAlert(PresentationAction<Never>)
    }

    @Dependency(\.databaseFiles) var databaseFiles
    @Dependency(\.mnemonic) var mnemonic
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

    var body: some Reducer<State, Action> {
        coordinatorReduce()
            .forEach(\.path, action: \.path)
            .ifLet(\.$submissionAlert, action: \.submissionAlert)
    }
}
