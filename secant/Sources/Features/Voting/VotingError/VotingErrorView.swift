//
//  VotingErrorView.swift
//  Zashi
//

import SwiftUI
import ComposableArchitecture

/// Blocking error screen — used for both `.error` (generic init failure)
/// and `.configError` (voting service config unavailable/decode failed)
/// root states. Offers a single Got-it that dismisses the flow.
struct VotingErrorView: View {
    @Environment(\.colorScheme) var colorScheme

    let store: StoreOf<VotingCoordFlow>
    let title: String
    let message: String

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 24) {
                Spacer()

                VStack(spacing: 12) {
                    Image(systemName: "exclamationmark.circle")
                        .font(.system(size: 40, weight: .regular))
                        .foregroundStyle(Design.Utility.ErrorRed._500.color(colorScheme))

                    Text(title)
                        .zFont(.semiBold, size: 20, style: Design.Text.primary)
                        .multilineTextAlignment(.center)

                    Text(message)
                        .zFont(.medium, size: 14, style: Design.Text.tertiary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 8)
                }
                .padding(.horizontal, 24)

                Spacer()

                ZashiButton(String(localizable: .coinVoteCommonGotIt)) {
                    store.send(.dismissFlow)
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
