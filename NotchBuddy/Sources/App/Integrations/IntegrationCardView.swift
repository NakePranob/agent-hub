import SwiftUI

// MARK: - Integration card (overview left card when an integration pill is focused)

struct IntegrationCardView: View {
    let task: AgentTask
    @Binding var showingDetail: Bool
    var onDiffTap: ((Int) -> Void)? = nil
    var onSessionList: () -> Void = {}
    var onOpen: () -> Void = {}
    @ObservedObject private var appState = AppState.shared
    @State private var githubDetailSection: GitHubDetailSection = .myPRs
    #if !APPSTORE
    @ObservedObject private var mailController = MailController.shared
    #endif

    private var isConfigured: Bool {
        switch task.id {
        // Cursor sessions are Claude Code running in Cursor's integrated terminal,
        // so the Cursor pill is set up exactly when the Claude Code hooks are.
        case "integration_claude", "agent_cursor":
            return HookServer.claudeHooksInstalled()
        case "agent_codex":
            #if !APPSTORE
            return HookServer.codexHooksInstalled()
            #else
            return false
            #endif
        case "agent_gemini":
            #if !APPSTORE
            return HookServer.geminiHooksInstalled()
            #else
            return false
            #endif
        case "agent_antigravity":
            #if !APPSTORE
            return HookServer.agyHooksInstalled()
            #else
            return false
            #endif
        case "agent_copilot":
            #if !APPSTORE
            return HookServer.copilotHooksInstalled()
            #else
            return false
            #endif
        case "agent_muse":
            #if !APPSTORE
            return HookServer.museHooksInstalled()
            #else
            return false
            #endif
        case "agent_opencode":
            #if !APPSTORE
            return HookServer.openCodePluginInstalled()
            #else
            return false
            #endif
        case "agent_amp":
            #if !APPSTORE
            return HookServer.ampPluginInstalled()
            #else
            return false
            #endif
        case "agent_hermes":
            #if !APPSTORE
            return HookServer.hermesPluginInstalled()
            #else
            return false
            #endif
        case "agent_claude-desktop":
            return true  // nothing to install: the relay tags desktop sessions on its own
        case "integration_music":
            #if !APPSTORE
            return true  // Apple Music is always installed on macOS
            #else
            return false
            #endif
        case "integration_mail":
            #if !APPSTORE
            return true  // Apple Mail is always installed on macOS: nothing to set up
            #else
            return false
            #endif
        case "integration_crypto":
            return true  // public market data: no key, nothing to set up
        case "ai_anthropic":  return KeychainStore.shared.get("anthropic-api-key") != nil
        case "ai_google":     return KeychainStore.shared.get("google-api-key")    != nil
        case "ai_openai":     return KeychainStore.shared.get("openai-api-key")    != nil
        case "ai_ollama":     return !AppState.shared.ollamaServerURL.isEmpty
        case "ai_lmstudio":   return !AppState.shared.lmstudioServerURL.isEmpty
        case "integration_resend":  return KeychainStore.shared.get("resend-api-key") != nil
        case "integration_n8n":     return KeychainStore.shared.get("n8n-api-key")    != nil
        case "integration_vercel":  return KeychainStore.shared.get("vercel-token")   != nil
        case "integration_github":  return KeychainStore.shared.get("github-token")   != nil
        case "integration_stripe":  return KeychainStore.shared.get("stripe-api-key") != nil
        case "integration_notion":  return KeychainStore.shared.get("notion-api-key") != nil
        case "integration_calcom":  return KeychainStore.shared.get("calcom-api-key") != nil
        default: return false
        }
    }

    private var openURL: URL? {
        switch task.id {
        case "integration_claude":  return nil  // uses terminal button below
        case "integration_resend":  return URL(string: "https://resend.com/emails")
        case "integration_n8n":
            if let s = KeychainStore.shared.get("n8n-url") { return URL(string: s) }
            return nil
        case "integration_vercel":  return URL(string: "https://vercel.com/dashboard")
        case "integration_github":  return URL(string: "https://github.com")
        case "integration_stripe":  return URL(string: "https://dashboard.stripe.com/payments")
        case "integration_notion":  return URL(string: "https://notion.so")
        case "integration_calcom":  return URL(string: "https://app.cal.com/bookings")
        default: return nil
        }
    }

    // Workspace/agent pill with active session: show ticker layout
    private var agentSessionActive: Bool {
        guard let def = PillCatalog.definition(for: task.id) else { return false }
        guard def.category == .workspace || def.category == .agent else { return false }
        // Several sessions: keep the row up even on one that hasn't done anything yet.
        return task.state != .idle || !task.steps.isEmpty || appState.sessionLanes[task.id] != nil
    }

    // n8n with a finished execution: show result row instead of "Open n8n" button
    private var n8nHasActivity: Bool {
        task.id == "integration_n8n" && !task.steps.isEmpty &&
        (task.state == .finished || task.state == .error)
    }

    // Vercel with recent deployments
    private var vercelHasActivity: Bool {
        task.id == "integration_vercel" && !appState.vercelDeployments.isEmpty
    }

    // Resend with recent emails
    private var resendHasData: Bool {
        task.id == "integration_resend" && !appState.resendEmails.isEmpty
    }

    // GitHub with stats or pulse loaded
    private var githubHasData: Bool {
        task.id == "integration_github" && (appState.githubPulse != nil || appState.githubStats != nil)
    }

    // GitHub with pulse loaded (richer card)
    private var githubHasPulse: Bool {
        task.id == "integration_github" && appState.githubPulse != nil
    }

    // Stripe: show card as soon as first poll completes (balance OR payments)
    private var stripeHasData: Bool {
        task.id == "integration_stripe" && appState.stripeLoaded
    }

    // Cal.com: show calendar as soon as first poll completes
    private var calcomHasData: Bool {
        task.id == "integration_calcom" && appState.calcomLoaded
    }

    // Notion: show pages as soon as first poll completes
    private var notionHasData: Bool {
        task.id == "integration_notion" && appState.notionLoaded
    }

    // Apple Music: show card when a track is loaded (playing or paused) or automation is denied
    private var musicIsActive: Bool {
        #if !APPSTORE
        guard task.id == "integration_music" else { return false }
        if appState.musicAutomationDenied { return true }
        return MusicController.shared.trackTitle != nil
        #else
        return false
        #endif
    }

    // Apple Mail: the message list once Mail is open and allowed (else the idle card says why)
    private var mailHasData: Bool {
        #if !APPSTORE
        guard task.id == "integration_mail" else { return false }
        let mail = MailController.shared
        return mail.isMailRunning && !mail.automationDenied
        #else
        return false
        #endif
    }

    // Spotify: its own card for every state (playing, idle, not installed, Automation denied)
    private var isSpotify: Bool {
        #if !APPSTORE
        return task.id == "integration_spotify"
        #else
        return false
        #endif
    }

    private var statusDot: Color {
        #if !APPSTORE
        if task.id == "integration_music" {
            if appState.musicAutomationDenied { return Color(hex: "#F4505E") }
            return appState.musicPlaying ? Color(hex: "#FA2D48") : Color(hex: "#22C55E")
        }
        #endif
        #if !APPSTORE
        if task.id == "integration_mail" {
            if mailController.automationDenied { return Color(hex: "#F4505E") }
            return mailController.isMailRunning ? Color(hex: "#22C55E") : Color(hex: "#6B7079")
        }
        #endif
        if PillCatalog.definition(for: task.id)?.comingSoon == true { return Color(hex: "#6B7079") }
        let svcErr = task.id == "integration_stripe" ? appState.stripeError
                   : task.id == "integration_calcom"  ? appState.calcomError
                   : nil
        if svcErr != nil { return Color(hex: "#F4505E") }
        return isConfigured ? Color(hex: "#22C55E") : Color(hex: "#F4505E")
    }

    private var statusLabel: String {
        #if !APPSTORE
        if task.id == "integration_music" {
            if appState.musicAutomationDenied { return String(localized: "Automation not allowed") }
            if appState.musicPlaying { return String(format: String(localized: "Playing · %@"), MusicController.shared.trackTitle ?? String(localized: "Unknown")) }
            return String(localized: "Not playing")
        }
        #endif
        #if !APPSTORE
        if task.id == "integration_mail" {
            if mailController.automationDenied { return String(localized: "Automation not allowed") }
            return mailController.isMailRunning ? String(localized: "Loading…") : String(localized: "Mail is closed")
        }
        #endif
        if PillCatalog.definition(for: task.id)?.comingSoon == true { return String(localized: "Coming soon") }
        let svcErr = task.id == "integration_stripe" ? appState.stripeError
                   : task.id == "integration_calcom"  ? appState.calcomError
                   : nil
        if let err = svcErr { return err }
        // Pills driven by hooks, never by a key: the idle card reports whether the
        // hooks are in place. integration_claude read "Connected · loading…" with
        // nothing left to load — a session replaces this card, it never resolves here.
        let isHooks = task.id == "integration_claude" || task.id == "agent_gemini"
                   || task.id == "agent_antigravity"  || task.id == "agent_cursor"
                   || task.id == "agent_codex"        || task.id == "agent_copilot"
                   || task.id == "agent_muse"         || task.id == "agent_opencode"
                   || task.id == "agent_amp"          || task.id == "agent_hermes"
        let isAI    = ChatProvider(pillID: task.id) != nil
        if isConfigured {
            if isHooks { return String(localized: "Hooks installed") }
            // No key or poller behind this pill: it only reflects hook events.
            if task.id == "agent_claude-desktop" { return String(localized: "Ready · no setup needed") }
            if isAI {
                let provider = ChatProvider(pillID: task.id)!
                if provider.isLocal {
                    let model = provider == .ollama ? appState.ollamaChatModel : appState.lmstudioChatModel
                    return String(localized: "Connected · \(model)")
                }
                let model: String
                switch task.id {
                case "ai_anthropic": model = appState.claudeModel
                case "ai_google":    model = appState.googleChatModel
                case "ai_openai":    model = appState.openAIChatModel
                default:             model = ""
                }
                return String(localized: "Key configured · \(model)")
            }
            return String(localized: "Connected · loading…")
        } else {
            if isHooks { return String(localized: "Hooks not installed") }
            if isAI {
                let provider = ChatProvider(pillID: task.id)!
                return provider.isLocal ? String(localized: "Not connected") : String(localized: "Key not configured")
            }
            return String(localized: "Key not configured")
        }
    }

    var body: some View {
        if showingDetail && n8nHasActivity {
            N8nDetailView(task: task) {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) { showingDetail = false }
            }
            .transition(.opacity)
        } else if showingDetail && vercelHasActivity {
            VercelDetailView(deployment: appState.vercelDeployments[0]) {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) { showingDetail = false }
            }
            .transition(.opacity)
        } else if vercelHasActivity {
            VercelDeploymentListView(deployments: appState.vercelDeployments, onOpenDetail: {
                withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) { showingDetail = true }
            })
            .transition(.opacity)
        } else if resendHasData {
            ResendCardView(emails: appState.resendEmails, total: appState.resendTotal)
                .transition(.opacity)
        } else if showingDetail && githubHasPulse {
            GitHubDetailView(
                section: githubDetailSection,
                pulse: appState.githubPulse!,
                activity: appState.githubActivity,
                stats: appState.githubStats,
                onBack: {
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) { showingDetail = false }
                }
            )
            .transition(.opacity)
        } else if githubHasPulse {
            GitHubPulseCardView(
                pulse: appState.githubPulse!,
                stats: appState.githubStats,
                activity: appState.githubActivity,
                onTapSection: { section in
                    githubDetailSection = section
                    withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) { showingDetail = true }
                }
            )
            .transition(.opacity)
        } else if githubHasData {
            GitHubStatsCardView(stats: appState.githubStats!)
                .transition(.opacity)
        } else if stripeHasData {
            StripeCardView()
                .transition(.opacity)
        } else if calcomHasData {
            CalcomCardView()
                .transition(.opacity)
        } else if notionHasData {
            NotionCardView()
                .transition(.opacity)
        } else if musicIsActive {
            #if !APPSTORE
            MusicCardView()
                .transition(.opacity)
            #endif
        } else if task.id == "integration_crypto" {
            // Its own card in every state (loading, no coins, prices).
            CryptoCardView()
                .transition(.opacity)
        } else if mailHasData {
            #if !APPSTORE
            MailCardView()
                .transition(.opacity)
            #endif
        } else if isSpotify {
            #if !APPSTORE
            SpotifyCardView()
                .transition(.opacity)
            #endif
        } else if agentSessionActive {
            SessionCardBody(task: task,
                            subtitle: PillCatalog.definition(for: task.id)?.sessionSubtitle ?? "Agent",
                            onSessionList: onSessionList, onDiffTap: onDiffTap, onOpen: onOpen)
        } else {
            // Idle / not connected view — slides in from left when returning from detail
            VStack(alignment: .leading, spacing: 6) {
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(hex: task.color))
                        .frame(width: 7, height: 7)
                    Text(task.id == "integration_claude" ? ClaudeHost.pillName(hostApp: task.hostApp)
                                                         : PillCatalog.definition(for: task.id)?.name ?? task.name)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(hex: "#F5F6F8"))
                    Text(PillCatalog.definition(for: task.id)?.subtitle ?? "Integration")
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "#8E939C"))
                    Spacer(minLength: 2)
                }
                .padding(.top, 6)
                .padding(.leading, 108)
                .padding(.trailing, 36)

                HStack(spacing: 5) {
                    Circle().fill(statusDot).frame(width: 5, height: 5)
                    Text(statusLabel)
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "#6B7079"))
                }
                .padding(.leading, 108)
                .padding(.top, 2)

                HStack(spacing: 8) {
                    if task.id == "integration_claude", task.hostApp != nil {
                        Button("Open \(ClaudeHost.name(for: task.hostApp))") { ClaudeHost.activate(task.hostApp) }
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(hex: task.color).opacity(0.7))
                            .buttonStyle(.plain)
                    } else if task.id == "integration_claude" {
                        Button("Open Visual Studio Code") { openVSCode() }
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(hex: task.color).opacity(0.7))
                            .buttonStyle(.plain)
                    } else if task.id == "agent_cursor" {
                        #if !APPSTORE
                        if let url = NSWorkspace.shared.urlForApplication(
                            withBundleIdentifier: "com.todesktop.230313mzl4w4u92") {
                            Button("Open Cursor") {
                                NSWorkspace.shared.openApplication(at: url, configuration: .init(),
                                                                   completionHandler: nil)
                            }
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(hex: task.color).opacity(0.85))
                            .buttonStyle(.plain)
                        }
                        #endif
                    } else if task.id == "agent_codex" {
                        #if !APPSTORE
                        if let url = NSWorkspace.shared.urlForApplication(
                            withBundleIdentifier: "com.openai.codex") {
                            Button("Open Codex") {
                                NSWorkspace.shared.openApplication(at: url, configuration: .init(),
                                                                   completionHandler: nil)
                            }
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(hex: task.color).opacity(0.85))
                            .buttonStyle(.plain)
                        }
                        #endif
                    } else if let provider = ChatProvider(pillID: task.id) {
                        if isConfigured {
                            Button(String(format: String(localized: "Chat with %@"), task.name)) {
                                switchChatProvider(provider)
                            }
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(hex: task.color).opacity(0.85))
                            .buttonStyle(.plain)
                        }
                    } else if task.id == "integration_music" {
                        #if !APPSTORE
                        Button("Open Music") { MusicController.shared.openMusic() }
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(hex: task.color).opacity(0.85))
                            .buttonStyle(.plain)
                        if appState.musicAutomationDenied {
                            Button("Open Settings…") { MusicController.shared.openAutomationSettings() }
                                .font(.system(size: 11))
                                .foregroundColor(Color(hex: "#8E939C"))
                                .buttonStyle(.plain)
                        }
                        #endif
                    } else if task.id == "integration_mail" {
                        #if !APPSTORE
                        Button("Open Mail") { MailController.shared.openMail() }
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(hex: task.color).opacity(0.85))
                            .buttonStyle(.plain)
                        if mailController.automationDenied {
                            Button("Open Settings…") { MailController.shared.openAutomationSettings() }
                                .font(.system(size: 11))
                                .foregroundColor(Color(hex: "#8E939C"))
                                .buttonStyle(.plain)
                        }
                        #endif
                    } else if n8nHasActivity {
                        // Clickable pill — tap to open execution detail
                        let success = task.state == .finished
                        let accent  = success ? Color(hex: "#22C55E") : Color(hex: "#F4505E")
                        Button(action: {
                            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) { showingDetail = true }
                        }) {
                            HStack(spacing: 5) {
                                Circle().fill(accent).frame(width: 5, height: 5)
                                Text(task.steps.first ?? "Workflow")
                                    .font(.system(size: 11))
                                    .foregroundColor(Color(hex: "#C5C8CD"))
                                    .lineLimit(1).truncationMode(.tail)
                                Image(systemName: "ellipsis")
                                    .font(.system(size: 8, weight: .medium))
                                    .foregroundColor(Color(hex: "#6B7079"))
                            }
                            .padding(.horizontal, 8).padding(.vertical, 3)
                            .background(accent.opacity(0.1))
                            .clipShape(Capsule())
                            .overlay(Capsule().stroke(accent.opacity(0.22), lineWidth: 1))
                        }
                        .buttonStyle(.plain)
                    } else if let url = openURL {
                        Button("Open \(task.name)") { NSWorkspace.shared.open(url) }
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(hex: task.color).opacity(0.85))
                            .buttonStyle(.plain)
                    }
                    if task.id == "integration_stripe" && isConfigured {
                        Button("Refresh") { Task { @MainActor in StripePoller.shared.pollNow() } }
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(hex: "#0570DE").opacity(0.85))
                            .buttonStyle(.plain)
                    }
                    if task.id == "integration_calcom" && isConfigured {
                        Button("Refresh") { Task { @MainActor in CalcomPoller.shared.pollNow() } }
                            .font(.system(size: 11, weight: .medium))
                            .foregroundColor(Color(hex: "#C9956A").opacity(0.85))
                            .buttonStyle(.plain)
                    }
                    // Settings button: shown when not configured, except cursor/codex and music
                    if !isConfigured
                       && task.id != "agent_cursor"
                       && task.id != "agent_codex"
                       && task.id != "integration_music"
                       && task.id != "integration_mail" {
                        Button("Settings…") {
                            let section: String
                            switch PillCatalog.definition(for: task.id)?.category {
                            case .workspace, .agent: section = "agents"
                            case .ai:                section = "chat"
                            default:                 section = "integrations"
                            }
                            NotificationCenter.default.post(name: .openFullSettings, object: section)
                        }
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "#8E939C"))
                        .buttonStyle(.plain)
                    }
                }
                .padding(.leading, 108)
                .padding(.top, 2)
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.top, 4)
            .transition(.opacity)
        }
    }

    private func openVSCode() {
        let ids = ["com.microsoft.VSCode", "com.microsoft.VSCodeInsiders", "com.vscodium.codium"]
        let appURL = ids.compactMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }.first

        // If we have a project folder, open it directly in VS Code
        if let cwd = task.sessionCwd, !cwd.isEmpty, let appURL = appURL {
            NSWorkspace.shared.open(
                [URL(fileURLWithPath: cwd)],
                withApplicationAt: appURL,
                configuration: .init(),
                completionHandler: nil
            )
            return
        }

        // No cwd: activate running instance or launch fresh
        if let running = ids.compactMap({ id in
            NSWorkspace.shared.runningApplications.first { $0.bundleIdentifier == id }
        }).first {
            running.activate(options: .activateIgnoringOtherApps)
            return
        }
        if let appURL = appURL {
            NSWorkspace.shared.openApplication(at: appURL, configuration: .init(), completionHandler: nil)
        }
    }

}
