//
//  VotingCoordFlowView.swift
//  Zashi
//

import SwiftUI
import ComposableArchitecture

struct VotingCoordFlowView: View {
    @Perception.Bindable var store: StoreOf<VotingCoordFlow>

    init(store: StoreOf<VotingCoordFlow>) {
        self.store = store
    }

    var body: some View {
        WithPerceptionTracking {
            NavigationStack(path: $store.scope(state: \.path, action: \.path)) {
                rootContent
                    .onAppear { store.send(.onAppear) }
            } destination: { destinationStore in
                // Pushed screens read both their path-scoped state (just
                // `roundId` for most cases) and the parent store's shared
                // round cache. The parent `store` is captured from the outer
                // closure so destinations can resolve their data via roundId.
                switch destinationStore.case {
                case let .proposalList(scoped):
                    ProposalListView(
                        store: store,
                        roundId: scoped.roundId,
                        mode: .voting
                    )
                case .proposalDetail:
                    // TODO Phase 4d: real proposal detail view.
                    Text("Proposal detail")
                case let .reviewVotes(scoped):
                    ProposalListView(
                        store: store,
                        roundId: scoped.roundId,
                        mode: .review
                    )
                case .confirmSubmission:
                    // TODO Phase 4f.
                    Text("Confirm submission")
                case .delegationSigning:
                    // TODO Phase 5.
                    Text("Delegation signing")
                case .tallying:
                    // TODO Phase 6.
                    Text("Tallying")
                case .results:
                    // TODO Phase 6.
                    Text("Results")
                case .ineligible:
                    // TODO Phase 7.
                    Text("Ineligible")
                case let .configSettings(configStore):
                    VotingConfigSettingsView(store: configStore)
                }
            }
        }
    }

    // MARK: - Root screen rendering

    @ViewBuilder
    private var rootContent: some View {
        // Phase 2 renders placeholder text per root state. Phase 3+ will
        // swap these out for the real PollsList / NoRounds / HowToVote /
        // WalletSyncing / error views.
        switch store.rootScreen {
        case .loading:
            ProgressView()
        case .howToVote:
            Text("How to vote")
        case .noRounds:
            Text("No rounds")
        case .pollsList:
            PollsListView(store: store)
        case .walletSyncing:
            Text("Wallet syncing")
        case let .error(message):
            Text("Error: \(message)")
        case let .configError(message):
            Text("Config error: \(message)")
        }
    }
}
