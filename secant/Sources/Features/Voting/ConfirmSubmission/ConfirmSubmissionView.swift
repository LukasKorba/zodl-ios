//
//  ConfirmSubmissionView.swift
//  Zashi
//

import SwiftUI
import ComposableArchitecture

/// Final review screen before vote submission. Displays each drafted vote
/// (proposal title + chosen option label) and the voting power that will
/// be applied. Renders progress, success, and error states once submission
/// is in flight via `RoundSession.batchSubmissionStatus`.
struct ConfirmSubmissionView: View {
    @Environment(\.colorScheme) var colorScheme
    @Environment(\.dismiss) private var dismiss

    let store: StoreOf<VotingCoordFlow>
    let roundId: String

    var body: some View {
        WithPerceptionTracking {
            let item = store.allRounds.first { $0.id == roundId }
            let proposals = item?.session.proposals ?? []
            let session = store.roundCache[roundId]
            let weight = session?.votingWeight ?? 0
            let drafts = session?.draftVotes ?? [:]
            let status = session?.batchSubmissionStatus ?? .idle
            let bundleCount = session?.bundleCount ?? 0

            ZStack(alignment: .bottom) {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        header(weight: weight, count: drafts.count, status: status)

                        if let step = session?.voteSubmissionStep, status.isInFlight {
                            progressCard(
                                step: step,
                                bundleIndex: session?.currentVoteBundleIndex,
                                bundleCount: session?.bundleCount ?? 0,
                                status: status
                            )
                        }

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
                    .padding(.bottom, 120)
                }
                .padding(.vertical, 1)

                submitCTA(status: status, drafts: drafts, bundleCount: bundleCount)
            }
            .applyScreenBackground()
            .screenTitle(String(localizable: .coinVoteCommonScreenTitle))
            .zashiBack {
                guard !status.isInFlight else { return }
                dismiss()
            }
            .alert(
                String(localizable: .coinVoteConfirmSubmissionAuthorizationFailedTitle),
                isPresented: authorizationErrorBinding(status: status)
            ) {
                Button(String(localizable: .coinVoteCommonTryAgain), role: nil) {
                    store.send(.retryBatchSubmission(roundId: roundId))
                }
                Button(String(localizable: .coinVoteCommonCancel), role: .cancel) {
                    store.send(.dismissBatchResults(roundId: roundId))
                }
            } message: {
                if case let .authorizationFailed(error) = status {
                    Text(error)
                }
            }
            .alert(
                String(localizable: .coinVoteConfirmSubmissionSubmissionFailedTitle),
                isPresented: submissionErrorBinding(status: status)
            ) {
                Button(String(localizable: .coinVoteCommonTryAgain), role: nil) {
                    store.send(.retryBatchSubmission(roundId: roundId))
                }
                Button(String(localizable: .coinVoteCommonCancel), role: .cancel) {
                    store.send(.dismissBatchResults(roundId: roundId))
                }
            } message: {
                if case let .submissionFailed(error, _, _) = status {
                    Text(error)
                }
            }
        }
    }

    @ViewBuilder
    private func header(weight: UInt64, count: Int, status: BatchSubmissionStatus) -> some View {
        let title: String = {
            switch status {
            case .completed:
                return String(localizable: .coinVoteCommonSubmission)
            case .authorizing, .submitting:
                return String(localizable: .coinVoteCommonSubmission)
            default:
                return String(localizable: .coinVoteCommonConfirmation)
            }
        }()

        VStack(alignment: .leading, spacing: 8) {
            Text(title)
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
    private func progressCard(
        step: VoteSubmissionStep,
        bundleIndex: UInt32?,
        bundleCount: UInt32,
        status: BatchSubmissionStatus
    ) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                ProgressView()
                    .scaleEffect(0.9)
                Text(step.label)
                    .zFont(.medium, size: 14, style: Design.Text.primary)
                    .tracking(-0.224)
            }

            if bundleCount > 1, let bundleIndex {
                Text("Bundle \(bundleIndex + 1) of \(bundleCount)")
                    .zFont(.medium, size: 12, style: Design.Text.tertiary)
                    .tracking(-0.144)
            }

            if case let .submitting(currentIndex, totalCount, _) = status, totalCount > 1 {
                Text("Vote \(currentIndex + 1) of \(totalCount)")
                    .zFont(.medium, size: 12, style: Design.Text.tertiary)
                    .tracking(-0.144)
            }
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
    private func submitCTA(status: BatchSubmissionStatus, drafts: [UInt32: VoteChoice], bundleCount: UInt32) -> some View {
        VStack(spacing: 0) {
            switch status {
            case .idle, .authorizationFailed, .submissionFailed:
                ZashiButton("Submit") {
                    store.send(.submitAllDraftsTapped(roundId: roundId))
                }
                .disabled(drafts.isEmpty || bundleCount == 0)
            case .authorizing, .submitting:
                ZashiButton(String(localizable: .coinVoteCommonSubmission)) {}
                    .disabled(true)
            case .completed:
                ZashiButton(String(localizable: .coinVoteCommonDone)) {
                    store.send(.dismissFlow)
                }
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

    // MARK: - Alert bindings

    private func authorizationErrorBinding(status: BatchSubmissionStatus) -> Binding<Bool> {
        Binding(
            get: {
                if case .authorizationFailed = status { return true }
                return false
            },
            set: { newValue in
                if !newValue {
                    store.send(.dismissBatchResults(roundId: roundId))
                }
            }
        )
    }

    private func submissionErrorBinding(status: BatchSubmissionStatus) -> Binding<Bool> {
        Binding(
            get: {
                if case .submissionFailed = status { return true }
                return false
            },
            set: { newValue in
                if !newValue {
                    store.send(.dismissBatchResults(roundId: roundId))
                }
            }
        )
    }
}

private extension BatchSubmissionStatus {
    /// True while we're actively making network/proving progress — used by
    /// the view to disable the back gesture and CTA.
    var isInFlight: Bool {
        switch self {
        case .authorizing, .submitting:
            return true
        case .idle, .completed, .authorizationFailed, .submissionFailed:
            return false
        }
    }
}
