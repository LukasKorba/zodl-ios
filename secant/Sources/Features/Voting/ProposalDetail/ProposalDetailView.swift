//
//  ProposalDetailView.swift
//  Zashi
//

import SwiftUI
import ComposableArchitecture

/// Read-only proposal detail view. Phase 4d renders title + description +
/// back navigation only; choice selection, draft persistence, and
/// next/previous navigation between proposals land in Phase 4e.
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
}
