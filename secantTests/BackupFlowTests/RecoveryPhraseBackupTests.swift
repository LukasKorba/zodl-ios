//
//  RecoveryFlowTests.swift
//  secantTests
//
//  Created by Francisco Gindre on 10/29/21.
//

import XCTest
@testable import zashi_internal

class RecoveryPhraseBackupTests: XCTestCase {
    /// `RecoveryPhrase.toGroups()` always splits the phrase into three equal groups
    /// (designed for the 3-column visual layout on the backup screen). For a 24-word
    /// BIP39 phrase that's three groups of eight words each.
    func testGiven24WordsBIP39ChunkItIntoThirds() throws {
        let words = [
            // group 0
            "bring", "salute", "thank",
            "require", "spirit", "toe",
            "boil", "hill",
            // group 1
            "casino", "trophy", "drink", "frown",
            "bird", "grit", "close", "morning",
            // group 2
            "bind", "cancel", "daughter", "salon",
            "quit", "pizza", "just", "garlic"
        ]
        let phrase = RecoveryPhrase(words: words.map { $0.redacted })

        let chunks = phrase.toGroups()

        XCTAssertEqual(chunks.count, 3)
        XCTAssertEqual(chunks[0].startIndex, 0)
        XCTAssertEqual(chunks[0].words, [
            "bring", "salute", "thank", "require", "spirit", "toe", "boil", "hill"
        ].map { $0.redacted })
        XCTAssertEqual(chunks[1].startIndex, 8)
        XCTAssertEqual(chunks[1].words, [
            "casino", "trophy", "drink", "frown", "bird", "grit", "close", "morning"
        ].map { $0.redacted })
        XCTAssertEqual(chunks[2].startIndex, 16)
        XCTAssertEqual(chunks[2].words, [
            "bind", "cancel", "daughter", "salon", "quit", "pizza", "just", "garlic"
        ].map { $0.redacted })
    }
}
