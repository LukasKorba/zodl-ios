import XCTest
import ComposableArchitecture
@preconcurrency import ZcashLightClientKit
@testable import zashi_internal

final class AutoServerSelectionClientTests: XCTestCase {
    private final class Recorder: @unchecked Sendable {
        var switchedTo: LightWalletEndpoint?
        var persisted: UserPreferencesStorage.ServerConfig?
    }

    private func endpoint(_ host: String) -> LightWalletEndpoint {
        LightWalletEndpoint(address: host, port: 443, secure: true, streamingCallTimeoutInMillis: 0)
    }

    /// Runs `refreshIfEnabled` with controlled dependencies and returns the recorder.
    private func run(
        flag: Bool?,
        current: LightWalletEndpoint,
        best: LightWalletEndpoint?,
        guardBusy: Bool = false
    ) async -> Recorder {
        let recorder = Recorder()
        await withDependencies {
            $0.userStoredPreferences.automaticServerSelection = { flag }
            $0.userStoredPreferences.setServer = { recorder.persisted = $0 }
            $0.zcashSDKEnvironment = .testnet
            $0.zcashSDKEnvironment.network = { ZcashNetworkBuilder.network(for: .mainnet) }
            $0.zcashSDKEnvironment.endpoint = { current }
            $0.sdkSynchronizer.evaluateBestOf = { _, _, _, _, _ in best.map { [$0] } ?? [] }
            $0.sdkSynchronizer.switchToEndpoint = { recorder.switchedTo = $0 }
            $0.transactionGuard = TransactionGuardClient(
                acquire: {},
                tryAcquire: { !guardBusy },
                release: {}
            )
        } operation: {
            await AutoServerSelectionClient.liveValue.refreshIfEnabled()
        }
        return recorder
    }

    func testNoOpWhenFlagOff() async {
        let r = await run(flag: false, current: endpoint("zec.rocks"), best: endpoint("na.zec.rocks"))
        XCTAssertNil(r.switchedTo)
        XCTAssertNil(r.persisted)
    }

    func testNoSwitchWhenBestEqualsCurrent() async {
        let r = await run(flag: true, current: endpoint("zec.rocks"), best: endpoint("zec.rocks"))
        XCTAssertNil(r.switchedTo)
        XCTAssertNil(r.persisted)
    }

    func testSwitchesAndPersistsWhenIdle() async {
        let r = await run(flag: true, current: endpoint("zec.rocks"), best: endpoint("na.zec.rocks"))
        XCTAssertEqual(r.switchedTo?.host, "na.zec.rocks")
        XCTAssertEqual(r.persisted?.host, "na.zec.rocks")
        XCTAssertEqual(r.persisted?.isCustom, false)
    }

    func testSkipsWhenGuardBusy() async {
        let r = await run(flag: true, current: endpoint("zec.rocks"), best: endpoint("na.zec.rocks"), guardBusy: true)
        XCTAssertNil(r.switchedTo)
        XCTAssertNil(r.persisted)
    }
}
