import CryptoKit
import Foundation
@preconcurrency import ZcashLightClientKit
import XCTest
@testable import zodl_internal

final class VotingServiceConfigTests: XCTestCase {
    func testDecodeFromFullZIP1244CompliantJSON() throws {
        let json = """
        {
          "config_version": 1,
          "vote_servers": [
            {"url": "https://vote1.example.com", "label": "validator-1"}
          ],
          "pir_endpoints": [
            {"url": "https://pir1.example.com", "label": "pir-1"}
          ],
          "supported_versions": {
            "pir": ["v0", "v1"],
            "vote_protocol": "v0",
            "tally": "v0",
            "vote_server": "v1"
          },
          "rounds": {}
        }
        """
        let config = try JSONDecoder().decode(VotingServiceConfig.self, from: Data(json.utf8))

        XCTAssertEqual(config.configVersion, 1)
        XCTAssertEqual(config.voteServers.count, 1)
        XCTAssertEqual(config.pirEndpoints.first?.label, "pir-1")
        XCTAssertEqual(config.supportedVersions.voteServer, "v1")
        XCTAssertEqual(config.supportedVersions.pir, ["v0", "v1"])
    }

    func testDecodeAcceptsConfigWithoutProposalsSnapshotOrDeadline() {
        let json = """
        {
          "config_version": 1,
          "vote_servers": [{"url": "https://x", "label": "a"}],
          "pir_endpoints": [{"url": "https://y", "label": "b"}],
          "supported_versions": {"pir": ["v0"], "vote_protocol": "v0", "tally": "v0", "vote_server": "v1"},
          "rounds": {}
        }
        """

        XCTAssertNoThrow(try JSONDecoder().decode(VotingServiceConfig.self, from: Data(json.utf8)))
    }

    func testDecodeAcceptsEmptyRoundsRegistry() throws {
        let config = try JSONDecoder().decode(VotingServiceConfig.self, from: Data("""
        {
          "config_version": 1,
          "vote_servers": [{"url": "https://x", "label": "a"}],
          "pir_endpoints": [{"url": "https://y", "label": "b"}],
          "supported_versions": {"pir": ["v0"], "vote_protocol": "v0", "tally": "v0", "vote_server": "v1"},
          "rounds": {}
        }
        """.utf8))

        XCTAssertTrue(config.rounds.isEmpty)
        XCTAssertNoThrow(try config.validate())
    }

    func testValidateRejectsNonHexRoundId() {
        let config = VotingServiceConfig(
            configVersion: 1,
            voteServers: [.init(url: "https://x", label: "a")],
            pirEndpoints: [.init(url: "https://y", label: "b")],
            supportedVersions: .init(pir: ["v0"], voteProtocol: "v0", tally: "v0", voteServer: "v1"),
            rounds: [
                String(repeating: "z", count: 64): .init(
                    authVersion: 1,
                    eaPk: Data(repeating: 0x01, count: 32),
                    signatures: []
                )
            ]
        )

        XCTAssertThrowsError(try config.validate())
    }

    func testStaticConfigValidationRejectsShortTrustedKey() {
        let config = makeStaticConfig(trustedKeyBytes: Data(repeating: 0x01, count: 31))

        XCTAssertThrowsError(try config.validate())
    }

    func testPinnedConfigSourceParseAcceptsCosmovisorChecksumAndStripsIt() throws {
        let hex = String(repeating: "0a", count: 32)
        let source = try PinnedConfigSource.parse(
            "https://example.com/static-voting-config.json?foo=bar&checksum=sha256:\(hex)&baz=qux"
        )

        XCTAssertEqual(source.url.absoluteString, "https://example.com/static-voting-config.json?foo=bar&baz=qux")
        XCTAssertEqual(source.sha256?.count, 32)
        XCTAssertEqual(source.sha256?.first, 0x0a)
    }

    func testPinnedConfigSourceParseAcceptsMissingChecksum() throws {
        let source = try PinnedConfigSource.parse("https://example.com/static-voting-config.json")

        XCTAssertEqual(source.url.absoluteString, "https://example.com/static-voting-config.json")
        XCTAssertNil(source.sha256)
    }

    func testPinnedConfigSourceParseRejectsMalformedSources() {
        let validHex = String(repeating: "0a", count: 32)
        let cases = [
            "https://example.com/static-voting-config.json?checksum=sha512:\(validHex)",
            "https://example.com/static-voting-config.json?checksum=sha256:\(String(repeating: "0A", count: 32))",
            "https://example.com/static-voting-config.json?checksum=sha256:\(String(repeating: "0g", count: 32))",
            "https://example.com/static-voting-config.json?checksum=sha256:\(String(repeating: "0a", count: 31))",
            "not a url?checksum=sha256:\(validHex)"
        ]

        for raw in cases {
            XCTAssertThrowsError(try PinnedConfigSource.parse(raw), raw) { error in
                guard case VotingConfigError.staticConfigSourceMalformed = error else {
                    return XCTFail("expected malformed source, got \(error)")
                }
            }
        }
    }

    func testStaticConfigDecodeAndVerifyAcceptsMatchingSHA256() throws {
        let config = makeStaticConfig()
        let data = try JSONEncoder().encode(config)
        let sha256 = Data(SHA256.hash(data: data))

        let decoded = try StaticVotingConfig.decodeAndVerify(data: data, expectedSHA256: sha256)

        XCTAssertEqual(decoded, config)
    }

    func testStaticConfigDecodeAndVerifyRejectsHashMismatch() throws {
        let data = try JSONEncoder().encode(makeStaticConfig())

        XCTAssertThrowsError(
            try StaticVotingConfig.decodeAndVerify(data: data, expectedSHA256: Data(repeating: 0, count: 32))
        ) { error in
            guard case VotingConfigError.staticConfigHashMismatch = error else {
                return XCTFail("expected hash mismatch, got \(error)")
            }
        }
    }

    func testStaticConfigDecodeAndVerifyStillValidatesDecodedConfig() throws {
        let config = makeStaticConfig(trustedKeyBytes: Data(repeating: 0x01, count: 31))
        let data = try JSONEncoder().encode(config)
        let sha256 = Data(SHA256.hash(data: data))

        XCTAssertThrowsError(try StaticVotingConfig.decodeAndVerify(data: data, expectedSHA256: sha256))
    }

    func testValidateAcceptsCurrentWalletCapabilities() {
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

    func testValidateAcceptsWhenPIRIntersectionIsNonEmpty() {
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

    private func makeConfig(supportedVersions: VotingServiceConfig.SupportedVersions) -> VotingServiceConfig {
        VotingServiceConfig(
            configVersion: 1,
            voteServers: [.init(url: "https://x", label: "a")],
            pirEndpoints: [.init(url: "https://y", label: "b")],
            supportedVersions: supportedVersions,
            rounds: [:]
        )
    }

    private func makeStaticConfig(
        trustedKeyBytes: Data = Data(repeating: 0x01, count: 32)
    ) -> StaticVotingConfig {
        StaticVotingConfig(
            staticConfigVersion: 1,
            dynamicConfigURL: URL(string: "https://example.com/dynamic-voting-config.json")!,
            trustedKeys: [
                .init(keyId: "test", alg: "ed25519", pubkey: trustedKeyBytes, notes: nil)
            ]
        )
    }
}

final class RoundAuthenticatorTests: XCTestCase {
    private let roundId = "58d9319ac86933b81769a7c0972444fa39212ad3790646398de6ce6534de2225"
    private let eaPK = Data(base64Encoded: "N72oXeIF96QwWBtChaCwde3tjTt75ZfAs455V4usYwM=")!
    private let adminPubkey = Data(base64Encoded: "rKDbmhkoW9ja7dMiCV+1uTao7wXWV6xN/57erkrOuiQ=")!
    private let adminSignature = Data(
        base64Encoded: "rnll+KsHIFt73GpyNoWrX57dlcX8hTi8GU5X/xpwg3vcE+jCARUXpD7LsK+OLw6R5q1kU/zccwNgzsmclt4WAg=="
    )!

    func testAuthenticateAcceptsFixtureFromDynamicConfig() {
        XCTAssertEqual(
            RoundAuthenticator.authenticate(
                chainEaPK: eaPK,
                roundIdHex: roundId,
                rounds: [roundId: makeEntry()],
                trustedKeys: [makeTrustedKey()]
            ),
            .authenticated
        )
    }

    func testAuthenticateReportsMissingRound() {
        XCTAssertEqual(
            RoundAuthenticator.authenticate(
                chainEaPK: eaPK,
                roundIdHex: roundId,
                rounds: [:],
                trustedKeys: [makeTrustedKey()]
            ),
            .missingRound
        )
    }

    func testAuthenticateReportsUnknownAuthVersion() {
        XCTAssertEqual(
            RoundAuthenticator.authenticate(
                chainEaPK: eaPK,
                roundIdHex: roundId,
                rounds: [roundId: makeEntry(authVersion: 2)],
                trustedKeys: [makeTrustedKey()]
            ),
            .unknownAuthVersion
        )
    }

    func testAuthenticateReportsInvalidSignatures() {
        var badSig = adminSignature
        badSig[0] ^= 0xFF

        XCTAssertEqual(
            RoundAuthenticator.authenticate(
                chainEaPK: eaPK,
                roundIdHex: roundId,
                rounds: [roundId: makeEntry(signature: badSig)],
                trustedKeys: [makeTrustedKey()]
            ),
            .invalidSignatures
        )
    }

    func testAuthenticateReportsEaPKMismatch() {
        var chainEaPK = eaPK
        chainEaPK[0] ^= 0xFF

        XCTAssertEqual(
            RoundAuthenticator.authenticate(
                chainEaPK: chainEaPK,
                roundIdHex: roundId,
                rounds: [roundId: makeEntry()],
                trustedKeys: [makeTrustedKey()]
            ),
            .eaPKMismatch
        )
    }

    func testAuthenticateReportsInvalidSignaturesWhenEntryEaPKIsShort() {
        XCTAssertEqual(
            RoundAuthenticator.authenticate(
                chainEaPK: eaPK,
                roundIdHex: roundId,
                rounds: [roundId: makeEntry(eaPK: Data(repeating: 0x01, count: 31))],
                trustedKeys: [makeTrustedKey()]
            ),
            .invalidSignatures
        )
    }

    func testVerifyEntrySignaturesRejectsUnknownKeyId() {
        let entry = makeEntry(keyId: "unknown-key")

        XCTAssertFalse(RoundAuthenticator.verifyEntrySignatures(entry: entry, trustedKeys: [makeTrustedKey()]))
    }

    func testVerifyEntrySignaturesRejectsSignatureAlgMismatch() {
        let entry = makeEntry(signatureAlg: "ed448")

        XCTAssertFalse(RoundAuthenticator.verifyEntrySignatures(entry: entry, trustedKeys: [makeTrustedKey()]))
    }

    func testVerifyEntrySignaturesRejectsTrustedKeyAlgMismatch() {
        let trustedKey = StaticVotingConfig.TrustedKey(
            keyId: "valar-test",
            alg: "ed448",
            pubkey: adminPubkey,
            notes: nil
        )

        XCTAssertFalse(RoundAuthenticator.verifyEntrySignatures(entry: makeEntry(), trustedKeys: [trustedKey]))
    }

    func testVerifyEntrySignaturesRejectsShortSignature() {
        let entry = makeEntry(signature: Data(repeating: 0x01, count: 63))

        XCTAssertFalse(RoundAuthenticator.verifyEntrySignatures(entry: entry, trustedKeys: [makeTrustedKey()]))
    }

    func testVerifyEntrySignaturesAcceptsWhenAnySignatureIsValid() {
        let entry = VotingServiceConfig.RoundEntry(
            authVersion: 1,
            eaPk: eaPK,
            signatures: [
                .init(keyId: "valar-test", alg: "ed25519", sig: Data(repeating: 0x01, count: 64)),
                .init(keyId: "valar-test", alg: "ed25519", sig: adminSignature)
            ]
        )

        XCTAssertTrue(RoundAuthenticator.verifyEntrySignatures(entry: entry, trustedKeys: [makeTrustedKey()]))
    }

    func testServiceConfigDropsOnlyRoundsWithoutValidSignatures() {
        var badSignature = adminSignature
        badSignature[0] ^= 0xFF
        let invalidRoundId = String(repeating: "b", count: 64)
        let config = VotingServiceConfig(
            configVersion: 1,
            voteServers: [.init(url: "https://vote.example.com", label: "vote")],
            pirEndpoints: [.init(url: "https://pir.example.com", label: "pir")],
            supportedVersions: .init(pir: ["v0"], voteProtocol: "v0", tally: "v0", voteServer: "v1"),
            rounds: [
                roundId: makeEntry(),
                invalidRoundId: makeEntry(signature: badSignature)
            ]
        )

        let filtered = serviceConfigRetainingRoundsWithValidSignatures(config, trustedKeys: [makeTrustedKey()])

        XCTAssertEqual(Set(filtered.rounds.keys), [roundId])
    }

    private func makeEntry(
        authVersion: Int = 1,
        eaPK: Data? = nil,
        keyId: String = "valar-test",
        signatureAlg: String = "ed25519",
        signature: Data? = nil
    ) -> VotingServiceConfig.RoundEntry {
        .init(
            authVersion: authVersion,
            eaPk: eaPK ?? self.eaPK,
            signatures: [
                .init(keyId: keyId, alg: signatureAlg, sig: signature ?? adminSignature)
            ]
        )
    }

    private func makeTrustedKey() -> StaticVotingConfig.TrustedKey {
        .init(keyId: "valar-test", alg: "ed25519", pubkey: adminPubkey, notes: nil)
    }
}

final class VotingSessionParsingTests: XCTestCase {
    func testParseVotingSessionAcceptsValidProposalBounds() {
        XCTAssertNoThrow(try parseVotingSession(from: makeRound()))
    }

    func testParseVotingSessionRejectsEmptyProposals() {
        XCTAssertThrowsError(try parseVotingSession(from: makeRound(proposals: [])))
    }

    func testParseVotingSessionRejectsTooManyProposals() {
        XCTAssertThrowsError(try parseVotingSession(from: makeRound(proposals: (1...16).map { makeProposal(id: $0) })))
    }

    func testParseVotingSessionRejectsProposalIdOutsideRange() {
        XCTAssertThrowsError(try parseVotingSession(from: makeRound(proposals: [makeProposal(id: 16)])))
    }

    func testParseVotingSessionRejectsDuplicateProposalIds() {
        XCTAssertThrowsError(try parseVotingSession(from: makeRound(proposals: [makeProposal(id: 1), makeProposal(id: 1)])))
    }

    func testParseVotingSessionRejectsTooFewOptions() {
        XCTAssertThrowsError(try parseVotingSession(from: makeRound(proposals: [
            makeProposal(id: 1, options: [makeOption(index: 0)])
        ])))
    }

    func testParseVotingSessionRejectsTooManyOptions() {
        XCTAssertThrowsError(try parseVotingSession(from: makeRound(proposals: [
            makeProposal(id: 1, options: (0...8).map { makeOption(index: $0) })
        ])))
    }

    func testParseVotingSessionRejectsDuplicateOptionIndices() {
        XCTAssertThrowsError(try parseVotingSession(from: makeRound(proposals: [
            makeProposal(id: 1, options: [makeOption(index: 0), makeOption(index: 0)])
        ])))
    }

    func testParseVotingSessionRejectsNonContiguousOptionIndices() {
        XCTAssertThrowsError(try parseVotingSession(from: makeRound(proposals: [
            makeProposal(id: 1, options: [makeOption(index: 0), makeOption(index: 2)])
        ])))
    }

    private func makeRound(proposals: [[String: Any]]? = nil) -> [String: Any] {
        [
            "vote_round_id": Data(repeating: 0xAA, count: 32).base64EncodedString(),
            "snapshot_height": 1,
            "snapshot_blockhash": Data(repeating: 0x01, count: 32).base64EncodedString(),
            "proposals_hash": Data(repeating: 0x02, count: 32).base64EncodedString(),
            "vote_end_time": 3,
            "ceremony_phase_start": 2,
            "ea_pk": Data(repeating: 0x03, count: 32).base64EncodedString(),
            "vk_zkp1": Data(repeating: 0x04, count: 32).base64EncodedString(),
            "vk_zkp2": Data(repeating: 0x05, count: 32).base64EncodedString(),
            "vk_zkp3": Data(repeating: 0x06, count: 32).base64EncodedString(),
            "nc_root": Data(repeating: 0x07, count: 32).base64EncodedString(),
            "nullifier_imt_root": Data(repeating: 0x08, count: 32).base64EncodedString(),
            "creator": "creator",
            "description": "description",
            "proposals": proposals ?? [makeProposal(id: 1)],
            "status": SessionStatus.active.rawValue,
            "created_at_height": 1,
            "title": "Round"
        ]
    }

    private func makeProposal(id: Int, options: [[String: Any]]? = nil) -> [String: Any] {
        [
            "id": id,
            "title": "Proposal \(id)",
            "description": "Proposal description",
            "options": options ?? [makeOption(index: 0), makeOption(index: 1)]
        ]
    }

    private func makeOption(index: Int) -> [String: Any] {
        ["index": index, "label": "Option \(index)"]
    }
}

final class ShareRecoveryPollingTests: XCTestCase {
    func testPollingConfirmsFromRecordedHelperInsteadOfFirstConfiguredHelper() async throws {
        let recorder = SharePostRecorder()
        let share = try makeShareDelegation(
            sentToURLs: [
                "https://helper-3.example.com",
                "https://helper-4.example.com",
                "https://helper-5.example.com"
            ],
            submitAt: 0,
            createdAt: 100
        )

        let result = await VotingCoordFlow.pollShareStatusesForRecovery(
            readyShares: [share],
            roundId: "aabb",
            now: 200,
            voteEndTime: 1_000,
            fetchShareStatus: { helperURL, _, _ in
                await recorder.record(helperURL)
                return helperURL == "https://helper-3.example.com" ? .confirmed : .pending
            }
        )

        let queriedServers = await recorder.servers()
        XCTAssertEqual(queriedServers, ["https://helper-3.example.com"])
        XCTAssertEqual(result.confirmedShares, [
            ShareDelegationKey(bundleIndex: 0, proposalId: 1, shareIndex: 0)
        ])
        XCTAssertTrue(result.resubmissionShares.isEmpty)
        XCTAssertEqual(result.queriedCount, 1)
    }

    func testPollingContinuesAfterOneRecordedHelperErrors() async throws {
        let recorder = SharePostRecorder()
        let share = try makeShareDelegation(
            sentToURLs: [
                "https://helper-3.example.com",
                "https://helper-4.example.com"
            ],
            submitAt: 0,
            createdAt: 100
        )

        let result = await VotingCoordFlow.pollShareStatusesForRecovery(
            readyShares: [share],
            roundId: "aabb",
            now: 200,
            voteEndTime: 1_000,
            fetchShareStatus: { helperURL, _, _ in
                await recorder.record(helperURL)
                if helperURL == "https://helper-3.example.com" {
                    throw SharePostFailure()
                }
                return .confirmed
            }
        )

        let queriedServers = await recorder.servers()
        XCTAssertEqual(queriedServers, [
            "https://helper-3.example.com",
            "https://helper-4.example.com"
        ])
        XCTAssertEqual(result.confirmedShares, [
            ShareDelegationKey(bundleIndex: 0, proposalId: 1, shareIndex: 0)
        ])
        XCTAssertTrue(result.resubmissionShares.isEmpty)
        XCTAssertEqual(result.queriedCount, 2)
    }

    func testImmediateSharesUseCreatedAtForReadinessAndResubmission() throws {
        let share = try makeShareDelegation(
            sentToURLs: ["https://helper.example.com"],
            submitAt: 0,
            createdAt: 100
        )

        XCTAssertFalse(VotingCoordFlow.isShareReadyForStatusCheck(share, now: 109))
        XCTAssertTrue(VotingCoordFlow.isShareReadyForStatusCheck(share, now: 110))
        XCTAssertFalse(VotingCoordFlow.shouldResubmitShare(share, now: 129, voteEndTime: 200))
        XCTAssertTrue(VotingCoordFlow.shouldResubmitShare(share, now: 130, voteEndTime: 200))
    }

    func testDelayedSharesUseSubmitAtForReadinessAndResubmission() throws {
        let share = try makeShareDelegation(
            sentToURLs: ["https://helper.example.com"],
            submitAt: 200,
            createdAt: 100
        )

        XCTAssertFalse(VotingCoordFlow.isShareReadyForStatusCheck(share, now: 209))
        XCTAssertTrue(VotingCoordFlow.isShareReadyForStatusCheck(share, now: 210))
        XCTAssertFalse(VotingCoordFlow.shouldResubmitShare(share, now: 229, voteEndTime: 320))
        XCTAssertTrue(VotingCoordFlow.shouldResubmitShare(share, now: 230, voteEndTime: 320))
    }
}

final class ShareResubmissionFallbackTests: XCTestCase {
    func testResubmissionTriesUntriedHelpersFirst() async {
        let recorder = SharePostRecorder()

        let acceptedServers = await resubmitSharePayload(
            makeRecoverySharePayload(),
            roundIdHex: "aabb",
            configuredServerURLs: [
                "https://already-sent.example.com",
                "https://untried.example.com"
            ],
            sentToURLs: ["https://already-sent.example.com"],
            postShare: { server, _ in
                await recorder.record(server)
            },
            orderServers: { $0 }
        )

        XCTAssertEqual(acceptedServers, ["https://untried.example.com"])
        let recordedServers = await recorder.servers()
        XCTAssertEqual(recordedServers, ["https://untried.example.com"])
    }

    func testResubmissionFallsBackToAlreadySentHelperWhenUntriedFails() async {
        let recorder = SharePostRecorder()

        let acceptedServers = await resubmitSharePayload(
            makeRecoverySharePayload(),
            roundIdHex: "aabb",
            configuredServerURLs: [
                "https://already-sent.example.com",
                "https://untried.example.com"
            ],
            sentToURLs: ["https://already-sent.example.com"],
            postShare: { server, _ in
                await recorder.record(server)
                if server == "https://untried.example.com" {
                    throw SharePostFailure()
                }
            },
            orderServers: { $0 }
        )

        XCTAssertEqual(acceptedServers, ["https://already-sent.example.com"])
        let recordedServers = await recorder.servers()
        XCTAssertEqual(recordedServers, [
            "https://untried.example.com",
            "https://already-sent.example.com"
        ])
    }

    func testResubmissionReturnsEmptyWhenAllHelpersFail() async {
        let recorder = SharePostRecorder()

        let acceptedServers = await resubmitSharePayload(
            makeRecoverySharePayload(),
            roundIdHex: "aabb",
            configuredServerURLs: [
                "https://already-sent.example.com",
                "https://untried.example.com"
            ],
            sentToURLs: ["https://already-sent.example.com"],
            postShare: { server, _ in
                await recorder.record(server)
                throw SharePostFailure()
            },
            orderServers: { $0 }
        )

        XCTAssertTrue(acceptedServers.isEmpty)
        let recordedServers = await recorder.servers()
        XCTAssertEqual(recordedServers, [
            "https://untried.example.com",
            "https://already-sent.example.com"
        ])
    }
}

final class ShareDelegationPostFallbackTests: XCTestCase {
    func testSelectedHelperFailureBackfillsSameShareAndPrunesFailedHelper() async throws {
        let recorder = SharePostRecorder()
        let payload = makeRecoverySharePayload()

        let result = try await delegateSharePayloads(
            [payload],
            roundIdHex: "aabb",
            initialServerURLs: [
                "https://online-one.example.com",
                "https://offline.example.com",
                "https://online-two.example.com"
            ],
            postShare: { server, _ in
                await recorder.record(server)
                if server == "https://offline.example.com" {
                    throw SharePostFailure()
                }
            },
            selectTargets: { servers, targetCount in Array(servers.prefix(targetCount)) }
        )

        let recordedServers = await recorder.servers()
        XCTAssertEqual(recordedServers.count, 3)
        XCTAssertEqual(Set(recordedServers), Set([
            "https://online-one.example.com",
            "https://offline.example.com",
            "https://online-two.example.com"
        ]))
        XCTAssertEqual(result.delegatedShares.first?.acceptedByServers, [
            "https://online-one.example.com",
            "https://online-two.example.com"
        ])
        XCTAssertEqual(result.remainingServerURLs, [
            "https://online-one.example.com",
            "https://online-two.example.com"
        ])
    }

    func testOfflineHelperIsAttemptedAtMostOnceThenLaterSharesUseOnlineHelper() async throws {
        let recorder = SharePostRecorder()
        let payloads = (0..<2).map { makeRecoverySharePayload(index: UInt32($0)) }

        let result = try await delegateSharePayloads(
            payloads,
            roundIdHex: "aabb",
            initialServerURLs: [
                "https://offline.example.com",
                "https://online.example.com"
            ],
            postShare: { server, _ in
                await recorder.record(server)
                if server == "https://offline.example.com" {
                    throw SharePostFailure()
                }
            },
            selectTargets: { servers, targetCount in Array(servers.prefix(targetCount)) }
        )

        let recordedServers = await recorder.servers()
        XCTAssertEqual(recordedServers, [
            "https://offline.example.com",
            "https://online.example.com",
            "https://online.example.com"
        ])
        XCTAssertEqual(result.delegatedShares.map(\.acceptedByServers), [
            ["https://online.example.com"],
            ["https://online.example.com"]
        ])
        XCTAssertEqual(result.remainingServerURLs, ["https://online.example.com"])
    }

    func testAllSelectedHelpersFailButBackfillHelperSucceeds() async throws {
        let recorder = SharePostRecorder()
        let payload = makeRecoverySharePayload()

        let result = try await delegateSharePayloads(
            [payload],
            roundIdHex: "aabb",
            initialServerURLs: [
                "https://offline-one.example.com",
                "https://offline-two.example.com",
                "https://online.example.com"
            ],
            postShare: { server, _ in
                await recorder.record(server)
                if server != "https://online.example.com" {
                    throw SharePostFailure()
                }
            },
            selectTargets: { servers, targetCount in Array(servers.prefix(targetCount)) }
        )

        let recordedServers = await recorder.servers()
        XCTAssertEqual(recordedServers.count, 3)
        XCTAssertEqual(Set(recordedServers), Set([
            "https://offline-one.example.com",
            "https://offline-two.example.com",
            "https://online.example.com"
        ]))
        XCTAssertEqual(result.delegatedShares.first?.acceptedByServers, ["https://online.example.com"])
        XCTAssertEqual(result.remainingServerURLs, ["https://online.example.com"])
    }

    func testAllConfiguredHelpersFailThrowsNoReachableVoteServers() async throws {
        do {
            _ = try await delegateSharePayloads(
                [makeRecoverySharePayload()],
                roundIdHex: "aabb",
                initialServerURLs: [
                    "https://offline-one.example.com",
                    "https://offline-two.example.com"
                ],
                postShare: { _, _ in throw SharePostFailure() },
                selectTargets: { servers, targetCount in Array(servers.prefix(targetCount)) }
            )
            XCTFail("Expected share delegation to fail")
        } catch {
            XCTAssertEqual(error as? ShareDelegationError, .noReachableVoteServers)
        }
    }
}

final class DelegateSharesWithFallbackTests: XCTestCase {
    func testDelegateSharesWithFallbackRetriesReachabilityExhaustion() async throws {
        let attempts = AttemptCounter()
        var votingAPI = VotingAPIClient()
        votingAPI.delegateShares = { _, _, serverURLs in
            let attempt = await attempts.increment()
            if attempt < 3 {
                throw ShareDelegationError.noReachableVoteServers
            }
            return ShareDelegationResult(delegatedShares: [], remainingServerURLs: serverURLs)
        }

        let result = try await Voting.delegateSharesWithFallback(
            [],
            roundId: "aabb",
            votingAPI: votingAPI,
            serverURLs: ["https://vote.example.com"],
            retryDelay: .zero
        )

        let attemptCount = await attempts.value()
        XCTAssertEqual(attemptCount, 3)
        XCTAssertEqual(result.remainingServerURLs, ["https://vote.example.com"])
    }

    func testDelegateSharesWithFallbackRethrowsUnexpectedErrorWithoutRetry() async {
        let attempts = AttemptCounter()
        var votingAPI = VotingAPIClient()
        votingAPI.delegateShares = { _, _, _ in
            _ = await attempts.increment()
            throw SharePostFailure()
        }

        do {
            _ = try await Voting.delegateSharesWithFallback(
                [],
                roundId: "aabb",
                votingAPI: votingAPI,
                serverURLs: ["https://vote.example.com"],
                retryDelay: .zero
            )
            XCTFail("Expected unexpected share delegation error")
        } catch {
            XCTAssertTrue(error is SharePostFailure)
        }
        let attemptCount = await attempts.value()
        XCTAssertEqual(attemptCount, 1)
    }
}

private actor SharePostRecorder {
    private var postedServers: [String] = []

    func record(_ server: String) {
        postedServers.append(server)
    }

    func servers() -> [String] {
        postedServers
    }
}

private actor AttemptCounter {
    private var count = 0

    func increment() -> Int {
        count += 1
        return count
    }

    func value() -> Int {
        count
    }
}

private struct SharePostFailure: Error {}

private func makeShareDelegation(
    roundId: String = "aabb",
    bundleIndex: UInt32 = 0,
    proposalId: UInt32 = 1,
    shareIndex: UInt32 = 0,
    sentToURLs: [String],
    confirmed: Bool = false,
    submitAt: UInt64,
    createdAt: UInt64,
    nullifier: [UInt8] = Array(repeating: 0x0A, count: 32)
) throws -> VotingShareDelegation {
    let object: [String: Any] = [
        "round_id": roundId,
        "bundle_index": bundleIndex,
        "proposal_id": proposalId,
        "share_index": shareIndex,
        "sent_to_urls": sentToURLs,
        "nullifier": nullifier.map { String(format: "%02x", $0) }.joined(),
        "confirmed": confirmed,
        "submit_at": submitAt,
        "created_at": createdAt
    ]
    let data = try JSONSerialization.data(withJSONObject: object)
    return try JSONDecoder().decode(VotingShareDelegation.self, from: data)
}

private func makeRecoverySharePayload(index: UInt32 = 0) -> SharePayload {
    let share = EncryptedShare(
        c1: Data(repeating: UInt8(index + 1), count: 32),
        c2: Data(repeating: UInt8(index + 2), count: 32),
        shareIndex: index
    )
    return SharePayload(
        sharesHash: Data(repeating: 0x01, count: 32),
        proposalId: 1,
        voteDecision: 0,
        encShare: share,
        treePosition: 10,
        allEncShares: [share],
        shareComms: [Data(repeating: 0x03, count: 32)],
        primaryBlind: Data(repeating: 0x04, count: 32),
        submitAt: 99
    )
}
