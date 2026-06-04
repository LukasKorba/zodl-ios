//
//  ServerSetup.swift
//  Zashi
//
//  Created by Lukáš Korba on 2024-02-07.
//

import Foundation
import ComposableArchitecture
@preconcurrency import ZcashLightClientKit

extension LightWalletEndpoint: @retroactive Equatable {
    public static func == (lhs: LightWalletEndpoint, rhs: LightWalletEndpoint) -> Bool {
        lhs.host == rhs.host
        && lhs.port == rhs.port
        && lhs.streamingCallTimeoutInMillis == rhs.streamingCallTimeoutInMillis
        && lhs.singleCallTimeoutInMillis == rhs.singleCallTimeoutInMillis
        && lhs.secure == rhs.secure
    }
}

@Reducer
struct ServerSetup {
    let streamingCallTimeoutInMillis = ZcashSDKEnvironment.ZcashSDKConstants.streamingCallTimeoutInMillis

    private enum Benchmark {
        // User-visible recommendation pass: can spend longer to rank several servers.
        static let evaluationTimeoutSeconds = 60.0
        static let blocksToDownload: UInt64 = 100
        static let recommendedServerCount = 3
        static let saveCompletionDelay: DispatchQueue.SchedulerTimeType.Stride = .seconds(1)
    }

    private enum CancelID {
        case evaluateServers
        case setServer
    }

    @ObservableState
    struct State: Equatable {
        @Presents var alert: AlertState<Action>?
        var connectionMode: UserPreferencesStorage.ConnectionMode
        var customServer: String
        var isEvaluatingServers = false
        var isUpdatingServer = false
        var activeSyncServer: String = ""
        var recommendedSyncServer: String?
        var initialConnectionMode: UserPreferencesStorage.ConnectionMode
        var initialCustomServer: String = ""
        var initialSelectedServer: String?
        var network: NetworkType = .mainnet
        var serverEvaluationRequestID = 0
        var selectedServer: String?
        var servers: [ZcashSDKEnvironment.Server]
        var topKServers: [ZcashSDKEnvironment.Server]

        var hasChanges: Bool {
            let modeChanged = connectionMode != initialConnectionMode
            let serverChanged = selectedServer != initialSelectedServer
            let customLabel = String(localizable: .serverSetupCustom)
            let customChanged = connectionMode == .manual
                && selectedServer == customLabel
                && customServer != initialCustomServer
            return modeChanged || serverChanged || customChanged
        }

        init(
            connectionMode: UserPreferencesStorage.ConnectionMode = .automatic,
            customServer: String = "",
            isEvaluatingServers: Bool = false,
            isUpdatingServer: Bool = false,
            recommendedSyncServer: String? = nil,
            network: NetworkType = .mainnet,
            serverEvaluationRequestID: Int = 0,
            selectedServer: String? = nil,
            servers: [ZcashSDKEnvironment.Server] = [],
            topKServers: [ZcashSDKEnvironment.Server] = []
        ) {
            self.connectionMode = connectionMode
            self.customServer = customServer
            self.isEvaluatingServers = isEvaluatingServers
            self.isUpdatingServer = isUpdatingServer
            self.recommendedSyncServer = recommendedSyncServer
            self.initialConnectionMode = connectionMode
            self.network = network
            self.serverEvaluationRequestID = serverEvaluationRequestID
            self.selectedServer = selectedServer
            self.servers = servers
            self.topKServers = topKServers
        }
    }

    enum Action: Equatable, BindableAction {
        case alert(PresentationAction<Action>)
        case binding(BindingAction<State>)
        case connectionModeChanged(UserPreferencesStorage.ConnectionMode)
        case evaluatedServers(Int, [LightWalletEndpoint])
        case evaluateServers
        case onAppear
        case refreshServersTapped
        case serverSelected(String)
        case setServerTapped
        case switchFailed(ZcashError)
        case switchSucceeded(String)
    }

    init() {}

    @Dependency(\.mainQueue) var mainQueue
    @Dependency(\.sdkSynchronizer) var sdkSynchronizer
    @Dependency(\.zcashSDKEnvironment) var zcashSDKEnvironment
    @Dependency(\.userStoredPreferences) var userStoredPreferences
    @Dependency(\.transactionGuard) var transactionGuard

    var body: some ReducerOf<Self> {
        BindingReducer()

        Reduce { state, action in
            switch action {
            case .onAppear:
                state.network = zcashSDKEnvironment.network().networkType
                let syncConfig = zcashSDKEnvironment.serverConfig()
                state.activeSyncServer = syncConfig.serverString()
                state.recommendedSyncServer = nil

                if !state.topKServers.isEmpty {
                    let allServers = ZcashSDKEnvironment.servers(for: state.network)
                    state.servers = allServers.filter { !state.topKServers.contains($0) }
                } else {
                    state.servers = ZcashSDKEnvironment.servers(for: state.network)
                }

                // Rehydrate from stored preferences so unsaved selections don't survive navigation.
                let isAutomatic = userStoredPreferences.automaticServerSelection() ?? true
                state.connectionMode = isAutomatic ? .automatic : .manual
                state.customServer = ""
                state.selectedServer = nil
                if state.connectionMode == .manual {
                    if syncConfig.isCustom {
                        state.customServer = syncConfig.serverString()
                        state.selectedServer = String(localizable: .serverSetupCustom)
                    } else {
                        state.selectedServer = syncConfig.serverString()
                    }
                }

                state.initialConnectionMode = state.connectionMode
                state.initialSelectedServer = state.selectedServer
                state.initialCustomServer = state.customServer
                return state.topKServers.isEmpty ? .send(.evaluateServers) : .none

            case .alert(.dismiss):
                state.alert = nil
                return .none

            case .alert:
                return .none

            case .binding:
                return .none

            case .connectionModeChanged(let mode):
                guard !state.isUpdatingServer else { return .none }

                let previousMode = state.connectionMode
                state.connectionMode = mode
                if mode == .automatic {
                    state.selectedServer = state.initialSelectedServer
                    state.customServer = state.initialCustomServer
                } else if mode == .manual {
                    if previousMode != .manual && state.selectedServer == nil {
                        state.selectActiveSyncServerForManualMode()
                    }
                    if state.topKServers.isEmpty {
                        return .send(.evaluateServers)
                    }
                }
                return .none

            case .evaluateServers:
                guard !state.isUpdatingServer else { return .none }

                state.isEvaluatingServers = true
                state.serverEvaluationRequestID += 1
                let requestID = state.serverEvaluationRequestID
                let network = state.network
                return .run { send in
                    let kBestServers = await sdkSynchronizer.evaluateBestOf(
                        ZcashSDKEnvironment.endpoints(for: network),
                        0, // ignored: SDKSynchronizerLive.evaluateBestOf doesn't forward this arg to the SDK
                        Benchmark.evaluationTimeoutSeconds,
                        Benchmark.blocksToDownload,
                        Benchmark.recommendedServerCount,
                        network
                    )
                    await send(.evaluatedServers(requestID, kBestServers))
                }
                .cancellable(id: CancelID.evaluateServers, cancelInFlight: true)

            case .evaluatedServers(let requestID, let bestServers):
                guard requestID == state.serverEvaluationRequestID else { return .none }

                state.isEvaluatingServers = false
                state.topKServers = bestServers.map {
                    if ZcashSDKEnvironment.Server.default.value(for: state.network) == $0.server() {
                        ZcashSDKEnvironment.Server.default
                    } else {
                        ZcashSDKEnvironment.Server.hardcoded("\($0.host):\($0.port)")
                    }
                }
                let allServers = ZcashSDKEnvironment.servers(for: state.network)
                state.servers = allServers.filter { !state.topKServers.contains($0) }
                state.recommendedSyncServer = bestServers.first?.server()
                return .none

            case .refreshServersTapped:
                guard !state.isUpdatingServer else { return .none }
                return .send(.evaluateServers)

            case .serverSelected(let serverString):
                guard !state.isUpdatingServer else { return .none }
                state.selectedServer = serverString
                return .none

            case .setServerTapped:
                guard state.hasChanges else { return .none }

                state.isUpdatingServer = true
                let network = state.network
                let timeout = streamingCallTimeoutInMillis

                switch state.connectionMode {
                case .automatic:
                    let cachedRecommendation = state.recommendedSyncServer
                    return .run { send in
                        do {
                            let best: LightWalletEndpoint
                            if let cachedRecommendation,
                               let cached = UserPreferencesStorage.ServerConfig.endpoint(
                                   for: cachedRecommendation,
                                   streamingCallTimeoutInMillis: timeout
                               ) {
                                best = cached
                            } else {
                                let ranked = await sdkSynchronizer.evaluateBestOf(
                                    ZcashSDKEnvironment.endpoints(for: network),
                                    0, // ignored: SDKSynchronizerLive.evaluateBestOf doesn't forward this arg to the SDK
                                    Benchmark.evaluationTimeoutSeconds,
                                    Benchmark.blocksToDownload,
                                    1,
                                    network
                                )
                                best = ranked.first ?? ZcashSDKEnvironment.defaultEndpoint(for: network)
                            }

                            let current = zcashSDKEnvironment.endpoint()
                            if best.host != current.host || best.port != current.port {
                                try await transactionGuard.switchWaiting {
                                    try await withTimeout(serverSwitchTimeout) {
                                        try await sdkSynchronizer.switchToEndpoint(best)
                                    }
                                }
                            }

                            userStoredPreferences.setAutomaticServerSelection(true)
                            try userStoredPreferences.setServer(
                                UserPreferencesStorage.ServerConfig(host: best.host, port: best.port, isCustom: false)
                            )

                            try await mainQueue.sleep(for: Benchmark.saveCompletionDelay)
                            await send(.switchSucceeded("\(best.host):\(best.port)"))
                        } catch is CancellationError {
                            return
                        } catch {
                            await send(.switchFailed(error.toZcashError()))
                        }
                    }
                    .cancellable(id: CancelID.setServer, cancelInFlight: true)

                case .manual:
                    let serverString = state.selectedServer == String(localizable: .serverSetupCustom)
                        ? state.customServer
                        : (state.selectedServer ?? "")
                    let isCustom = state.selectedServer == String(localizable: .serverSetupCustom)

                    guard let endpoint = UserPreferencesStorage.ServerConfig.endpoint(
                        for: serverString,
                        streamingCallTimeoutInMillis: timeout
                    ) else {
                        state.isUpdatingServer = false
                        state.alert = AlertState.endpointSwitchFailed(ZcashError.synchronizerServerSwitch)
                        return .none
                    }

                    return .run { send in
                        do {
                            let current = zcashSDKEnvironment.endpoint()
                            if endpoint.host != current.host || endpoint.port != current.port {
                                try await transactionGuard.switchWaiting {
                                    try await withTimeout(serverSwitchTimeout) {
                                        try await sdkSynchronizer.switchToEndpoint(endpoint)
                                    }
                                }
                            }

                            userStoredPreferences.setAutomaticServerSelection(false)
                            try userStoredPreferences.setServer(
                                UserPreferencesStorage.ServerConfig(host: endpoint.host, port: endpoint.port, isCustom: isCustom)
                            )

                            try await mainQueue.sleep(for: Benchmark.saveCompletionDelay)
                            await send(.switchSucceeded("\(endpoint.host):\(endpoint.port)"))
                        } catch is CancellationError {
                            return
                        } catch {
                            await send(.switchFailed(error.toZcashError()))
                        }
                    }
                    .cancellable(id: CancelID.setServer, cancelInFlight: true)
                }

            case .switchFailed(let error):
                state.isUpdatingServer = false
                state.alert = AlertState.endpointSwitchFailed(error)
                return .none

            case .switchSucceeded(let activeServer):
                state.isUpdatingServer = false
                if state.connectionMode == .automatic {
                    state.selectedServer = nil
                    state.customServer = ""
                }
                state.initialConnectionMode = state.connectionMode
                state.initialSelectedServer = state.selectedServer
                state.initialCustomServer = state.customServer
                state.activeSyncServer = activeServer
                return .none
            }
        }
    }
}

private extension ServerSetup.State {
    /// When switching to Manual, preselect the currently-active sync server.
    mutating func selectActiveSyncServerForManualMode() {
        guard let endpoint = UserPreferencesStorage.ServerConfig.endpoint(
            for: activeSyncServer,
            streamingCallTimeoutInMillis: ZcashSDKEnvironment.ZcashSDKConstants.streamingCallTimeoutInMillis
        ) else {
            selectedServer = nil
            customServer = ""
            return
        }

        let endpointString = endpoint.server()
        let isKnown = ZcashSDKEnvironment.servers(for: network).contains { server in
            server.value(for: network) == endpointString
        }
        if isKnown {
            selectedServer = endpointString
            customServer = ""
        } else {
            selectedServer = String(localizable: .serverSetupCustom)
            customServer = endpointString
        }
    }
}

// MARK: Alerts

extension AlertState where Action == ServerSetup.Action {
    static func endpointSwitchFailed(_ error: ZcashError) -> AlertState {
        AlertState {
            TextState(String(localizable: .serverSetupAlertFailedTitle))
        } actions: {
            ButtonState(action: .alert(.dismiss)) {
                TextState(String(localizable: .generalOk))
            }
        } message: {
            TextState(String(localizable: .serverSetupAlertFailedMessage(error.detailedMessage)))
        }
    }
}

extension ServerSetup.State {
    static var initial = ServerSetup.State()
}
