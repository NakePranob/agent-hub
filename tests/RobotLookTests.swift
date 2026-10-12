import Foundation

// The robot's wardrobe (App/Robot/RobotLook.swift): saved looks read back whatever is wrong in
// them, the look each pill wears, and Coucou's states folded into the robot's five moods.

enum BotState: CaseIterable { case idle, working, thinking, searching, approval, question, error, finished, ratelimit, sleeping, dizzy }
enum PillCategory { case workspace, agent, ai, service }
struct PillDefinition { let id: String; let category: PillCategory }
enum PillCatalog {
    static let all: [PillDefinition] = [
        .init(id: "integration_claude", category: .workspace),
        .init(id: "agent_cursor", category: .workspace),
        .init(id: "agent_gemini", category: .agent),
        .init(id: "integration_stripe", category: .service),
        .init(id: "ai_openai", category: .ai),
    ]
}

@main
enum RobotLookTests {
    static var failures = 0

    static func check(_ label: String, _ got: Bool) {
        if got { print("  ✓ \(label)") }
        else   { print("  ✗ \(label)"); failures += 1 }
    }

    static func decode(_ json: String) -> RobotLook? {
        try? JSONDecoder().decode(RobotLook.self, from: Data(json.utf8))
    }

    static func main() {
        print("RobotLook — a saved look, whatever is wrong in it back to the standard")
        let full = decode(##"{"skin":"dots","ears":"dial","accessory":"beanie","body":"#112233","ink":"#445566","hat":"#778899"}"##)
        check("a whole look reads back as saved",
              full?.skin == .dots && full?.ears == .dial && full?.accessory == .beanie
              && full?.body == "#112233" && full?.ink == "#445566" && full?.hat == "#778899")
        let empty = decode("{}")
        check("an empty one is the standard look", empty == .standard)
        let bad = decode(##"{"skin":"tartan","ears":7,"body":"red","ink":"#12345","hat":"#GGGGGG"}"##)
        check("unknown skin → plain", bad?.skin == .plain)
        check("unreadable ears → ring", bad?.ears == .hatch)
        check("bad colours → the standard ones",
              bad?.body == RobotLook.standard.body && bad?.ink == RobotLook.standard.ink && bad?.hat == RobotLook.standard.hat)
        if let round = try? JSONEncoder().encode(full), let back = try? JSONDecoder().decode(RobotLook.self, from: round) {
            check("encodes and decodes to the same look", back == full)
        } else { check("encodes and decodes to the same look", false) }

        print("RobotWardrobe.look(for:) — the look each pill wears")
        var dotted = RobotLook.standard; dotted.skin = .dots
        var striped = RobotLook.standard; striped.skin = .stripes
        var w = RobotWardrobe()
        w.looks = ["integration_claude": dotted, "agent_cursor": striped, "integration_stripe": striped]
        w.defaultPill = "integration_claude"
        check("an agent dressed of its own wears its look", w.look(for: "agent_cursor") == striped)
        check("an agent not dressed wears the default's", w.look(for: "agent_gemini") == dotted)
        check("a service wears the default's, even with a look saved for it", w.look(for: "integration_stripe") == dotted)
        check("a chat provider wears the default's", w.look(for: "ai_openai") == dotted)
        check("no pill in focus wears the default's", w.look(for: nil) == dotted)
        check("an unknown pill wears the default's", w.look(for: "agent_nobody") == dotted)
        w.looks = [:]
        check("nothing dressed: the standard look", w.look(for: "agent_cursor") == .standard)

        print("RobotMood(BotState) — Coucou's states in the robot's five moods")
        let moods: [BotState: RobotMood] = [
            .idle: .idle, .sleeping: .idle,
            .working: .working, .thinking: .working, .searching: .working,
            .approval: .needsYou, .question: .needsYou,
            .error: .error, .ratelimit: .error, .dizzy: .error,
            .finished: .done,
        ]
        check("every state has its mood", moods.count == BotState.allCases.count)
        for state in BotState.allCases {
            check("\(state) → \(moods[state]!)", RobotMood(state) == moods[state])
        }

        print(failures == 0 ? "\nAll passed." : "\n\(failures) failed.")
        exit(failures == 0 ? 0 : 1)
    }
}
