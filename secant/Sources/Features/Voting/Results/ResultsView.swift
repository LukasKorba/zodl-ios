//
//  ResultsView.swift
//  Zashi
//

import SwiftUI
import ComposableArchitecture

/// Final results view for a finalized round. Renders per-proposal tally:
/// each option's accumulated voting power + a winning indicator. Tally
/// results are cached in `RoundSession.tallyResults`; the view triggers
/// `.fetchTallyResults` on first appear and is idempotent on re-entry
/// because finalized rounds are immutable.
struct ResultsView: View {
    @Environment(\.colorScheme) var colorScheme

    let store: StoreOf<VotingCoordFlow>
    let roundId: String

    var body: some View {
        WithPerceptionTracking {
            let item = store.allRounds.first { $0.id == roundId }
            let proposals = item?.session.proposals ?? []
            let cached = store.roundCache[roundId]
            let tallyResults = cached?.tallyResults ?? [:]
            let loaded = cached?.tallyFetched ?? false

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    Text(item?.title ?? "")
                        .zFont(.semiBold, size: 24, style: Design.Text.primary)
                        .tracking(-0.384)
                        .fixedSize(horizontal: false, vertical: true)

                    if !loaded {
                        HStack(spacing: 8) {
                            ProgressView().scaleEffect(0.75)
                            Text("Loading results…")
                                .zFont(.medium, size: 14, style: Design.Text.tertiary)
                        }
                        .padding(.top, 8)
                    } else if proposals.isEmpty {
                        Text("No proposals in this round")
                            .zFont(.medium, size: 14, style: Design.Text.tertiary)
                    } else {
                        ForEach(proposals) { proposal in
                            resultCard(proposal, tally: tallyResults[proposal.id])
                        }
                    }
                }
                .padding(.horizontal, 24)
                .padding(.top, 12)
                .padding(.bottom, 24)
            }
            .padding(.vertical, 1)
            .applyScreenBackground()
            .screenTitle(String(localizable: .coinVoteCommonScreenTitle))
            .zashiBack()
            .onAppear { store.send(.fetchTallyResults(roundId: roundId)) }
        }
    }

    @ViewBuilder
    private func resultCard(_ proposal: VotingProposal, tally: TallyResult?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(proposal.title)
                .zFont(.semiBold, size: 16, style: Design.Text.primary)
                .tracking(-0.256)
                .fixedSize(horizontal: false, vertical: true)

            if let tally, !tally.entries.isEmpty {
                let total = tally.entries.reduce(UInt64(0)) { $0 + $1.amount }
                let winningIndex = tally.entries.max { $0.amount < $1.amount }?.decision
                ForEach(proposal.options, id: \.index) { option in
                    let amount = tally.entries.first { $0.decision == option.index }?.amount ?? 0
                    let pct = total > 0 ? Double(amount) / Double(total) : 0
                    optionResultRow(
                        label: option.label,
                        amount: amount,
                        pct: pct,
                        winning: option.index == winningIndex
                    )
                }
            } else {
                Text("No votes recorded")
                    .zFont(.medium, size: 14, style: Design.Text.tertiary)
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

    @ViewBuilder
    private func optionResultRow(label: String, amount: UInt64, pct: Double, winning: Bool) -> some View {
        HStack {
            Text(label)
                .zFont(winning ? .semiBold : .medium, size: 14, style: Design.Text.primary)
            Spacer()
            Text("\(Int(pct * 100))%")
                .zFont(.medium, size: 14, style: Design.Text.tertiary)
        }
        .padding(.vertical, 4)
    }
}
