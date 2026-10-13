import SwiftUI

// MARK: - Music Pill (GitHub build only)

#if !APPSTORE
struct MusicPill: View {
    let task: AgentTask
    @ObservedObject var state: AppState
    @Binding var swapping: Bool
    let onTap: () -> Void
    @State private var isHovered = false

    private var isPlaying: Bool { AppState.shared.musicPlaying }
    private var showControls: Bool { isHovered && MusicController.shared.trackTitle != nil }

    var body: some View {
        ZStack {
            // Selection target — full pill area, receives taps where controls don't
            Capsule()
                .fill(Color.clear)
                .contentShape(Capsule())
                .onTapGesture { onTap() }

            // Visual fills
            Capsule()
                .fill(isHovered ? Color(hex: task.color).opacity(0.18) : Color(hex: "#0E0F11"))
                .allowsHitTesting(false)
            Capsule()
                .stroke(Color(hex: task.color).opacity(isHovered ? 0.55 : 0.14), lineWidth: 1)
                .allowsHitTesting(false)

            // The app's logo at leading edge
            HStack(spacing: 0) {
                PillLogo(task: task, size: 17)
                    .frame(width: 22, height: 22, alignment: .center)
                    .padding(.leading, 8)
                Spacer()
            }
            .allowsHitTesting(false)

            // Title — trailing padding grows on hover to make room for buttons
            Text(task.name)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(isHovered ? Color(hex: task.color).lighter(by: 0.3) : Color(hex: "#6B7079"))
                .lineLimit(1)
                .truncationMode(.tail)
                .padding(.leading, 34)
                .padding(.trailing, showControls ? 52 : 10)
                .frame(maxWidth: .infinity, alignment: .center)
                .animation(.spring(response: 0.2, dampingFraction: 0.7), value: showControls)
                .allowsHitTesting(false)

            // Playback controls — appear on hover when a track is loaded
            if showControls {
                HStack(spacing: 0) {
                    Spacer()
                    HStack(spacing: 2) {
                        MusicControlButton(icon: isPlaying ? "pause.fill" : "play.fill", color: task.color) {
                            MusicController.shared.playPause()
                        }
                        MusicControlButton(icon: "forward.fill", color: task.color) {
                            MusicController.shared.nextTrack()
                        }
                    }
                    .padding(.trailing, 4)
                }
                .transition(.opacity.combined(with: .scale(scale: 0.85, anchor: .trailing)))
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: 28)
        .shadow(color: Color(hex: task.color).opacity(isHovered ? 0.35 : 0), radius: 10, x: 0, y: 2)
        .scaleEffect(isHovered ? 1.04 : 1.0)
        .brightness(isHovered ? 0.06 : 0)
        .onHover { newHover in
            guard !swapping else { return }
            withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) { isHovered = newHover }
        }
    }
}

struct MusicControlButton: View {
    let icon: String
    let color: String
    let action: () -> Void
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Circle()
                    .fill(isHovered ? Color(hex: color).opacity(0.18) : Color(hex: "#0E0F11"))
                Circle()
                    .stroke(Color(hex: color).opacity(isHovered ? 0.55 : 0.14), lineWidth: 1)
                Image(systemName: icon)
                    .font(.system(size: 8, weight: .semibold))
                    .foregroundColor(isHovered ? Color(hex: color).lighter(by: 0.3) : Color(hex: "#6B7079"))
            }
            .frame(width: 20, height: 20)
            .shadow(color: Color(hex: color).opacity(isHovered ? 0.35 : 0), radius: 6)
        }
        .buttonStyle(.plain)
        .scaleEffect(isHovered ? 1.1 : 1.0)
        .onHover { newHover in
            withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) { isHovered = newHover }
        }
    }
}
#endif

// MARK: - Music Card View (GitHub build only)

#if !APPSTORE
struct MusicCardView: View {
    @ObservedObject private var controller = MusicController.shared
    @ObservedObject private var appState = AppState.shared

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            if appState.musicAutomationDenied {
                // Automation denied — prompt user to fix
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(hex: "#F4505E"))
                        .frame(width: 7, height: 7)
                    Text("Apple Music")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Color(hex: "#F5F6F8"))
                    Spacer(minLength: 2)
                }
                .padding(.top, 6)
                .padding(.leading, 108)
                .padding(.trailing, 36)

                Text("Allow Coucou to control Music")
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "#8E939C"))
                    .padding(.leading, 108)
                    .padding(.trailing, 12)

                Button("Open Settings…") { MusicController.shared.openAutomationSettings() }
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Color(hex: "#FA2D48").opacity(0.85))
                    .buttonStyle(.plain)
                    .padding(.leading, 108)
                    .padding(.top, 2)
            } else {
                // Line 1: dot + title
                HStack(spacing: 6) {
                    Circle()
                        .fill(Color(hex: "#FA2D48"))
                        .frame(width: 7, height: 7)
                    if let title = controller.trackTitle {
                        Text(title)
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundColor(Color(hex: "#F5F6F8"))
                            .lineLimit(1).truncationMode(.tail)
                            .frame(maxWidth: 150, alignment: .leading)
                    }
                }
                .padding(.top, 6)
                .padding(.leading, 108)

                // Line 2: artist
                if let artist = controller.artist {
                    Text(artist)
                        .font(.system(size: 11))
                        .foregroundColor(Color(hex: "#8E939C"))
                        .lineLimit(1).truncationMode(.tail)
                        .frame(maxWidth: 150, alignment: .leading)
                        .padding(.leading, 108)
                }

                // Line 3: controls
                HStack(spacing: 8) {
                    Button(action: { MusicController.shared.previousTrack() }) {
                        Image(systemName: "backward.fill")
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: "#8E939C"))
                    }
                    .buttonStyle(.plain)
                    Button(action: { MusicController.shared.playPause() }) {
                        Image(systemName: appState.musicPlaying ? "pause.fill" : "play.fill")
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: "#FA2D48"))
                    }
                    .buttonStyle(.plain)
                    Button(action: { MusicController.shared.nextTrack() }) {
                        Image(systemName: "forward.fill")
                            .font(.system(size: 11))
                            .foregroundColor(Color(hex: "#8E939C"))
                    }
                    .buttonStyle(.plain)
                }
                .padding(.leading, 108)
                .padding(.top, 6)
            }
        }
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .padding(.top, 4)
    }
}
#endif
