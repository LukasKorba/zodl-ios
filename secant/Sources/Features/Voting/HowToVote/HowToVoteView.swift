//
//  HowToVoteView.swift
//  Zashi
//

import SwiftUI
import ComposableArchitecture

/// First-time intro shown to users who have not yet seen the Coinholder
/// Polling onboarding. Continue marks the per-wallet `hasSeenHowToVote`
/// flag and re-triggers `.onAppear` which advances into `.initialize`.
struct HowToVoteView: View {
    @Environment(\.colorScheme) var colorScheme

    let store: StoreOf<VotingCoordFlow>

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 24) {
                Spacer()

                VStack(alignment: .leading, spacing: 12) {
                    Text("How Coinholder Polling works")
                        .zFont(.semiBold, size: 24, style: Design.Text.primary)
                        .tracking(-0.384)
                        .frame(maxWidth: .infinity, alignment: .leading)

                    Text("Your voting power is derived from your shielded ZEC at the round's snapshot height. Vote choices are private; results are tallied by helper servers using zero-knowledge proofs.")
                        .zFont(.medium, size: 14, style: Design.Text.tertiary)
                        .fixedSize(horizontal: false, vertical: true)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.horizontal, 24)

                Spacer()

                ZashiButton(String(localizable: .coinVoteCommonGotIt)) {
                    store.send(.howToVoteContinueTapped)
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
