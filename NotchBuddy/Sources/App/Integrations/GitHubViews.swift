import SwiftUI

// MARK: - GitHub Pulse Card View

private func ciWorstState(_ prs: [GitHubPR]) -> CIState {
    if prs.contains(where: { $0.ci == .failure }) { return .failure }
    if prs.contains(where: { $0.ci == .pending }) { return .pending }
    if prs.contains(where: { $0.ci == .success }) { return .success }
    return .unknown
}

private func ciColor(_ state: CIState) -> String {
    switch state {
    case .failure: return "#F4505E"
    case .pending: return "#F5A524"
    case .success: return "#22C55E"
    case .unknown: return "#6B7079"
    }
}

private func mainCIWorst(_ repos: [GitHubRepoCI]) -> CIState {
    if repos.contains(where: { $0.ci == .failure }) { return .failure }
    if repos.contains(where: { $0.ci == .pending }) { return .pending }
    if repos.contains(where: { $0.ci == .success }) { return .success }
    return .unknown
}

struct GitHubPulseCardView: View {
    let pulse: GitHubPulse
    let stats: GitHubStats?
    let activity: GitHubActivity?
    let onTapSection: (GitHubDetailSection) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 6) {
                Circle()
                    .fill(Color(hex: "#F4505E"))
                    .frame(width: 7, height: 7)
                Text("GitHub")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(hex: "#F5F6F8"))
                if let s = stats {
                    // Stars + 7-day mini-row → opens Activity detail
                    Button(action: { onTapSection(.activity) }) {
                        HStack(spacing: 4) {
                            Text("★ \(formatCount(s.totalStars))")
                                .font(.system(size: 11))
                                .foregroundColor(Color(hex: "#8E939C"))
                                .lineLimit(1)
                            if let act = activity {
                                HStack(spacing: 2) {
                                    ForEach(act.lastDays(7), id: \.date) { day in
                                        RoundedRectangle(cornerRadius: 1.5)
                                            .fill(contributionColor(day.level))
                                            .frame(width: 7, height: 7)
                                    }
                                }
                            }
                        }
                    }
                    .buttonStyle(.plain)
                } else if let act = activity {
                    // No stats yet but activity loaded — show mini-row only
                    Button(action: { onTapSection(.activity) }) {
                        HStack(spacing: 2) {
                            ForEach(act.lastDays(7), id: \.date) { day in
                                RoundedRectangle(cornerRadius: 1.5)
                                    .fill(contributionColor(day.level))
                                    .frame(width: 7, height: 7)
                            }
                        }
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("Overview")
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "#8E939C"))
                }
            }
            .padding(.top, 6)
            .padding(.leading, 108)
            .padding(.trailing, 36)

            // Stat rows
            VStack(alignment: .leading, spacing: 4) {
                // My PRs
                let prWorst = ciWorstState(pulse.myPRs)
                let prValue: String = {
                    let n = pulse.myPRs.count
                    if n == 0 { return "0" }
                    let failing = pulse.myPRs.filter { $0.ci == .failure }.count
                    let pending = pulse.myPRs.filter { $0.ci == .pending }.count
                    if failing > 0 { return "\(n) · \(failing) failing" }
                    if pending > 0 { return "\(n) · running" }
                    return "\(n)"
                }()
                GitHubStatRow(
                    icon: "arrow.triangle.pull", iconColor: ciColor(prWorst),
                    label: String(localized: "My PRs"), value: prValue
                ) { onTapSection(.myPRs) }

                // To review
                let reviewCount = pulse.toReview.count
                GitHubStatRow(
                    icon: "eye",
                    iconColor: reviewCount > 0 ? "#8AB4F8" : "#6B7079",
                    label: String(localized: "To review"),
                    value: "\(reviewCount)"
                ) { onTapSection(.toReview) }

                // Default branch CI
                let mainWorst = mainCIWorst(pulse.mainCI)
                let (ciIcon, ciIconColor, ciValue): (String, String, String) = {
                    switch mainWorst {
                    case .failure:
                        let n = pulse.mainCI.filter { $0.ci == .failure }.count
                        return ("xmark.octagon.fill", "#F4505E", "\(n) failing")
                    case .pending:
                        return ("checkmark.seal.fill", "#F5A524", "running")
                    case .success:
                        return ("checkmark.seal.fill", "#22C55E", "all green")
                    case .unknown:
                        return ("checkmark.seal.fill", "#6B7079", pulse.mainCI.isEmpty ? "no repos" : "unknown")
                    }
                }()
                GitHubStatRow(
                    icon: ciIcon, iconColor: ciIconColor,
                    label: "Default branch CI", value: ciValue
                ) { onTapSection(.mainCI) }
            }
            .padding(.top, 6)
            .padding(.leading, 108)
            .padding(.trailing, 12)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.top, 4)
        .clipped()
    }

    private func formatCount(_ n: Int) -> String {
        if n >= 1000 { return String(format: "%.1fk", Double(n) / 1000) }
        return "\(n)"
    }
}

private struct GitHubStatRow: View {
    let icon: String
    let iconColor: String
    let label: String
    let value: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 10))
                    .foregroundColor(Color(hex: iconColor))
                    .frame(width: 14)
                Text(label)
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "#6B7079"))
                Spacer()
                Text(value)
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(hex: "#C5C8CD"))
                    .monospacedDigit()
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.plain)
    }
}

// MARK: - GitHub Detail View

struct GitHubDetailView: View {
    let section: GitHubDetailSection
    let pulse: GitHubPulse
    let activity: GitHubActivity?
    let stats: GitHubStats?
    let onBack: () -> Void
    @ObservedObject private var appState = AppState.shared

    private var title: String {
        switch section {
        case .myPRs:    return String(localized: "My PRs")
        case .toReview: return String(localized: "To review")
        case .mainCI:   return "Default branch CI"
        case .activity: return String(localized: "Activity")
        }
    }

    private var items: [GitHubPR] {
        switch section {
        case .myPRs:    return pulse.myPRs
        case .toReview: return pulse.toReview
        case .mainCI, .activity: return []
        }
    }

    private var repoItems: [GitHubRepoCI] {
        section == .mainCI ? pulse.mainCI : []
    }

    private var totalItems: Int { items.count + repoItems.count }

    var body: some View {
        if section == .activity {
            GitHubActivityDetailContent(
                activity: activity,
                stats: stats,
                login: pulse.login,
                onBack: onBack
            )
        } else {
            VStack(alignment: .leading, spacing: 0) {
                // Header
                HStack(spacing: 6) {
                    Button(action: onBack) {
                        HStack(spacing: 3) {
                            Image(systemName: "chevron.left")
                                .font(.system(size: 8, weight: .medium))
                            Text(title)
                                .font(.system(size: 12, weight: .semibold))
                        }
                        .foregroundColor(Color(hex: "#F5F6F8"))
                    }
                    .buttonStyle(.plain)
                    Spacer(minLength: 2)
                }
                .padding(.top, 6)
                .padding(.leading, 108)
                .padding(.trailing, 12)

                // List
                if items.isEmpty && repoItems.isEmpty {
                    Text("Nothing here")
                        .font(.system(size: 10.5))
                        .foregroundColor(Color(hex: "#6B7079"))
                        .padding(.top, 8)
                        .padding(.leading, 108)
                } else {
                    ScrollView(.vertical, showsIndicators: false) {
                        VStack(alignment: .leading, spacing: 0) {
                            ForEach(Array(items.enumerated()), id: \.element.id) { idx, pr in
                                GitHubPRRowView(pr: pr, showCI: section == .myPRs,
                                               selected: appState.cardSelection == idx)
                            }
                            ForEach(Array(repoItems.enumerated()), id: \.element.repo) { idx, repo in
                                GitHubRepoCIRowView(repo: repo,
                                                   selected: appState.cardSelection == items.count + idx)
                            }
                        }
                    }
                    .frame(maxHeight: 60)  // 3 rows × 20 pt; rest scrolls
                    .mask(
                        Group {
                            if totalItems > 3 {
                                LinearGradient(
                                    stops: [
                                        .init(color: .black, location: 0),
                                        .init(color: .black, location: 0.8),
                                        .init(color: .clear,  location: 1.0)
                                    ],
                                    startPoint: .top, endPoint: .bottom
                                )
                            } else {
                                Color.black
                            }
                        }
                    )
                    .padding(.top, 4)
                    .padding(.leading, 108)
                    .padding(.trailing, 8)
                }
            }
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .padding(.top, 4)
            .clipped()
            .onAppear {
                GithubPoller.shared.refreshIfStale()
                appState.cardItemCount = totalItems
            }
            .onDisappear { appState.cardItemCount = 0 }
            .onReceive(NotificationCenter.default.publisher(for: .islandActivateCardSelection)) { _ in
                guard let sel = appState.cardSelection else { return }
                if sel < items.count {
                    let pr = items[sel]
                    if let url = safeWebURL(pr.url), url.host == "github.com" {
                        NSWorkspace.shared.open(url)
                    }
                } else {
                    let repoIdx = sel - items.count
                    guard repoIdx < repoItems.count else { return }
                    let repo = repoItems[repoIdx]
                    let actionsURL = repo.url.hasSuffix("/") ? repo.url + "actions" : repo.url + "/actions"
                    if let url = safeWebURL(actionsURL), url.host == "github.com" {
                        NSWorkspace.shared.open(url)
                    }
                }
            }
            .onExitCommand { onBack() }
        }
    }
}

// MARK: - GitHub Activity Detail

private struct GitHubActivityDetailContent: View {
    let activity: GitHubActivity?
    let stats: GitHubStats?
    let login: String
    let onBack: () -> Void

    @State private var hoveredDay: ContributionDay? = nil

    // Dynamic grid: s=7pt, spacing=1.5pt; numWeeks = floor((202 + 1.5) / (7 + 1.5)) = 23
    private let squareSize: CGFloat = 7
    private let spacing: CGFloat = 1.5
    private var numWeeks: Int { Int((202 + spacing) / (squareSize + spacing)) }

    private var headerRight: String {
        if let day = hoveredDay {
            let label: String
            switch day.count {
            case 0:  label = String(localized: "No contributions")
            case 1:  label = "1 contribution"
            default: label = "\(day.count) contributions"
            }
            return "\(activityDateLabel(day.date)) · \(label)"
        }
        guard let act = activity else { return "" }
        let total = activityTotalLabel(act.total)
        if let s = stats { return "\(total) past year · \(s.totalRepos) repos" }
        return "\(total) past year"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 6) {
                Button(action: onBack) {
                    HStack(spacing: 3) {
                        Image(systemName: "chevron.left")
                            .font(.system(size: 8, weight: .medium))
                        Text("Activity")
                            .font(.system(size: 12, weight: .semibold))
                    }
                    .foregroundColor(Color(hex: "#F5F6F8"))
                }
                .buttonStyle(.plain)
                Spacer(minLength: 2)
                if activity != nil {
                    Button(action: {
                        let urlStr = "https://github.com/\(login)"
                        if let url = safeWebURL(urlStr), url.host == "github.com" {
                            NSWorkspace.shared.open(url)
                        }
                    }) {
                        Text(headerRight)
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: "#8E939C"))
                            .lineLimit(1)
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.top, 6)
            .padding(.leading, 108)
            .padding(.trailing, 12)

            // Grid
            if let act = activity {
                let weeks = act.lastWeeks(numWeeks)
                HStack(alignment: .top, spacing: spacing) {
                    ForEach(weeks.indices, id: \.self) { wi in
                        VStack(spacing: spacing) {
                            ForEach(0..<7, id: \.self) { dow in
                                if let day = weeks[wi].first(where: { $0.weekday == dow }) {
                                    RoundedRectangle(cornerRadius: 1.5)
                                        .fill(contributionColor(day.level))
                                        .frame(width: squareSize, height: squareSize)
                                        .onHover { hovering in hoveredDay = hovering ? day : nil }
                                        .onTapGesture {
                                            hoveredDay = (hoveredDay?.date == day.date) ? nil : day
                                        }
                                } else {
                                    Color.clear.frame(width: squareSize, height: squareSize)
                                }
                            }
                        }
                    }
                }
                .padding(.top, 5)
                .padding(.leading, 108)
                .padding(.trailing, 12)
            } else {
                Text("Loading…")
                    .font(.system(size: 10.5))
                    .foregroundColor(Color(hex: "#6B7079"))
                    .padding(.top, 8)
                    .padding(.leading, 108)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.top, 4)
        .clipped()
        .onAppear { GithubPoller.shared.refreshActivityIfStale() }
        .onExitCommand { onBack() }
    }

    private func activityDateLabel(_ dateStr: String) -> String {
        let parts = dateStr.split(separator: "-")
        guard parts.count == 3,
              let month = Int(parts[1]), month >= 1 && month <= 12,
              let day   = Int(parts[2]) else { return dateStr }
        let months = ["Jan","Feb","Mar","Apr","May","Jun","Jul","Aug","Sep","Oct","Nov","Dec"]
        return "\(months[month - 1]) \(day)"
    }

    private func activityTotalLabel(_ n: Int) -> String {
        let nf = NumberFormatter()
        nf.numberStyle = .decimal
        nf.locale = Locale(identifier: "en_US")
        return nf.string(from: NSNumber(value: n)) ?? "\(n)"
    }
}

private func contributionColor(_ level: Int) -> Color {
    switch level {
    case 1: return Color(hex: "#0E4429")
    case 2: return Color(hex: "#006D32")
    case 3: return Color(hex: "#26A641")
    case 4: return Color(hex: "#39D353")
    default: return Color.white.opacity(0.06)
    }
}

private func ghCIDot(_ ci: CIState) -> Color {
    switch ci {
    case .failure: return Color(hex: "#F4505E")
    case .pending: return Color(hex: "#F5A524")
    case .success: return Color(hex: "#22C55E")
    case .unknown: return Color.clear
    }
}

private struct GitHubPRRowView: View {
    let pr: GitHubPR
    let showCI: Bool
    var selected: Bool = false

    var body: some View {
        Button(action: {
            if let url = safeWebURL(pr.url), url.host == "github.com" {
                NSWorkspace.shared.open(url)
            }
        }) {
            HStack(spacing: 5) {
                if showCI {
                    Circle()
                        .fill(ghCIDot(pr.ci))
                        .frame(width: 5, height: 5)
                        .opacity(pr.ci == .unknown ? 0 : 1)
                } else {
                    Spacer().frame(width: 5)
                }
                Text("\(pr.repo.components(separatedBy: "/").last ?? pr.repo)#\(pr.number)")
                    .font(.system(size: 10.5))
                    .foregroundColor(Color(hex: "#9398A1"))
                    .lineLimit(1)
                Text(pr.title)
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "#C5C8CD"))
                    .lineLimit(1)
                    .truncationMode(.tail)
                if pr.isDraft {
                    Text("Draft")
                        .font(.system(size: 9.5))
                        .foregroundColor(Color(hex: "#6B7079"))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 20)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.12))
                    .opacity(selected ? 1 : 0)
            )
        }
        .buttonStyle(.plain)
    }
}

private struct GitHubRepoCIRowView: View {
    let repo: GitHubRepoCI
    var selected: Bool = false

    private var ciStateWord: String? {
        switch repo.ci {
        case .failure: return "failing"
        case .pending: return "running"
        case .success: return "passing"
        case .unknown: return nil
        }
    }

    var body: some View {
        Button(action: {
            let actionsURL = repo.url.hasSuffix("/") ? repo.url + "actions" : repo.url + "/actions"
            if let url = safeWebURL(actionsURL), url.host == "github.com" {
                NSWorkspace.shared.open(url)
            }
        }) {
            HStack(spacing: 5) {
                Circle()
                    .fill(ghCIDot(repo.ci))
                    .frame(width: 5, height: 5)
                    .opacity(repo.ci == .unknown ? 0 : 1)
                Text(repo.repo.components(separatedBy: "/").last ?? repo.repo)
                    .font(.system(size: 10.5))
                    .foregroundColor(Color(hex: "#9398A1"))
                    .lineLimit(1)
                Text(repo.branch)
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "#C5C8CD"))
                    .lineLimit(1)
                    .truncationMode(.tail)
                Spacer(minLength: 4)
                if let word = ciStateWord {
                    Text(word)
                        .font(.system(size: 10))
                        .foregroundColor(ghCIDot(repo.ci))
                        .lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .frame(height: 20)
            .overlay(
                RoundedRectangle(cornerRadius: 4)
                    .fill(Color.white.opacity(0.12))
                    .opacity(selected ? 1 : 0)
            )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - GitHub Stats Card View

struct GitHubStatsCardView: View {
    let stats: GitHubStats

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 6) {
                Circle()
                    .fill(Color(hex: "#F4505E"))
                    .frame(width: 7, height: 7)
                Text("GitHub")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(hex: "#F5F6F8"))
                Text("Overview")
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "#8E939C"))
            }
            .padding(.top, 6)
            .padding(.leading, 108)
            .padding(.trailing, 36)

            // Stats rows
            VStack(alignment: .leading, spacing: 5) {
                StatRow(icon: "star.fill", color: "#F5A524",
                        label: "Total stars", value: formatCount(stats.totalStars))
                StatRow(icon: "square.stack.fill", color: "#6B7079",
                        label: "Repositories", value: "\(stats.totalRepos)")
            }
            .padding(.top, 8)
            .padding(.leading, 108)
            .padding(.trailing, 12)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.top, 4)
    }

    private func formatCount(_ n: Int) -> String {
        if n >= 1000 { return String(format: "%.1fk", Double(n) / 1000) }
        return "\(n)"
    }
}

private struct StatRow: View {
    let icon: String
    let color: String
    let label: String
    let value: String

    var body: some View {
        HStack(spacing: 7) {
            Image(systemName: icon)
                .font(.system(size: 10))
                .foregroundColor(Color(hex: color))
                .frame(width: 14)
            Text(label)
                .font(.system(size: 11))
                .foregroundColor(Color(hex: "#6B7079"))
            Spacer()
            Text(value)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Color(hex: "#C5C8CD"))
                .monospacedDigit()
        }
        .frame(maxWidth: .infinity)
    }
}
