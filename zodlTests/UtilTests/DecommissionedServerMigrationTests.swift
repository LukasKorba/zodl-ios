//
//  DecommissionedServerMigrationTests.swift
//  secantTests
//
//  Created on 2026-06-05.
//

import XCTest
import ComposableArchitecture
@preconcurrency import ZcashLightClientKit
@testable import zodl_internal

final class DecommissionedServerMigrationTests: XCTestCase {
    // MARK: - Removal of decommissioned servers

    func test_endpoints_doNotContainDecommissionedServers() {
        let hosts = ZcashSDKEnvironment.endpoints().map { $0.host }

        XCTAssertFalse(hosts.contains("eu2.zec.stardust.rest"), "eu2.zec.stardust.rest must be removed from endpoints()")
        XCTAssertFalse(hosts.contains("jp.zec.stardust.rest"), "jp.zec.stardust.rest must be removed from endpoints()")

        let mainnetServers = ZcashSDKEnvironment.servers(for: .mainnet)
        XCTAssertFalse(mainnetServers.contains(.hardcoded("eu2.zec.stardust.rest:443")), "eu2 must be removed from servers(for:)")
        XCTAssertFalse(mainnetServers.contains(.hardcoded("jp.zec.stardust.rest:443")), "jp must be removed from servers(for:)")
    }

    // MARK: - Helpers

    private static let suiteName = "DecommissionedServerMigrationTests"

    /// A real `UserPreferencesStorage` backed by an isolated, cleared UserDefaults suite (stateful).
    private func makeStorage() throws -> UserPreferencesStorage {
        let suite = try XCTUnwrap(UserDefaults(suiteName: Self.suiteName))
        let storage = UserPreferencesStorage(
            defaultExchangeRate: Data(),
            defaultServer: Data(),
            userDefaults: .live(userDefaults: suite)
        )
        storage.removeAll()
        return storage
    }

    /// Wraps the storage in a `UserPreferencesStorageClient`, mirroring `UserPreferencesStorageLive.live()`.
    private func client(_ storage: UserPreferencesStorage) -> UserPreferencesStorageClient {
        UserPreferencesStorageClient(
            server: { storage.server },
            setServer: { try storage.setServer($0) },
            exchangeRate: { storage.exchangeRate },
            setExchangeRate: { try storage.setExchangeRate($0) },
            removeAll: { storage.removeAll() }
        )
    }

    private var mainnetDefault: UserPreferencesStorage.ServerConfig {
        UserPreferencesStorage.ServerConfig(host: "zec.rocks", port: 443, isCustom: false)
    }

    // MARK: - Rule 1: default server -> no migration

    func test_noStoredServer_noMigration() throws {
        let storage = try makeStorage()

        withDependencies {
            $0.userStoredPreferences = client(storage)
        } operation: {
            ZcashSDKEnvironment.migrateDecommissionedServersIfNeeded(for: .mainnet)
        }

        XCTAssertNil(storage.server)
    }

    func test_storedDefaultServer_noMigration() throws {
        let storage = try makeStorage()
        try storage.setServer(mainnetDefault)

        withDependencies {
            $0.userStoredPreferences = client(storage)
        } operation: {
            ZcashSDKEnvironment.migrateDecommissionedServersIfNeeded(for: .mainnet)
        }

        XCTAssertEqual(storage.server, mainnetDefault)
    }

    // MARK: - Rule 2: manual server, not removed -> no migration

    func test_manualServerNotRemoved_noMigration() throws {
        let storage = try makeStorage()
        let original = UserPreferencesStorage.ServerConfig(host: "na.zec.rocks", port: 443, isCustom: false)
        try storage.setServer(original)

        withDependencies {
            $0.userStoredPreferences = client(storage)
        } operation: {
            ZcashSDKEnvironment.migrateDecommissionedServersIfNeeded(for: .mainnet)
        }

        XCTAssertEqual(storage.server, original)
    }

    // MARK: - Rule 3: manual server, removed -> migrate to default

    func test_manualServerRemoved_eu2_migratesToDefault() throws {
        let storage = try makeStorage()
        try storage.setServer(UserPreferencesStorage.ServerConfig(host: "eu2.zec.stardust.rest", port: 443, isCustom: false))

        withDependencies {
            $0.userStoredPreferences = client(storage)
        } operation: {
            ZcashSDKEnvironment.migrateDecommissionedServersIfNeeded(for: .mainnet)
        }

        XCTAssertEqual(storage.server, mainnetDefault)
    }

    func test_manualServerRemoved_jp_migratesToDefault() throws {
        let storage = try makeStorage()
        try storage.setServer(UserPreferencesStorage.ServerConfig(host: "jp.zec.stardust.rest", port: 443, isCustom: false))

        withDependencies {
            $0.userStoredPreferences = client(storage)
        } operation: {
            ZcashSDKEnvironment.migrateDecommissionedServersIfNeeded(for: .mainnet)
        }

        XCTAssertEqual(storage.server, mainnetDefault)
    }

    // MARK: - Rule 4: custom server, other URL -> no migration

    func test_customServerOther_noMigration() throws {
        let storage = try makeStorage()
        let original = UserPreferencesStorage.ServerConfig(host: "my.custom.node", port: 443, isCustom: true)
        try storage.setServer(original)

        withDependencies {
            $0.userStoredPreferences = client(storage)
        } operation: {
            ZcashSDKEnvironment.migrateDecommissionedServersIfNeeded(for: .mainnet)
        }

        XCTAssertEqual(storage.server, original)
    }

    // MARK: - Rule 5: custom server, exact decommissioned URL -> migrate to default

    func test_customServerExact_eu2_migratesToDefault() throws {
        let storage = try makeStorage()
        try storage.setServer(UserPreferencesStorage.ServerConfig(host: "eu2.zec.stardust.rest", port: 443, isCustom: true))

        withDependencies {
            $0.userStoredPreferences = client(storage)
        } operation: {
            ZcashSDKEnvironment.migrateDecommissionedServersIfNeeded(for: .mainnet)
        }

        XCTAssertEqual(storage.server, mainnetDefault)
    }

    func test_customServerExact_jp_migratesToDefault() throws {
        let storage = try makeStorage()
        try storage.setServer(UserPreferencesStorage.ServerConfig(host: "jp.zec.stardust.rest", port: 443, isCustom: true))

        withDependencies {
            $0.userStoredPreferences = client(storage)
        } operation: {
            ZcashSDKEnvironment.migrateDecommissionedServersIfNeeded(for: .mainnet)
        }

        XCTAssertEqual(storage.server, mainnetDefault)
    }

    // MARK: - Edge: decommissioned host on a non-443 port -> no migration ("exactly :443")

    func test_customDecommissionedHost_nonDefaultPort_noMigration() throws {
        let storage = try makeStorage()
        let original = UserPreferencesStorage.ServerConfig(host: "eu2.zec.stardust.rest", port: 9067, isCustom: true)
        try storage.setServer(original)

        withDependencies {
            $0.userStoredPreferences = client(storage)
        } operation: {
            ZcashSDKEnvironment.migrateDecommissionedServersIfNeeded(for: .mainnet)
        }

        XCTAssertEqual(storage.server, original)
    }

    // MARK: - Edge: testnet user on a decommissioned custom URL -> migrate to testnet default

    func test_testnetCustomDecommissioned_migratesToTestnetDefault() throws {
        let storage = try makeStorage()
        try storage.setServer(UserPreferencesStorage.ServerConfig(host: "eu2.zec.stardust.rest", port: 443, isCustom: true))

        withDependencies {
            $0.userStoredPreferences = client(storage)
        } operation: {
            ZcashSDKEnvironment.migrateDecommissionedServersIfNeeded(for: .testnet)
        }

        XCTAssertEqual(storage.server, UserPreferencesStorage.ServerConfig(host: "testnet.zec.rocks", port: 443, isCustom: false))
    }

    // MARK: - Idempotency

    func test_migrationIsIdempotent() throws {
        let storage = try makeStorage()
        try storage.setServer(UserPreferencesStorage.ServerConfig(host: "jp.zec.stardust.rest", port: 443, isCustom: true))

        let prefsClient = client(storage)
        withDependencies {
            $0.userStoredPreferences = prefsClient
        } operation: {
            ZcashSDKEnvironment.migrateDecommissionedServersIfNeeded(for: .mainnet)
            ZcashSDKEnvironment.migrateDecommissionedServersIfNeeded(for: .mainnet)
        }

        XCTAssertEqual(storage.server, mainnetDefault)
    }

    // MARK: - Integration: serverConfig(for:) returns the default after migrating

    func test_serverConfig_returnsDefault_afterMigratingDecommissionedServer() throws {
        let storage = try makeStorage()
        try storage.setServer(UserPreferencesStorage.ServerConfig(host: "eu2.zec.stardust.rest", port: 443, isCustom: false))

        let result = withDependencies {
            $0.userStoredPreferences = client(storage)
            $0.userDefaults = .noOp
        } operation: {
            ZcashSDKEnvironment.serverConfig(for: .mainnet)
        }

        XCTAssertEqual(result, mainnetDefault, "serverConfig(for:) must return the default that the SDK Initializer will use")
        XCTAssertEqual(storage.server, mainnetDefault, "the migration must be persisted")
    }
}
