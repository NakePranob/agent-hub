import Foundation

// MARK: - PillSessionRegistry

/// Keeps track of the agent sessions living behind each pill.
///
/// A pill is picked from the client that sent the event — bundle ID,
/// `term_program`, `coucou_agent` — never from the session. Two `claude`
/// started in two projects under VS Code therefore land on the same
/// `integration_claude`, while `AppState.tasks` holds one entry per pill.
/// Without a session set, the first session to end wipes the card and the
/// diffs the second one is still filling.
///
/// A value type on purpose: the hook server owns one copy and every change
/// goes through a `mutating` call, so no other object can alias the state.
struct PillSessionRegistry {

    /// A session unheard of for this long counts as gone. A `SessionEnd` that
    /// never arrives — a killed terminal, a crash — would otherwise pin a card
    /// to a session nobody is running any more.
    static let maxSilence: TimeInterval = 12 * 3600

    /// A session mid-turn emits a hook event every few seconds, so this long
    /// without one means its `Stop` went missing. Stops counting it as working,
    /// which is what keeps a sibling session from staying stuck out of its
    /// finished state. Longer than any tool call Claude Code will wait on.
    static let maxTurnSilence: TimeInterval = 30 * 60

    /// How far a terminal event is allowed to reach.
    enum TerminalScope: Equatable {
        /// No other session is mid-turn behind this pill, so the pill may
        /// follow: finished state, sound, badge, card removal.
        case pill
        /// Another session is still working — leave the pill as it is.
        case sessionOnly
    }

    /// What a pill shows while a session owns it.
    struct Display: Equatable {
        var session: String
        var projectName: String
        var cwd: String
        /// Terminal the session runs in (bundle id), for "Open terminal".
        var hostApp: String? = nil
        /// Bundle id of the client (VS Code, Cursor…) that sent the event.
        var bundleId: String = ""
        /// The session's folder name, which tells sessions apart on the card. An external
        /// agent's `projectName` is the agent's own name, so its folder only shows here.
        var folder: String = ""
    }

    /// One live session, as the card's session row shows it.
    struct Lane: Equatable, Identifiable {
        let id: String          // session id
        var label: String
        var cwd: String
        var hostApp: String?
        var bundleId: String
        var isWorking: Bool
        /// Waiting on a permission or a question. The registry doesn't know: HookServer
        /// sets it from its approval queue when it publishes the lanes.
        var isWaiting = false
        /// This session's own ticker lines, oldest first.
        var steps: [String]
        /// When it last went from idle to working: the card follows the session you
        /// prompted last, so two sessions working side by side don't make it flicker.
        var turnStartedAt: Date
        /// This session's last prompt and what came of it.
        var turn: AgentTurn? = nil
    }

    private struct Session {
        var projectName: String
        var cwd: String
        var hostApp: String?
        var bundleId: String
        var isWorking: Bool
        var lastSeen: Date
        var turnStartedAt: Date
        var folder = ""
        var steps: [String] = []
        var turn: AgentTurn? = nil
    }

    /// Ticker lines kept per session, like the pill's own log.
    static let maxSteps = 20

    private struct Pill {
        /// Live sessions, oldest first. The first one owns name and cwd.
        var order: [String] = []
        var sessions: [String: Session] = [:]
    }

    private var pills: [String: Pill] = [:]

    // MARK: - Recording activity

    /// Records the session that sent an event as live behind `pill`.
    /// `working` says whether the event means the session is mid-turn: a
    /// `PreToolUse` does, a `SessionStart` or a stray notification does not.
    mutating func note(pill: String, display: Display, working: Bool, now: Date = Date()) {
        var p = pills[pill] ?? Pill()
        sweep(&p, now: now)
        if p.sessions[display.session] == nil {
            p.order.append(display.session)
        }
        var session = p.sessions[display.session]
            ?? Session(projectName: display.projectName, cwd: display.cwd,
                       hostApp: display.hostApp, bundleId: display.bundleId,
                       isWorking: false, lastSeen: now, turnStartedAt: now)
        session.projectName = display.projectName
        if !display.cwd.isEmpty { session.cwd = display.cwd }
        if display.hostApp != nil { session.hostApp = display.hostApp }
        if !display.bundleId.isEmpty { session.bundleId = display.bundleId }
        if !display.folder.isEmpty { session.folder = display.folder }
        if working && !session.isWorking { session.turnStartedAt = now }
        if working { session.isWorking = true }
        session.lastSeen = now
        p.sessions[display.session] = session
        pills[pill] = p
    }

    /// Adds a ticker line to one session's own log. A session never noted stays untracked.
    mutating func appendStep(pill: String, session: String, step: String) {
        pills[pill]?.sessions[session]?.steps.append(step)
        pills[pill]?.sessions[session]?.turn?.stepCount += 1
        if let count = pills[pill]?.sessions[session]?.steps.count, count > Self.maxSteps {
            pills[pill]?.sessions[session]?.steps.removeFirst(count - Self.maxSteps)
        }
    }

    /// Changes one session's turn. A session never noted stays untracked.
    mutating func updateTurn(pill: String, session: String, _ change: (inout AgentTurn?) -> Void) {
        guard pills[pill]?.sessions[session] != nil else { return }
        change(&pills[pill]!.sessions[session]!.turn)
    }

    // MARK: - Terminal events

    /// Ends a session's turn without ending the session: a `Stop` closes a
    /// turn, and the user can send another prompt right after.
    ///
    /// A session we have never seen stays untracked — Coucou can start in the
    /// middle of one, and a session we only ever heard stop owns nothing.
    mutating func endTurn(pill: String, session: String, now: Date = Date()) -> TerminalScope {
        var p = pills[pill] ?? Pill()
        sweep(&p, now: now)
        p.sessions[session]?.isWorking = false
        p.sessions[session]?.lastSeen = now
        if p.order.isEmpty { pills.removeValue(forKey: pill) } else { pills[pill] = p }
        return p.sessions.values.contains(where: \.isWorking) ? .sessionOnly : .pill
    }

    /// Drops a session for good. `.pill` only when it was the last one live,
    /// so the card and the diffs survive a sibling session ending.
    mutating func endSession(pill: String, session: String, now: Date = Date()) -> TerminalScope {
        var p = pills[pill] ?? Pill()
        sweep(&p, now: now)
        p.order.removeAll { $0 == session }
        p.sessions.removeValue(forKey: session)
        guard !p.order.isEmpty else {
            pills.removeValue(forKey: pill)
            return .pill
        }
        pills[pill] = p
        return .sessionOnly
    }

    // MARK: - Reading

    /// The session whose project name and cwd the pill shows. Ownership goes
    /// to the oldest live session and only moves on when that one ends, so a
    /// single name field stops flipping between two parallel sessions.
    func displayOwner(of pill: String) -> Display? {
        guard let p = pills[pill], let id = p.order.first,
              let session = p.sessions[id] else { return nil }
        return Display(session: id, projectName: session.projectName, cwd: session.cwd,
                       hostApp: session.hostApp, bundleId: session.bundleId)
    }

    /// Whether this session may write the pill's name and cwd. True when the
    /// pill has no live session yet, so a first event is never dropped.
    func ownsDisplay(pill: String, session: String) -> Bool {
        guard let owner = displayOwner(of: pill) else { return true }
        return owner.session == session
    }

    /// Live sessions behind `pill`, oldest first.
    func lanes(of pill: String) -> [Lane] {
        guard let p = pills[pill] else { return [] }
        return p.order.compactMap { id in
            guard let s = p.sessions[id] else { return nil }
            return Lane(id: id, label: s.folder.isEmpty ? s.projectName : s.folder, cwd: s.cwd,
                        hostApp: s.hostApp, bundleId: s.bundleId, isWorking: s.isWorking,
                        steps: s.steps, turnStartedAt: s.turnStartedAt, turn: s.turn)
        }
    }

    func liveCount(pill: String) -> Int { pills[pill]?.order.count ?? 0 }

    func workingCount(pill: String) -> Int {
        pills[pill]?.sessions.values.filter(\.isWorking).count ?? 0
    }

    // MARK: - Silence sweep

    private func sweep(_ pill: inout Pill, now: Date) {
        for (id, session) in pill.sessions.map({ ($0.key, $0.value) }) {
            let silence = now.timeIntervalSince(session.lastSeen)
            if silence > Self.maxSilence {
                pill.sessions.removeValue(forKey: id)
                pill.order.removeAll { $0 == id }
            } else if session.isWorking, silence > Self.maxTurnSilence {
                pill.sessions[id]?.isWorking = false
            }
        }
    }
}
