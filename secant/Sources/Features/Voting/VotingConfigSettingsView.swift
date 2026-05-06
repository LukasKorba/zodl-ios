import SwiftUI
import ComposableArchitecture

struct VotingConfigSettingsView: View {
    let store: StoreOf<VotingConfigSettings>

    var body: some View {
        WithPerceptionTracking {
            ScrollView {
                VStack(alignment: .leading, spacing: 24) {
                    header
                    activeConfig
                    urlInput
                    actions
                }
                .padding(.horizontal, 24)
                .padding(.top, 32)
                .padding(.bottom, 24)
            }
            .applyScreenBackground()
            .onAppear {
                store.send(.onAppear)
            }
            .votingSheet(
                isPresented: warningPresented,
                iconSystemName: "exclamationmark.triangle",
                title: "Not endorsed by Zodl",
                message: "This voting chain is not endorsed by Zodl. Polls served from a non-endorsed chain are not gated by the Zodl approval key.",
                primary: .init(title: "Continue", style: .primary) {
                    store.send(.warningContinueTapped)
                },
                secondary: .init(title: "Cancel", style: .secondary) {
                    store.send(.warningCancelTapped)
                }
            )
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text("Voting chain config")
                .zFont(.semiBold, size: 22, style: Design.Text.primary)

            Spacer()

            Button {
                store.send(.dismissTapped)
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 16, weight: .semibold))
                    .zForegroundColor(Design.Text.tertiary)
                    .frame(width: 32, height: 32)
            }
            .accessibilityLabel("Cancel")
        }
    }

    private var activeConfig: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text("Currently active")
                    .zFont(.medium, size: 14, style: Design.Text.primary)

                configPill
            }

            Text(activeURL)
                .zFont(size: 13, style: Design.Text.secondary)
                .lineLimit(3)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .padding(16)
        .background {
            RoundedRectangle(cornerRadius: Design.Radius._lg)
                .fill(Design.Surfaces.bgSecondary.color(colorScheme))
        }
    }

    private var configPill: some View {
        Text(hasOverride ? "Custom" : "Default")
            .zFont(.semiBold, size: 12, style: hasOverride ? Design.Surfaces.bgPrimary : Design.Text.tertiary)
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background {
                Capsule()
                    .fill(hasOverride ? Asset.Colors.primary.color : Design.Surfaces.bgTertiary.color(colorScheme))
            }
    }

    private var urlInput: some View {
        VStack(alignment: .leading, spacing: 8) {
            ZashiTextField(
                text: urlBinding,
                placeholder: "https://example.com/static-voting-config.json?checksum=sha256:HEX",
                title: "Static config URL",
                error: validationError
            )
            .keyboardType(.URL)
            .textInputAutocapitalization(.never)
            .autocorrectionDisabled()

            Text("Pin is optional. If present, it is checked against the response body's SHA-256 hash.")
                .zFont(size: 13, style: Design.Text.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var actions: some View {
        VStack(spacing: 12) {
            ZashiButton(saveTitle) {
                store.send(.saveTapped)
            }
            .disabled(saveDisabled)

            if hasOverride {
                ZashiButton("Reset to default", type: .secondary) {
                    store.send(.resetToDefaultTapped)
                }
            }
        }
    }

    private var urlBinding: Binding<String> {
        Binding(
            get: { store.urlInput },
            set: { store.send(.urlChanged($0)) }
        )
    }

    private var warningPresented: Binding<Bool> {
        Binding(
            get: { store.pendingURL != nil },
            set: { newValue in
                if !newValue && store.pendingURL != nil {
                    store.send(.warningCancelTapped)
                }
            }
        )
    }

    @Environment(\.colorScheme)
    private var colorScheme

    private var activeURL: String {
        hasOverride ? store.override : StaticVotingConfig.bundledPinnedSource
    }

    private var hasOverride: Bool {
        !store.override.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private var validationError: String? {
        if case .error(let message) = store.validationStatus {
            return message
        }
        return nil
    }

    private var saveDisabled: Bool {
        store.urlInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isValidating
    }

    private var saveTitle: String {
        isValidating ? "Validating..." : "Save"
    }

    private var isValidating: Bool {
        store.validationStatus == .validating
    }
}

#Preview {
    VotingConfigSettingsView(
        store: Store(
            initialState: VotingConfigSettings.State()
        ) {
            VotingConfigSettings()
        }
    )
}
