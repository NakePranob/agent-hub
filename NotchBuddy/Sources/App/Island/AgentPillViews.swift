import SwiftUI

// MARK: - Agent pills (overview right card, and its "+N" list)

/// The overview's right card: the other pills' logos in a column, in their usual order.
/// Three fit; past three the last slot is "+N", which opens them all in the left card.
struct AgentColumnView: View {
    @ObservedObject var state: AppState
    let showingAll: Bool
    let onMore: () -> Void
    @State private var swapping = false

    var body: some View {
        let others = state.tasks.filter { $0.id != state.focusId }
        let shown = others.count > 3 ? Array(others.prefix(2)) : others
        let hidden = others.dropFirst(shown.count)
        VStack(spacing: 8) {
            ForEach(shown) { task in
                AgentIcon(task: task, swapping: $swapping) { focus(task) }
            }
            if !hidden.isEmpty {
                Button(action: onMore) {
                    Text(verbatim: "+\(hidden.count)")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Color(hex: showingAll ? "#F5F6F8" : "#8E939C"))
                        .frame(width: 22, height: 22)
                        .background(Circle().fill(Color.white.opacity(showingAll ? 0.10 : 0.04)))
                        .overlay(alignment: .topTrailing) {
                            if let mood = Self.urgent(hidden) {
                                Circle().fill(Color(hex: mood.glowHex))
                                    .frame(width: 6, height: 6)
                                    .offset(x: 1, y: -1)
                            }
                        }
                        .contentShape(Circle())
                }
                .buttonStyle(.plain)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    /// What the hidden pills most need: you, then an error, then work in progress.
    static func urgent(_ tasks: some Sequence<AgentTask>) -> RobotMood? {
        let moods = Set(tasks.map { RobotMood($0.state) })
        return [RobotMood.needsYou, .error, .working].first(where: moods.contains)
    }

    private func focus(_ task: AgentTask) {
        swapping = true
        state.setFocus(task.id)
        SoundEngine.shared.play("blip")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { swapping = false }
    }
}

/// A pill as its logo alone, one slot of the right card's column; its name shows on hover.
struct AgentIcon: View {
    let task: AgentTask
    @Binding var swapping: Bool
    let onTap: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: onTap) {
            PillLogo(task: task, size: 22)
                .overlay(alignment: .topTrailing) {
                    if let badge = task.pillBadge {
                        PillBadgeView(badge: badge, taskColor: task.color)
                            .scaleEffect(0.8)
                            .offset(x: 4, y: -4)
                    }
                }
        }
        .buttonStyle(.plain)
        .help(task.id == "integration_claude" ? ClaudeHost.pillName(hostApp: task.hostApp) : task.name)
        .scaleEffect(isHovered ? 1.1 : 1.0)
        .brightness(isHovered ? 0.06 : 0)
        .onHover { newHover in
            guard !swapping else { return }
            withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) { isHovered = newHover }
        }
    }
}

/// Every pill but the focused one, as tiles over the left of the card: each one's logo,
/// name and what it has going on. Opened by the rail's "+N"; a click focuses that pill,
/// which closes the list. "Manage" opens Settings → Active pills.
struct AgentPillsView: View {
    @ObservedObject var state: AppState
    let onDismiss: () -> Void
    @State private var swapping = false

    private let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 3)

    var body: some View {
        let others = state.tasks.filter { $0.id != state.focusId }
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 7) {
                ListBackButton(action: onDismiss)
                Text("Apps").font(.system(size: 14, weight: .semibold))
                ListCount(text: "\(others.count)")
                Spacer(minLength: 4)
                Button {
                    NotificationCenter.default.post(name: .openFullSettings, object: "activepills")
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "gearshape").font(.system(size: 10))
                        Text("Manage")
                    }
                    .font(.system(size: 12))
                    .foregroundColor(Color(hex: "#6B7079"))
                }
                .buttonStyle(.plain)
            }
            .frame(height: 18)

            // Two rows show; more scroll.
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: columns, spacing: 4) {
                    ForEach(others) { task in
                        AppTile(task: task, swapping: $swapping) { focus(task) }
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

    private func focus(_ task: AgentTask) {
        swapping = true
        state.setFocus(task.id)
        SoundEngine.shared.play("blip")
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { swapping = false }
    }
}

/// The round ‹ that closes a list over the card.
struct ListBackButton: View {
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "chevron.left")
                .font(.system(size: 9, weight: .bold))
                .foregroundColor(Color(hex: "#9C9CA3"))
                .frame(width: 18, height: 18)
                .background(Circle().fill(Color.white.opacity(0.08)))
        }
        .buttonStyle(.plain)
    }
}

/// One app in the list: its logo, ringed in its state and with its alert, its name, and a
/// line on what it has going on. Music and Spotify show their controls on hover.
struct AppTile: View {
    let task: AgentTask
    @Binding var swapping: Bool
    let onTap: () -> Void
    @State private var hovered = false

    var body: some View {
        HStack(spacing: 8) {
            PillLogo(task: task, size: 20)
                .overlay(alignment: .topTrailing) {
                    if let badge = task.pillBadge {
                        PillBadgeView(badge: badge, taskColor: task.color)
                            .scaleEffect(0.7)
                            .offset(x: 5, y: -5)
                    }
                }
            VStack(alignment: .leading, spacing: 0) {
                Text(task.id == "integration_claude" ? ClaudeHost.pillName(hostApp: task.hostApp) : task.name)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(hex: "#F5F6F8"))
                Text(AppStatusLine.text(for: task))
                    .font(.system(size: 10))
                    .foregroundColor(Color(hex: "#9C9CA3"))
            }
            .lineLimit(1)
            Spacer(minLength: 0)
            if hovered { controls }
        }
        .padding(.leading, 7)
        .padding(.trailing, 6)
        .frame(height: 30)
        .background(RoundedRectangle(cornerRadius: 10, style: .continuous)
            .fill(Color.white.opacity(hovered ? 0.09 : 0.05)))
        .contentShape(Rectangle())
        .onTapGesture { onTap() }
        .onHover { h in
            guard !swapping else { return }
            withAnimation(.easeOut(duration: 0.15)) { hovered = h }
        }
    }

    @ViewBuilder private var controls: some View {
        #if !APPSTORE
        if task.id == "integration_music", MusicController.shared.trackTitle != nil {
            HStack(spacing: 2) {
                MusicControlButton(icon: AppState.shared.musicPlaying ? "pause.fill" : "play.fill", color: task.color) {
                    MusicController.shared.playPause()
                }
                MusicControlButton(icon: "forward.fill", color: task.color) { MusicController.shared.nextTrack() }
            }
        } else if task.id == "integration_spotify", SpotifyController.shared.track != nil {
            HStack(spacing: 2) {
                MusicControlButton(icon: SpotifyController.shared.isPlaying ? "pause.fill" : "play.fill", color: task.color) {
                    SpotifyController.shared.playPause()
                }
                MusicControlButton(icon: "forward.fill", color: task.color) { SpotifyController.shared.nextTrack() }
            }
        }
        #endif
    }
}

/// What a pill has going on, in a few words, for its tile: "2 to review", "3 unread", the
/// song playing, what the agent is doing. Otherwise the catalog's line about it.
@MainActor
enum AppStatusLine {
    static func text(for task: AgentTask) -> String {
        let state = AppState.shared
        switch task.state {
        case .approval, .question: return String(localized: "Waiting for you")
        case .error:               return String(localized: "Failed")
        case .working, .thinking, .searching:
            return ActivityBox.current(task).flatMap(StepKind.of)?.activity ?? String(localized: "Working")
        default: break
        }
        switch task.id {
        case "integration_github":
            if let pulse = state.githubPulse {
                if !pulse.toReview.isEmpty { return String(localized: "\(pulse.toReview.count) to review") }
                if !pulse.myPRs.isEmpty { return String(localized: "\(pulse.myPRs.count) open PRs") }
                return String(localized: "All clear")
            }
        case "integration_vercel":
            if let last = state.vercelDeployments.first {
                return "\(last.state.capitalized) · \(relative(last.createdAt))"
            }
        case "integration_resend":
            if let total = state.resendTotal { return String(localized: "\(total) emails") }
        case "integration_calcom":
            if state.calcomLoaded { return String(localized: "\(state.calcomBookings.count) upcoming") }
        case "integration_notion":
            if state.notionLoaded { return String(localized: "\(state.notionPages.count) pages") }
        case "integration_crypto":
            if let quote = CryptoController.shared.quotes.first {
                let price = quote.price.formatted(.number.precision(.fractionLength(0...2)))
                return "\(quote.symbol) \(price) " + String(format: "%+.1f%%", quote.change)
            }
        #if !APPSTORE
        case "integration_music":
            if let title = MusicController.shared.trackTitle {
                return [title, MusicController.shared.artist].compactMap { $0 }.joined(separator: " · ")
            }
        case "integration_spotify":
            if let track = SpotifyController.shared.track { return "\(track.title) · \(track.artist)" }
        case "integration_mail":
            if let unread = MailController.shared.unreadCount {
                return unread == 0 ? String(localized: "No unread mail") : String(localized: "\(unread) unread")
            }
        #endif
        default: break
        }
        if let provider = ChatProvider(pillID: task.id) { return String(localized: "Chat with \(provider.displayName)") }
        return PillCatalog.definition(for: task.id)?.subtitle ?? ""
    }

    private static func relative(_ date: Date) -> String {
        let f = RelativeDateTimeFormatter()
        f.unitsStyle = .abbreviated
        return f.localizedString(for: date, relativeTo: Date())
    }
}

struct AgentPill: View {
    let task: AgentTask
    @ObservedObject var state: AppState
    @Binding var swapping: Bool
    let onTap: () -> Void
    @State private var isHovered = false

    private var effectiveColor: String { task.color }

    // The Claude pill shows "VS Code" (or "Claude Code" for a terminal session) regardless of project name
    private var displayName: String {
        task.id == "integration_claude" ? ClaudeHost.pillName(hostApp: task.hostApp) : task.name
    }

    var body: some View {
        Button(action: { onTap() }) {
            ZStack(alignment: .topTrailing) {
                ZStack {
                    Capsule()
                        .fill(isHovered
                              ? Color(hex: effectiveColor).opacity(0.18)
                              : Color(hex: "#0E0F11"))
                    Capsule()
                        .stroke(Color(hex: effectiveColor).opacity(isHovered ? 0.55 : 0.14), lineWidth: 1)
                    HStack(spacing: 0) {
                        PillLogo(task: task, size: 17)
                            .frame(width: 22, height: 22, alignment: .center)
                            .padding(.leading, 8)
                        Spacer()
                    }
                    Text(displayName)
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(isHovered
                                         ? Color(hex: effectiveColor).lighter(by: 0.3)
                                         : Color(hex: "#6B7079"))
                        .lineLimit(1)
                        .truncationMode(.tail)
                        .frame(maxWidth: .infinity, alignment: .center)
                }
                .frame(maxWidth: .infinity)
                .frame(height: 28)
                .shadow(color: Color(hex: effectiveColor).opacity(isHovered ? 0.35 : 0), radius: 10, x: 0, y: 2)

                // Alert badge (approval / finished / error)
                if let badge = task.pillBadge {
                    PillBadgeView(badge: badge, taskColor: effectiveColor)
                        .offset(x: 3, y: -3)
                }
            }
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered ? 1.04 : 1.0)
        .brightness(isHovered ? 0.06 : 0)
        .onHover { newHover in
            guard !swapping else { return }
            withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) { isHovered = newHover }
        }
    }
}

struct PillBadgeView: View {
    let badge: PillBadge
    let taskColor: String

    private var badgeColor: Color {
        switch badge {
        case .approval: return Color(hex: "#F5A524")
        case .finished: return Color(hex: "#22C55E")
        case .error:    return Color(hex: "#F4505E")
        }
    }

    private var icon: String {
        switch badge {
        case .approval: return "exclamationmark"
        case .finished: return "checkmark"
        case .error:    return "xmark"
        }
    }

    var body: some View {
        ZStack {
            Circle()
                .fill(Color(hex: "#0B0C0E"))
                .frame(width: 14, height: 14)
            Circle()
                .fill(badgeColor)
                .frame(width: 12, height: 12)
            Image(systemName: icon)
                .font(.system(size: 6, weight: .bold))
                .foregroundColor(.black)
        }
        .shadow(color: badgeColor.opacity(0.6), radius: 4, x: 0, y: 0)
    }
}

// MARK: - Column agents (right side of non-overview views)

struct ColumnAgentsView: View {
    @ObservedObject var state: AppState

    var others: [AgentTask] {
        state.tasks.filter { $0.id != state.focusId }
    }

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(others.prefix(4).enumerated()), id: \.1.id) { idx, task in
                PillLogo(task: task, size: 13)
                    .frame(width: 16, height: 16)
                    .position(x: 0, y: CGFloat(50 + idx * 24))
                    .animation(.spring(response: 0.5, dampingFraction: 0.72).delay(Double(idx) * 0.035), value: idx)
            }
        }
    }
}
