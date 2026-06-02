//
//  AutoServerSelectionInterface.swift
//  Zashi
//

import Foundation
import ComposableArchitecture

extension DependencyValues {
    var autoServerSelection: AutoServerSelectionClient {
        get { self[AutoServerSelectionClient.self] }
        set { self[AutoServerSelectionClient.self] = newValue }
    }
}

@DependencyClient
struct AutoServerSelectionClient {
    /// Benchmarks known endpoints and switches to the fastest one when Automatic mode is enabled.
    /// A no-op when Automatic is off, when the best server equals the current one, or when a
    /// transaction submission is in progress (it retries on the next trigger).
    var refreshIfEnabled: @Sendable () async -> Void
}

enum AutoServerSelectionConstants {
    // Lightweight startup/foreground benchmark: cheap checks, short fetch.
    static let connectionTimeoutMilliseconds = 300.0
    static let evaluationTimeoutSeconds = 5.0
    static let blocksToDownload: UInt64 = 1
    static let candidateCount = 3
}
