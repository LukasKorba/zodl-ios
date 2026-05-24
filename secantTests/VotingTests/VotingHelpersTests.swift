import Foundation
import XCTest
@testable import zashi_internal

final class VotingHelpersTests: XCTestCase {
    func testSmartBundlesUsesRustOrderingAndPerBundleQuantization() {
        let notes = [
            note(value: 31_568_000, position: 0),
            note(value: 26_000_000, position: 1),
            note(value: 13_000_000, position: 2),
            note(value: 12_500_000, position: 3),
            note(value: 5_000_000, position: 4),
            note(value: 4_000_000, position: 5),
            note(value: 3_000_000, position: 6),
            note(value: 3_000_000, position: 7),
            note(value: 2_000_000, position: 8),
            note(value: 1_000_000, position: 9)
        ]

        let result = notes.smartBundles()

        XCTAssertEqual(result.bundles.map { $0.map(\.position) }, [
            [0, 1, 2, 3, 4],
            [5, 6, 7, 8, 9]
        ])
        XCTAssertEqual(result.bundles.map(Self.total), [
            88_068_000,
            13_000_000
        ])
        XCTAssertEqual(result.eligibleWeight, 100_000_000)
        XCTAssertEqual(result.droppedCount, 0)
    }

    func testSmartBundlesDropsTrailingDustBundle() {
        let notes = [
            note(value: 30_000_000, position: 0),
            note(value: 20_000_000, position: 1),
            note(value: 10_000_000, position: 2),
            note(value: 10_000_000, position: 3),
            note(value: 5_000_000, position: 4),
            note(value: 1_000_000, position: 5)
        ]

        let result = notes.smartBundles()

        XCTAssertEqual(result.bundles.map { $0.map(\.position) }, [[0, 1, 2, 3, 4]])
        XCTAssertEqual(result.eligibleWeight, 75_000_000)
        XCTAssertEqual(result.droppedCount, 1)
    }

    func testVotingAuthorizationMemoUsesRawEightDecimalBundleTotal() {
        XCTAssertEqual(votingRawZecString(31_568_000), "0.31568000")
        XCTAssertEqual(
            votingAuthorizationMemo(pollTitle: "Shielded Poll", rawWeight: 31_568_000),
            "I am authorizing this hotkey managed by my wallet to vote on Shielded Poll with 0.31568000 ZEC."
        )
    }

    private static func total(_ notes: [NoteInfo]) -> UInt64 {
        notes.reduce(UInt64(0)) { $0 + $1.value }
    }

    private func note(value: UInt64, position: UInt64) -> NoteInfo {
        let byte = UInt8(position % UInt64(UInt8.max))
        return NoteInfo(
            commitment: Data(repeating: byte, count: 32),
            nullifier: Data(repeating: byte, count: 32),
            value: value,
            position: position,
            diversifier: Data(repeating: byte, count: 11),
            rho: Data(repeating: byte, count: 32),
            rseed: Data(repeating: byte, count: 32),
            scope: 0,
            ufvkStr: "ufvk-\(position)"
        )
    }
}
