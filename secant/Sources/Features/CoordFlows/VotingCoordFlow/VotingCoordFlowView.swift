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
            } destination: { store in
                // TODO Phase 3+: render each pushed screen by binding the
                // matching child reducer to its real View. Phase 2 renders
                // a placeholder to verify the architecture compiles.
                switch store.case {
                case .proposalList:
                    Text("Proposal list")
                case .proposalDetail:
                    Text("Proposal detail")
                case .reviewVotes:
                    Text("Review votes")
                case .confirmSubmission:
                    Text("Confirm submission")
                case .delegationSigning:
                    Text("Delegation signing")
                case .tallying:
                    Text("Tallying")
                case .results:
                    Text("Results")
                case .ineligible:
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
