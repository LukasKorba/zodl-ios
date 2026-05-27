//
//  DelegationSigningStore.swift
//  Zashi
//

import ComposableArchitecture

@Reducer
struct DelegationSigning {
    @ObservableState
    struct State: Equatable {
        let roundId: String

        init(roundId: String) {
            self.roundId = roundId
        }
    }

    enum Action: Equatable {}

    var body: some ReducerOf<Self> {
        EmptyReducer()
    }
}

import SwiftUI
/// Keystone QR signing screen for the multi-bundle delegation flow. One
/// PCZT is built per note bundle and rendered as a QR; the user signs on
/// the Keystone device, scans the signed PCZT back, and the loop advances
/// to the next bundle until all signatures are gathered.
struct DelegationSigningView: View {
    @Environment(\.colorScheme) var colorScheme
    @Dependency(\.sdkSynchronizer) var sdkSynchronizer

    @Perception.Bindable var store: StoreOf<VotingCoordFlow>
    let roundId: String

    var body: some View {
        WithPerceptionTracking {
            let session = store.roundCache[roundId]
            let status = session?.keystoneSigningStatus ?? .idle
            let bundleCount = session?.bundleCount ?? 0
            let currentBundle = session?.currentKeystoneBundleIndex ?? 0
            let pollTitle = store.allRounds.first { $0.id == roundId }?.title ?? ""
            let currentBundleMemo = Self.currentBundleMemo(
                session: session,
                pollTitle: pollTitle
            )
            let isSigningRouteActive = Self.isSigningRouteActive(store.path, roundId: roundId)

            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: 0) {
                        keystoneDeviceCard()
                            .padding(.top, 40)

                        if bundleCount > 1 {
                            multiBundleProgressCard(current: currentBundle, total: bundleCount)
                                .padding(.top, 24)
                        }

                        if let currentBundleMemo {
                            memoCard(memo: currentBundleMemo)
                                .padding(.top, 16)
                        }

                        if isSigningRouteActive {
                            qrCodeSection(status: status)
                                .padding(.top, bundleCount > 1 || currentBundleMemo != nil ? 24 : 32)

                            instructionText(status: status)
                                .padding(.top, 32)
                        }
                    }
                    .padding(.horizontal, 24)
                }

                Spacer()

                if isSigningRouteActive {
                    actionButtons(status: status)
                        .padding(.horizontal, 24)
                        .padding(.bottom, 24)
                }
            }
            .applyScreenBackground()
            .screenTitle(String(localizable: .coinVoteCommonConfirmation))
            .zashiBack {
                store.send(.delegationRejected(roundId: roundId))
            }
            .navigationBarBackButtonHidden()
            .sheet(
                store: store.scope(state: \.$keystoneScan, action: \.keystoneScan)
            ) { scanStore in
                ScanView(store: scanStore, popoverRatio: 1.075)
            }
        }
    }

    // MARK: - Keystone device card

    @ViewBuilder
    private func keystoneDeviceCard() -> some View {
        HStack(spacing: 0) {
            Asset.Assets.Partners.keystoneLogo.image
                .resizable()
                .frame(width: 24, height: 24)
                .padding(8)
                .background {
                    Circle().fill(Design.Surfaces.bgAlt.color(colorScheme))
                }
                .padding(.trailing, 12)

            VStack(alignment: .leading, spacing: 0) {
                Text(localizable: .accountsKeystone)
                    .zFont(.semiBold, size: 16, style: Design.Text.primary)

                if let address = store.selectedWalletAccount?.unifiedAddress {
                    Text(address)
                        .zFont(fontFamily: .robotoMono, size: 12, style: Design.Text.tertiary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
            }

            Spacer()

            Text(localizable: .keystoneSignWithHardware)
                .zFont(.medium, size: 12, style: Design.Utility.HyperBlue._700)
                .padding(.vertical, 2)
                .padding(.horizontal, 8)
                .background {
                    RoundedRectangle(cornerRadius: Design.Radius._2xl)
                        .fill(Design.Utility.HyperBlue._50.color(colorScheme))
                        .background {
                            RoundedRectangle(cornerRadius: Design.Radius._2xl)
                                .stroke(Design.Utility.HyperBlue._200.color(colorScheme))
                        }
                }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background {
            RoundedRectangle(cornerRadius: Design.Radius._2xl)
                .stroke(Design.Surfaces.strokeSecondary.color(colorScheme))
        }
    }

    @ViewBuilder
    private func multiBundleProgressCard(current: UInt32, total: UInt32) -> some View {
        HStack {
            Text(localizable: .coinVoteDelegationSigningCurrentBundleProgress(String(current + 1), String(total)))
                .zFont(.semiBold, size: 14, style: Design.Text.primary)
            Spacer()
        }
        .padding(Design.Spacing._xl)
        .frame(maxWidth: .infinity)
        .background(Design.Surfaces.bgPrimary.color(colorScheme))
        .clipShape(RoundedRectangle(cornerRadius: Design.Radius._2xl))
        .overlay(
            RoundedRectangle(cornerRadius: Design.Radius._2xl)
                .stroke(Design.Surfaces.strokeSecondary.color(colorScheme), lineWidth: 1)
        )
    }

    @ViewBuilder
    private func memoCard(memo: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(localizable: .coinVoteDelegationSigningMemo)
                .zFont(size: 14, style: Design.Text.tertiary)

            Text(memo)
                .zFont(.medium, size: 13, style: Design.Text.primary)
                .fixedSize(horizontal: false, vertical: true)
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

    // MARK: - QR

    @ViewBuilder
    private func qrCodeSection(status: KeystoneSigningStatus) -> some View {
        switch status {
        case .idle, .preparingRequest:
            VStack {
                ProgressView()
                    .padding(.bottom, 8)
                if case .preparingRequest = status {
                    Text(localizable: .coinVoteDelegationSigningPreparingRequestEllipsis)
                        .zFont(.medium, size: 13, style: Design.Text.tertiary)
                        .multilineTextAlignment(.center)
                }
            }
            .frame(width: 216, height: 216)
            .padding(24)
            .background {
                RoundedRectangle(cornerRadius: Design.Radius._xl)
                    .fill(Asset.Colors.ZDesign.Base.bone.color)
                    .background {
                        RoundedRectangle(cornerRadius: Design.Radius._xl)
                            .stroke(Design.Surfaces.strokeSecondary.color(colorScheme))
                    }
            }

        case .awaitingSignature:
            if let pczt = store.roundCache[roundId]?.pendingUnsignedDelegationPczt,
               let encoder = sdkSynchronizer.urEncoderForPCZT(pczt) {
                AnimatedQRCode(urEncoder: encoder, size: 216)
                    .padding(24)
                    .background {
                        RoundedRectangle(cornerRadius: Design.Radius._xl)
                            .fill(Asset.Colors.ZDesign.Base.bone.color)
                            .background {
                                RoundedRectangle(cornerRadius: Design.Radius._xl)
                                    .stroke(Design.Surfaces.strokeSecondary.color(colorScheme))
                            }
                    }
            } else {
                ProgressView()
                    .frame(width: 216, height: 216)
            }

        case .parsingSignature:
            VStack {
                ProgressView()
                Text(localizable: .coinVoteDelegationSigningParsingSignatureEllipsis)
                    .zFont(.medium, size: 13, style: Design.Text.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
            }
            .frame(width: 216, height: 216)
            .padding(24)
            .background {
                RoundedRectangle(cornerRadius: Design.Radius._xl)
                    .fill(Asset.Colors.ZDesign.Base.bone.color)
                    .background {
                        RoundedRectangle(cornerRadius: Design.Radius._xl)
                            .stroke(Design.Surfaces.strokeSecondary.color(colorScheme))
                    }
            }

        case .finalizingAuthorization:
            VStack {
                ProgressView()
                Text(localizable: .coinVoteDelegationSigningFinalizingAuthorizationEllipsis)
                    .zFont(.medium, size: 13, style: Design.Text.tertiary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
            }
            .frame(width: 216, height: 216)
            .padding(24)
            .background {
                RoundedRectangle(cornerRadius: Design.Radius._xl)
                    .fill(Asset.Colors.ZDesign.Base.bone.color)
                    .background {
                        RoundedRectangle(cornerRadius: Design.Radius._xl)
                            .stroke(Design.Surfaces.strokeSecondary.color(colorScheme))
                    }
            }

        case .failed(let message):
            VStack {
                Image(systemName: "exclamationmark.circle")
                    .font(.system(size: 32))
                    .foregroundStyle(Design.Utility.ErrorRed._500.color(colorScheme))
                    .padding(.bottom, 8)
                Text(message)
                    .zFont(.medium, size: 13, style: Design.Text.tertiary)
                    .multilineTextAlignment(.center)
            }
            .frame(width: 216, height: 216)
            .padding(24)
            .background {
                RoundedRectangle(cornerRadius: Design.Radius._xl)
                    .fill(Asset.Colors.ZDesign.Base.bone.color)
                    .background {
                        RoundedRectangle(cornerRadius: Design.Radius._xl)
                            .stroke(Design.Surfaces.strokeSecondary.color(colorScheme))
                    }
            }
        }
    }

    @ViewBuilder
    private func instructionText(status: KeystoneSigningStatus) -> some View {
        switch status {
        case .awaitingSignature:
            Text(store.roundCache[roundId]?.keystoneSigningNotice
                 ?? String(localizable: .coinVoteDelegationSigningScanSignedPCZTInstruction))
                .zFont(.medium, size: 14, style: Design.Text.primary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        default:
            EmptyView()
        }
    }

    // MARK: - Memo

    private static func currentBundleMemo(session: RoundSession?, pollTitle: String) -> String? {
        guard
            let session,
            session.bundleCount > 0
        else {
            return nil
        }

        let bundles = session.walletNotes.smartBundles().bundles
        let bundleIndex = Int(session.currentKeystoneBundleIndex)
        guard bundleIndex < Int(session.bundleCount), bundleIndex < bundles.count else {
            return nil
        }

        let bundleTotal = bundles[bundleIndex].reduce(UInt64(0)) { $0 + $1.value }
        return votingAuthorizationMemo(pollTitle: pollTitle, rawWeight: bundleTotal)
    }

    private static func isSigningRouteActive(
        _ path: StackState<VotingCoordFlow.Path.State>,
        roundId: String
    ) -> Bool {
        path.contains {
            guard case let .delegationSigning(signingState) = $0 else {
                return false
            }
            return signingState.roundId == roundId
        }
    }

    // MARK: - Action buttons

    @ViewBuilder
    private func actionButtons(status: KeystoneSigningStatus) -> some View {
        switch status {
        case .awaitingSignature:
            VStack(spacing: 12) {
                ZashiButton(String(localizable: .coinVoteDelegationSigningScanSignedPCZTCTA)) {
                    store.send(.openKeystoneSignatureScan)
                }
                if (store.roundCache[roundId]?.bundleCount ?? 0) > 1
                    && (store.roundCache[roundId]?.resolvedKeystonePrefixCount ?? 0) > 0 {
                    ZashiButton(
                        String(localizable: .coinVoteDelegationSigningSkipRemainingBundlesCTA),
                        type: .tertiary
                    ) {
                        store.send(.skipRemainingKeystoneBundles(roundId: roundId))
                    }
                }
            }
        case .failed:
            ZashiButton(String(localizable: .coinVoteCommonGoBack)) {
                store.send(.delegationRejected(roundId: roundId))
            }
        default:
            EmptyView()
        }
    }
}
