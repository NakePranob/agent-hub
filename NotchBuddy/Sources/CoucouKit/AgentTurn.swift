import Foundation

/// What a ticker step does, which gives it its icon and colour on the session card.
enum StepKind: CaseIterable {
    case search, read, edit, run, test, web, agent, plan, fail
}

/// One prompt and what the agent did about it: the session card's title, clock and summary.
struct AgentTurn: Equatable {
    var prompt: String
    var startedAt: Date
    var endedAt: Date? = nil
    /// Steps appended since the prompt: the card's wheel shows only this turn's, and
    /// numbers them by it so a row keeps its identity when the log drops its oldest line.
    var stepCount = 0
    /// Tools used, by kind.
    var tally: [StepKind: Int] = [:]
    var files: Set<String> = []
    var added = 0
    var removed = 0
}
