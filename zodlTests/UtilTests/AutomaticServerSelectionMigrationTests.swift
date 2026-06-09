import XCTest
import ComposableArchitecture
@preconcurrency import ZcashLightClientKit
@testable import zodl_internal

final class AutomaticServerSelectionMigrationTests: XCTestCase {
    /// In-memory stand-in for the parts of `userStoredPreferences` the migration touches.
    private final class Box: @unchecked Sendable {
        var server: UserPreferencesStorage.ServerConfig?
        var flag: Bool?
        init(server: UserPreferencesStorage.ServerConfig?) { self.server = server }
    }

    private func runMigration(network: NetworkType, server: UserPreferencesStorage.ServerConfig?) -> Bool? {
        let box = Box(server: server)
        withDependencies {
            $0.userStoredPreferences.server = { box.server }
            $0.userStoredPreferences.automaticServerSelection = { box.flag }
            $0.userStoredPreferences.setAutomaticServerSelection = { box.flag = $0 }
        } operation: {
            ZcashSDKEnvironment.initializeAutomaticServerSelectionIfNeeded(for: network)
        }
        return box.flag
    }

    func testNoStoredServerEnablesAutomatic() {
        XCTAssertEqual(runMigration(network: .mainnet, server: nil), true)
    }

    func testDefaultServerEnablesAutomatic() {
        let def = ZcashSDKEnvironment.defaultEndpoint(for: .mainnet)
        let config = UserPreferencesStorage.ServerConfig(host: def.host, port: def.port, isCustom: false)
        XCTAssertEqual(runMigration(network: .mainnet, server: config), true)
    }

    func testCustomServerSelectsManual() {
        let config = UserPreferencesStorage.ServerConfig(host: "my.server.example", port: 9067, isCustom: true)
        XCTAssertEqual(runMigration(network: .mainnet, server: config), false)
    }

    func testNonDefaultKnownServerSelectsManual() {
        let config = UserPreferencesStorage.ServerConfig(host: "na.zec.rocks", port: 443, isCustom: false)
        XCTAssertEqual(runMigration(network: .mainnet, server: config), false)
    }

    func testRunsOnlyOnce() {
        let box = Box(server: nil)
        box.flag = false // pretend the user already chose Manual
        withDependencies {
            $0.userStoredPreferences.server = { box.server }
            $0.userStoredPreferences.automaticServerSelection = { box.flag }
            $0.userStoredPreferences.setAutomaticServerSelection = { box.flag = $0 }
        } operation: {
            ZcashSDKEnvironment.initializeAutomaticServerSelectionIfNeeded(for: .mainnet)
        }
        XCTAssertEqual(box.flag, false, "Migration must not overwrite an already-set flag")
    }
}
