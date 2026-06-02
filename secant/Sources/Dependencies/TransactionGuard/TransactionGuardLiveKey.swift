//
//  TransactionGuardLiveKey.swift
//  Zashi
//

import ComposableArchitecture

extension TransactionGuardClient: DependencyKey {
    static let liveValue: TransactionGuardClient = {
        let guardActor = TransactionGuard()
        return TransactionGuardClient(
            acquire: { await guardActor.acquire() },
            tryAcquire: { await guardActor.tryAcquire() },
            release: { await guardActor.release() }
        )
    }()
}
