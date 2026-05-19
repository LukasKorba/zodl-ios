//
//  ProposalListView.swift
//  Zashi
//

import SwiftUI
import ComposableArchitecture

/// Read-only proposal list for a single voting round.
///
/// Bound to the new `VotingCoordFlow` parent store. The path destination
/// only carries `roundId`; all data (round metadata, proposals, voting
/// weight, hotkey, etc.) is read from the parent's state and cache.
///
/// This phase (4c) renders the structural skeleton: header with voting
/// weight + proposal cards. Vote drafting, draft persistence, submission
/// flow, share tracking, edit-from-review, and the bottom CTA all land in
/// Phase 4d and beyond. The view compiles + renders today; tapping a
/// proposal is a no-op until Phase 4d.
struct ProposalListView: View {
    enum Mode: Equatable { case voting, review }

    @Environment(\.colorScheme) var colorScheme

    let store: StoreOf<VotingCoordFlow>
    let roundId: String
    let mode: Mode

    var body: some View {
        WithPerceptionTracking {
            let item = store.allRounds.first { $0.id == roundId }
            let proposals = item?.session.proposals ?? []
            let weight = store.roundCache[roundId]?.votingWeight ?? 0
            let pipelineReady = store.roundCache[roundId]?.hotkeyAddress != nil

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header(title: item?.title ?? "", weight: weight, ready: pipelineReady)

                    if proposals.isEmpty {
                        Text(localizable: .coinVotePollsListEmptyMessage)
                            .zFont(size: 14, style: Design.Text.tertiary)
                    } else {
                        ForEach(proposals) { proposal in
                            proposalCard(proposal)
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .applyScreenBackground()
            .screenTitle(String(localizable: .coinVoteCommonScreenTitle))
            .zashiBack { store.send(.path(.popFrom(id: store.path.ids.last ?? -1))) }
        }
    }

    @ViewBuilder
    private func header(title: String, weight: UInt64, ready: Bool) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .zFont(.semiBold, size: 24, style: Design.Text.primary)
                .tracking(-0.384)
                .fixedSize(horizontal: false, vertical: true)

            if ready {
                Text("Voting power: \(weight)")
                    .zFont(.medium, size: 14, style: Design.Text.tertiary)
            } else {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.75)
                    Text("Preparing your voting power…")
                        .zFont(.medium, size: 14, style: Design.Text.tertiary)
                }
            }

            if mode == .review {
                Text("Review your submitted votes")
                    .zFont(.medium, size: 14, style: Design.Text.tertiary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 8)
    }

    @ViewBuilder
    private func proposalCard(_ proposal: VotingProposal) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(proposal.title)
                .zFont(.semiBold, size: 16, style: Design.Text.primary)
                .tracking(-0.256)
                .fixedSize(horizontal: false, vertical: true)

            if !proposal.description.isEmpty {
                Text(proposal.description)
                    .zFont(.medium, size: 14, style: Design.Text.tertiary)
                    .tracking(-0.224)
                    .lineLimit(3)
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
    }
}
