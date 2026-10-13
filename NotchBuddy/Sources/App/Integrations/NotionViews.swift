import SwiftUI

// MARK: - Notion Card View

struct NotionCardView: View {
    @ObservedObject private var appState = AppState.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 6) {
                Circle().fill(Color(hex: "#E8E8E8")).frame(width: 7, height: 7)
                Text("Notion").font(.system(size: 12, weight: .semibold)).foregroundColor(Color(hex: "#F5F6F8"))
                Text("Recent").font(.system(size: 11)).foregroundColor(Color(hex: "#8E939C"))
            }
            .padding(.top, 6).padding(.leading, 108).padding(.trailing, 36)

            VStack(alignment: .leading, spacing: 2) {
                ForEach(appState.notionPages.prefix(3)) { page in
                    Button {
                        if let url = safeWebURL(page.url) { NSWorkspace.shared.open(url) }
                    } label: {
                        HStack(spacing: 6) {
                            if let emoji = page.emoji {
                                Text(emoji).font(.system(size: 10)).frame(width: 14)
                            } else {
                                Image(systemName: "doc.text").font(.system(size: 9))
                                    .foregroundColor(Color(hex: "#6B7079")).frame(width: 14)
                            }
                            Text(page.title).font(.system(size: 11))
                                .foregroundColor(Color(hex: "#C5C8CD"))
                                .lineLimit(1).truncationMode(.tail).layoutPriority(1)
                            Spacer(minLength: 4)
                            Text(page.timeAgo).font(.system(size: 9))
                                .foregroundColor(Color(hex: "#4B5563"))
                        }
                        .padding(.horizontal, 6).padding(.vertical, 4)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.leading, 102).padding(.trailing, 12).padding(.top, 5)
        }
        .frame(maxWidth: .infinity, alignment: .topLeading).padding(.top, 4)
        .transition(.opacity)
    }
}
