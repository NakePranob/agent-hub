import SwiftUI

/// Top-level SwiftUI view rendered inside the 720×320 transparent panel.
/// The island is drawn at the top-center; everything else is transparent and click-through.
/// Note: drag-drop is handled at the AppKit level in IslandWindowController (FileDropNSView),
/// not in SwiftUI, to avoid interfering with SwiftUI hit-testing.
struct IslandRootView: View {
    @EnvironmentObject var state: AppState

    var body: some View {
        ZStack(alignment: .top) {
            Color.clear
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            IslandContainer(state: state)
                .frame(maxWidth: .infinity, alignment: .center)
        }
        .ignoresSafeArea()
    }
}

// MARK: - Island container

struct IslandContainer: View {
    @ObservedObject var state: AppState
    @ObservedObject private var demoEngine = DemoEngine.shared
    @State private var islandWidth:  CGFloat = IslandConst.notchWidth
    @State private var islandHeight: CGFloat = IslandConst.notchHeight
    @State private var cornerRadius: CGFloat = IslandConst.roundedCorner
    // topRadius > 0 → convex expanded corners; < 0 → concave ear cutouts
    @State private var islandTopRadius: CGFloat = 0
    @State private var shoulder: CGFloat = 0
    @State private var greetNotif: Bool = false

    private let openSpring = Animation.spring(response: 0.5, dampingFraction: 0.72)
    private let closeEase  = Animation.timingCurve(0.45, 0, 0.2, 1, duration: 0.34)

    private var chatPromptHeight: CGFloat {
        let base: CGFloat = 240
        let perMsg: CGFloat = 40
        return min(300, base + CGFloat(state.chatHistory.count) * perMsg)
    }

    /// Pixels the content must be pushed down to clear the concave ear transparent area.
    /// = 0 in expanded mode (no ears), = earRadius in compact/notch mode.
    private var earOffset: CGFloat { max(0, -islandTopRadius) }

    var body: some View {
        // Canvas active during drag-over (.upload), post-drop animation (.uploading),
        // AND choose overlay (.choose) — canvas handles the full sequence through user action.
        // Engine deactivates when user clicks a canvas choose button or navigates away.
        let uploadActive = state.mode == .expanded
            && UploadSequenceEngine.shared.isActive
            && (state.view == .upload || state.view == .uploading || state.view == .choose)

        let greetingActive = state.mode == .expanded && state.view == .greeting

        return ZStack(alignment: .topLeading) {
            // Black island shape
            IslandShape(width: islandWidth, height: islandHeight,
                        cornerRadius: cornerRadius, topRadius: islandTopRadius, shoulder: shoulder)
                .fill(Color.black)

            // Content
            if state.mode == .expanded {
                if greetingActive {
                    // Greeting canvas: fixed 640-wide, centered by offset so x=320 aligns with island center
                    GreetingCanvasView(state: state)
                        .frame(width: IslandConst.expandedWidth, height: 150)
                        .offset(x: (islandWidth - IslandConst.expandedWidth) / 2)
                        .clipShape(IslandShape(width: islandWidth, height: islandHeight,
                                              cornerRadius: cornerRadius, topRadius: islandTopRadius))
                        .transition(.opacity)
                } else if uploadActive {
                    ZStack(alignment: .topLeading) {
                        UploadCanvasView(state: state)
                            .frame(width: islandWidth, height: islandHeight)
                            .clipShape(IslandShape(width: islandWidth, height: islandHeight,
                                                  cornerRadius: cornerRadius, topRadius: islandTopRadius))
                        // Header overlaid in the menu bar's row, as in the other views; the canvas
                        // draws its card at its own fixed place under it.
                        IslandHeader(state: state)
                            .frame(width: islandWidth, height: min(state.notchHeight, IslandConst.designHeaderBottom))
                    }
                    .transition(.opacity)
                } else {
                    IslandContentView(state: state)
                        .frame(width: islandWidth, height: islandHeight - earOffset)
                        .offset(y: earOffset)
                        .clipShape(IslandShape(width: islandWidth, height: islandHeight,
                                              cornerRadius: cornerRadius, topRadius: islandTopRadius))
                        .transition(.opacity)
                }
            }

            // Single BotPlacement — always alive in the view tree so spring animations
            // fire from the current position (e.g. choose at 60,101) when canvas deactivates.
            // Hidden during upload canvas or greeting (both draw their own Mochi).
            BotPlacement(state: state, islandW: islandWidth, islandH: islandHeight)
                // Keep idle animations inside the resting strip. Expanded views
                // retain the panel's full height for particles and hands.
                .mask(alignment: .topLeading) {
                    Rectangle().frame(width: islandWidth,
                                      height: state.mode == .expanded ? 320 : islandHeight)
                }
                .opacity(uploadActive || greetingActive ? 0 : 1)
                .animation(.easeInOut(duration: 0.25), value: uploadActive || greetingActive)

            CountdownBar(state: state, islandW: islandWidth)

            if demoEngine.isActive {
                Text(verbatim: "DEMO")
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundColor(.black)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color(hex: "#4ADE80"))
                    .clipShape(Capsule())
                    .position(x: 18, y: islandHeight - 8)
                    .transition(.opacity.combined(with: .scale(scale: 0.8)))
                    .animation(.spring(response: 0.3, dampingFraction: 0.8), value: demoEngine.isActive)
            }

            Group {
                if state.mode == .compact {
                    CompactMiniGrid(state: state)
                        .scaleEffect(IslandRestingLayout(width: islandWidth, height: islandHeight).miniGridScale)
                        .position(x: IslandRestingLayout(width: islandWidth, height: islandHeight).miniGridCenterX,
                                  y: islandHeight / 2)
                        .transition(.opacity)
                }
            }
            .animation(.easeInOut(duration: 0.25), value: state.mode == .compact)
        }
        .frame(width: islandWidth, height: islandHeight, alignment: .topLeading)
        .onChange(of: state.mode) { oldMode, newMode in
            let shrinking = modeOrder(newMode) < modeOrder(oldMode)
            let anim = shrinking ? closeEase : openSpring
            let (w, h) = islandSize(mode: newMode, view: state.view,
                                    progress: state.uploadProgress,
                                    nw: state.notchWidth, nh: state.notchHeight)
            let cr  = newMode == .expanded ? IslandConst.expandedCorner : IslandConst.roundedCorner
            let tr: CGFloat = 0
            withAnimation(anim) {
                islandWidth      = w
                islandHeight     = (newMode == .expanded && state.view == .prompt) ? chatPromptHeight : h
                cornerRadius     = cr
                islandTopRadius  = tr
                shoulder         = Self.shoulder(for: newMode)
            }
        }
        .onChange(of: state.view) { _, newView in
            guard state.mode == .expanded else { return }
            // Deactivate engine if user navigates outside the upload flow
            let uploadViews: Set<IslandView> = [.upload, .uploading, .choose]
            if UploadSequenceEngine.shared.isActive && !uploadViews.contains(newView) {
                UploadSequenceEngine.shared.deactivate()
            }
            let (w, h) = islandSize(mode: .expanded, view: newView,
                                    progress: state.uploadProgress,
                                    nw: state.notchWidth, nh: state.notchHeight)
            withAnimation(openSpring) {
                islandWidth  = w
                islandHeight = newView == .prompt ? chatPromptHeight : h
            }
        }
        .onChange(of: state.chatHistory.count) { _, _ in
            guard state.mode == .expanded, state.view == .prompt else { return }
            withAnimation(openSpring) { islandHeight = chatPromptHeight }
        }
        .onAppear {
            let (w, h) = islandSize(mode: state.mode, view: state.view,
                                    progress: state.uploadProgress,
                                    nw: state.notchWidth, nh: state.notchHeight)
            islandWidth      = w
            islandHeight     = state.view == .prompt ? chatPromptHeight : h
            cornerRadius     = state.mode == .expanded ? IslandConst.expandedCorner : IslandConst.roundedCorner
            islandTopRadius  = 0
            shoulder         = Self.shoulder(for: state.mode)
        }
        .onReceive(NotificationCenter.default.publisher(for: .botGreet)) { _ in
            greetNotif.toggle()
        }
        .onReceive(NotificationCenter.default.publisher(for: .islandScreenChanged)) { _ in
            // New screen, new resting size (notch ↔ bar): snap without animation.
            let (w, h) = islandSize(mode: state.mode, view: state.view,
                                    progress: state.uploadProgress,
                                    nw: state.notchWidth, nh: state.notchHeight)
            islandWidth  = w
            islandHeight = (state.mode == .expanded && state.view == .prompt) ? chatPromptHeight : h
        }
    }

    private func modeOrder(_ m: IslandMode) -> Int {
        switch m { case .hidden: return 0; case .compact: return 1; case .expanded: return 2 }
    }

    /// None while hidden, where the island is the notch itself.
    private static func shoulder(for mode: IslandMode) -> CGFloat {
        switch mode {
        case .hidden:   return 0
        case .compact:  return IslandConst.compactShoulder
        case .expanded: return IslandConst.expandedShoulder
        }
    }
}

// MARK: - Island shape
//
// topRadius > 0  → convex rounded top corners (expanded mode)
// topRadius < 0  → concave ear cutouts, |topRadius| = ear radius (compact/notch mode)
// topRadius = 0  → sharp top corners (transient during animation)
// shoulder > 0   → beeprio's shoulders: concave curves out past either side, down from the
//                  top of the screen (only with topRadius ≥ 0; the fill, not the clips)

struct IslandShape: Shape {
    var width: CGFloat
    var height: CGFloat
    var cornerRadius: CGFloat   // bottom corners
    var topRadius: CGFloat      // see above
    var shoulder: CGFloat = 0

    var animatableData: AnimatablePair<AnimatablePair<AnimatablePair<CGFloat, CGFloat>, CGFloat>, AnimatablePair<CGFloat, CGFloat>> {
        get { .init(.init(.init(width, height), cornerRadius), .init(topRadius, shoulder)) }
        set {
            width        = newValue.first.first.first
            height       = newValue.first.first.second
            cornerRadius = newValue.first.second
            topRadius    = newValue.second.first
            shoulder     = newValue.second.second
        }
    }

    func path(in rect: CGRect) -> Path {
        let cr = max(0, cornerRadius)
        var p  = Path()
        // A cubic Bézier's handle for a quarter circle, as a share of its radius.
        let k: CGFloat = 0.5522847498
        let s = max(0, min(shoulder, height - cr))

        if topRadius >= 0 && s > 0 {
            // ── Shoulders (beeprio): flush with the top, flaring out to meet the screen's edge ──
            p.move(to: CGPoint(x: -s, y: 0))
            p.addLine(to: CGPoint(x: width + s, y: 0))
            p.addCurve(to: CGPoint(x: width, y: s),
                       control1: CGPoint(x: width + s - k * s, y: 0), control2: CGPoint(x: width, y: s - k * s))
            p.addLine(to: CGPoint(x: width, y: height - cr))
            p.addArc(center: CGPoint(x: width - cr, y: height - cr), radius: cr,
                     startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
            p.addLine(to: CGPoint(x: cr, y: height))
            p.addArc(center: CGPoint(x: cr, y: height - cr), radius: cr,
                     startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
            p.addLine(to: CGPoint(x: 0, y: s))
            p.addCurve(to: CGPoint(x: -s, y: 0),
                       control1: CGPoint(x: 0, y: s - k * s), control2: CGPoint(x: -s + k * s, y: 0))
        } else if topRadius >= 0 {
            // ── Convex rounded top corners (expanded) ──────────────────────────
            let tr = min(topRadius, min(width / 2, height / 2))
            p.move(to: CGPoint(x: tr, y: 0))
            p.addLine(to: CGPoint(x: width - tr, y: 0))
            // Top-right convex corner
            p.addArc(center: CGPoint(x: width - tr, y: tr), radius: tr,
                     startAngle: .degrees(270), endAngle: .degrees(0), clockwise: false)
            // Right edge
            p.addLine(to: CGPoint(x: width, y: height - cr))
            // Bottom-right corner
            p.addArc(center: CGPoint(x: width - cr, y: height - cr), radius: cr,
                     startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
            // Bottom edge
            p.addLine(to: CGPoint(x: cr, y: height))
            // Bottom-left corner
            p.addArc(center: CGPoint(x: cr, y: height - cr), radius: cr,
                     startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
            // Left edge
            p.addLine(to: CGPoint(x: 0, y: tr))
            // Top-left convex corner
            p.addArc(center: CGPoint(x: tr, y: tr), radius: tr,
                     startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
        } else {
            // ── Concave ear cutouts (compact / notch) ─────────────────────────
            let er = -topRadius   // positive ear radius
            p.move(to: CGPoint(x: 0, y: 0))
            // Top-left ear
            p.addArc(center: CGPoint(x: 0, y: er), radius: er,
                     startAngle: .degrees(270), endAngle: .degrees(0), clockwise: false)
            // Top edge
            p.addLine(to: CGPoint(x: width - er, y: er))
            // Top-right ear
            p.addArc(center: CGPoint(x: width, y: er), radius: er,
                     startAngle: .degrees(180), endAngle: .degrees(270), clockwise: false)
            // Right edge
            p.addLine(to: CGPoint(x: width, y: height - cr))
            // Bottom-right corner
            p.addArc(center: CGPoint(x: width - cr, y: height - cr), radius: cr,
                     startAngle: .degrees(0), endAngle: .degrees(90), clockwise: false)
            // Bottom edge
            p.addLine(to: CGPoint(x: cr, y: height))
            // Bottom-left corner
            p.addArc(center: CGPoint(x: cr, y: height - cr), radius: cr,
                     startAngle: .degrees(90), endAngle: .degrees(180), clockwise: false)
            // Left edge back to top-left corner
            p.addLine(to: CGPoint(x: 0, y: 0))
        }

        p.closeSubpath()
        return p
    }
}

// MARK: - Bot placement helper

struct BotPlacement: View {
    @ObservedObject var state: AppState
    let islandW: CGFloat
    let islandH: CGFloat

    var body: some View {
        let (cx, cy, diameter, opacity) = botPosition(mode: state.mode, view: state.view, islandW: islandW, islandH: islandH, uploadProgress: state.uploadProgress, hasNotch: state.hasNotch, nh: state.notchHeight)
        let canvasSize = diameter / 0.6
        let isUploading = state.view == .uploading

        Group {
            // The robot's light behind it, in its mood's colour (beeprio's island). None in
            // uploading mode: the tiny dot doesn't need it.
            if state.mode == .expanded && !isUploading {
                Circle()
                    .fill(RadialGradient(
                        gradient: Gradient(colors: [
                            Color(hex: RobotMood(state.effectiveState).glowHex).opacity(0.4),
                            .clear
                        ]),
                        center: .center,
                        startRadius: 0,
                        endRadius: diameter * 0.84
                    ))
                    .frame(width: diameter * 1.68, height: diameter * 1.68)
                    .position(x: cx, y: cy)
                    .animation(.easeInOut(duration: 0.4), value: state.effectiveState)
            }

            // Uploading: no particle overhang (no hearts during upload), positioned directly at cy.
            // BotEngine cy = H/2 + 0 + oy*R + R*0.06 ≈ H/2 (body centered in canvas).
            // With .position(x:y:) placing the frame center at (uploadCx, cy), bot is at cy ✓.
            //
            // Normal: extra 40pt canvas at top for heart particles; position offset up by 20pt;
            // BotEngine compensates with cy = H/2 + particleOverhang/2 + oy*R + R*0.06.
            if isUploading {
                TimelineView(.animation) { tl in
                    let elapsed: Double = {
                        guard let start = state.uploadStartTime else { return 0 }
                        return tl.date.timeIntervalSince(start)
                    }()
                    let t = min(1.0, max(0, elapsed / state.uploadDuration))
                    // cx = 36 + 526*t: bot center at fill right edge (bar left=36, width=526)
                    let uploadCx = 36 + CGFloat(t * (2 - t)) * 526
                    IslandRobotView(state: state, paused: state.mochiOnDesktop)
                        .frame(width: canvasSize, height: canvasSize)
                        .opacity(state.isDraggingBot || state.mochiOnDesktop ? 0 : opacity)
                        .position(x: uploadCx, y: cy)
                }
                .transition(.scale(scale: 0.01, anchor: .center).combined(with: .opacity))
            } else {
                // Invisible while the robot lives on the desktop: no drawing either.
                IslandRobotView(state: state, paused: state.mochiOnDesktop || state.isDraggingBot)
                    .frame(width: canvasSize, height: canvasSize)
                    .opacity(state.isDraggingBot || state.mochiOnDesktop ? 0 : opacity)
                    .position(x: cx, y: cy)
                    .animation(.spring(response: 0.5, dampingFraction: 0.72), value: cx)
                    .animation(.spring(response: 0.5, dampingFraction: 0.72), value: cy)
                    .animation(.spring(response: 0.5, dampingFraction: 0.72), value: canvasSize)
                    .transition(.scale(scale: 0.01, anchor: .center).combined(with: .opacity))
            }

            // The app the focused session runs in, at the robot's shoulder, ringed in its state.
            if state.mode == .expanded, state.view == .overview, !state.mochiOnDesktop, !state.isDraggingBot,
               let task = state.focusTask.map(state.cardTask), Self.isSession(task) {
                PillLogo(task: task, size: 16)
                    .padding(2)
                    .background(RoundedRectangle(cornerRadius: 6, style: .continuous).fill(Color(hex: "#161719")))
                    .position(x: cx - diameter * 0.5, y: cy - diameter * 0.42)
                    .transition(.opacity)
            }
        }
        // Branch switch (uploading ↔ normal) animates with a fast spring: uploading dot
        // scales out at bar-end while normal bot scales in at choose position.
        .animation(.spring(response: 0.36, dampingFraction: 0.72), value: isUploading)
        // Slap, drag, and hover are handled by the AppKit NSEvent monitor in
        // IslandWindowController — not SwiftUI gestures — so this is safe.
        .allowsHitTesting(false)
    }

    /// A coding agent's pill, not a service's.
    private static func isSession(_ task: AgentTask) -> Bool {
        guard let def = PillCatalog.definition(for: task.id) else { return !task.isIntegration }
        return def.category == .workspace || def.category == .agent
    }
}

func botPosition(mode: IslandMode, view: IslandView, islandW: CGFloat, islandH: CGFloat, uploadProgress: Double, hasNotch: Bool = true,
                 nh: CGFloat = IslandConst.notchHeight) -> (CGFloat, CGFloat, CGFloat, Double) {
    let resting = IslandRestingLayout(width: islandW, height: islandH)
    switch mode {
    case .hidden:
        return hasNotch ? (46, 16, 6, 0)
            : (islandW / 2, resting.botCenterY, resting.botDiameter, 1)
    case .compact: return (resting.botCenterX, resting.botCenterY, resting.botDiameter, 1)
    case .expanded:
        let layout = IslandConst.viewLayouts[view]!
        let diameter = layout.botDiameter
        // Uploading: Mochi dot rides the leading edge of the progress fill.
        // Bar in island coords: left=36, width=526. cx = 36 + progress*526 (dot center at fill right edge).
        // cy comes from ViewLayout.botY (bar center in island coords).
        if view == .uploading {
            let cx = 36 + CGFloat(uploadProgress) * 526
            return (cx, layout.botY ?? 103, diameter, 1)
        }
        let cx = layout.botX
        let cy: CGFloat
        if let fixedY = layout.botY {
            cy = fixedY
        } else {
            // Center of the fixed 84pt card, under the header in the menu bar's row
            let headerBottom: CGFloat = IslandConst.designHeaderBottom - IslandConst.headerLift(nh: nh)
            let cardH: CGFloat = 84
            cy = headerBottom + (islandH - headerBottom - cardH) / 2 + cardH / 2
        }
        return (cx, cy, diameter, 1)
    }
}

// MARK: - Active island view

private struct IslandViewActiveKey: EnvironmentKey {
    static let defaultValue = true
}

extension EnvironmentValues {
    /// False inside the island views that are mounted but not shown (opacity 0):
    /// TimelineViews in them pause. True everywhere else.
    var islandViewActive: Bool {
        get { self[IslandViewActiveKey.self] }
        set { self[IslandViewActiveKey.self] = newValue }
    }
}

// MARK: - Countdown bar

struct CountdownBar: View {
    @ObservedObject var state: AppState
    let islandW: CGFloat
    @State private var barWidth: CGFloat = 0
    @State private var timer: Timer? = nil

    var body: some View {
        GeometryReader { _ in
            Rectangle()
                .fill(Color.white.opacity(0.35))
                .frame(width: barWidth, height: 2)
                .cornerRadius(2)
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        }
        // The bar only exists in the open island: its 10 Hz timer runs only then
        // (CLAUDE.md: 0 % CPU when the island is hidden).
        .onAppear { if state.mode == .expanded { startTimer() } }
        .onChange(of: state.mode) { _, mode in
            if mode == .expanded { startTimer() } else { stopTimer() }
        }
        .onDisappear { stopTimer() }
    }

    private func startTimer() {
        guard timer == nil else { return }
        let t = Timer.scheduledTimer(withTimeInterval: 0.1, repeats: true) { _ in
            MainActor.assumeIsolated { updateBar() }
        }
        t.tolerance = 0.02
        timer = t
    }

    private func stopTimer() {
        timer?.invalidate()
        timer = nil
        if barWidth != 0 { barWidth = 0 }
    }

    private func updateBar() {
        guard state.mode == .expanded && !state.isPinned else {
            if barWidth != 0 { barWidth = 0 }
            return
        }
        let autoClose = state.autoCloseInterval
        let window = min(10.0, autoClose * 0.6)
        let elapsed = Date.now.timeIntervalSince(state.lastActivity)
        let remaining = autoClose - elapsed
        let target: CGFloat = remaining < window ? max(0, CGFloat(remaining / window) * 160) : 0
        // The timer ticks at 10 Hz; a linear animation over the same 0.1 s glides between ticks,
        // so the bar shrinks on every display frame instead of in 10 steps a second.
        if target < barWidth && barWidth - target < 40 {
            withAnimation(.linear(duration: 0.1)) { barWidth = target }
        } else if target != barWidth {
            barWidth = target
        }
    }
}

// MARK: - Island content (header + views, only in expanded mode)

struct IslandContentView: View {
    @ObservedObject var state: AppState

    var body: some View {
        VStack(spacing: 0) {
            // In the menu bar's row, as tall as the notch, like the Mac's own menus.
            IslandHeader(state: state)
                .frame(height: min(state.notchHeight, IslandConst.designHeaderBottom))
                .padding(.bottom, max(0, state.notchHeight - IslandConst.designHeaderBottom))
                .opacity(state.view == .confused ? 0 : 1)
                .animation(.easeInOut(duration: 0.2), value: state.view == .confused)

            ZStack {
                ForEach(IslandView.allCases, id: \.self) { v in
                    let active = state.view == v
                    // Views that fill available height instead of the fixed 98pt content frame:
                    // chat (prompt) is always flexible; mail is flexible only when active so
                    // it doesn't push the ZStack taller when inactive.
                    let isTall = v == .prompt || (v == .mail && active)
                    let anim: Animation = active
                        ? .spring(response: 0.4, dampingFraction: 0.8).delay(0.16)
                        : .easeIn(duration: 0.16)
                    IslandViewContent(view: v, state: state)
                        // Views behind the active one stay mounted (for the cross-fade)
                        // but stop their endless animations: nobody sees them.
                        .environment(\.islandViewActive, active)
                        .frame(maxWidth: .infinity)
                        .frame(height: isTall ? nil : 98)
                        .frame(minHeight: (isTall && !active) ? 0 : nil, maxHeight: isTall ? .infinity : nil)
                        .opacity(active ? 1 : 0)
                        .scaleEffect(active ? 1 : 0.97)
                        .allowsHitTesting(active)
                        .animation(anim, value: state.view)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .padding(.horizontal, 10)
        }
        .padding(.bottom, 10)
        .foregroundColor(Color(hex: "#F5F6F8"))
    }
}

// MARK: - Island header (tabs + icons)

struct IslandHeader: View {
    @ObservedObject var state: AppState

    @State private var closeHovered = false

    /// Pending approval or mail draft: the island refuses to fold (fsm.isHeldOpen), so the
    /// close cross is not shown.
    private var heldOpen: Bool { state.pendingApproval != nil || state.voiceMailDraft != nil }

    var body: some View {
        HStack(spacing: 0) {
            // Left: tab capsules
            HStack(spacing: 5) {
                TabButton(icon: "house.fill", view: .overview, state: state)
                TabButton(icon: "bubble.left.fill", view: .prompt, state: state, preAction: {
                    #if !APPSTORE
                    if state.promptContext == nil {
                        state.promptContext = WindowContextCapture.captureActive(from: state.lastExternalApp)
                    }
                    #endif
                })
                TabButton(icon: "plus", view: .upload, state: state)
            }
            .padding(.leading, 14)

            Spacer()

            // Right: plan pill (GitHub build, home view only) + action icons
            HStack(spacing: 8) {
                #if !APPSTORE
                // Claude and Codex both on: only Claude here (two pills and the icons do not
                // clear the notch); Codex is a row in the Claude plan card.
                if state.view == .overview && state.showPlanInNotch && state.planRelayInstalled {
                    ClaudePlanHeaderPill(state: state)
                } else if state.view == .overview && state.showCodexPlanInNotch {
                    ClaudePlanHeaderPill(state: state, codex: true)
                }
                #endif
                HStack(spacing: 14) {
                    Button(action: {
                        withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                            state.view = .settings
                        }
                    }) {
                        Image(systemName: state.view == .settings ? "gearshape.fill" : "gearshape")
                            .font(.system(size: 14))
                            .foregroundColor(state.view == .settings ? Color(hex: "#F5F6F8") : Color(hex: "#8E939C"))
                    }
                    .buttonStyle(.plain)

                    Button(action: { state.soundEnabled.toggle() }) {
                        Image(systemName: state.soundEnabled ? "speaker.wave.2" : "speaker.slash")
                            .font(.system(size: 14))
                            .foregroundColor(Color(hex: "#8E939C"))
                    }
                    .buttonStyle(.plain)

                    // Fold back to the compact island now, without waiting for the timer.
                    if !heldOpen {
                        Button(action: {
                            NotificationCenter.default.post(name: .islandCollapse, object: nil)
                        }) {
                            Image(systemName: "xmark")
                                .font(.system(size: 12, weight: .medium))
                                .foregroundColor(Color(hex: closeHovered ? "#F5F6F8" : "#8E939C"))
                                .frame(width: 16, height: 16)
                                .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help(String(localized: "Close"))
                        .onHover { closeHovered = $0 }
                    }
                }
            }
            .padding(.trailing, 16)
        }
        .frame(maxHeight: .infinity)
    }
}

struct TabButton: View {
    let icon: String
    let view: IslandView
    @ObservedObject var state: AppState
    var preAction: (() -> Void)? = nil
    @State private var isHovered = false

    private var isOn: Bool {
        if view == .overview { return state.view == .overview || state.view == .empty }
        return state.view == view
    }

    var body: some View {
        Button(action: {
            preAction?()
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                state.view = view
            }
        }) {
            Image(systemName: icon)
                .font(.system(size: 13))
                .foregroundColor(isOn ? Color(hex: "#F5F6F8") : (isHovered ? Color(hex: "#B0B5BE") : Color(hex: "#8E939C")))
                .frame(width: 30, height: 22)
                .background(
                    isOn ? Color(hex: "#1D1F23") :
                    isHovered ? Color.white.opacity(0.07) : Color.clear
                )
                .clipShape(Capsule())
        }
        .buttonStyle(.plain)
        .onHover { isHovered = $0 }
    }
}

// MARK: - Claude Plan header pill (GitHub build only)

#if !APPSTORE
struct ClaudePlanHeaderPill: View {
    @ObservedObject var state: AppState
    var codex: Bool = false
    @State private var isHovered = false

    private var effectiveColor: String {
        if codex { return CodexPlanGauge.color(state.codexPlanUsage) }
        return ClaudePlanGauge.color(for: (state.demoPlanUsageOverride ?? state.claudePlanUsage).flatMap { ClaudePlanGauge.dominantPct($0) })
    }

    private var label: String {
        if codex { return CodexPlanGauge.pillLabel(state.codexPlanUsage) }
        guard let usage = state.demoPlanUsageOverride ?? state.claudePlanUsage,
              let pct = ClaudePlanGauge.dominantPct(usage) else { return "Claude —" }
        return "Claude \(Int(pct.rounded()))%"
    }

    private var isOpen: Bool { state.showingPlanDetail && state.planDetailIsCodex == codex }
    private var isActive: Bool { isOpen || isHovered }

    var body: some View {
        Button(action: {
            withAnimation(.spring(response: 0.28, dampingFraction: 0.82)) {
                let open = isOpen
                state.planDetailIsCodex = codex
                state.showingPlanDetail = !open
            }
            if codex { state.refreshCodexPlanUsage() }
        }) {
            HStack(spacing: 4) {
                Circle()
                    .fill(Color(hex: effectiveColor))
                    .frame(width: 6, height: 6)
                Text(label)
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundColor(isActive
                                     ? Color(hex: effectiveColor).lighter(by: 0.3)
                                     : Color(hex: "#6B7079"))
                    .lineLimit(1)
                    .fixedSize()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .background(
                Capsule()
                    .fill(isActive
                          ? Color(hex: effectiveColor).opacity(0.18)
                          : Color(hex: "#0E0F11"))
            )
            .overlay(
                Capsule()
                    .stroke(Color(hex: effectiveColor).opacity(isActive ? 0.55 : 0.14), lineWidth: 1)
            )
        }
        .buttonStyle(.plain)
        .onHover { h in
            withAnimation(.spring(response: 0.2, dampingFraction: 0.7)) { isHovered = h }
        }
        .onAppear { if codex { state.refreshCodexPlanUsage() } }
    }
}
#endif

// MARK: - Compact mini mochi grid (2×2 to the right of the notch)

struct CompactMiniGrid: View {
    @ObservedObject var state: AppState

    private var others: [AgentTask] {
        Array(state.tasks.filter { $0.id != state.focusId }.prefix(4))
    }

    var body: some View {
        let cols = [GridItem(.fixed(12), spacing: 4), GridItem(.fixed(12), spacing: 4)]
        LazyVGrid(columns: cols, spacing: 4) {
            ForEach(others) { task in
                PillLogo(task: task, size: 10)
                    .frame(width: 12, height: 12, alignment: .center)
            }
        }
        .frame(width: 28, height: 28)
    }
}
