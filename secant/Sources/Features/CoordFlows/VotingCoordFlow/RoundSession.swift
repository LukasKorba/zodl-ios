//
//  RoundSession.swift
//  Zashi
//

import Foundation

/// Cached per-round state that survives navigation within the voting flow.
///
/// Populated on first entry into a round (witness verification, hotkey
/// derivation, vote weight computation). Re-entering the same round uses
/// this cache instead of re-running the 30–120 s pipeline.
///
/// Evicted on `.dismissFlow`, wallet-account switch, or voting-service-config
/// change. All other navigation pops leave the cache intact — the rule that
/// makes "back" feel like a real pop instead of a teardown.
struct RoundSession: Equatable {
    let roundId: String

    // MARK: - Pipeline outputs (Phase 4b populates)

    /// Total voting power for this wallet at the round's snapshot height,
    /// derived from eligible notes after bundling (5-note bundles, dropped
    /// if below `ballotDivisor`). Constant across navigation for a given
    /// (wallet, round) pair until a new snapshot or wallet rescan.
    var votingWeight: UInt64 = 0

    /// Eligible notes at the round's snapshot height. Cached because the
    /// SDK query is non-trivial and the snapshot is immutable.
    var walletNotes: [NoteInfo] = []

    /// Per-round hotkey address derived deterministically from the per-
    /// account hotkey mnemonic (in the Keychain) and the round id. Same
    /// address every time for a given (wallet, round) pair.
    var hotkeyAddress: String?

    /// Draft votes the user has selected but not yet submitted. Keyed by
    /// proposal id. Hydrated from the encrypted voting metadata file on
    /// round entry; mutations write through to disk so drafts survive an
    /// app restart.
    var draftVotes: [UInt32: VoteChoice] = [:]

    /// Per-proposal tally results from the voting service. Cached for
    /// finalized rounds — these are immutable post-finalization, so we
    /// never refetch them once populated.
    var tallyResults: [UInt32: TallyResult] = [:]

    /// True when a tally fetch has been initiated for this round (so the
    /// Results view doesn't show "loading" indefinitely after the response
    /// arrives empty).
    var tallyFetched: Bool = false

    /// Last tally-fetch failure message, set by `.tallyResultsFailed`.
    /// Non-nil = ResultsView renders a retry surface instead of the
    /// "Loading results…" spinner. Cleared by `.retryFetchTallyResults`.
    var tallyError: String?

    // Phase 4c+ will add: witnessResults, delegationProofStatus,
    // delegationPrecomputeStatus, bundleCount, tallyResults, voteRecord,
    // draftVotes, etc. Each addition stays append-only — once a field is
    // populated, navigation pops never clear it.
}
