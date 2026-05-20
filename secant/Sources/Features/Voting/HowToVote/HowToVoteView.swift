//
//  HowToVoteView.swift
//  Zashi
//

import SwiftUI
import ComposableArchitecture

/// First-time intro shown to users who have not yet seen the Coinholder
/// Polling onboarding. Renders the same 2-step layout for Zodl and Keystone
/// accounts; only the brand icon + title copy differ.
struct HowToVoteView: View {
    @Environment(\.colorScheme) var colorScheme

    let store: StoreOf<VotingCoordFlow>

    var body: some View {
        WithPerceptionTracking {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        iconRow
                            .padding(.top, 24)
                            .padding(.bottom, 24)

                        Text(titleCopy)
                            .zFont(.semiBold, size: 24, style: Design.Text.primary)
                            .tracking(-0.384)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.bottom, 8)

                        Text(subtitleCopy)
                            .zFont(.medium, size: 14, style: Design.Text.tertiary)
                            .tracking(-0.224)
                            .fixedSize(horizontal: false, vertical: true)
                            .padding(.bottom, 24)

                        stepRow(
                            number: 1,
                            title: "Voting on Proposals",
                            body: "Vote on each question by selecting an answer. You can skip questions and update your choices anytime before submitting."
                        )
                        .padding(.bottom, 16)

                        stepRow(
                            number: 2,
                            title: "Authorize and Submit",
                            body: "When you're ready, you'll confirm a small authorization transaction and submit your vote in one step. After submission, your vote cannot be changed."
                        )
                    }
                    .padding(.horizontal, 24)
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                .padding(.vertical, 1)

                snapshotNote
                    .padding(.horizontal, 24)
                    .padding(.bottom, 12)

                ZashiButton(String(localizable: .coinVoteCommonContinue)) {
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

    // MARK: - Top icon row

    @ViewBuilder
    private var iconRow: some View {
        HStack(spacing: -8) {
            ZStack {
                Circle()
                    .fill(Design.Text.primary.color(colorScheme))
                    .frame(width: 48, height: 48)

                brandIcon
            }

            ZStack {
                Circle()
                    .fill(Design.Surfaces.bgSecondary.color(colorScheme))
                    .frame(width: 48, height: 48)

                Image(systemName: "hand.thumbsup.fill")
                    .font(.system(size: 20))
                    .foregroundStyle(Design.Text.primary.color(colorScheme))
            }
        }
    }

    @ViewBuilder
    private var brandIcon: some View {
        if store.isKeystoneUser {
            Asset.Assets.Partners.keystoneLogo.image
                .resizable()
                .frame(width: 48, height: 48)
                .clipShape(Circle())
        } else {
            Asset.Assets.zashiLogo.image
                .zImage(size: 22, color: Design.Surfaces.bgPrimary.color(colorScheme))
        }
    }

    // MARK: - Steps

    @ViewBuilder
    private func stepRow(number: Int, title: String, body: String) -> some View {
        HStack(alignment: .top, spacing: 12) {
            ZStack {
                Circle()
                    .fill(Design.Text.primary.color(colorScheme))
                    .frame(width: 24, height: 24)

                Text("\(number)")
                    .zFont(.semiBold, size: 12, color: Design.Surfaces.bgPrimary.color(colorScheme))
            }

            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .zFont(.semiBold, size: 16, style: Design.Text.primary)
                    .tracking(-0.256)
                    .fixedSize(horizontal: false, vertical: true)

                Text(body)
                    .zFont(.medium, size: 14, style: Design.Text.tertiary)
                    .tracking(-0.224)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Bottom info note

    @ViewBuilder
    private var snapshotNote: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "info.circle")
                .font(.system(size: 16, weight: .regular))
                .foregroundStyle(Design.Text.tertiary.color(colorScheme))
                .padding(.top, 1)

            Text("Your balance at the snapshot time determines your voting weight. You don't need to move your funds anywhere.")
                .zFont(.medium, size: 13, style: Design.Text.tertiary)
                .tracking(-0.208)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    // MARK: - Variant copy

    private var titleCopy: String {
        store.isKeystoneUser ? "How to vote with Keystone" : "How to vote with Zodl"
    }

    private var subtitleCopy: String {
        "Your ZEC gives you a voice. Shape the future of the Zcash network by voting on active proposals."
    }
}
