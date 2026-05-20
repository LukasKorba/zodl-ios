//
//  ProposalListView.swift
//  Zashi
//

import SwiftUI
import ComposableArchitecture

/// Proposal list for a single voting round.
///
/// Bound to the new `VotingCoordFlow` parent store. The path destination
/// only carries `roundId`; all data (round metadata, proposals, voting
/// weight, drafts, submitted votes, etc.) is read from the parent's state
/// and cache.
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
            let session = store.roundCache[roundId]
            let weight = displayWeight(
                session: session,
                voteRecord: session?.voteRecord ?? store.voteRecords[roundId]
            )
            let pipelineReady = session?.hotkeyAddress != nil && (session?.bundleCount ?? 0) > 0
            let drafts = session?.draftVotes ?? [:]
            let submittedVotes = session?.votes ?? [:]
            let displayedChoices = displayedChoices(
                drafts: drafts,
                submittedVotes: submittedVotes
            )
            let canSubmit = mode == .voting && !drafts.isEmpty && pipelineReady

            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header(
                            title: item?.title ?? "",
                            weight: weight,
                            ready: mode == .review || pipelineReady
                        )

                        if proposals.isEmpty {
                            Text(localizable: .coinVotePollsListEmptyMessage)
                                .zFont(size: 14, style: Design.Text.tertiary)
                        } else {
                            ForEach(proposals) { proposal in
                                Button {
                                    store.send(.proposalTapped(
                                        roundId: roundId,
                                        proposalId: proposal.id,
                                        mode: mode == .review ? .review : .voting
                                    ))
                                } label: {
                                    proposalCard(
                                        proposal,
                                        choice: displayedChoices[proposal.id]
                                    )
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                    .padding(.horizontal, 24)
                    .padding(.top, 12)
                    .padding(.bottom, canSubmit ? 96 : 24)
                }
                .padding(.vertical, 1)

                if canSubmit {
                    submitCTA(draftCount: drafts.count)
                }
            }
            .applyScreenBackground()
            .screenTitle(String(localizable: .coinVoteCommonScreenTitle))
            .zashiBack()
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
    private func proposalCard(_ proposal: VotingProposal, choice: VoteChoice?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top) {
                Text(proposal.title)
                    .zFont(.semiBold, size: 16, style: Design.Text.primary)
                    .tracking(-0.256)
                    .fixedSize(horizontal: false, vertical: true)
                    .frame(maxWidth: .infinity, alignment: .leading)

                if let choice, let label = label(for: choice, options: proposal.options) {
                    draftPill(label: label)
                }
            }

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

    private func label(for choice: VoteChoice, options: [VoteOption]) -> String? {
        options.first { $0.index == choice.index }?.label
    }

    private func displayWeight(session: RoundSession?, voteRecord: Voting.VoteRecord?) -> UInt64 {
        if mode == .review, let voteRecord {
            return voteRecord.votingWeight
        }
        return session?.votingWeight ?? 0
    }

    private func displayedChoices(
        drafts: [UInt32: VoteChoice],
        submittedVotes: [UInt32: VoteChoice]
    ) -> [UInt32: VoteChoice] {
        guard mode == .voting else { return submittedVotes }

        var choices = submittedVotes
        choices.merge(drafts) { _, draft in draft }
        return choices
    }

    @ViewBuilder
    private func draftPill(label: String) -> some View {
        Text(label)
            .zFont(.medium, size: 12, style: Design.Text.primary)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(Design.Utility.SuccessGreen._50.color(colorScheme))
            .clipShape(Capsule())
            .overlay(
                Capsule()
                    .stroke(Design.Utility.SuccessGreen._200.color(colorScheme), lineWidth: 1)
            )
    }

    @ViewBuilder
    private func submitCTA(draftCount: Int) -> some View {
        VStack(spacing: 0) {
            ZashiButton("Submit votes (\(draftCount))") {
                store.send(.submitTapped(roundId: roundId))
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
