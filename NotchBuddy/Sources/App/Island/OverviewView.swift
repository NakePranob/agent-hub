import SwiftUI

// MARK: - Overview

struct OverviewView: View {
    @ObservedObject var state: AppState
    @State private var showingN8nDetail = false
    @State private var activeDiffId: Int? = nil
    @State private var showingSessions = false
    @State private var showingApps = false

    var agent: AgentTask? { state.focusTask.map(state.cardTask) }

    var body: some View {
        // One card: the focused pill on the left, the other pills' rail on the right.
        HStack(spacing: 0) {
            ZStack(alignment: .topLeading) {
                Color.clear

                // Title row + step wheel (or integration card)
                if let agent = agent {
                    if agent.isIntegration {
                        IntegrationCardView(task: agent, showingDetail: $showingN8nDetail, onDiffTap: { diffIdx in
                            withAnimation(.easeIn(duration: 0.16)) { activeDiffId = diffIdx }
                        }, onSessionList: openSessionList, onOpen: { openApp(agent) })
                    } else {
                        SessionCardBody(task: agent, subtitle: {
                            switch agent.source {
                            case .claudeCode: return "Claude Code"
                            case .agent:      return "Agent"
                            case .n8n:        return "n8n"
                            }
                        }(), onSessionList: openSessionList, onDiffTap: { diffIdx in
                            withAnimation(.easeIn(duration: 0.16)) { activeDiffId = diffIdx }
                        }, onOpen: { openApp(agent) })
                    }
                }

                // Plan detail overlays on top of normal content (GitHub build, home view only)
                #if !APPSTORE
                if state.showingPlanDetail {
                    CardMaterial.fill   // square: the card's shape clips it
                    Group {
                        if state.planDetailIsCodex {
                            CodexPlanCardView(usage: state.codexPlanUsage)
                        } else {
                            // Claude and Codex both on: the header shows only the Claude pill,
                            // Codex is a third row here that opens its own card.
                            let bothPlans = state.showPlanInNotch && state.planRelayInstalled
                                && state.showCodexPlanInNotch
                            ClaudePlanCardView(usage: state.claudePlanUsage,
                                               codexRow: bothPlans,
                                               codexUsage: state.codexPlanUsage,
                                               onCodex: {
                                                   withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                                                       state.planDetailIsCodex = true
                                                   }
                                                   state.refreshCodexPlanUsage()
                                               })
                        }
                    }
                    .transition(.opacity)
                }
                #endif

                // Diff overlay — replaces ticker when a diff step is tapped
                if let diffId = activeDiffId,
                   let task = agent,
                   let diff = state.sessionDiffs[task.id]?.first(where: { $0.id == diffId }) {
                    CardMaterial.fill   // square: the card's shape clips it
                    DiffCardView(diff: diff, onDismiss: { activeDiffId = nil })
                        .transition(.opacity)
                }

                // Session list — every session behind the pill, from the session row's "+N"
                if showingSessions, let task = agent, let lanes = state.sessionLanes[task.id] {
                    CardMaterial.fill   // square: the card's shape clips it
                    SessionListView(pillId: task.id, lanes: lanes,
                                    shownId: state.shownLane(of: task.id)?.id,
                                    onDismiss: {
                                        withAnimation(.easeIn(duration: 0.16)) { showingSessions = false }
                                    })
                        .transition(.opacity)
                }

                // Every other pill, from the right card's "+N"
                if showingApps {
                    CardMaterial.fill   // square: the card's shape clips it
                    AgentPillsView(state: state, onDismiss: {
                        withAnimation(.easeIn(duration: 0.16)) { showingApps = false }
                    })
                        .transition(.opacity)
                }

                // ↗ jump button — last in ZStack so it renders on top; hidden while any detail is open
                #if !APPSTORE
                let hideJumpButton = showingN8nDetail || state.showingPlanDetail || activeDiffId != nil || showingSessions || showingApps
                #else
                let hideJumpButton = showingN8nDetail || activeDiffId != nil || showingSessions || showingApps
                #endif
                if !hideJumpButton {
                    Button(action: { openAgentTarget(agent) }) {
                        Image(systemName: "arrow.up.right")
                            .font(.system(size: 8, weight: .medium))
                            .foregroundColor(Color(hex: "#5F646D"))
                            .frame(width: 16, height: 16)
                            .background(Color.white.opacity(0.07))
                            .clipShape(Circle())
                    }
                    .buttonStyle(.plain)
                    .padding(.top, 8)
                    .padding(.trailing, 10)
                    .frame(maxWidth: .infinity, alignment: .trailing)
                }
            }

            Rectangle()
                .fill(Color.white.opacity(0.06))
                .frame(width: 1)
                .padding(.vertical, 14)

            // The other pills' logos, "+N" for the rest
            AgentColumnView(state: state, showingAll: showingApps, onMore: {
                withAnimation(.easeIn(duration: 0.16)) { showingApps.toggle() }
            })
            .frame(width: 46)
        }
        .background {
            let glow = SessionCardBody.glow(for: agent)
            ZStack {
                // A turn just over lights the card green from below, as long as the pill shows it.
                CardBackground(wash: agent?.state == .finished ? .green : agent?.state == .error ? .red : nil)
                // The step's colour, rising from the robot's side.
                RadialGradient(colors: [(glow ?? .clear).opacity(0.18), .clear],
                               center: UnitPoint(x: 0.08, y: 0.5), startRadius: 0, endRadius: 280)
            }
            .animation(.easeInOut(duration: 0.5), value: glow)
            .animation(.easeInOut(duration: 0.4), value: agent?.state)
        }
        .clipShape(RoundedRectangle(cornerRadius: 22))
        .onChange(of: state.focusId) { _, new in
            showingN8nDetail = false
            activeDiffId = nil
            showingSessions = false
            showingApps = false
            #if !APPSTORE
            withAnimation(.easeIn(duration: 0.16)) { state.showingPlanDetail = false }
            #endif
            if new == "integration_github" { GithubPoller.shared.refreshIfStale() }
        }
        #if !APPSTORE
        .onChange(of: state.view) { _, v in
            if v != .overview { state.showingPlanDetail = false; activeDiffId = nil }
        }
        #endif
        .onChange(of: state.mode) { _, m in
            if m != .expanded { showingSessions = false; showingApps = false }
            #if !APPSTORE
            if m != .expanded { state.showingPlanDetail = false; activeDiffId = nil }
            #endif
            if m == .expanded && state.focusId == "integration_github" {
                GithubPoller.shared.refreshIfStale()
            }
        }
        .onReceive(NotificationCenter.default.publisher(for: .islandToggleDiff)) { _ in
            if let id = activeDiffId {
                withAnimation(.easeIn(duration: 0.16)) { activeDiffId = nil }
                _ = id
            } else if let task = state.focusTask,
                      let last = state.sessionDiffs[task.id]?.last {
                withAnimation(.easeIn(duration: 0.16)) { activeDiffId = last.id }
            }
        }
    }

    private func openSessionList() {
        withAnimation(.easeIn(duration: 0.16)) { showingSessions = true }
    }

    /// A finished turn's "Open …": the session's app, then the island folds out of the way.
    private func openApp(_ task: AgentTask?) {
        openAgentTarget(task)
        NotificationCenter.default.post(name: .islandCollapse, object: nil)
    }

    private func openAgentTarget(_ task: AgentTask?) {
        guard let task else { return }
        switch task.id {
        case "integration_claude":
            if ClaudeHost.activate(task.hostApp) { return }
            let vscodeBundleId = "com.microsoft.VSCode"
            if let app = NSWorkspace.shared.runningApplications.first(where: { $0.bundleIdentifier == vscodeBundleId }) {
                app.activate(options: .activateIgnoringOtherApps)
            } else {
                NSWorkspace.shared.open(URL(fileURLWithPath: "/Applications/Visual Studio Code.app"))
            }
        case "integration_resend":
            NSWorkspace.shared.open(URL(string: "https://resend.com/emails")!)
        case "integration_mail":
            #if !APPSTORE
            MailController.shared.openMail()
            #endif
        case "integration_crypto":
            let exchange = CryptoSettings.exchange
            if let first = CryptoSettings.coins.first,
               let url = exchange.tradeURL(exchange.pair(first, CryptoSettings.currency)) {
                NSWorkspace.shared.open(url)
            }
        case "integration_vercel":
            NSWorkspace.shared.open(URL(string: "https://vercel.com/dashboard")!)
        case "integration_github":
            NSWorkspace.shared.open(URL(string: "https://github.com/pulls")!)
        case "integration_n8n":
            if let urlStr = KeychainStore.shared.get("n8n-url"), let url = URL(string: urlStr) {
                NSWorkspace.shared.open(url)
            }
        case "integration_stripe":
            NSWorkspace.shared.open(URL(string: "https://dashboard.stripe.com/payments")!)
        case "integration_notion":
            NSWorkspace.shared.open(URL(string: "https://notion.so")!)
        case "integration_calcom":
            NSWorkspace.shared.open(URL(string: "https://app.cal.com/bookings")!)
        case "agent_cursor":
            #if !APPSTORE
            if let url = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: "com.todesktop.230313mzl4w4u92") {
                NSWorkspace.shared.openApplication(at: url, configuration: .init(), completionHandler: nil)
            }
            #endif
        case "agent_codex":
            #if !APPSTORE
            if let url = NSWorkspace.shared.urlForApplication(
                withBundleIdentifier: "com.openai.codex") {
                NSWorkspace.shared.openApplication(at: url, configuration: .init(), completionHandler: nil)
            }
            #endif
        case "agent_claude-desktop":
            openClaudeDesktopApp()
        case "agent_gemini", "agent_antigravity",
             "agent_copilot", "agent_muse", "agent_opencode", "agent_amp":
            #if !APPSTORE
            TerminalTarget.activate(sessionBundleId: nil)
            #endif
        case "ai_anthropic":
            switchChatProvider(.anthropic)
        case "ai_google":
            switchChatProvider(.google)
        case "ai_openai":
            switchChatProvider(.openai)
        case "ai_ollama":
            switchChatProvider(.ollama)
        case "ai_lmstudio":
            switchChatProvider(.lmstudio)
        case "integration_music":
            #if !APPSTORE
            MusicController.shared.openMusic()
            #endif
        case "integration_spotify":
            #if !APPSTORE
            SpotifyController.shared.openSpotify()
            #endif
        default:
            // Non-integration real tasks
            if task.source == .n8n {
                if let urlStr = KeychainStore.shared.get("n8n-url"), let url = URL(string: urlStr) {
                    NSWorkspace.shared.open(url)
                }
            } else {
                #if !APPSTORE
                TerminalTarget.activate(sessionBundleId: task.sessionBundleId)
                #endif
            }
        }
    }
}
