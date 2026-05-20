//
//  VotingCoordFlowCoordinator.swift
//  Zashi
//

import Foundation
import ComposableArchitecture
@preconcurrency import ZcashLightClientKit

extension VotingCoordFlow {
    /// Handles all action dispatch. Matches the
    /// `<Name>CoordFlowCoordinator.swift` convention used elsewhere in the
    /// codebase (e.g. `RestoreWalletCoordFlowCoordinator`).
    // swiftlint:disable:next cyclomatic_complexity
    func coordinatorReduce() -> Reduce<State, Action> {
        Reduce { state, action in
            switch action {

                // MARK: - Path

            case .path(.element(id: _, action: .configSettings(.delegate(.dismiss)))):
                // VotingConfigSettings emits `.delegate(.dismiss)` from its
                // back button; pop the settings push so the user returns to
                // the polls list. Re-fetch is handled by `.delegate(.saved)`
                // separately (Phase 4+).
                if !state.path.isEmpty {
                    state.path.removeLast()
                }
                return .none

            case .path(.element(id: _, action: .configSettings(.delegate(.saved)))):
                // Save closes the settings screen and re-runs initialize so
                // the new pinned config takes effect. Voting state from the
                // previous source has to go: round ids can collide across
                // sources, cached per-round pipeline output (hotkey, weight,
                // witnesses, drafts) is keyed only by round id and would
                // happily serve stale data after the switch. Cancel the
                // in-flight pipeline too so it doesn't race the new init.
                if !state.path.isEmpty {
                    state.path.removeLast()
                }
                state.allRounds = []
                state.roundCache.removeAll()
                state.voteRecords.removeAll()
                state.zodlEndorsedRoundIds = []
                state.pendingPipelineRoundId = nil
                state.serviceConfig = nil
                state.pollsLoadError = false
                state.rootScreen = .loading
                return .merge(
                    .cancel(id: cancelPipelineId),
                    .send(.initialize)
                )

            case .path:
                return .none

                // MARK: - Lifecycle

            case .onAppear:
                // Re-entry from a nested screen pop = no-op. The user just
                // navigated back to the polls list root; we already have
                // rounds + service config loaded, so don't flip rootScreen
                // back to `.loading` and re-fetch.
                //
                // Without this guard, NavigationStack's pop fires `.onAppear`
                // again on the root content, which would briefly show the
                // loading screen before the polls list re-renders.
                if state.serviceConfig != nil {
                    return .none
                }

                // First-time entry: show the intro before initializing the
                // round-loading pipeline. The intro's continue button drives
                // `.howToVoteContinueTapped` which re-enters `.onAppear` with
                // the flag set.
                guard state.hasSeenHowToVoteForCurrentWallet else {
                    state.rootScreen = .howToVote
                    return .none
                }
                state.rootScreen = .loading
                return .send(.initialize)

            case .initialize:
                // Sweep legacy plaintext keys from a prior internal-build
                // persistence shape. Idempotent and cheap; safe to keep.
                Voting.sweepLegacyUserDefaultsVotingKeys()

                // Defensively reset the process-wide encrypted metadata cache
                // before loading the current account, so a nil-account window
                // can't surface a previous account's data.
                votingMetadata.reset()
                if let account = state.selectedWalletAccount?.account {
                    try? votingMetadata.load(account)
                }

                // Read straight from UserDefaults rather than from
                // `state.votingConfigOverrideURL` so this picks up the value
                // VotingConfigSettings just wrote, even when the @Shared
                // change has not yet propagated to parent state at dismiss
                // time. Otherwise the first save after a chain switch refetches
                // with the previous override.
                let overrideURLString = UserDefaults.standard
                    .string(forKey: .votingConfigOverrideURL) ?? ""

                return .run { [votingAPI] send in
                    let override: PinnedConfigSource?
                    if overrideURLString.isEmpty {
                        override = nil
                    } else {
                        override = try? PinnedConfigSource.parse(overrideURLString)
                    }
                    let config = try await votingAPI.fetchServiceConfig(override)
                    await send(.serviceConfigLoaded(config))
                } catch: { error, send in
                    LoggerProxy.error("Service config unavailable: \(error)")
                    let message = (error as? LocalizedError)?.errorDescription
                        ?? error.localizedDescription
                    await send(.configUnsupported(message))
                }

            case .serviceConfigLoaded(let config):
                state.serviceConfig = config
                let walletId = state.walletId
                return .run { [votingAPI, votingCrypto] send in
                    // 1. Configure API client URLs from the loaded config.
                    await votingAPI.configureURLs(config)

                    // 2. Open the voting DB and scope it to this wallet.
                    let dbPath = FileManager.default
                        .urls(for: .documentDirectory, in: .userDomainMask)[0]
                        .appendingPathComponent("voting.sqlite3").path
                    try await votingCrypto.openDatabase(dbPath)
                    try await votingCrypto.setWalletId(walletId)

                    // 3. Fetch rounds. Network failures surface as a
                    //    recoverable sheet on the polls list rather than the
                    //    blocking error screen.
                    do {
                        let rounds = try await votingAPI.fetchAllRounds()
                        await send(.allRoundsLoaded(rounds))
                    } catch {
                        LoggerProxy.error("Failed to fetch rounds: \(error)")
                        await send(.roundsLoadFailed)
                    }
                } catch: { error, send in
                    LoggerProxy.error("Voting initialization failed: \(error)")
                    await send(.initializeFailed(error.localizedDescription))
                }

            case .allRoundsLoaded(let sessions):
                state.pollsLoadError = false

                // Stable creation-order numbering.
                let sorted = sessions.sorted { $0.createdAtHeight < $1.createdAtHeight }
                state.allRounds = sorted.enumerated().map { index, session in
                    RoundListItem(roundNumber: index + 1, session: session)
                }

                // Hydrate per-round vote records from the encrypted metadata
                // file so the polls list can render the Voted state for any
                // rounds the user has fully submitted on this device.
                let account = state.selectedWalletAccount?.account
                var records: [String: Voting.VoteRecord] = [:]
                for item in state.allRounds {
                    if let record = Voting.loadCompletedVoteRecord(
                        roundId: item.id,
                        account: account
                    ) {
                        records[item.id] = record
                    }
                }
                state.voteRecords = records

                state.rootScreen = state.allRounds.isEmpty ? .noRounds : .pollsList

                // If the user is currently on TallyingView for a round whose
                // status just flipped to .finalized, swap the topmost path
                // entry for ResultsView so the 30 s auto-poll on
                // TallyingView lands them on the right screen without a
                // manual back tap. Same for proposal list → results when a
                // previously-active round finalized out from under them.
                if let topRoundId = finalizedTopOfPath(state) {
                    _ = state.path.popLast()
                    state.path.append(.results(Results.State(roundId: topRoundId)))
                }

                // Fetch the Zodl endorsement list right after the rounds
                // list lands. PollsListView filters bundled rounds by this
                // set when `isOnDefaultConfig` is true, so without the
                // fetch the list would be empty on the default source.
                return .run { [votingAPI] send in
                    do {
                        let ids = try await votingAPI.fetchZodlEndorsedRoundIds()
                        await send(.zodlEndorsementsLoaded(ids))
                    } catch {
                        LoggerProxy.error("Failed to fetch zodl endorsements: \(error)")
                        await send(.zodlEndorsementsFailed)
                    }
                }

            case let .zodlEndorsementsLoaded(ids):
                state.zodlEndorsedRoundIds = ids
                return .none

            case .zodlEndorsementsFailed:
                // Leave the existing set in place; the polls list either
                // renders empty (default source) or unaffected (custom source
                // skips the filter). The polls-list error sheet already
                // covers the user-visible network-failure surface.
                return .none

            case .roundsLoadFailed:
                state.pollsLoadError = true
                // Keep any previously loaded rounds visible behind the error
                // sheet. If nothing was ever loaded, the empty list shows
                // blank chrome underneath; the sheet still offers retry.
                state.rootScreen = .pollsList
                return .none

            case .configUnsupported(let message):
                state.rootScreen = .configError(message)
                return .none

            case .initializeFailed(let message):
                state.rootScreen = .error(message)
                return .none

                // MARK: - User actions

            case .dismissFlow:
                state.roundCache.removeAll()
                state.path.removeAll()
                return .none

            case .howToVoteContinueTapped:
                if state.isKeystoneUser {
                    state.$hasSeenHowToVoteForKeystone.withLock { $0 = true }
                } else {
                    state.$hasSeenHowToVoteForZashi.withLock { $0 = true }
                }
                return .send(.onAppear)

            case .retryLoadRounds:
                state.rootScreen = .loading
                return .send(.initialize)

            case .openConfigSettings:
                state.path.append(.configSettings(VotingConfigSettings.State()))
                return .none

            case .roundTapped(let roundId):
                // Route by round status. Voted rounds in active phase
                // surface read-only review; not-yet-voted rounds go to the
                // voting list; tallying/finalized rounds skip the proposal
                // list entirely and land on the status screen.
                guard let item = state.allRounds.first(where: { $0.id == roundId }) else {
                    return .none
                }
                switch item.session.status {
                case .active:
                    // Hydrate drafts from disk on every entry — they may have
                    // been edited from a different surface or app session.
                    let drafts = Voting.loadDrafts(roundId: roundId)
                    if state.roundCache[roundId] == nil {
                        state.roundCache[roundId] = RoundSession(roundId: roundId)
                    }
                    state.roundCache[roundId]?.draftVotes = drafts

                    if state.voteRecords[roundId] != nil {
                        // Already submitted — review-mode read-only, no
                        // pipeline needed.
                        state.path.append(.reviewVotes(ReviewVotes.State(roundId: roundId)))
                        return .none
                    }
                    state.path.append(.proposalList(ProposalList.State(roundId: roundId)))
                    // Cache check: skip pipeline if hotkey is already
                    // populated for this round. Re-entry within the same
                    // session is instant.
                    if let cached = state.roundCache[roundId], cached.hotkeyAddress != nil {
                        return .none
                    }
                    return .send(.startActiveRoundPipeline(roundId: roundId))
                case .tallying:
                    state.path.append(.tallying(Tallying.State(roundId: roundId)))
                    return .none
                case .finalized:
                    state.path.append(.results(Results.State(roundId: roundId)))
                    return .none
                case .unspecified:
                    return .none
                }

            case .viewMyVotesTapped(let roundId):
                // Explicit user intent to view submitted votes in read-only
                // form. Always routes to reviewVotes regardless of round
                // status (active or finalized — both have a vote record).
                state.path.append(.reviewVotes(ReviewVotes.State(roundId: roundId)))
                return .none

            case let .proposalTapped(roundId, proposalId, mode):
                state.path.append(
                    .proposalDetail(
                        ProposalDetail.State(roundId: roundId, proposalId: proposalId, mode: mode)
                    )
                )
                return .none

            case let .submitTapped(roundId):
                state.path.append(.confirmSubmission(ConfirmSubmission.State(roundId: roundId)))
                return .none

            case .submitAllDraftsTapped:
                // TODO Phase 5: real submission pipeline (auth → delegation
                // proof → per-vote ZKPs → share delegation → success).
                // Until then, surface an alert so the DEBUG entry doesn't
                // silently swallow the tap and so testers route to the
                // legacy Coinholder Polling entry for actual votes.
                state.submissionAlert = AlertState {
                    TextState("Submission not wired yet")
                } message: {
                    TextState("The new voting flow's submission pipeline lands in Phase 5. To submit votes today, use the legacy 'Coinholder Polling' entry in Settings.")
                }
                return .none

            case .submissionAlert:
                return .none

                // MARK: - Tally results

            case let .fetchTallyResults(roundId):
                // Cache hit on finalized round = no refetch. Tally results
                // are immutable post-finalization.
                if let cached = state.roundCache[roundId],
                   cached.tallyFetched,
                   cached.tallyError == nil {
                    return .none
                }
                if state.roundCache[roundId] == nil {
                    state.roundCache[roundId] = RoundSession(roundId: roundId)
                }
                state.roundCache[roundId]?.tallyError = nil
                return .run { [votingAPI] send in
                    do {
                        let results = try await votingAPI.fetchTallyResults(roundId)
                        await send(.tallyResultsLoaded(roundId: roundId, results: results))
                    } catch {
                        LoggerProxy.error("Failed to fetch tally results: \(error)")
                        await send(.tallyResultsFailed(roundId: roundId, message: error.localizedDescription))
                    }
                }

            case let .tallyResultsLoaded(roundId, results):
                state.roundCache[roundId, default: RoundSession(roundId: roundId)]
                    .tallyResults = results
                state.roundCache[roundId, default: RoundSession(roundId: roundId)]
                    .tallyFetched = true
                return .none

            case let .tallyResultsFailed(roundId, message):
                // Surface the failure on ResultsView so the user sees a
                // retry button instead of an indefinite loading spinner.
                if state.roundCache[roundId] == nil {
                    state.roundCache[roundId] = RoundSession(roundId: roundId)
                }
                state.roundCache[roundId]?.tallyError = message
                return .none

            case let .draftVoteSet(roundId, proposalId, choice):
                // Write through to cache + disk so the choice survives both
                // navigation pops and app restarts. Snapshot the drafts
                // before persisting so the disk call runs without holding
                // the inout state reference.
                state.roundCache[roundId, default: RoundSession(roundId: roundId)]
                    .draftVotes[proposalId] = choice
                let drafts = state.roundCache[roundId]?.draftVotes ?? [:]
                let account = state.selectedWalletAccount?.account
                Voting.persistDrafts(drafts, roundId: roundId, account: account)
                return .none

                // MARK: - Per-round pipeline

            case .startActiveRoundPipeline(let roundId):
                guard let item = state.allRounds.first(where: { $0.id == roundId }),
                      item.session.status == .active else {
                    return .none
                }
                let session = item.session
                let snapshotHeight = session.snapshotHeight
                let network = zcashSDKEnvironment.network
                let walletDbPath = databaseFiles.dataDbURLFor(network).path
                let networkId: UInt32 = network.networkType.votingRustNetworkId
                let accountId = state.selectedWalletAccount?.id
                let accountUUID: [UInt8] = accountId?.id ?? []

                // Seed the cache entry so subsequent re-entries see an
                // in-progress session and don't trigger duplicate pipelines.
                if state.roundCache[roundId] == nil {
                    state.roundCache[roundId] = RoundSession(roundId: roundId)
                }
                state.pendingPipelineRoundId = roundId

                return .run { [votingCrypto, mnemonic, walletStorage, sdkSynchronizer] send in
                    // 1. Wallet sync gate.
                    //
                    // Spend-before-Sync scans both head-first and birthday-
                    // first in parallel — a `latestScannedHeight` past the
                    // snapshot from the head doesn't imply the snapshot
                    // itself has been scanned. We need the contiguous-from-
                    // birthday `fullyScannedHeight` instead. The SDK
                    // synchronizer may report 0 briefly on cold start before
                    // it hydrates state — retry a few times.
                    var walletScannedHeight = UInt64(sdkSynchronizer.latestState().fullyScannedHeight)
                    if walletScannedHeight == 0 {
                        for _ in 0..<5 {
                            try await Task.sleep(for: .seconds(1))
                            walletScannedHeight = UInt64(sdkSynchronizer.latestState().fullyScannedHeight)
                            if walletScannedHeight > 0 { break }
                        }
                    }
                    if walletScannedHeight < snapshotHeight {
                        await send(
                            .walletNotSynced(
                                roundId: roundId,
                                scannedHeight: walletScannedHeight,
                                snapshotHeight: snapshotHeight
                            )
                        )
                        return
                    }

                    // 2. Notes + eligible voting weight after bundling.
                    // `smartBundles().eligibleWeight` mirrors the Rust
                    // chunking: groups of 5 notes, drops any bundle below
                    // ballotDivisor (0.125 ZEC). An empty / sub-threshold
                    // wallet must land on IneligibleView instead of
                    // marching through hotkey generation only to fail
                    // submission later.
                    let notes = try await votingCrypto.getWalletNotes(
                        walletDbPath,
                        snapshotHeight,
                        networkId,
                        accountUUID
                    )
                    let bundleResult = notes.smartBundles()
                    let eligibleWeight = bundleResult.eligibleWeight
                    if notes.isEmpty || eligibleWeight == 0 {
                        await send(.ineligibleForRound(roundId: roundId))
                        return
                    }
                    await send(.votingWeightLoaded(roundId: roundId, weight: eligibleWeight, notes: notes))

                    // 3. Hotkey: load or generate the per-account hotkey
                    // mnemonic, then derive this round's hotkey address.
                    guard let accountId else {
                        LoggerProxy.error("No selected account; skipping voting hotkey generation")
                        return
                    }
                    let phrase: String
                    if let stored = try? walletStorage.exportVotingHotkey(accountId) {
                        phrase = stored.seedPhrase.value()
                    } else {
                        phrase = try mnemonic.randomMnemonic()
                        try walletStorage.importVotingHotkey(phrase, accountId)
                    }
                    let seed = try mnemonic.toSeed(phrase)
                    let hotkey = try await votingCrypto.generateHotkey(roundId, seed)
                    await send(.hotkeyLoaded(roundId: roundId, address: hotkey.address))
                } catch: { error, send in
                    LoggerProxy.error("Active round pipeline failed: \(error)")
                    await send(.pipelineFailed(roundId: roundId, message: error.localizedDescription))
                }
                .cancellable(id: cancelPipelineId, cancelInFlight: true)

            case let .walletNotSynced(roundId, scannedHeight, snapshotHeight):
                // Pop any pushed screens — the user can't proceed into the
                // round until the wallet catches up. Show the WalletSyncing
                // root. Once synced, the polling loop restarts the pipeline
                // and re-pushes the proposal list.
                state.path.removeAll()
                state.walletScannedHeight = scannedHeight
                state.pendingPipelineRoundId = roundId
                state.rootScreen = .walletSyncing
                return .run { [sdkSynchronizer] send in
                    while !Task.isCancelled {
                        try await Task.sleep(for: .seconds(2))
                        let height = UInt64(sdkSynchronizer.latestState().fullyScannedHeight)
                        await send(.walletSyncProgressUpdated(height: height))
                        if height >= snapshotHeight {
                            await send(.startActiveRoundPipeline(roundId: roundId))
                            return
                        }
                    }
                } catch: { _, _ in }
                .cancellable(id: cancelPipelineId, cancelInFlight: true)

            case .walletSyncProgressUpdated(let height):
                state.walletScannedHeight = height
                // When sync catches up while user is on the walletSyncing
                // screen, restore the polls-list root and push the proposal
                // list before the pipeline action lands (visually the user
                // sees the polls list briefly then the proposal list).
                if state.rootScreen == .walletSyncing,
                   let roundId = state.pendingPipelineRoundId,
                   let item = state.allRounds.first(where: { $0.id == roundId }),
                   height >= item.session.snapshotHeight {
                    state.rootScreen = .pollsList
                    state.path.append(.proposalList(ProposalList.State(roundId: roundId)))
                }
                return .none

            case let .votingWeightLoaded(roundId, weight, notes):
                state.roundCache[roundId, default: RoundSession(roundId: roundId)].votingWeight = weight
                state.roundCache[roundId, default: RoundSession(roundId: roundId)].walletNotes = notes
                return .none

            case let .hotkeyLoaded(roundId, address):
                state.roundCache[roundId, default: RoundSession(roundId: roundId)].hotkeyAddress = address
                if state.pendingPipelineRoundId == roundId {
                    state.pendingPipelineRoundId = nil
                }
                return .none

            case let .pipelineFailed(roundId, message):
                // Pop the proposal list back to the polls list and surface
                // the error as the blocking error root. Cache stays around
                // (we just won't claim a hotkey was loaded); user can retry
                // by tapping the round again.
                if state.pendingPipelineRoundId == roundId {
                    state.pendingPipelineRoundId = nil
                }
                state.path.removeAll()
                state.rootScreen = .error(message)
                return .none

            case let .ineligibleForRound(roundId):
                // No eligible notes at the snapshot height (no notes at all,
                // or every bundle dropped below ballotDivisor). Swap the
                // proposal list at the top of the path for IneligibleView
                // so the user sees the terminal explanation instead of
                // sitting in the "Preparing your voting power…" header
                // forever.
                if case .proposalList = state.path.last {
                    _ = state.path.popLast()
                }
                state.path.append(.ineligible(Ineligible.State(roundId: roundId)))
                return .cancel(id: cancelPipelineId)

            case .refreshActiveRoundsList:
                // Lightweight re-fetch used by the tallying-status poll.
                // Reuses the same allRoundsLoaded path so we pick up any
                // status transition (active → tallying → finalized) without
                // disturbing rootScreen.
                return .run { [votingAPI] send in
                    do {
                        let sessions = try await votingAPI.fetchAllRounds()
                        await send(.allRoundsLoaded(sessions))
                    } catch {
                        LoggerProxy.warn("Tallying poll: rounds re-fetch failed: \(error)")
                    }
                }

            case let .retryFetchTallyResults(roundId):
                // Manual retry from ResultsView when the previous fetch
                // errored. Clear the error and re-trigger the fetch.
                if state.roundCache[roundId] != nil {
                    state.roundCache[roundId]?.tallyError = nil
                }
                return .send(.fetchTallyResults(roundId: roundId))
            }
        }
    }

    /// Returns the topmost path element's round id when it's a
    /// `.tallying` / `.proposalList` entry whose round status just flipped
    /// to `.finalized`, otherwise nil. Used by the tallying-status auto-
    /// poll to redirect the user onto ResultsView.
    private func finalizedTopOfPath(_ state: State) -> String? {
        guard let top = state.path.last else { return nil }
        let candidate: String?
        switch top {
        case let .tallying(scoped):
            candidate = scoped.roundId
        case let .proposalList(scoped):
            candidate = scoped.roundId
        default:
            candidate = nil
        }
        guard let roundId = candidate,
              let item = state.allRounds.first(where: { $0.id == roundId }),
              item.session.status == .finalized
        else { return nil }
        return roundId
    }
}
