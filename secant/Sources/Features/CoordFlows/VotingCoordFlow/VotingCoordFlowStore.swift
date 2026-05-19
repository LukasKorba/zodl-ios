//
//  VotingCoordFlowStore.swift
//  Zashi
//

import ComposableArchitecture
import Foundation

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

        init() {}
    }

    enum Action {
        case path(StackActionOf<Path>)
        case onAppear
        case dismissFlow
        case howToVoteContinueTapped
        case retryLoadRounds
        case openConfigSettings
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .path:
                return .none

            case .onAppear:
                // TODO Phase 3+: load service config, fetch rounds, transition
                // rootScreen based on result (howToVote first-time, pollsList
                // when rounds exist, noRounds when empty, walletSyncing when
                // SDK not caught up, configError on service unavailable).
                return .none

            case .dismissFlow:
                // TODO Phase 3+: cancel polling effects, evict roundCache,
                // dismiss the flow back to Settings.
                state.roundCache.removeAll()
                state.path.removeAll()
                return .none

            case .howToVoteContinueTapped:
                // TODO Phase 3+: persist the per-account hasSeenHowToVote
                // flag and re-run `.onAppear` to advance past the intro.
                return .send(.onAppear)

            case .retryLoadRounds:
                // TODO Phase 3+: re-issue the rounds fetch from the empty
                // state.
                state.rootScreen = .loading
                return .send(.onAppear)

            case .openConfigSettings:
                state.path.append(.configSettings(VotingConfigSettings.State()))
                return .none
            }
        }
        .forEach(\.path, action: \.path)
    }
}
