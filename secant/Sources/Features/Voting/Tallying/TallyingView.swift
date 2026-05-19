//
//  TallyingView.swift
//  Zashi
//

import SwiftUI
import ComposableArchitecture

/// Tallying-phase view. Voting has closed and the helper servers are
/// computing the final tally. Shows the round title + a "tallying"
/// message; once status flips to finalized, the parent transitions to
/// Results.
struct TallyingView: View {
    @Environment(\.colorScheme) var colorScheme

    let store: StoreOf<VotingCoordFlow>
    let roundId: String

    var body: some View {
        WithPerceptionTracking {
            let item = store.allRounds.first { $0.id == roundId }

            VStack(alignment: .leading, spacing: 16) {
                Text(item?.title ?? "")
                    .zFont(.semiBold, size: 24, style: Design.Text.primary)
                    .tracking(-0.384)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 12) {
                    ProgressView()
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Tallying in progress")
                            .zFont(.semiBold, size: 16, style: Design.Text.primary)
                        Text("Voting has closed. Final results will appear here once the helpers finish tallying.")
                            .zFont(.medium, size: 14, style: Design.Text.tertiary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .padding(Design.Spacing._xl)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Design.Surfaces.bgPrimary.color(colorScheme))
                .clipShape(RoundedRectangle(cornerRadius: Design.Radius._2xl))
                .overlay(
                    RoundedRectangle(cornerRadius: Design.Radius._2xl)
                        .stroke(Design.Surfaces.strokeSecondary.color(colorScheme), lineWidth: 1)
                )

                Spacer()
            }
            .padding(.horizontal, 24)
            .padding(.top, 12)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .applyScreenBackground()
            .screenTitle(String(localizable: .coinVoteCommonScreenTitle))
            .zashiBack()
        }
    }
}
