import Foundation

/// The ticker's verbs ("Reads · file.swift") and the kinds of step they make. The hook
/// server writes steps with these verbs and the session card reads the kind back from
/// them, so the step log the iPhone and the Live Activity get stays plain text.
extension StepKind {
    private enum Verb {
        static let reads    = String(localized: "step.reads",    defaultValue: "Reads")
        static let searches = String(localized: "step.searches", defaultValue: "Searches")
        static let edits    = String(localized: "step.edits",    defaultValue: "Edits")
        static let runs     = String(localized: "step.runs",     defaultValue: "Runs")
        static let tests    = String(localized: "step.tests",    defaultValue: "Tests")
        static let tasks    = String(localized: "step.tasks",    defaultValue: "Tasks")
        static let agent    = String(localized: "step.agent",    defaultValue: "Agent")
    }

    /// Each tool's verb, and the kind of step it makes.
    static let tools: [String: (verb: String, kind: StepKind)] = [
        "Bash":         (Verb.runs, .run),
        "Read":         (Verb.reads, .read),
        "Write":        (String(localized: "step.writes", defaultValue: "Writes"), .edit),
        "Edit":         (Verb.edits, .edit),
        "Glob":         (Verb.searches, .search),
        "Grep":         (Verb.searches, .search),
        "WebSearch":    (String(localized: "step.web-search", defaultValue: "Searches the web"), .web),
        "WebFetch":     (String(localized: "step.fetches", defaultValue: "Fetches"), .web),
        "TodoWrite":    (Verb.tasks, .plan),
        "Task":         (Verb.agent, .agent),
        "Agent":        (Verb.agent, .agent),
        "LS":           (String(localized: "step.lists", defaultValue: "Lists"), .search),
        "MultiEdit":    (Verb.edits, .edit),
        "NotebookEdit": (String(localized: "step.notebook", defaultValue: "Notebook"), .edit),
        // Codex tools
        "apply_patch":  (Verb.edits, .edit),
        "update_plan":  (Verb.tasks, .plan),
        "spawn_agent":  (Verb.agent, .agent),
    ]

    /// A shell command's verb, from its first word: reading, searching and testing get theirs.
    static func shell(_ command: String) -> (verb: String, kind: StepKind) {
        let first = command.split(whereSeparator: { $0.isWhitespace }).first.map(String.init) ?? ""
        switch first {
        case "cat", "bat", "head", "tail", "less", "more", "nl": return (Verb.reads, .read)
        case "rg", "grep", "find", "fd", "ls", "tree", "wc":    return (Verb.searches, .search)
        default: break
        }
        let testRunners = ["pytest", "vitest", "jest", "npm test", "npm run test",
                           "cargo test", "go test", "swift test", "make test",
                           "xcodebuild test", "unittest"]
        if testRunners.contains(where: { command.contains($0) }) { return (Verb.tests, .test) }
        return (Verb.runs, .run)
    }

    /// The line a failed tool leaves.
    static let failedStep = "⚠ failed"

    private static let byVerb: [String: StepKind] = {
        var map = [Verb.tests: StepKind.test]
        for (verb, kind) in tools.values { map[verb] = kind }
        return map
    }()

    /// The kind of a ticker line, from the verb it starts with. Nil for anything else:
    /// a prompt, an answer, a question, an MCP tool.
    static func of(_ step: String) -> StepKind? {
        if step.isDiffStep { return .edit }
        if step == failedStep { return .fail }
        let verb = step.components(separatedBy: " · ").first ?? step
        return byVerb[verb]
    }
}
