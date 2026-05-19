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
                // NavigationStack's destination closure is escaping; it needs
                // its own WithPerceptionTracking so reads from
                // `destinationStore` and the captured parent `store` register
                // with TCA's observation machinery.
                WithPerceptionTracking {
                    switch destinationStore.case {
                    case let .proposalList(scoped):
                        ProposalListView(
                            store: store,
                            roundId: scoped.roundId,
                            mode: .voting
                        )
                    case let .proposalDetail(scoped):
                        ProposalDetailView(
                            store: store,
                            roundId: scoped.roundId,
                            proposalId: scoped.proposalId
                        )
                    case let .reviewVotes(scoped):
                        ProposalListView(
                            store: store,
                            roundId: scoped.roundId,
                            mode: .review
                        )
                    case let .confirmSubmission(scoped):
                        ConfirmSubmissionView(store: store, roundId: scoped.roundId)
                    case .delegationSigning:
                        // TODO Phase 5.
                        Text("Delegation signing")
                    case let .tallying(scoped):
                        TallyingView(store: store, roundId: scoped.roundId)
                    case let .results(scoped):
                        ResultsView(store: store, roundId: scoped.roundId)
                    case .ineligible:
                        // TODO Phase 7.
                        Text("Ineligible")
                    case let .configSettings(configStore):
                        VotingConfigSettingsView(store: configStore)
                    }
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
