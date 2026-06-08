//
//  HomeTests.swift
//  secantTests
//
//  Created by Lukáš Korba on 02.06.2022.
//

@preconcurrency import Combine
import XCTest
import ComposableArchitecture
@testable import zodl_internal
@testable @preconcurrency import ZcashLightClientKit

class HomeTests: XCTestCase {
    @MainActor func testSynchronizerErrorBringsUpAlert() async {
        let testError = ZcashError.synchronizerNotPrepared

        var state = SynchronizerState.zero
        state.syncStatus = .error(testError)
        
        let store = TestStore(
            initialState: .initial
        ) {
            Home()
        }

        await store.send(.synchronizerStateChanged(state.redacted))

        await store.receive(.showSynchronizerErrorAlert(testError))
        
        await store.finish()
    }
}
