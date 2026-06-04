import XCTest
import ComposableArchitecture
@preconcurrency import ZcashLightClientKit
@testable import zashi_internal

@MainActor
final class ServerSetupStoreTests: XCTestCase {
    private final class Prefs: @unchecked Sendable {
        var automatic: Bool?
        var server: UserPreferencesStorage.ServerConfig?
    }

    func testManualSaveSwitchesPersistsAndFlagsManual() async {
        let prefs = Prefs()
        let switched = LockIsolated<LightWalletEndpoint?>(nil)

        var initial = ServerSetup.State()
        initial.connectionMode = .manual
        initial.initialConnectionMode = .automatic // a real change so hasChanges is true
        initial.selectedServer = "na.zec.rocks:443"
        initial.network = .mainnet

        let store = TestStore(initialState: initial) {
            ServerSetup()
        } withDependencies: {
            $0.mainQueue = .immediate
            $0.zcashSDKEnvironment = .testnet
            $0.zcashSDKEnvironment.endpoint = {
                LightWalletEndpoint(address: "zec.rocks", port: 443, secure: true, streamingCallTimeoutInMillis: 0)
            }
            $0.sdkSynchronizer.switchToEndpoint = { switched.setValue($0) }
            $0.userStoredPreferences.setAutomaticServerSelection = { prefs.automatic = $0 }
            $0.userStoredPreferences.setServer = { prefs.server = $0 }
            $0.transactionGuard = .testValue
        }
        store.exhaustivity = .off

        await store.send(.setServerTapped)
        await store.receive(\.switchSucceeded)

        XCTAssertEqual(switched.value?.host, "na.zec.rocks")
        XCTAssertEqual(prefs.automatic, false)
        XCTAssertEqual(prefs.server?.host, "na.zec.rocks")
        XCTAssertEqual(prefs.server?.isCustom, false)
    }

    func testAutomaticSaveFlagsAutomatic() async {
        let prefs = Prefs()

        var initial = ServerSetup.State()
        initial.connectionMode = .automatic
        initial.initialConnectionMode = .manual // a real change
        initial.recommendedSyncServer = "na.zec.rocks:443"
        initial.network = .mainnet

        let store = TestStore(initialState: initial) {
            ServerSetup()
        } withDependencies: {
            $0.mainQueue = .immediate
            $0.zcashSDKEnvironment = .testnet
            $0.zcashSDKEnvironment.endpoint = {
                LightWalletEndpoint(address: "zec.rocks", port: 443, secure: true, streamingCallTimeoutInMillis: 0)
            }
            $0.sdkSynchronizer.switchToEndpoint = { _ in }
            $0.sdkSynchronizer.evaluateBestOf = { _, _, _, _, _ in [] }
            $0.userStoredPreferences.setAutomaticServerSelection = { prefs.automatic = $0 }
            $0.userStoredPreferences.setServer = { prefs.server = $0 }
            $0.transactionGuard = .testValue
        }
        store.exhaustivity = .off

        await store.send(.setServerTapped)
        await store.receive(\.switchSucceeded)

        XCTAssertEqual(prefs.automatic, true)
        XCTAssertEqual(prefs.server?.host, "na.zec.rocks")
    }

    func testNoChangesDoesNothing() async {
        let store = TestStore(initialState: ServerSetup.State()) {
            ServerSetup()
        } withDependencies: {
            $0.transactionGuard = .testValue
        }
        // connectionMode == initialConnectionMode and no selection -> hasChanges is false
        await store.send(.setServerTapped)
    }

    func testOnAppearClearsStuckUpdatingFlag() async {
        var initial = ServerSetup.State()
        initial.isUpdatingServer = true   // a previous switch that hung or was cancelled left this set
        initial.network = .mainnet
        initial.topKServers = [.default]  // non-empty so onAppear doesn't kick off an evaluation

        let store = TestStore(initialState: initial) {
            ServerSetup()
        } withDependencies: {
            $0.zcashSDKEnvironment = .testnet
            $0.zcashSDKEnvironment.network = { ZcashNetworkBuilder.network(for: .mainnet) }
            $0.zcashSDKEnvironment.serverConfig = {
                UserPreferencesStorage.ServerConfig(host: "zec.rocks", port: 443, isCustom: false)
            }
            $0.userStoredPreferences.automaticServerSelection = { true }
        }
        store.exhaustivity = .off

        await store.send(.onAppear)

        XCTAssertFalse(store.state.isUpdatingServer, "onAppear must clear a stuck isUpdatingServer flag so the screen isn't wedged")
    }
}
