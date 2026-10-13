import SwiftUI

// MARK: - n8n Execution Detail View

struct N8nDetailView: View {
    let task: AgentTask
    let onClose: () -> Void

    private var success: Bool  { task.state == .finished }
    private var accent: Color  { success ? Color(hex: "#22C55E") : Color(hex: "#F4505E") }
    private var statusLabel: String { success ? String(localized: "Success") : String(localized: "Failed") }
    private var detail: String? { task.steps.dropFirst().first }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {

            // Header: back button + workflow name + status badge
            HStack(spacing: 7) {
                Button(action: onClose) {
                    Image(systemName: "chevron.left")
                        .font(.system(size: 10, weight: .semibold))
                        .foregroundColor(Color(hex: "#6B7079"))
                        .frame(width: 28, height: 28)   // large hit area
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Circle().fill(accent).frame(width: 6, height: 6)

                Text(task.steps.first ?? "Workflow")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Color(hex: "#F5F6F8"))
                    .lineLimit(1).truncationMode(.middle)
                    .layoutPriority(1)

                Spacer(minLength: 2)

                Text(statusLabel)
                    .font(.system(size: 10, weight: .medium))
                    .foregroundColor(accent)
                    .padding(.horizontal, 6).padding(.vertical, 2)
                    .background(accent.opacity(0.14))
                    .clipShape(Capsule())
            }

            // Detail body — monospaced, selectable
            if let detail {
                ScrollView(.vertical, showsIndicators: false) {
                    Text(detail)
                        .font(.system(size: 10.5, design: .monospaced))
                        .foregroundColor(Color(hex: "#9398A1"))
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .lineSpacing(2)
                        .textSelection(.enabled)
                }
                .frame(maxHeight: 88)
            } else {
                Text(success ? String(localized: "Completed successfully.") : String(localized: "No error details available."))
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "#6B7079"))
            }
        }
        .padding(.top, 8)
        .padding(.leading, 108)
        .padding(.trailing, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .contentShape(Rectangle())   // prevent taps falling through transparent areas
    }
}
