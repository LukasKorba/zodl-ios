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
                    .onAppear {
                        store.send(.onAppear)
                        store.send(.warmProvingCaches)
                    }
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
                            proposalId: scoped.proposalId,
                            mode: scoped.mode
                        )
                    case let .reviewVotes(scoped):
                        ProposalListView(
                            store: store,
                            roundId: scoped.roundId,
                            mode: .review
                        )
                    case let .confirmSubmission(scoped):
                        ConfirmSubmissionView(store: store, roundId: scoped.roundId)
                    case let .delegationSigning(scoped):
                        DelegationSigningView(store: store, roundId: scoped.roundId)
                    case let .tallying(scoped):
                        TallyingView(store: store, roundId: scoped.roundId)
                    case let .results(scoped):
                        ResultsView(store: store, roundId: scoped.roundId)
                    case let .ineligible(scoped):
                        IneligibleView(store: store, roundId: scoped.roundId)
                    case let .configSettings(configStore):
                        VotingConfigSettingsView(store: configStore)
                    }
                }
            }
            .alert($store.scope(state: \.submissionAlert, action: \.submissionAlert))
            .alert($store.scope(state: \.skipBundlesAlert, action: \.skipBundlesAlert))
            .alert($store.scope(state: \.pollClosedAlert, action: \.pollClosedAlert))
        }
    }

    // MARK: - Root screen rendering

    @ViewBuilder
    private var rootContent: some View {
        switch store.rootScreen {
        case .loading:
            VotingCoordFlowBackdrop(store: store)
        case .howToVote:
            HowToVoteView(store: store)
        case .noRounds:
            NoRoundsView(store: store)
        case .pollsList:
            PollsListView(store: store)
        case .walletSyncing:
            WalletSyncingView(store: store)
        case let .error(message):
            VotingErrorView(
                store: store,
                title: "Something went wrong",
                message: message
            )
        case let .configError(message):
            VotingErrorView(
                store: store,
                title: "Voting unavailable",
                message: message
            )
        }
    }
}
