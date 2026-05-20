//
//  VotingMetadata.swift
//  Zashi
//

import Foundation

/// On-disk shape for per-account encrypted voting state.
///
/// Carries the user's in-flight draft votes and per-round completion records.
/// Encrypted at rest using the same per-account keys as the user-metadata
/// file, but stored in a separate file with a different filename so the two
/// concerns stay isolated and the cross-platform user-metadata schema doesn't
/// have to learn about voting.
///
/// Lives only on this device — no iCloud sync, no remote merge strategy.
struct VotingMetadata: Codable, Equatable, Sendable {
    enum Constants {
        /// Bumped when the on-disk shape changes incompatibly. Future loaders
        /// branch on this value; v1 is the initial encrypted-file release.
        static let version = 1
    }

    /// `[roundIdHex: [proposalIdString: optionIndex]]`. Mirrors the in-memory
    /// `draftVotes` dictionary that `Voting.State` already holds.
    var drafts: [String: [String: UInt32]]

    /// `[roundIdHex: VoteRecord]`. One record per round the user has fully
    /// submitted.
    var records: [String: PersistedVotingRecord]

    /// Latest schema version this file was written with.
    var schemaVersion: Int

    init(
        drafts: [String: [String: UInt32]] = [:],
        records: [String: PersistedVotingRecord] = [:],
        schemaVersion: Int = Constants.version
    ) {
        self.drafts = drafts
        self.records = records
        self.schemaVersion = schemaVersion
    }
}

/// Persisted shape of `Voting.VoteRecord`. Kept as a separate Codable type so
/// the in-memory `Voting.VoteRecord` (which uses `Date`) can stay free of any
/// Codable concerns while this on-disk form serialises `votedAt` as a Unix
/// timestamp.
struct PersistedVotingRecord: Codable, Equatable, Sendable {
    let votedAt: Double
    let votingWeight: UInt64
    let proposalCount: Int
}
