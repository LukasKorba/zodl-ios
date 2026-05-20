//
//  ProposalDetailStore.swift
//  Zashi
//

import ComposableArchitecture

@Reducer
struct ProposalDetail {
    @ObservableState
    struct State: Equatable {
        let roundId: String
        let proposalId: UInt32

        init(roundId: String, proposalId: UInt32) {
            self.roundId = roundId
            self.proposalId = proposalId
        }
    }

    enum Action: Equatable {}

    var body: some ReducerOf<Self> {
        EmptyReducer()
    }
}
