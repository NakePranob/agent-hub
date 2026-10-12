import AppKit
import MetalKit
import SwiftUI

/// A transparent Metal view that draws one robot and lets every click through.
final class RobotMTKView: MTKView {
    let renderer: RobotRenderer

    /// Nil where Metal or the robot's shaders aren't available.
    static func make() -> RobotMTKView? {
        RobotGPU.shared.map { RobotMTKView(gpu: $0) }
    }

    private init(gpu: RobotGPU) {
        renderer = RobotRenderer(gpu: gpu)
        super.init(frame: .zero, device: gpu.device)
        colorPixelFormat = RobotGPU.colorFormat
        depthStencilPixelFormat = RobotGPU.depthFormat
        sampleCount = RobotGPU.sampleCount
        clearColor = MTLClearColor(red: 0, green: 0, blue: 0, alpha: 0)
        layer?.isOpaque = false
        preferredFramesPerSecond = 30
        delegate = renderer
    }

    @available(*, unavailable)
    required init(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    override var isOpaque: Bool { false }
    override func hitTest(_ point: NSPoint) -> NSView? { nil }

    /// Stops drawing altogether (0 % CPU) or starts again without a jump.
    func setPaused(_ paused: Bool) {
        guard isPaused != paused else { return }
        if !paused { renderer.resume() }
        isPaused = paused
    }
}

/// Reaches the renderer of a `RobotView` from SwiftUI, to send it a blink, a start, an emote.
@MainActor
final class RobotHandle {
    fileprivate(set) weak var renderer: RobotRenderer?
}

/// One robot, dressed in `look` and showing `mood`.
struct RobotView: NSViewRepresentable {
    var look: RobotLook
    var mood: RobotMood
    var paused = false
    /// Asleep whatever the pointer does.
    var asleep = false
    var patchLabel = (initials: "CC", colour: "#C8714F")
    /// Where the pointer is from the bot, about −1.5…1.5 each way, y up; nil leaves it looking about.
    var pointer: (@MainActor () -> SIMD2<Float>?)? = nil
    var handle: RobotHandle? = nil

    func makeNSView(context: Context) -> NSView {
        guard let view = RobotMTKView.make() else { return NSView() }
        handle?.renderer = view.renderer
        update(view)
        return view
    }

    func updateNSView(_ nsView: NSView, context: Context) {
        guard let view = nsView as? RobotMTKView else { return }
        update(view)
    }

    private func update(_ view: RobotMTKView) {
        let r = view.renderer
        r.look = look
        r.life.setMood(mood)
        r.life.forceDoze = asleep
        r.patchLabel = patchLabel
        r.pointer = pointer
        handle?.renderer = r
        view.setPaused(paused)
    }
}

extension RobotView {
    /// An agent's two letters: its first two words' first letters, or a lone word's first two.
    static func initials(_ name: String) -> String {
        let words = name.split(whereSeparator: \.isWhitespace).map(String.init)
        if words.count > 1, let a = words[0].first, let b = words[1].first { return (String(a) + String(b)).uppercased() }
        let w = Array(words.first ?? "")
        return (w.first.map { String($0).uppercased() } ?? "") + (w.count > 1 ? String(w[1]).lowercased() : "")
    }
}
