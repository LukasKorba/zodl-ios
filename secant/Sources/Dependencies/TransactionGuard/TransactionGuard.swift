//
//  TransactionGuard.swift
//  Zashi
//

import Foundation

/// A fair (FIFO) async mutex shared between server switches and transaction submissions so the two
/// can never overlap. The SDK's `switchTo(endpoint:)` tears down and rebuilds the synchronizer and
/// is unsafe while a transaction is being broadcast, so a submission and a switch must be exclusive.
actor TransactionGuard {
    private var isBusy = false
    private var waiters: [CheckedContinuation<Void, Never>] = []

    /// Wait until the guard is free, then take it. Callers must `release()` when done.
    func acquire() async {
        guard isBusy else {
            isBusy = true
            return
        }
        await withCheckedContinuation { waiters.append($0) }
        // Ownership was handed to us by `release()`; `isBusy` is already true.
    }

    /// Take the guard only if it is free right now; never waits. Returns `false` if busy.
    func tryAcquire() -> Bool {
        guard !isBusy else { return false }
        isBusy = true
        return true
    }

    /// Release the guard, handing ownership to the next waiter (FIFO) if there is one.
    func release() {
        if waiters.isEmpty {
            isBusy = false
        } else {
            let next = waiters.removeFirst()
            next.resume() // `isBusy` stays true — ownership transfers to the resumed waiter.
        }
    }
}
