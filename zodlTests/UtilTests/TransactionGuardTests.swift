import XCTest
@testable import zashi_internal

final class TransactionGuardTests: XCTestCase {
    func testTryAcquireFailsWhileHeld() async {
        let guardActor = TransactionGuard()
        await guardActor.acquire()
        let acquired = await guardActor.tryAcquire()
        XCTAssertFalse(acquired, "tryAcquire must fail while the guard is held")
        await guardActor.release()
        let acquiredAfter = await guardActor.tryAcquire()
        XCTAssertTrue(acquiredAfter, "tryAcquire must succeed after release")
    }

    func testSwitchIsSkippedWhileSubmissionActive() async {
        let client = TransactionGuardClient.liveValue
        let submissionStarted = AsyncBox()
        let releaseSubmission = AsyncBox()

        let submission = Task {
            try await client.withSubmission {
                await submissionStarted.signal()
                await releaseSubmission.wait()
            }
        }

        await submissionStarted.wait()
        let didSwitch = try? await client.switchIfIdle { /* would switch here */ }
        XCTAssertEqual(didSwitch, false, "Auto switch must skip while a submission is active")

        await releaseSubmission.signal()
        _ = try? await submission.value

        let didSwitchAfter = try? await client.switchIfIdle { }
        XCTAssertEqual(didSwitchAfter, true, "Auto switch must run once the submission finished")
    }

    func testManualSwitchWaitsForSubmission() async {
        let client = TransactionGuardClient.liveValue
        let order = OrderRecorder()
        let submissionStarted = AsyncBox()
        let releaseSubmission = AsyncBox()

        let submission = Task {
            try await client.withSubmission {
                await submissionStarted.signal()
                await releaseSubmission.wait()
                await order.record("submission-end")
            }
        }
        await submissionStarted.wait()

        let manual = Task {
            try await client.switchWaiting {
                await order.record("switch")
            }
        }

        // Give the manual switch a moment to park on the guard, then let the submission finish.
        try? await Task.sleep(for: .milliseconds(50))
        await releaseSubmission.signal()
        _ = try? await submission.value
        _ = try? await manual.value

        let recorded = await order.values
        XCTAssertEqual(recorded, ["submission-end", "switch"], "Manual switch must wait for the submission")
    }
}

/// Minimal async one-shot signal for ordering test steps.
private actor AsyncBox {
    private var signaled = false
    private var waiters: [CheckedContinuation<Void, Never>] = []
    func signal() {
        signaled = true
        let w = waiters; waiters.removeAll(); w.forEach { $0.resume() }
    }
    func wait() async {
        if signaled { return }
        await withCheckedContinuation { waiters.append($0) }
    }
}

private actor OrderRecorder {
    private(set) var values: [String] = []
    func record(_ value: String) { values.append(value) }
}
