//
//  DecommissionedServerMigrationTests.swift
//  secantTests
//
//  Created on 2026-06-05.
//

import XCTest
@preconcurrency import ZcashLightClientKit
@testable import zashi_internal

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
}
