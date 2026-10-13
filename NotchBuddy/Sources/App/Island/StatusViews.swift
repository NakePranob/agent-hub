import SwiftUI

// MARK: - Empty

struct EmptyStateView: View {
    @ObservedObject var state: AppState

    var body: some View {
        ZStack {
            CardBackground(wash: nil)
            VStack(alignment: .leading, spacing: 5) {
                Text("Nothing running right now.")
                    .font(.system(size: 15, weight: .semibold))
                Text("Drop a file or window, or ask me anything.")
                    .font(.system(size: 12.5))
                    .foregroundColor(Color(hex: "#9C9CA3"))
                HStack(spacing: 7) {
                    PrimaryButton("Ask Claude") { state.view = .prompt }
                    SecondaryButton("Choose a file…") { Self.chooseFile(state) }
                    SecondaryButton("Character") {
                        NotificationCenter.default.post(name: .openFullSettings, object: "character")
                    }
                }
                .padding(.top, 4)
            }
            .padding(.leading, 112)
            .padding(.trailing, 16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// The button's way to what a drop on the notch does: pick a file, then choose what to do with it.
    static func chooseFile(_ state: AppState) {
        let panel = NSOpenPanel()
        panel.canChooseFiles = true
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return }
        state.droppedFile = DroppedFile(url: url, name: url.lastPathComponent)
        state.view = .choose
    }
}

// MARK: - Approval

struct ApprovalView: View {
    @ObservedObject var state: AppState
    @State private var showingDiff = false

    var approval: ApprovalInfo? { state.pendingApproval }

    /// The pill, named after the session that asks (several sessions can share a pill).
    private var asker: AgentTask? {
        guard var task = state.focusTask else { return nil }
        if let project = approval?.projectName, !project.isEmpty { task.name = project }
        return task
    }

    var body: some View {
        // Captured when the card is drawn: a click answers the request that was on screen,
        // and is ignored if the card has moved on to the next one since.
        let shownId = approval?.id
        let kind = approval.flatMap { StepKind.tools[$0.tool]?.kind }
        let count = approval?.queueCount ?? 1
        ZStack {
            CardBackground(wash: nil)
            SoftGlow(color: StatusColor.waiting)
            VStack(alignment: .leading, spacing: 4) {
                StatusHeader(task: asker,
                             status: kind.map { String(localized: "wants to \($0.request)") } ?? String(localized: "needs permission"),
                             color: StatusColor.waiting,
                             counter: count > 1 ? "1/\(count)" : nil)
                // What it is for: Claude Code's description of a command, or the file it touches.
                if let detail = approval?.detail, !detail.isEmpty {
                    HStack(spacing: 6) {
                        Text(detail)
                            .font(.system(size: 13, weight: .semibold))
                            .foregroundColor(Color(hex: "#F5F6F8"))
                            .lineLimit(1).truncationMode(.tail)
                        if let diff = approval?.diff {
                            DiffCounts(added: diff.added, removed: diff.removed)
                        }
                    }
                }
                CodeBlock(text: approval?.command ?? approval?.tool ?? "…")
                HStack(spacing: 7) {
                    SecondaryButton("Deny") {
                        HookServer.shared.sendApprovalDecision("deny", for: shownId)
                    }
                    // Codex, Copilot CLI and Muse Code do not support updatedPermissions
                    let hideAlways = approval?.pillId == "agent_codex"
                        || approval?.pillId == "agent_copilot"
                        || approval?.pillId == "agent_muse"
                    if !hideAlways {
                        SecondaryButton("Always") {
                            HookServer.shared.sendApprovalDecision("always", for: shownId)
                        }
                    }
                    Spacer(minLength: 4)
                    if approval?.diff != nil {
                        SecondaryButton("View diff") { showingDiff = true }
                    }
                    PrimaryButton("Allow", tint: StatusColor.waiting) {
                        HookServer.shared.sendApprovalDecision("allow", for: shownId)
                    }
                }
            }
            .padding(.leading, 112)
            .padding(.trailing, 14)
            .frame(maxWidth: .infinity, alignment: .leading)

            // The change itself, over the card; ← or Esc comes back to the buttons.
            if showingDiff, let diff = approval?.diff {
                CardBackground(wash: nil)
                DiffCardView(diff: diff, onDismiss: { showingDiff = false })
                    .transition(.opacity)
            }
        }
        .onChange(of: approval?.id) { _, _ in showingDiff = false }
    }
}

/// "+4 −8", the lines a change adds and removes.
struct DiffCounts: View {
    let added: Int
    let removed: Int

    var body: some View {
        HStack(spacing: 4) {
            if added > 0 { Text(verbatim: "+\(added)").foregroundColor(StatusColor.done) }
            if removed > 0 { Text(verbatim: "−\(removed)").foregroundColor(StatusColor.failed) }
        }
        .font(.system(size: 11.5, weight: .medium).monospacedDigit())
        .fixedSize()
    }
}

// MARK: - Question

struct QuestionView: View {
    @ObservedObject var state: AppState
    @State private var questionIndex = 0
    // Per-question selected labels (empty = none chosen yet)
    @State private var selections: [[String]] = []
    // Per-question custom "Other…" text
    @State private var otherTexts: [String] = []
    // Per-question "Other…" mode active
    @State private var showOther: [Bool] = []
    @FocusState private var otherFieldFocused: Bool

    var question: AskQuestion? { state.pendingQuestion }

    var body: some View {
        ZStack {
            CardBackground(wash: nil)
            SoftGlow(color: StatusColor.waiting)
            if let q = question, !q.questions.isEmpty {
                let qi = min(questionIndex, q.questions.count - 1)
                let item = q.questions[qi]
                let isLast = qi == q.questions.count - 1
                let isMulti = item.multiSelect
                let curSel = qi < selections.count ? selections[qi] : []
                let curOther = qi < showOther.count ? showOther[qi] : false
                let curOtherText = qi < otherTexts.count ? otherTexts[qi] : ""
                let canProceed = !curSel.isEmpty || (curOther && !curOtherText.isEmpty)

                VStack(alignment: .leading, spacing: 5) {
                    HStack(spacing: 8) {
                        StatusHeader(task: asker(q), status: String(localized: "is asking"),
                                     color: StatusColor.waiting,
                                     counter: q.questions.count > 1 ? "\(qi + 1)/\(q.questions.count)" : nil)
                        Button("Reply in terminal") { HookServer.shared.sendQuestionAsk() }
                            .buttonStyle(.plain)
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: "#6B7079"))
                            .fixedSize()
                    }
                    // Optional short header label above question text
                    if !item.header.isEmpty {
                        Text(item.header.uppercased())
                            .font(.system(size: 10.5, weight: .semibold))
                            .tracking(0.4)
                            .foregroundColor(StatusColor.waiting)
                    }
                    Text(item.question)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(Color(hex: "#F5F6F8"))
                        .fixedSize(horizontal: false, vertical: true)
                    // Options (wrapping) or "Other…" compact inline row
                    if curOther {
                        HStack(spacing: 6) {
                            TextField("Your answer…", text: Binding(
                                get: { qi < otherTexts.count ? otherTexts[qi] : "" },
                                set: { v in if qi < otherTexts.count { otherTexts[qi] = v } }
                            ))
                            .textFieldStyle(.plain)
                            .font(.system(size: 12.5))
                            .foregroundColor(Color(hex: "#F5F6F8"))
                            .focused($otherFieldFocused)
                            .onAppear { otherFieldFocused = true }
                            .onSubmit { commitOtherAndProceed(q: q, qi: qi, isLast: isLast) }
                            .onExitCommand { if qi < showOther.count { showOther[qi] = false } }
                            .padding(.horizontal, 10).frame(height: 27)
                            .background(RoundedRectangle(cornerRadius: 9).fill(Color.white.opacity(0.07)))
                            .overlay(RoundedRectangle(cornerRadius: 9).stroke(StatusColor.waiting.opacity(0.55)))
                            PrimaryButton(isLast ? "Send" : "Next", tint: StatusColor.waiting) {
                                commitOtherAndProceed(q: q, qi: qi, isLast: isLast)
                            }
                            .disabled(curOtherText.isEmpty)
                            .opacity(curOtherText.isEmpty ? 0.4 : 1)
                            Button { if qi < showOther.count { showOther[qi] = false } } label: {
                                Image(systemName: "xmark").font(.system(size: 9, weight: .semibold))
                            }
                            .buttonStyle(.plain)
                            .foregroundColor(Color(hex: "#6B7079"))
                        }
                    } else if item.hasDescriptions {
                        VStack(alignment: .leading, spacing: 5) {
                            ForEach(Array(item.options.enumerated()), id: \.offset) { idx, opt in
                                let isSelected = curSel.contains(opt.label)
                                Button {
                                    if isMulti {
                                        toggleSelection(qi: qi, label: opt.label)
                                    } else {
                                        selectAndProceed(q: q, qi: qi, label: opt.label, isLast: isLast)
                                    }
                                } label: {
                                    OptionRow(label: opt.label, description: opt.description,
                                              number: idx + 1, selected: isSelected, checkbox: isMulti)
                                }
                                .buttonStyle(.plain)
                                .keyboardShortcut(KeyEquivalent(Character(String(idx + 1))), modifiers: [])
                            }
                            SecondaryButton("Other…") {
                                if qi < showOther.count { showOther[qi] = true }
                            }
                        }
                    } else {
                        ChipFlowLayout(spacing: 6) {
                            ForEach(Array(item.options.enumerated()), id: \.offset) { idx, opt in
                                let isSelected = curSel.contains(opt.label)
                                Button {
                                    if isMulti {
                                        toggleSelection(qi: qi, label: opt.label)
                                    } else {
                                        selectAndProceed(q: q, qi: qi, label: opt.label, isLast: isLast)
                                    }
                                } label: {
                                    OptionChip(label: opt.label, number: idx + 1,
                                               selected: isSelected, checkbox: isMulti)
                                }
                                .buttonStyle(.plain)
                                .keyboardShortcut(KeyEquivalent(Character(String(idx + 1))), modifiers: [])
                            }
                            // "Other…" implicit free-text option
                            Button {
                                if qi < showOther.count { showOther[qi] = true }
                            } label: {
                                OptionChip(label: String(localized: "Other…"), number: nil, selected: false, checkbox: false)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                    // Send/Next — only for multi-select (and not while "Other…" field is open)
                    if isMulti && !curOther {
                        HStack {
                            Spacer()
                            PrimaryButton(isLast ? "Send" : "Next", tint: StatusColor.waiting) {
                                proceedFromQuestion(q: q, qi: qi, isLast: isLast)
                            }
                            .disabled(!canProceed)
                            .opacity(canProceed ? 1 : 0.4)
                        }
                    }
                }
                .padding(.leading, 112)
                .padding(.trailing, 14)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .onAppear { resetQuestionState() }
        .onChange(of: state.pendingQuestion) { _, _ in resetQuestionState() }
        .onDisappear { HookServer.shared.releaseQuestionFD() }
    }

    /// The pill, named after the session that asks (several sessions can share a pill).
    private func asker(_ q: AskQuestion) -> AgentTask? {
        guard var task = state.focusTask else { return nil }
        if !q.projectName.isEmpty { task.name = q.projectName }
        return task
    }

    private func resetQuestionState() {
        questionIndex = 0
        let count = state.pendingQuestion?.questions.count ?? 0
        selections = Array(repeating: [], count: count)
        otherTexts = Array(repeating: "", count: count)
        showOther  = Array(repeating: false, count: count)
    }

    private func toggleSelection(qi: Int, label: String) {
        guard qi < selections.count else { return }
        if let i = selections[qi].firstIndex(of: label) {
            selections[qi].remove(at: i)
        } else {
            selections[qi].append(label)
        }
    }

    // Single-select: pick a label and immediately advance/send
    private func selectAndProceed(q: AskQuestion, qi: Int, label: String, isLast: Bool) {
        guard qi < selections.count else { return }
        selections[qi] = [label]
        if isLast { sendAnswers(q: q) } else { withAnimation { questionIndex = qi + 1 } }
    }

    // Multi-select Send/Next button
    private func proceedFromQuestion(q: AskQuestion, qi: Int, isLast: Bool) {
        if isLast { sendAnswers(q: q) } else { withAnimation { questionIndex = qi + 1 } }
    }

    // "Other…" confirm
    private func commitOtherAndProceed(q: AskQuestion, qi: Int, isLast: Bool) {
        let text = qi < otherTexts.count ? otherTexts[qi] : ""
        guard !text.isEmpty else { return }
        if qi < selections.count { selections[qi] = [text] }
        if isLast {
            sendAnswers(q: q)
        } else {
            if qi < showOther.count { showOther[qi] = false }
            withAnimation { questionIndex = qi + 1 }
        }
    }

    private func sendAnswers(q: AskQuestion) {
        let answers = AskQuestion.buildAnswers(questions: q.questions, selections: selections)
        HookServer.shared.sendQuestionAnswers(answers)
    }
}

/// One answer to a question, as a chip: its label and the number key that picks it. With
/// several answers allowed, a box to tick.
struct OptionChip: View {
    let label: String
    let number: Int?
    let selected: Bool
    let checkbox: Bool

    var body: some View {
        HStack(spacing: 6) {
            if checkbox { OptionMark(selected: selected, round: false) }
            Text(label).font(.system(size: 12.5, weight: .medium))
            if let number { KeyHint(text: "\(number)") }
        }
        .padding(.horizontal, 11)
        .frame(height: 27)
        .foregroundColor(Color(hex: selected ? "#FFFFFF" : "#E5E5EA"))
        .background(RoundedRectangle(cornerRadius: 9, style: .continuous)
            .fill(selected ? StatusColor.waiting.opacity(0.18) : Color.white.opacity(0.07)))
        .overlay(RoundedRectangle(cornerRadius: 9, style: .continuous)
            .stroke(selected ? StatusColor.waiting.opacity(0.55) : .clear, lineWidth: 1))
        .contentShape(Rectangle())
    }
}

/// One answer with its explanation, as a row: a radio (or a box), the label, the text under it.
struct OptionRow: View {
    let label: String
    let description: String
    let number: Int
    let selected: Bool
    let checkbox: Bool

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            OptionMark(selected: selected, round: !checkbox).padding(.top, 2)
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Color(hex: "#F5F6F8"))
                if !description.isEmpty {
                    Text(description)
                        .font(.system(size: 12))
                        .foregroundColor(Color(hex: "#9C9CA3"))
                        .multilineTextAlignment(.leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: 4)
            KeyHint(text: "\(number)")
        }
        .padding(.horizontal, 10).padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(selected ? StatusColor.waiting.opacity(0.14) : Color.white.opacity(0.05)))
        .overlay(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .stroke(selected ? StatusColor.waiting.opacity(0.5) : .clear, lineWidth: 1))
        .contentShape(Rectangle())
    }
}

/// A radio or a tick box, filled in the waiting colour once chosen.
struct OptionMark: View {
    let selected: Bool
    let round: Bool

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: round ? 7 : 4, style: .continuous)
        ZStack {
            shape.stroke(selected ? StatusColor.waiting : Color.white.opacity(0.34), lineWidth: selected && round ? 4 : 1.5)
            if selected && !round {
                shape.fill(StatusColor.waiting)
                Image(systemName: "checkmark").font(.system(size: 8, weight: .heavy)).foregroundColor(.black)
            }
        }
        .frame(width: 14, height: 14)
    }
}

/// The key that does it, in a thin box: "1".
struct KeyHint: View {
    let text: String

    var body: some View {
        Text(verbatim: text)
            .font(.system(size: 10, weight: .medium))
            .foregroundColor(Color(hex: "#8E939C"))
            .padding(.horizontal, 4)
            .overlay(RoundedRectangle(cornerRadius: 4).stroke(Color.white.opacity(0.22)))
    }
}

/// Brings the Claude desktop app forward (or launches it) — target of the Claude Desktop pill.
let claudeDesktopBundleId = "com.anthropic.claudefordesktop"

func openClaudeDesktopApp() {
    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: claudeDesktopBundleId) {
        NSWorkspace.shared.openApplication(at: url, configuration: .init(), completionHandler: nil)
    }
}

// MARK: - Confused

struct ConfusedView: View {
    var body: some View {
        ZStack {
            CardBackground(wash: nil)
            SoftGlow(color: StatusColor.note)
            NoticeRow(symbol: "exclamationmark", tint: StatusColor.note,
                      title: String(localized: "Too many hits at once."),
                      subtitle: String(localized: "Give me a sec — back to work in three seconds."))
        }
    }
}

// MARK: - Choose

struct ChooseView: View {
    @ObservedObject var state: AppState

    var body: some View {
        ZStack(alignment: .leading) {
            CardBackground(wash: nil)
            VStack(alignment: .leading, spacing: 8) {
                if let file = state.droppedFile {
                    // The file itself: its icon, its name, its size.
                    HStack(spacing: 9) {
                        Image(nsImage: NSWorkspace.shared.icon(forFile: file.url.path))
                            .resizable().interpolation(.high)
                            .frame(width: 30, height: 30)
                        VStack(alignment: .leading, spacing: 1) {
                            Text(file.name)
                                .font(.system(size: 13, weight: .semibold))
                                .lineLimit(1).truncationMode(.middle)
                            Text(Self.subtitle(file.url))
                                .font(.system(size: 11.5))
                                .foregroundColor(Color(hex: "#9C9CA3"))
                                .lineLimit(1)
                        }
                    }
                    .padding(.vertical, 5).padding(.leading, 6).padding(.trailing, 12)
                    .background(RoundedRectangle(cornerRadius: 11, style: .continuous).fill(Color.white.opacity(0.06)))
                }
                HStack(spacing: 7) {
                    PrimaryButton("Ask a question") { state.view = .prompt }
                    SecondaryButton("Send by email") { state.view = .mail }
                }
            }
            .padding(.leading, 112)
            .padding(.trailing, 16)
        }
    }

    /// "1.2 MB · What do you want to do with it?"
    private static func subtitle(_ url: URL) -> String {
        let ask = String(localized: "What do you want to do with it?")
        guard let bytes = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize else { return ask }
        return ByteCountFormatter.string(fromByteCount: Int64(bytes), countStyle: .file) + " · " + ask
    }
}

// MARK: - Note (short message, auto-closes)

struct NoteView: View {
    @ObservedObject var state: AppState

    var body: some View {
        // A note after an error says what went wrong; the others say where things went.
        let failed = state.stateOverride == .error
        ZStack(alignment: .leading) {
            CardBackground(wash: nil)
            if failed { SoftGlow(color: StatusColor.failed) }
            NoticeRow(symbol: failed ? "xmark" : "info", tint: failed ? StatusColor.failed : StatusColor.working,
                      title: state.noteMessage ?? "", subtitle: nil)
        }
    }
}

/// A short notice: its icon in a tinted square, a line in bold, maybe one under it.
struct NoticeRow: View {
    let symbol: String
    let tint: Color
    let title: String
    let subtitle: String?

    var body: some View {
        HStack(spacing: 10) {
            KindChip(symbol: symbol, tint: tint, size: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.system(size: 15, weight: .semibold))
                    .lineLimit(2)
                if let subtitle {
                    Text(subtitle)
                        .font(.system(size: 12.5))
                        .foregroundColor(Color(hex: "#9C9CA3"))
                        .lineLimit(1)
                }
            }
        }
        .padding(.leading, 112)
        .padding(.trailing, 16)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
