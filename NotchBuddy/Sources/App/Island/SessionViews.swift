import SwiftUI

// MARK: - Ticker (overview scrolling task steps) V2

// MARK: - Session row

/// The card's title row when several sessions share one pill: the shown session's
/// folder in full, with a dot for what it is doing, then "+N" for the others. Its dot is
/// the most urgent of theirs, and a click opens the list to switch sessions.
struct SessionLaneRow: View {
    let pillId: String
    let lanes: [PillSessionRegistry.Lane]
    let shownId: String?
    let onMore: () -> Void

    var body: some View {
        let shown = lanes.firstIndex { $0.id == shownId } ?? 0
        let others = lanes.indices.filter { $0 != shown }.map { lanes[$0] }
        HStack(spacing: 6) {
            Circle()
                .fill(Self.dot(lanes[shown]))
                .frame(width: 7, height: 7)
            Text(Self.label(shown, in: lanes))
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color(hex: "#F5F6F8"))
                .lineLimit(1).truncationMode(.middle)
                .help(lanes[shown].cwd)
            Button(action: onMore) {
                let projects = Set(lanes.map { SessionProject.of(cwd: $0.cwd).project }).count
                HStack(spacing: 4) {
                    Circle().fill(Self.dot(waiting: others.contains(where: \.isWaiting),
                                           working: others.contains(where: \.isWorking)))
                        .frame(width: 6, height: 6)
                    Text(verbatim: projects > 1 ? "+\(others.count) · \(projects) projects" : "+\(others.count) sessions")
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "#9C9CA3"))
                }
                .fixedSize()
                .chip(selected: false)
            }
            .buttonStyle(.plain)
        }
    }

    /// Two sessions in one folder read "coucou" and "coucou 2".
    static func label(_ i: Int, in lanes: [PillSessionRegistry.Lane]) -> String {
        let name = lanes[i].label
        let before = lanes[..<i].filter { $0.label == name }.count
        return before == 0 ? name : "\(name) \(before + 1)"
    }

    static func dot(_ lane: PillSessionRegistry.Lane) -> Color {
        dot(waiting: lane.isWaiting, working: lane.isWorking)
    }

    /// Waiting for you wins over working, working over idle.
    static func dot(waiting: Bool, working: Bool) -> Color {
        if waiting { return StatusColor.waiting }
        if working { return StatusColor.working }
        return Color(hex: "#6B7079")
    }
}

private extension View {
    func chip(selected: Bool) -> some View {
        self.padding(.horizontal, 7)
            .padding(.vertical, 1)
            .background(Capsule().fill(Color.white.opacity(selected ? 0.12 : 0.07)))
            .contentShape(Capsule())
    }
}

/// Every session sharing the pill, grouped by project: the project's name once, with its
/// colour, then one row per session — its state, what it is doing or was asked, its branch
/// when the project's sessions differ in theirs, its time and the app it runs in. The
/// projects with a session waiting for you come first. With a single project, the branch
/// tells the rows apart instead. A click shows that session in the card.
struct SessionListView: View {
    let pillId: String
    let lanes: [PillSessionRegistry.Lane]
    let shownId: String?
    let onDismiss: () -> Void

    struct Row: Identifiable {
        let lane: PillSessionRegistry.Lane
        let info: SessionProject.Info
        let firstOfProject: Bool
        let showBranch: Bool
        var id: String { lane.id }
    }

    /// Projects in order of urgency (waiting, working, done, idle), their sessions likewise.
    static func rows(_ lanes: [PillSessionRegistry.Lane]) -> [Row] {
        let infos = lanes.map { SessionProject.of(cwd: $0.cwd) }
        func rank(_ i: Int) -> Int {
            let lane = lanes[i]
            return lane.isWaiting ? 0 : lane.isWorking ? 1 : lane.turn?.endedAt != nil ? 2 : 3
        }
        var order: [String] = []
        for info in infos where !order.contains(info.project) { order.append(info.project) }
        let groups = order.map { project in lanes.indices.filter { infos[$0].project == project } }
            .sorted { ($0.map(rank).min() ?? 3) < ($1.map(rank).min() ?? 3) }
        return groups.flatMap { members -> [Row] in
            let branches = Set(members.map { infos[$0].branch ?? "" })
            return members.sorted { rank($0) < rank($1) }.enumerated().map { n, i in
                Row(lane: lanes[i], info: infos[i], firstOfProject: n == 0, showBranch: branches.count > 1)
            }
        }
    }

    var body: some View {
        let rows = Self.rows(lanes)
        let projects = Set(rows.map(\.info.project))
        let single = projects.count == 1
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                Button(action: onDismiss) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundColor(Color(hex: "#9C9CA3"))
                        .frame(width: 18, height: 18)
                        .background(Circle().fill(Color.white.opacity(0.08)))
                }
                .buttonStyle(.plain)
                Text("Sessions").font(.system(size: 14, weight: .semibold))
                ListCount(text: "\(lanes.count)")
                if !single { ListCount(text: String(localized: "\(projects.count) projects")) }
                Spacer(minLength: 4)
                if single, let project = projects.first {
                    HStack(spacing: 5) {
                        Circle().fill(Self.color(of: project)).frame(width: 7, height: 7)
                        Text(project)
                    }
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: "#6B7079"))
                } else if let name = PillCatalog.definition(for: pillId)?.name {
                    Text(name).font(.system(size: 12)).foregroundColor(Color(hex: "#6B7079"))
                }
            }
            .frame(height: 18)

            ScrollView(.vertical, showsIndicators: false) {
                VStack(alignment: .leading, spacing: 2) {
                    ForEach(rows) { row in
                        Button {
                            AppState.shared.pickedLane[pillId] = row.lane.id
                            onDismiss()
                        } label: {
                            SessionListRow(row: row, shown: row.lane.id == shownId, single: single)
                        }
                        .buttonStyle(.plain)
                        .help(row.lane.cwd)
                    }
                }
            }
        }
        .padding(.leading, 104)
        .padding(.trailing, 10)
        .padding(.vertical, 7)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onExitCommand { onDismiss() }
    }

    /// The project's own colour: the one set for it, or one picked from its name, the
    /// same every time.
    static func color(of project: String) -> Color {
        if let hex = IslandConst.projectColors[project.lowercased()] { return Color(hex: hex) }
        let palette = ["#62A8FF", "#F29B38", "#B48EF0", "#4FD1A5", "#FF6B81", "#F5C451", "#5AC8FA", "#A3E635"]
        let hash = project.unicodeScalars.reduce(UInt32(5381)) { ($0 << 5) &+ $0 &+ $1.value }
        return Color(hex: palette[Int(hash % UInt32(palette.count))])
    }
}

/// "5", "3 projects": a count beside a list's title.
struct ListCount: View {
    let text: String

    var body: some View {
        Text(text)
            .font(.system(size: 11))
            .foregroundColor(Color(hex: "#9C9CA3"))
            .padding(.horizontal, 7).padding(.vertical, 1)
            .background(Capsule().fill(Color.white.opacity(0.07)))
    }
}

/// One session in the list.
struct SessionListRow: View {
    let row: SessionListView.Row
    let shown: Bool
    /// One project only: the branch takes the project's place on the left.
    let single: Bool

    var body: some View {
        let lane = row.lane
        let project = SessionListView.color(of: row.info.project)
        HStack(spacing: 8) {
            Group {
                if single {
                    if let branch = row.info.branch { BranchTag(branch: branch) }
                } else if row.firstOfProject {
                    HStack(spacing: 6) {
                        Circle().fill(project).frame(width: 7, height: 7)
                        Text(row.info.project)
                            .font(.system(size: 12.5, weight: .semibold))
                            .lineLimit(1).truncationMode(.tail)
                    }
                } else {
                    // The project's other sessions hang from its name.
                    Capsule().fill(project.opacity(0.55)).frame(width: 1.5, height: 20).padding(.leading, 3)
                }
            }
            .frame(width: 112, alignment: .leading)

            SessionStateMark(lane: lane)
            what(lane)
                .lineLimit(1).truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            if row.showBranch, !single, let branch = row.info.branch { BranchTag(branch: branch) }
            time(lane)
            if let icon = PillIcons.appIcon(bundleId: lane.hostApp ?? lane.bundleId) {
                Image(nsImage: icon).resizable().interpolation(.high).frame(width: 14, height: 14)
            }
        }
        .padding(.leading, 4).padding(.trailing, 6)
        .frame(height: 21)
        .background(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .fill(shown ? StatusColor.working.opacity(0.14) : .clear))
        .overlay(RoundedRectangle(cornerRadius: 8, style: .continuous)
            .stroke(shown ? StatusColor.working.opacity(0.45) : .clear, lineWidth: 1))
        .contentShape(Rectangle())
    }

    /// Waiting for you, the step it is on, or what was asked last.
    private func what(_ lane: PillSessionRegistry.Lane) -> Text {
        let gray = Color(hex: "#9C9CA3")
        if lane.isWaiting {
            return Text("Waiting for you").font(.system(size: 12, weight: .medium)).foregroundColor(StatusColor.waiting)
        }
        if lane.isWorking {
            let count = lane.turn.map { min($0.stepCount, lane.steps.count) } ?? lane.steps.count
            guard count > 0, let step = lane.steps.last else {
                return Text("Thinking").font(.system(size: 12, weight: .medium)).foregroundColor(.white)
            }
            let parts = step.isDiffStep ? [StepKind.edit.activity, step.parseDiffStep()?.filename ?? ""]
                : step.components(separatedBy: " · ")
            let verb = StepKind.of(step)?.activity ?? parts[0]
            let rest = parts.count > 1 ? " · " + parts.dropFirst().joined(separator: " · ") : ""
            return Text(verb).font(.system(size: 12, weight: .medium)).foregroundColor(.white)
                + Text(rest).font(.system(size: 12)).foregroundColor(gray)
        }
        let prompt = lane.turn?.prompt ?? ""
        return Text(prompt.isEmpty ? String(localized: "Idle") : prompt).font(.system(size: 12)).foregroundColor(gray)
    }

    @ViewBuilder private func time(_ lane: PillSessionRegistry.Lane) -> some View {
        if let turn = lane.turn {
            Group {
                if turn.endedAt != nil, !lane.isWorking {
                    Text(turn.failed ? "Failed" : "Done").foregroundColor(turn.failed ? StatusColor.failed : StatusColor.done)
                } else {
                    Text(verbatim: TurnClock.format(Date().timeIntervalSince(turn.startedAt)))
                        .foregroundColor(Color(hex: "#6B7079"))
                }
            }
            .font(.system(size: 11).monospacedDigit())
            .fixedSize()
        }
    }
}

/// A session's state as a small badge, like the robot's: dots working, "!" waiting, a
/// check done, an empty ring idle.
struct SessionStateMark: View {
    let lane: PillSessionRegistry.Lane

    var body: some View {
        let (color, symbol): (Color?, String?) =
            lane.isWaiting ? (StatusColor.waiting, "exclamationmark")
            : lane.isWorking ? (StatusColor.working, "ellipsis")
            : lane.turn?.failed == true ? (StatusColor.failed, "xmark")
            : lane.turn?.endedAt != nil ? (StatusColor.done, "checkmark") : (nil, nil)
        ZStack {
            if let color {
                Circle().fill(color)
                Image(systemName: symbol ?? "").font(.system(size: 7.5, weight: .heavy)).foregroundColor(.white)
            } else {
                Circle().stroke(Color.white.opacity(0.34), lineWidth: 1.5)
            }
        }
        .frame(width: 14, height: 14)
    }
}

/// A branch, in a small monospaced tag.
struct BranchTag: View {
    let branch: String

    var body: some View {
        Text(branch)
            .font(.system(size: 10.5, design: .monospaced))
            .foregroundColor(Color(hex: "#9C9CA3"))
            .lineLimit(1).truncationMode(.middle)
            .padding(.horizontal, 6).padding(.vertical, 1)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color.white.opacity(0.06)))
            .fixedSize(horizontal: false, vertical: true)
    }
}

// MARK: - Session card (the session, what was asked, what the agent is doing)

/// The left of the card for a pill with a live session: the session on top, then what was
/// asked, then what the agent is doing in a box whose bottom edge runs while it works —
/// or, once the turn is over, its answer, the prompt moving up beside the session.
struct SessionCardBody: View {
    let task: AgentTask
    /// Shown until something is asked ("Claude Code", "Agent").
    let subtitle: String
    var onSessionList: () -> Void = {}
    var onDiffTap: ((Int) -> Void)? = nil
    var onOpen: () -> Void = {}
    @ObservedObject private var appState = AppState.shared

    var body: some View {
        let prompt = task.turn?.prompt ?? ""
        let failed = Self.failed(task)
        let done = !Self.busy(task) && !failed && task.turn?.endedAt != nil
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 7) {
                PillLogo(task: task, size: 14, ringed: false)
                if let lanes = appState.sessionLanes[task.id] {
                    SessionLaneRow(pillId: task.id, lanes: lanes,
                                   shownId: appState.shownLane(of: task.id)?.id,
                                   onMore: onSessionList)
                        .layoutPriority(1)
                } else {
                    Text(task.name)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color(hex: "#F5F6F8"))
                        .lineLimit(1).truncationMode(.tail)
                        .layoutPriority(1)
                }
                if done || prompt.isEmpty {
                    Text(prompt.isEmpty ? subtitle : prompt)
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "#9C9CA3"))
                        .lineLimit(1).truncationMode(.tail)
                        .padding(.horizontal, 7)
                        .padding(.vertical, 1)
                        .background(Capsule().fill(Color.white.opacity(0.07)))
                        .help(prompt)
                }
                Spacer(minLength: 4)
                if let turn = task.turn {
                    TurnClock(turn: turn, running: task.state != .idle, failed: failed)
                }
            }
            .frame(height: 18)
            .padding(.trailing, 26)   // the ↗ button

            if !done, !prompt.isEmpty {
                Text(prompt)
                    .font(.system(size: 12.5))
                    .foregroundColor(Color(hex: "#9C9CA3"))
                    .lineLimit(1).truncationMode(.tail)
                    .padding(.leading, 8)
                    .overlay(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.18)).frame(width: 2)
                    }
                    .help(prompt)
            }

            ActivityBox(task: task, busy: Self.busy(task), done: done, failed: failed,
                        onDiffTap: onDiffTap, onOpen: onOpen)
                .id(appState.shownLane(of: task.id)?.id)  // another session: start over
        }
        .padding(.leading, 108)
        .padding(.trailing, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
    }

    static func busy(_ task: AgentTask) -> Bool {
        task.state == .working || task.state == .thinking || task.state == .searching
    }

    /// The pill's error, or this session's turn ending on one (its sibling may still work).
    static func failed(_ task: AgentTask) -> Bool {
        task.state == .error || (!busy(task) && task.turn?.failed == true)
    }

    /// The light the card takes from the robot's side: the step's colour while the agent
    /// works, green once the turn is over, red when it failed.
    static func glow(for task: AgentTask?) -> Color? {
        guard let task, task.turn != nil else { return nil }
        if failed(task) { return StatusColor.failed }
        if busy(task) {
            guard let step = ActivityBox.current(task) else { return StepKind.plan.tint }
            return StepKind.of(step)?.tint
        }
        return task.turn?.endedAt != nil ? ActivityBox.doneGreen : nil
    }
}

/// How long the turn has taken: counting while the agent is at it, "Done · 2:14" after.
struct TurnClock: View {
    let turn: AgentTurn
    let running: Bool
    var failed = false
    @Environment(\.islandViewActive) private var active

    var body: some View {
        Group {
            if let end = turn.endedAt {
                Text(verbatim: "\(failed ? String(localized: "Failed") : String(localized: "Done")) · \(Self.format(end.timeIntervalSince(turn.startedAt)))")
                    .foregroundColor(failed ? StatusColor.failed : ActivityBox.doneGreen)
            } else if running {
                TimelineView(.animation(minimumInterval: 1, paused: !active)) { tl in
                    Text(verbatim: Self.format(tl.date.timeIntervalSince(turn.startedAt)))
                }
                .foregroundColor(Color(hex: "#6B7079"))
            }
        }
        .font(.system(size: 12).monospacedDigit())
        .fixedSize()
    }

    static func format(_ interval: TimeInterval) -> String {
        let s = max(0, Int(interval))
        return s >= 3600 ? String(format: "%d:%02d:%02d", s / 3600, s / 60 % 60, s % 60)
                         : String(format: "%d:%02d", s / 60, s % 60)
    }
}

/// What the agent is doing, in a soft box: its kind's icon, the verb, what it acts on and
/// how many steps the turn has taken. The bottom edge runs in the kind's colour while it
/// works. Once the turn is over, the box holds the answer behind a check.
struct ActivityBox: View {
    let task: AgentTask
    let busy: Bool
    let done: Bool
    /// The turn failed: the box keeps the step it failed on, in red, with the way back to the app.
    var failed = false
    var onDiffTap: ((Int) -> Void)? = nil
    var onOpen: () -> Void = {}

    static let doneGreen = Color(hex: "#30D158")

    /// This turn's latest step; nil before the first one. Without a turn (an agent that
    /// never sends its prompt), the log's latest.
    static func current(_ task: AgentTask) -> String? {
        let count = task.turn.map { min($0.stepCount, task.steps.count) } ?? task.steps.count
        return count > 0 ? task.steps.last : nil
    }

    var body: some View {
        let step = Self.current(task)
        let kind = step.flatMap(StepKind.of)
        let tint = failed ? StatusColor.failed : done ? Self.doneGreen
            : step == nil ? StepKind.plan.tint : kind?.tint ?? Color(hex: "#8E939C")
        let symbol = failed ? "xmark" : done ? "checkmark" : step == nil ? "sparkle" : kind?.symbol ?? "chevron.right"
        HStack(spacing: 9) {
            Image(systemName: symbol)
                .font(.system(size: 10.5, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: 22, height: 22)
                .background(RoundedRectangle(cornerRadius: 7, style: .continuous).fill(tint.opacity(0.2)))
            if done {
                // The answer, when the turn ended on one; otherwise just that it is done.
                let answer = step.flatMap { StepKind.of($0) == nil ? $0 : nil } ?? String(localized: "Done")
                Text(answer)
                    .font(.system(size: 12.5))
                    .foregroundColor(Color(hex: "#F5F6F8"))
                    .lineLimit(2).lineSpacing(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                openButton
            } else if failed {
                content(step, kind)
                Spacer(minLength: 4)
                openButton
            } else {
                content(step, kind)
                Spacer(minLength: 4)
                if let n = task.turn?.tally.values.reduce(0, +), n > 0 {
                    Text(verbatim: "step \(n)")
                        .font(.system(size: 11).monospacedDigit())
                        .foregroundColor(Color(hex: "#6B7079"))
                        .fixedSize()
                }
            }
        }
        .padding(.leading, 7)
        .padding(.trailing, 12)
        .padding(.vertical, done ? 7 : 0)
        .frame(maxWidth: .infinity, minHeight: 36, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 12, style: .continuous)
            .fill(failed ? StatusColor.failed.opacity(0.1) : Color.white.opacity(0.05)))
        .overlay(alignment: .bottom) {
            if busy { RunningEdge(tint: tint) }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .contentShape(Rectangle())
        .onTapGesture {
            if let dp = step?.parseDiffStep() { onDiffTap?(dp.diffId) }
        }
        .animation(.easeInOut(duration: 0.25), value: step)
    }

    /// Back to the app the session runs in: VS Code, its terminal, Cursor…
    private var openButton: some View {
        let app = task.id == "integration_claude" ? ClaudeHost.name(for: task.hostApp)
            : PillCatalog.definition(for: task.id)?.name ?? task.name
        return Button(action: onOpen) {
            HStack(spacing: 5) {
                PillLogo(task: task, size: 13, ringed: false)
                Text(String(localized: "Open \(app)"))
                    .font(.system(size: 12, weight: .semibold))
            }
            .foregroundColor(.black)
            .padding(.horizontal, 10)
            .frame(height: 26)
            .background(Capsule().fill(Color.white))
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .fixedSize()
    }

    @ViewBuilder private func content(_ step: String?, _ kind: StepKind?) -> some View {
        let detail = Color(hex: "#9C9CA3")
        if let step, let dp = step.parseDiffStep() {
            verb(StepKind.edit.activity)
            Text(dp.filename)
                .font(.system(size: 12.5))
                .foregroundColor(detail)
                .lineLimit(1).truncationMode(.middle)
            if dp.added > 0 {
                Text(verbatim: "+\(dp.added)").font(.system(size: 11.5, weight: .medium).monospacedDigit())
                    .foregroundColor(Self.doneGreen).fixedSize()
            }
            if dp.removed > 0 {
                Text(verbatim: "−\(dp.removed)").font(.system(size: 11.5, weight: .medium).monospacedDigit())
                    .foregroundColor(Color(hex: "#FF453A")).fixedSize()
            }
        } else if let step {
            // "Runs · Build the app": the kind's verb (or the step's own), then what it acts on.
            let parts = step.components(separatedBy: " · ")
            if parts.count > 1 || kind != nil {
                verb(kind?.activity ?? parts[0])
                if parts.count > 1 {
                    Text(parts.dropFirst().joined(separator: " · "))
                        .font(.system(size: 12.5))
                        .foregroundColor(detail)
                        .lineLimit(1).truncationMode(.tail)
                }
            } else {
                verb(step)   // a question, a line of its own
            }
        } else {
            verb(String(localized: "Thinking"))
        }
    }

    private func verb(_ text: String) -> some View {
        Text(text)
            .font(.system(size: 13, weight: .semibold))
            .foregroundColor(Color(hex: "#F5F6F8"))
            .lineLimit(1)
            .layoutPriority(1)
    }
}

/// The activity box's bottom edge while the agent works: a light running across.
struct RunningEdge: View {
    let tint: Color
    @Environment(\.islandViewActive) private var active

    var body: some View {
        TimelineView(.animation(minimumInterval: 1.0 / 30, paused: !active)) { tl in
            let p = tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1.6) / 1.6
            let eased = p * p * (3 - 2 * p)
            GeometryReader { geo in
                let w = geo.size.width * 0.4
                LinearGradient(colors: [.clear, tint, .clear], startPoint: .leading, endPoint: .trailing)
                    .frame(width: w, height: 2)
                    .offset(x: -w + (geo.size.width + w) * eased)
            }
        }
        .frame(height: 2)
        .allowsHitTesting(false)
    }
}

extension StepKind {
    var symbol: String {
        switch self {
        case .search: "magnifyingglass"
        case .read:   "doc.text"
        case .edit:   "pencil"
        case .run:    "terminal"
        case .test:   "testtube.2"
        case .web:    "globe"
        case .agent:  "person.2"
        case .plan:   "sparkle"
        case .fail:   "exclamationmark.triangle"
        }
    }

    /// By group, not by tool: blue looks, green changes, indigo runs, teal tests, purple thinks.
    var tint: Color {
        switch self {
        case .search, .read, .web: Color(hex: "#0A84FF")
        case .edit:                Color(hex: "#30D158")
        case .run:                 Color(hex: "#5E5CE6")
        case .test:                Color(hex: "#64D2FF")
        case .agent, .plan:        Color(hex: "#BF5AF2")
        case .fail:                Color(hex: "#FF453A")
        }
    }

    /// What an agent asks to do, for the approval card: "wants to run".
    var request: String {
        switch self {
        case .search: String(localized: "search")
        case .read:   String(localized: "read a file")
        case .edit:   String(localized: "edit a file")
        case .run:    String(localized: "run a command")
        case .test:   String(localized: "run tests")
        case .web:    String(localized: "go online")
        case .agent:  String(localized: "start an agent")
        case .plan:   String(localized: "plan")
        case .fail:   String(localized: "retry")
        }
    }

    /// What the agent is doing, as the activity box says it.
    var activity: String {
        switch self {
        case .search: String(localized: "Searching")
        case .read:   String(localized: "Reading")
        case .edit:   String(localized: "Editing")
        case .run:    String(localized: "Running")
        case .test:   String(localized: "Testing")
        case .web:    String(localized: "Browsing")
        case .agent:  String(localized: "Delegating")
        case .plan:   String(localized: "Planning")
        case .fail:   String(localized: "Failed")
        }
    }
}
