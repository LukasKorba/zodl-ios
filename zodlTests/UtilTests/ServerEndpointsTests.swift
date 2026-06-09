import XCTest
@preconcurrency import ZcashLightClientKit
@testable import zodl_internal

final class ServerEndpointsTests: XCTestCase {
    func testTestnetReturnsOnlyDefault() {
        let endpoints = ZcashSDKEnvironment.endpoints(for: .testnet)
        XCTAssertEqual(endpoints.count, 1)
        XCTAssertEqual(endpoints.first?.host, ZcashSDKEnvironment.defaultEndpoint(for: .testnet).host)
    }

    func testTestnetSkipDefaultIsEmpty() {
        XCTAssertTrue(ZcashSDKEnvironment.endpoints(for: .testnet, skipDefault: true).isEmpty)
    }

    func testMainnetContainsKnownServersWithSecureAndTimeout() {
        let endpoints = ZcashSDKEnvironment.endpoints(for: .mainnet)
        XCTAssertTrue(endpoints.contains { $0.host == "zec.rocks" && $0.port == 443 })
        XCTAssertTrue(endpoints.contains { $0.host == "eu.zec.stardust.rest" })
        XCTAssertTrue(endpoints.allSatisfy { $0.secure })
        XCTAssertTrue(endpoints.allSatisfy {
            $0.streamingCallTimeoutInMillis == ZcashSDKEnvironment.ZcashSDKConstants.streamingCallTimeoutInMillis
        })
    }

    func testMainnetSkipDefaultExcludesDefaultHost() {
        let endpoints = ZcashSDKEnvironment.endpoints(for: .mainnet, skipDefault: true)
        XCTAssertFalse(endpoints.contains { $0.host == "zec.rocks" })
    }
}
