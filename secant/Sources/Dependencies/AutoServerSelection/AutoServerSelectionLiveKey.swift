//
//  AutoServerSelectionLiveKey.swift
//  Zashi
//

import ComposableArchitecture
@preconcurrency import ZcashLightClientKit

extension AutoServerSelectionClient: DependencyKey {
    static let liveValue = AutoServerSelectionClient(
        refreshIfEnabled: {
            @Dependency(\.userStoredPreferences) var userStoredPreferences
            @Dependency(\.zcashSDKEnvironment) var zcashSDKEnvironment
            @Dependency(\.sdkSynchronizer) var sdkSynchronizer
            @Dependency(\.transactionGuard) var transactionGuard

            guard userStoredPreferences.automaticServerSelection() == true else { return }

            let network = zcashSDKEnvironment.network().networkType
            let endpoints = ZcashSDKEnvironment.endpoints(for: network)

            let ranked = await sdkSynchronizer.evaluateBestOf(
                endpoints,
                0, // ignored: SDKSynchronizerLive.evaluateBestOf doesn't forward this arg to the SDK
                AutoServerSelectionConstants.evaluationTimeoutSeconds,
                AutoServerSelectionConstants.blocksToDownload,
                AutoServerSelectionConstants.candidateCount,
                network
            )

            guard let best = ranked.first else { return }

            let current = zcashSDKEnvironment.endpoint()
            guard best.host != current.host || best.port != current.port else { return }

            // The user may have switched to Manual while the benchmark was running.
            guard userStoredPreferences.automaticServerSelection() == true else { return }

            do {
                let didSwitch = try await transactionGuard.switchIfIdle {
                    try await withTimeout(serverSwitchTimeout) {
                        try await sdkSynchronizer.switchToEndpoint(best)
                    }
                }
                guard didSwitch else { return }

                try userStoredPreferences.setServer(
                    UserPreferencesStorage.ServerConfig(host: best.host, port: best.port, isCustom: false)
                )
            } catch {
                LoggerProxy.error("[AutoServerSelection] Failed to switch endpoint: \(error)")
            }
        }
    )
}
