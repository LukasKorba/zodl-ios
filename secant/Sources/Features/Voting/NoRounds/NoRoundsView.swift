//
//  NoRoundsView.swift
//  Zashi
//

import SwiftUI
import ComposableArchitecture

/// Empty-state shown when the voting service returns zero rounds. Renders the
/// shimmering polls-list backdrop with a dimmed "No polls right now" sheet on
/// top, matching the same pattern used while the polls list is loading.
struct NoRoundsView: View {
    let store: StoreOf<VotingCoordFlow>

    var body: some View {
        WithPerceptionTracking {
            VotingCoordFlowBackdrop(store: store)
                .votingBlockingSheet(
                    isActive: { store.rootScreen == .noRounds },
                    visualStyle: .unverifiedWarning,
                    onExit: { store.send(.dismissFlow) }
                ) { dismiss in
                    VotingSheetContent(
                        iconSystemName: "exclamationmark.circle",
                        iconStyle: Design.Utility.ErrorRed._500,
                        title: String(localizable: .coinVotePollsListEmptyTitle),
                        message: String(localizable: .coinVotePollsListEmptyMessage),
                        primary: .init(
                            title: String(localizable: .coinVoteCommonGotIt),
                            style: .primary
                        ) {
                            dismiss()
                        },
                        secondary: .init(
                            title: String(localizable: .coinVoteCommonRefresh),
                            style: .secondary
                        ) {
                            store.send(.retryLoadRounds)
                        },
                        visualStyle: .unverifiedWarning
                    )
                }
        }
    }
}

/// Shared shimmering backdrop used by the `.loading` and `.noRounds` root
/// screens. Renders the screen title + a single outlined skeleton card so the
/// chrome stays consistent across loading, empty, and error states.
struct VotingCoordFlowBackdrop: View {
    let store: StoreOf<VotingCoordFlow>

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                PollsListSkeletonCard()
            }
            .padding(.horizontal, 24)
            .padding(.top, 8)
            .padding(.bottom, 24)
        }
        .padding(.vertical, 1)
        .applyScreenBackground()
        .screenTitle(String(localizable: .coinVoteCommonScreenTitle))
        .zashiBack { store.send(.dismissFlow) }
    }
}
