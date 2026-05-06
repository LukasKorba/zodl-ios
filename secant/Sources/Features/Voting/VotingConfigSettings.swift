import ComposableArchitecture
import Foundation

@Reducer
struct VotingConfigSettings {
    @ObservableState
    struct State: Equatable {
        var urlInput: String = ""
        var validationStatus: ValidationStatus = .idle
        /// Holds a validated non-default URL while the non-endorsed-chain warning is visible.
        var pendingURL: String?
        /// Keeps the parsed source paired with `pendingURL` so Continue cannot persist an unvalidated edit.
        var pendingPinnedSource: PinnedConfigSource?

        /// Empty means "use the bundled hash-pinned config".
        @Shared(.appStorage(.votingConfigOverrideURL))
        var override: String = ""

        enum ValidationStatus: Equatable {
            case idle
            case validating
            case error(String)
        }
    }

    enum Action: Equatable {
        case onAppear
        case urlChanged(String)
        case saveTapped
        case validationFailed(String, rawURL: String)
        case validationPassed(PinnedConfigSource, rawURL: String, isDefault: Bool)
        case warningContinueTapped
        case warningCancelTapped
        case resetToDefaultTapped
        case dismissTapped
    }

    @Dependency(\.dismiss) var dismiss

    private enum CancelID {
        case validation
    }

    var body: some Reducer<State, Action> {
        Reduce { state, action in
            switch action {
            case .onAppear:
                state.urlInput = state.override
                state.validationStatus = .idle
                state.pendingURL = nil
                state.pendingPinnedSource = nil
                return .none

            case .urlChanged(let url):
                state.urlInput = url
                state.validationStatus = .idle
                state.pendingURL = nil
                state.pendingPinnedSource = nil
                return .cancel(id: CancelID.validation)

            case .saveTapped:
                let rawURL = state.urlInput.trimmingCharacters(in: .whitespacesAndNewlines)
                state.validationStatus = .validating
                state.pendingURL = nil
                state.pendingPinnedSource = nil

                return .run { send in
                    do {
                        let source = try PinnedConfigSource.parse(rawURL)
                        // Reuse the production static-config path so optional pins, bad pins,
                        // transport failures, decode errors, and config validation behave identically here.
                        _ = try await StaticVotingConfig.loadFromNetwork(source: source, session: .shared)
                        await send(.validationPassed(
                            source,
                            rawURL: rawURL,
                            isDefault: Self.isBundledDefault(source)
                        ))
                    } catch {
                        await send(.validationFailed(Self.message(from: error), rawURL: rawURL))
                    }
                }
                .cancellable(id: CancelID.validation, cancelInFlight: true)

            case .validationPassed(let source, let rawURL, let isDefault):
                // Ignore stale validation results if the user edited the field while the fetch was in flight.
                guard rawURL == state.urlInput.trimmingCharacters(in: .whitespacesAndNewlines) else {
                    return .none
                }
                state.validationStatus = .idle
                if isDefault {
                    // Saving the bundled source is equivalent to clearing the override.
                    state.$override.withLock { $0 = "" }
                    return .run { _ in await dismiss() }
                }
                state.pendingURL = rawURL
                state.pendingPinnedSource = source
                return .none

            case .validationFailed(let message, let rawURL):
                // A cancelled fetch can still finish; only show errors for the current input.
                guard rawURL == state.urlInput.trimmingCharacters(in: .whitespacesAndNewlines) else {
                    return .none
                }
                state.validationStatus = .error(message)
                state.pendingURL = nil
                state.pendingPinnedSource = nil
                return .none

            case .warningContinueTapped:
                // Persist only after the warning acknowledgement, which is the one-time consent gate.
                guard let pendingURL = state.pendingURL,
                      state.pendingPinnedSource != nil
                else {
                    return .none
                }
                state.$override.withLock { $0 = pendingURL }
                state.pendingURL = nil
                state.pendingPinnedSource = nil
                state.validationStatus = .idle
                return .run { _ in await dismiss() }

            case .warningCancelTapped:
                state.pendingURL = nil
                state.pendingPinnedSource = nil
                state.validationStatus = .idle
                return .none

            case .resetToDefaultTapped:
                state.$override.withLock { $0 = "" }
                state.urlInput = ""
                state.validationStatus = .idle
                state.pendingURL = nil
                state.pendingPinnedSource = nil
                return .merge(
                    .cancel(id: CancelID.validation),
                    .run { _ in await dismiss() }
                )

            case .dismissTapped:
                return .merge(
                    .cancel(id: CancelID.validation),
                    .run { _ in await dismiss() }
                )
            }
        }
    }

    private static func isBundledDefault(_ source: PinnedConfigSource) -> Bool {
        guard let bundled = try? PinnedConfigSource.parse(StaticVotingConfig.bundledPinnedSource) else {
            return false
        }
        return source.url == bundled.url
    }

    private static func message(from error: Error) -> String {
        (error as? LocalizedError)?.errorDescription ?? error.localizedDescription
    }
}
