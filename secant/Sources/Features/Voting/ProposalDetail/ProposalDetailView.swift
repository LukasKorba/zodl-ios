//
//  ProposalDetailView.swift
//  Zashi
//

import SwiftUI
import ComposableArchitecture

/// Proposal detail with vote-choice selection. Tapping an option writes
/// through to `roundCache[roundId].draftVotes[proposalId]` and persists
/// to the encrypted voting metadata file. Re-entering the same proposal
/// surfaces the previously selected choice.
struct ProposalDetailView: View {
    @Environment(\.colorScheme) var colorScheme

    let store: StoreOf<VotingCoordFlow>
    let roundId: String
    let proposalId: UInt32

    var body: some View {
        WithPerceptionTracking {
            let proposal = store.allRounds
                .first { $0.id == roundId }?
                .session.proposals
                .first { $0.id == proposalId }
            let selected = store.roundCache[roundId]?.draftVotes[proposalId]

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    if let proposal {
                        Text(proposal.title)
                            .zFont(.semiBold, size: 24, style: Design.Text.primary)
                            .tracking(-0.384)
                            .fixedSize(horizontal: false, vertical: true)

                        if !proposal.description.isEmpty {
                            Text(proposal.description)
                                .zFont(.medium, size: 14, style: Design.Text.primary)
                                .tracking(-0.224)
                                .fixedSize(horizontal: false, vertical: true)
                        }

                        if !proposal.options.isEmpty {
                            VStack(spacing: 8) {
                                ForEach(proposal.options, id: \.index) { option in
                                    optionRow(option, selected: selected)
                                }
                            }
                            .padding(.top, 8)
                        }
                    } else {
                        Text("Proposal not found")
                            .zFont(.medium, size: 14, style: Design.Text.tertiary)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .padding(.vertical, 1)
            .applyScreenBackground()
            .screenTitle(String(localizable: .coinVoteCommonScreenTitle))
            .zashiBack()
        }
    }

    @ViewBuilder
    private func optionRow(_ option: VoteOption, selected: VoteChoice?) -> some View {
        let isSelected = selected == .option(option.index)
        Button {
            store.send(
                .draftVoteSet(
                    roundId: roundId,
                    proposalId: proposalId,
                    choice: .option(option.index)
                )
            )
        } label: {
            HStack(spacing: 12) {
                ZStack {
                    Circle()
                        .stroke(
                            isSelected
                                ? Design.Text.primary.color(colorScheme)
                                : Design.Surfaces.strokeSecondary.color(colorScheme),
                            lineWidth: 2
                        )
                        .frame(width: 22, height: 22)
                    if isSelected {
                        Circle()
                            .fill(Design.Text.primary.color(colorScheme))
                            .frame(width: 12, height: 12)
                    }
                }

                Text(option.label)
                    .zFont(.medium, size: 16, style: Design.Text.primary)
                    .tracking(-0.256)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(Design.Spacing._xl)
            .background(Design.Surfaces.bgPrimary.color(colorScheme))
            .clipShape(RoundedRectangle(cornerRadius: Design.Radius._2xl))
            .overlay(
                RoundedRectangle(cornerRadius: Design.Radius._2xl)
                    .stroke(
                        isSelected
                            ? Design.Text.primary.color(colorScheme)
                            : Design.Surfaces.strokeSecondary.color(colorScheme),
                        lineWidth: isSelected ? 2 : 1
                    )
            )
        }
        .buttonStyle(.plain)
    }
}
