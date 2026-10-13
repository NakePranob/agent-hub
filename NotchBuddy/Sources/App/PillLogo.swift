import AppKit
import SwiftUI

/// A pill's app: its own icon when the app is on this Mac, else its initials on the pill's colour;
/// ringed in the colour of what it is doing. It takes the place of the pills' mini Mochis: the
/// robot on the island is the character, the pills say which app.
struct PillLogo: View {
    let task: AgentTask
    var size: CGFloat
    /// The state ring; off where the card already says what the agent is doing.
    var ringed = true
    @Environment(\.islandViewActive) private var active

    var body: some View {
        ZStack {
            if let icon = PillIcons.icon(for: task) {
                Image(nsImage: icon)
                    .resizable()
                    .interpolation(.high)
                    .frame(width: size * 1.12, height: size * 1.12)   // app icons carry a margin of their own
            } else {
                RoundedRectangle(cornerRadius: size * 0.28, style: .continuous)
                    .fill(Color(hex: task.color))
                Text(verbatim: RobotView.initials(PillIcons.name(of: task)))
                    .font(.system(size: size * 0.42, weight: .bold, design: .rounded))
                    .foregroundColor(PillIcons.isLight(task.color) ? Color.black.opacity(0.78) : .white)
            }
        }
        .frame(width: size, height: size)
        .overlay { if ringed { ring } }
    }

    /// Working: an arc running round. Waiting for you, an error, done: a ring in that mood's colour.
    @ViewBuilder private var ring: some View {
        let mood = RobotMood(task.state)
        let colour = Color(hex: mood.glowHex)
        let line = max(1, size * 0.09)
        switch mood {
        case .idle:
            EmptyView()
        case .working:
            TimelineView(.animation(minimumInterval: 1.0 / 24, paused: !active)) { tl in
                Circle()
                    .trim(from: 0, to: 0.28)
                    .stroke(colour, style: StrokeStyle(lineWidth: line, lineCap: .round))
                    .rotationEffect(.degrees(tl.date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: 1) * 360))
            }
            .padding(-line * 1.6)
        case .needsYou, .error, .done:
            Circle()
                .stroke(colour, lineWidth: line)
                .padding(-line * 1.6)
        }
    }
}

/// The installed app behind each pill, looked up once.
@MainActor
enum PillIcons {
    private static var cache: [String: NSImage?] = [:]

    /// Bundle IDs and then app names to look for, by pill.
    private static let apps: [String: (ids: [String], names: [String])] = [
        "integration_claude":   (["com.microsoft.VSCode"], ["Visual Studio Code"]),
        "agent_cursor":         (["com.todesktop.230313mzl4w4u92"], ["Cursor"]),
        "agent_antigravity":    (["com.google.antigravity"], ["Antigravity"]),
        "agent_codex":          (["com.openai.codex"], ["Codex"]),
        "agent_claude-desktop": (["com.anthropic.claudefordesktop"], ["Claude"]),
        "ai_anthropic":         (["com.anthropic.claudefordesktop"], ["Claude"]),
        "ai_openai":            (["com.openai.chat"], ["ChatGPT"]),
        "ai_ollama":            (["com.electron.ollama"], ["Ollama"]),
        "ai_lmstudio":          (["ai.elementlabs.lmstudio"], ["LM Studio"]),
        "integration_music":    (["com.apple.Music"], []),
        "integration_spotify":  (["com.spotify.client"], ["Spotify"]),
        "integration_mail":     (["com.apple.mail"], []),
        "integration_notion":   (["notion.id"], ["Notion"]),
        "integration_github":   (["com.github.GitHubClient"], ["GitHub Desktop"]),
    ]

    static func icon(for task: AgentTask) -> NSImage? {
        // A Claude Code session shows the app it runs in: a terminal, or VS Code.
        let host = task.id == "integration_claude" ? task.hostApp : nil
        let key = task.id + "|" + (host ?? "")
        if let hit = cache[key] { return hit }
        var ids = host.map { [$0] } ?? []
        let known = apps[task.id]
        ids += known?.ids ?? []
        let ws = NSWorkspace.shared
        var found: NSImage?
        if let url = ids.lazy.compactMap({ ws.urlForApplication(withBundleIdentifier: $0) }).first {
            found = ws.icon(forFile: url.path)
        } else {
            let dirs = ["/Applications", NSHomeDirectory() + "/Applications", "/System/Applications"]
            if let path = (known?.names ?? []).lazy.flatMap({ name in dirs.map { "\($0)/\(name).app" } })
                .first(where: { FileManager.default.fileExists(atPath: $0) }) {
                found = ws.icon(forFile: path)
            }
        }
        cache[key] = found
        return found
    }

    /// What the initials are taken from.
    static func name(of task: AgentTask) -> String {
        PillCatalog.definition(for: task.id)?.name ?? task.name
    }

    static func isLight(_ hex: String) -> Bool {
        let c = RobotColor.srgb(hex)
        return 0.2126 * c.x + 0.7152 * c.y + 0.0722 * c.z > 0.6
    }
}
