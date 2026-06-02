import XCTest
import ComposableArchitecture
@testable import zashi_internal

final class AutomaticServerSelectionStorageTests: XCTestCase {
    func testFlagDefaultsToNilThenRoundTrips() {
        let storage = UserPreferencesStorage(
            defaultExchangeRate: Data(),
            defaultServer: Data(),
            userDefaults: .ephemeralForTests()
        )

        XCTAssertNil(storage.automaticServerSelection, "Flag must be nil before it is ever set")

        storage.setAutomaticServerSelection(true)
        XCTAssertEqual(storage.automaticServerSelection, true)

        storage.setAutomaticServerSelection(false)
        XCTAssertEqual(storage.automaticServerSelection, false)
    }
}

private extension UserDefaultsClient {
    /// An in-memory `UserDefaultsClient` backed by a dictionary, for tests that need real read/write
    /// without touching `UserDefaults.standard`.
    static func ephemeralForTests() -> UserDefaultsClient {
        let storage = LockIsolated<[String: Any]>([:])
        return UserDefaultsClient(
            objectForKey: { storage.value[$0] },
            remove: { key in storage.withValue { $0.removeValue(forKey: key) } },
            setValue: { value, key in storage.withValue { $0[key] = value } }
        )
    }
}
