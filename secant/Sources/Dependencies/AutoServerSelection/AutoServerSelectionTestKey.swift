//
//  AutoServerSelectionTestKey.swift
//  Zashi
//

import ComposableArchitecture

extension AutoServerSelectionClient: TestDependencyKey {
    static let testValue = AutoServerSelectionClient(refreshIfEnabled: {})
}
