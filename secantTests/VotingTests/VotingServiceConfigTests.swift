import XCTest
import VotingModels

// Test fixtures contain pinned canonical JSON strings that intentionally exceed
// the project's line-length limit — keeping them single-line makes the expected
// byte output obvious and prevents accidental line-ending differences from
// changing the pinned hash.
// swiftlint:disable line_length

final class VotingServiceConfigTests: XCTestCase {

    // MARK: - Canonical JSON (ZIP 1244 §"Proposals Hash")

    /// ZIP 1244 worked example.
    private static let zipExampleProposal = VotingServiceConfig.Proposal(
        id: 1,
        title: "Approve protocol upgrade",
        description: "Approve or oppose the proposed protocol upgrade.",
        options: [
            .init(index: 0, label: "Support"),
            .init(index: 1, label: "Oppose"),
        ]
    )
    private static let zipExampleCanonical =
        #"[{"id":1,"title":"Approve protocol upgrade","description":"Approve or oppose the proposed protocol upgrade.","options":[{"index":0,"label":"Support"},{"index":1,"label":"Oppose"}]}]"#
    /// SHA-256 of the above canonical string, computed with `shasum -a 256` for reference.
    private static let zipExampleHashHex = "3f9a361d43c4ddb77ad138a091374e2e2958718e64937f33df99a09bd567e63d"

    func testCanonicalJSONMatchesZIPExample() {
        let canonical = VotingServiceConfig.canonicalProposalsJSON([Self.zipExampleProposal])
        XCTAssertEqual(canonical, Self.zipExampleCanonical)
    }

    func testComputeProposalsHashMatchesZIPExample() {
        let data = VotingServiceConfig.computeProposalsHash([Self.zipExampleProposal])
        let hex = data.map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(hex, Self.zipExampleHashHex)
    }

    func testCanonicalJSONSortsProposalsByIdAndOptionsByIndex() {
        let unsorted = [
            VotingServiceConfig.Proposal(
                id: 2,
                title: "B",
                description: "second",
                options: [.init(index: 1, label: "No"), .init(index: 0, label: "Yes")]
            ),
            VotingServiceConfig.Proposal(
                id: 1,
                title: "A",
                description: "first",
                options: [.init(index: 0, label: "X"), .init(index: 1, label: "Y")]
            ),
        ]
        let canonical = VotingServiceConfig.canonicalProposalsJSON(unsorted)
        XCTAssertEqual(
            canonical,
            #"[{"id":1,"title":"A","description":"first","options":[{"index":0,"label":"X"},{"index":1,"label":"Y"}]},{"id":2,"title":"B","description":"second","options":[{"index":0,"label":"Yes"},{"index":1,"label":"No"}]}]"#
        )
    }

    func testCanonicalJSONEscapesSpecialCharactersInStrings() {
        let proposal = VotingServiceConfig.Proposal(
            id: 1,
            title: "Quote \" and backslash \\",
            description: "tab\there",
            options: [.init(index: 0, label: "tab\there")]
        )
        let canonical = VotingServiceConfig.canonicalProposalsJSON([proposal])
        XCTAssertTrue(canonical.contains(#"\""#), "should escape double quotes")
        XCTAssertTrue(canonical.contains(#"\\"#), "should escape backslashes")
        XCTAssertTrue(canonical.contains(#"\t"#), "should escape tabs")
    }

    /// Pins the canonicalization to Rust `serde_json::to_string` byte output for a
    /// title containing `/`. Swift's `JSONSerialization` default would emit `\/`; Rust
    /// emits `/`. A mismatch here would cause every wallet to hard-fail `proposalsHashMismatch`
    /// against the chain's `proposals_hash` for any round with a slash in a title or label.
    /// The reference hash is computed from: `shasum -a 256` of the serde_json form below.
    func testCanonicalJSONDoesNotEscapeForwardSlashInTitles() {
        let proposal = VotingServiceConfig.Proposal(
            id: 1,
            title: "NU5/NU6 activation",
            description: "Should we activate NU5/NU6?",
            options: [
                .init(index: 0, label: "Yes"),
                .init(index: 1, label: "No"),
            ]
        )
        let canonical = VotingServiceConfig.canonicalProposalsJSON([proposal])
        XCTAssertEqual(
            canonical,
            #"[{"id":1,"title":"NU5/NU6 activation","description":"Should we activate NU5/NU6?","options":[{"index":0,"label":"Yes"},{"index":1,"label":"No"}]}]"#
        )
        let hex = VotingServiceConfig.computeProposalsHash([proposal])
            .map { String(format: "%02x", $0) }.joined()
        XCTAssertEqual(hex, "d4a105be1f44c96ca4abc6c952d7a6deb3f7cf4df2059a2afe4bb828b96078a1")
    }

    // MARK: - Decode regression for post-Part-E CDN JSON

    func testDecodeFromFullZIP1244CompliantJSON() throws {
        let json = """
        {
          "config_version": 1,
          "vote_round_id": "aabbccddeeff00112233445566778899aabbccddeeff00112233445566778899",
          "vote_servers": [
            {"url": "https://vote1.example.com", "label": "validator-1"}
          ],
          "pir_endpoints": [
            {"url": "https://pir1.example.com", "label": "pir-1"}
          ],
          "snapshot_height": 2800000,
          "vote_end_time": 1735689600,
          "proposals": [
            {
              "id": 1,
              "title": "Approve protocol upgrade",
              "description": "Approve or oppose the proposed protocol upgrade.",
              "options": [
                {"index": 0, "label": "Support"},
                {"index": 1, "label": "Oppose"}
              ]
            }
          ],
          "supported_versions": {
            "pir": ["v0", "v1"],
            "vote_protocol": "v0",
            "tally": "v0",
            "vote_server": "v1"
          }
        }
        """
        let data = Data(json.utf8)
        let config = try JSONDecoder().decode(VotingServiceConfig.self, from: data)

        XCTAssertEqual(config.configVersion, 1)
        XCTAssertEqual(config.voteRoundId, "aabbccddeeff00112233445566778899aabbccddeeff00112233445566778899")
        XCTAssertEqual(config.voteServers.count, 1)
        XCTAssertEqual(config.pirEndpoints.first?.label, "pir-1")
        XCTAssertEqual(config.snapshotHeight, 2_800_000)
        XCTAssertEqual(config.voteEndTime, 1_735_689_600)
        XCTAssertEqual(config.proposals.count, 1)
        XCTAssertEqual(config.proposals[0].options.count, 2)
        XCTAssertEqual(config.supportedVersions.voteServer, "v1")
        XCTAssertEqual(config.supportedVersions.pir, ["v0", "v1"])
    }

    func testDecodeFailsWhenRequiredFieldMissing() {
        let jsonMissingProposals = """
        {
          "config_version": 1,
          "vote_round_id": "aabbccddeeff00112233445566778899aabbccddeeff00112233445566778899",
          "vote_servers": [{"url": "https://x", "label": "a"}],
          "pir_endpoints": [{"url": "https://y", "label": "b"}],
          "snapshot_height": 1,
          "vote_end_time": 1,
          "supported_versions": {"pir": ["v0"], "vote_protocol": "v0", "tally": "v0", "vote_server": "v1"}
        }
        """
        XCTAssertThrowsError(
            try JSONDecoder().decode(VotingServiceConfig.self, from: Data(jsonMissingProposals.utf8))
        )
    }

    // MARK: - validate() — supported_versions enforcement

    private func makeConfig(supportedVersions: VotingServiceConfig.SupportedVersions) -> VotingServiceConfig {
        VotingServiceConfig(
            configVersion: 1,
            voteRoundId: String(repeating: "a", count: 64),
            voteServers: [.init(url: "https://x", label: "a")],
            pirEndpoints: [.init(url: "https://y", label: "b")],
            snapshotHeight: 1,
            voteEndTime: 1,
            proposals: [Self.zipExampleProposal],
            supportedVersions: supportedVersions
        )
    }

    func testValidateAcceptsCurrentWalletCapabilities() throws {
        let config = makeConfig(
            supportedVersions: .init(pir: ["v0"], voteProtocol: "v0", tally: "v0", voteServer: "v1")
        )
        XCTAssertNoThrow(try config.validate())
    }

    func testValidateRejectsUnknownVoteServer() {
        let config = makeConfig(
            supportedVersions: .init(pir: ["v0"], voteProtocol: "v0", tally: "v0", voteServer: "v99")
        )
        XCTAssertThrowsError(try config.validate()) { error in
            guard case VotingConfigError.unsupportedVersion(let component, let advertised) = error else {
                return XCTFail("expected unsupportedVersion, got \(error)")
            }
            XCTAssertEqual(component, "vote_server")
            XCTAssertEqual(advertised, "v99")
        }
    }

    func testValidateRejectsWhenPIRIntersectionIsEmpty() {
        let config = makeConfig(
            supportedVersions: .init(pir: ["v42"], voteProtocol: "v0", tally: "v0", voteServer: "v1")
        )
        XCTAssertThrowsError(try config.validate()) { error in
            guard case VotingConfigError.unsupportedVersion(let component, _) = error else {
                return XCTFail("expected unsupportedVersion, got \(error)")
            }
            XCTAssertEqual(component, "pir")
        }
    }

    func testValidateAcceptsWhenPIRIntersectionIsNonEmpty() throws {
        let config = makeConfig(
            supportedVersions: .init(pir: ["v42", "v0"], voteProtocol: "v0", tally: "v0", voteServer: "v1")
        )
        XCTAssertNoThrow(try config.validate())
    }

    func testValidateRejectsUnknownVoteProtocol() {
        let config = makeConfig(
            supportedVersions: .init(pir: ["v0"], voteProtocol: "v99", tally: "v0", voteServer: "v1")
        )
        XCTAssertThrowsError(try config.validate()) { error in
            guard case VotingConfigError.unsupportedVersion(let component, _) = error else {
                return XCTFail("expected unsupportedVersion, got \(error)")
            }
            XCTAssertEqual(component, "vote_protocol")
        }
    }

    func testValidateRejectsUnknownTally() {
        let config = makeConfig(
            supportedVersions: .init(pir: ["v0"], voteProtocol: "v0", tally: "v99", voteServer: "v1")
        )
        XCTAssertThrowsError(try config.validate()) { error in
            guard case VotingConfigError.unsupportedVersion(let component, _) = error else {
                return XCTFail("expected unsupportedVersion, got \(error)")
            }
            XCTAssertEqual(component, "tally")
        }
    }
}
// swiftlint:enable line_length
