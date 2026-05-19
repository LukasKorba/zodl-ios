//
//  NoRoundsView.swift
//  Zashi
//

import SwiftUI
import ComposableArchitecture

/// Empty-state shown when the voting service returns zero rounds. Offers
/// a Refresh (re-fetch) and exit-flow path.
struct NoRoundsView: View {
    @Environment(\.colorScheme) var colorScheme

    let store: StoreOf<VotingCoordFlow>

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 24) {
                Spacer()

                VStack(spacing: 12) {
                    Image(systemName: "tray")
                        .font(.system(size: 40, weight: .regular))
                        .foregroundStyle(Design.Text.tertiary.color(colorScheme))

                    Text(localizable: .coinVotePollsListEmptyTitle)
                        .zFont(.semiBold, size: 20, style: Design.Text.primary)

                    Text(localizable: .coinVotePollsListEmptyMessage)
                        .zFont(.medium, size: 14, style: Design.Text.tertiary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.horizontal, 24)

                Spacer()

                VStack(spacing: 8) {
                    ZashiButton(String(localizable: .coinVoteCommonRefresh)) {
                        store.send(.retryLoadRounds)
                    }
                    ZashiButton(String(localizable: .coinVoteCommonGotIt), type: .tertiary) {
                        store.send(.dismissFlow)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 24)
            }
            .applyScreenBackground()
            .screenTitle(String(localizable: .coinVoteCommonScreenTitle))
            .zashiBack { store.send(.dismissFlow) }
        }
    }
}
