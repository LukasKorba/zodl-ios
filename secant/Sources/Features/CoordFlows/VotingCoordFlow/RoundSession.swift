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
    // Fields populated incrementally as each phase migrates them off the
    // monolithic Voting.State. See the migration plan for the full schema.
}
