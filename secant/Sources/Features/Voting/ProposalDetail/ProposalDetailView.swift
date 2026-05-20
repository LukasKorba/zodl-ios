//
//  ProposalDetailView.swift
//  Zashi
//

import SwiftUI
import ComposableArchitecture

/// Proposal detail with vote-choice selection. Tapping an option writes
/// through to `roundCache[roundId].draftVotes[proposalId]` and persists
/// to the encrypted voting metadata file. Submitted choices are read from
/// `roundCache[roundId].votes[proposalId]` and rendered read-only.
struct ProposalDetailView: View {
    @Environment(\.colorScheme) var colorScheme

    let store: StoreOf<VotingCoordFlow>
    let roundId: String
    let proposalId: UInt32
    let mode: ProposalDetail.Mode

    init(
        store: StoreOf<VotingCoordFlow>,
        roundId: String,
        proposalId: UInt32,
        mode: ProposalDetail.Mode = .voting
    ) {
        self.store = store
        self.roundId = roundId
        self.proposalId = proposalId
        self.mode = mode
    }

    var body: some View {
        WithPerceptionTracking {
            let proposal = store.allRounds
                .first { $0.id == roundId }?
                .session.proposals
                .first { $0.id == proposalId }
            let session = store.roundCache[roundId]
            let draftChoice = session?.draftVotes[proposalId]
            let submittedChoice = session?.votes[proposalId]
            let selected = selectedChoice(
                draftChoice: draftChoice,
                submittedChoice: submittedChoice
            )
            let isLocked = mode == .review || submittedChoice != nil

            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    if let proposal {
                        VStack(alignment: .leading, spacing: 16) {
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
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal, 24)
                        .padding(.top, 12)

                        if !proposal.options.isEmpty {
                            VStack(spacing: 0) {
                                ForEach(Array(proposal.options.enumerated()), id: \.element.index) { offset, option in
                                    if offset > 0 {
                                        Divider()
                                            .frame(height: 1)
                                    }
                                    optionRow(
                                        option,
                                        selected: selected,
                                        isLocked: isLocked
                                    )
                                }
                            }
                            .padding(.top, 16)
                        }
                    } else {
                        Text("Proposal not found")
                            .zFont(.medium, size: 14, style: Design.Text.tertiary)
                            .padding(.horizontal, 24)
                            .padding(.top, 12)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.bottom, 24)
            }
            .padding(.vertical, 1)
            .applyScreenBackground()
            .screenTitle(String(localizable: .coinVoteCommonScreenTitle))
            .zashiBack()
        }
    }

    @ViewBuilder
    private func optionRow(_ option: VoteOption, selected: VoteChoice?, isLocked: Bool) -> some View {
        let isSelected = selected == .option(option.index)
        Button {
            // Suppress option taps for submitted proposals: writing a new
            // draft here would make the review state diverge from what was
            // already accepted by the voting backend.
            guard !isLocked else { return }
            store.send(
                .draftVoteSet(
                    roundId: roundId,
                    proposalId: proposalId,
                    choice: .option(option.index)
                )
            )
        } label: {
            HStack(alignment: .center, spacing: 12) {
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

                VStack(alignment: .leading, spacing: 4) {
                    Text(option.label)
                        .zFont(.semiBold, size: 16, style: Design.Text.primary)
                        .tracking(-0.256)
                        .fixedSize(horizontal: false, vertical: true)

                    if let description = option.description?
                        .trimmingCharacters(in: .whitespacesAndNewlines),
                       !description.isEmpty {
                        Text(description)
                            .zFont(.medium, size: 14, style: Design.Text.tertiary)
                            .tracking(-0.224)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .padding(.horizontal, 24)
            .padding(.vertical, 16)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isLocked)
    }

    private func selectedChoice(
        draftChoice: VoteChoice?,
        submittedChoice: VoteChoice?
    ) -> VoteChoice? {
        submittedChoice ?? draftChoice
    }
}
