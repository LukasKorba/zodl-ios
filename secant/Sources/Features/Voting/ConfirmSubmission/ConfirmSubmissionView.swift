//
//  ConfirmSubmissionView.swift
//  Zashi
//

import SwiftUI
import ComposableArchitecture

/// Final review screen before vote submission. Displays each drafted vote
/// (proposal title + chosen option label) and the voting power that will
/// be applied. The Submit button is a placeholder until Phase 5 wires the
/// real submission pipeline (delegation proof + per-vote ZKPs + share
/// delegation to helper servers).
struct ConfirmSubmissionView: View {
    @Environment(\.colorScheme) var colorScheme

    let store: StoreOf<VotingCoordFlow>
    let roundId: String

    var body: some View {
        WithPerceptionTracking {
            let item = store.allRounds.first { $0.id == roundId }
            let proposals = item?.session.proposals ?? []
            let weight = store.roundCache[roundId]?.votingWeight ?? 0
            let drafts = store.roundCache[roundId]?.draftVotes ?? [:]

            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header(weight: weight, count: drafts.count)

                        VStack(spacing: 8) {
                            ForEach(proposals) { proposal in
                                if let choice = drafts[proposal.id],
                                   let label = proposal.options.first(where: { $0.index == choice.index })?.label {
                                    summaryRow(title: proposal.title, choice: label)
                                }
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                    .padding(.bottom, 96)
                }
                .padding(.vertical, 1)

                submitCTA
            }
            .applyScreenBackground()
            .screenTitle(String(localizable: .coinVoteCommonScreenTitle))
            .zashiBack()
        }
    }

    @ViewBuilder
    private func header(weight: UInt64, count: Int) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Review and submit")
                .zFont(.semiBold, size: 24, style: Design.Text.primary)
                .tracking(-0.384)

            Text("Submitting \(count) vote\(count == 1 ? "" : "s") with voting power \(weight).")
                .zFont(.medium, size: 14, style: Design.Text.tertiary)
                .tracking(-0.224)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func summaryRow(title: String, choice: String) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(title)
                .zFont(.semiBold, size: 16, style: Design.Text.primary)
                .tracking(-0.256)
                .fixedSize(horizontal: false, vertical: true)

            Text(choice)
                .zFont(.medium, size: 14, style: Design.Text.tertiary)
                .tracking(-0.224)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Design.Spacing._xl)
        .background(Design.Surfaces.bgPrimary.color(colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: Design.Radius._2xl))
        .overlay(
            RoundedRectangle(cornerRadius: Design.Radius._2xl)
                .stroke(Design.Surfaces.strokeSecondary.color(colorScheme), lineWidth: 1)
        )
    }

    @ViewBuilder
    private var submitCTA: some View {
        VStack(spacing: 0) {
            // TODO Phase 5: wire to the submission pipeline. For now this
            // logs the intent so we can verify Phase 4 end-to-end without
            // touching Keystone / delegation proof / vote ZKPs.
            ZashiButton("Submit") {
                store.send(.submitAllDraftsTapped(roundId: roundId))
            }
        }
        .padding(.horizontal, 24)
        .padding(.bottom, 24)
        .background(
            LinearGradient(
                colors: [
                    Design.Surfaces.bgPrimary.color(colorScheme).opacity(0),
                    Design.Surfaces.bgPrimary.color(colorScheme).opacity(0.95)
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}
