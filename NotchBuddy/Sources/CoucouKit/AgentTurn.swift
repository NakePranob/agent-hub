import Foundation

/// What a ticker step does, which gives it its icon and colour on the session card.
enum StepKind: CaseIterable {
    case search, read, edit, run, test, web, agent, plan, fail
}

/// One prompt and what the agent did about it: the session card's prompt, clock and step count.
struct AgentTurn: Equatable {
    var prompt: String
    var startedAt: Date
    var endedAt: Date? = nil
    /// Steps appended since the prompt: the card shows only this turn's, so "Thinking"
    /// until the first one rather than the previous turn's last line.
    var stepCount = 0
    /// Tools used, by kind.
    var tally: [StepKind: Int] = [:]
}
