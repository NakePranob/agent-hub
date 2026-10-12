import AppKit
import SwiftUI

extension RobotHandle {
    /// Coucou's island events, as the robot does them.
    func react(to note: Notification) {
        switch note.name {
        case .triggerSlap: jolt()
        case .botBlink: renderer?.life.blinkNow()
        case .botGreet: renderer?.life.show(.happy, for: 1.6)
        case .triggerEmote: if let e = note.object as? BotEmote { emote(e) }
        default: break
        }
    }

    /// A slap or a poke: it starts, with a shake.
    func jolt() { renderer?.life.jolt() }

    /// Mochi's emotes, as the robot's eyes for a moment.
    func emote(_ e: BotEmote) {
        guard let life = renderer?.life else { return }
        switch e {
        case .love, .happy, .proud: life.show(.happy, for: 1.8)
        case .surprised: life.show(.wide, for: 1.2)
        case .wink, .yawn: life.show(.closed, for: 1.2)
        case .annoyed: life.show(.narrow, for: 1.8)
        case .listening: life.show(.open, for: 1.2)
        }
    }
}

/// The robot on the island and its drag ghost: dressed as the focused agent, in its state, looking at the pointer.
struct IslandRobotView: View {
    @ObservedObject var state: AppState
    var paused = false
    @State private var handle = RobotHandle()

    var body: some View {
        let pill = state.focusTask?.id
        RobotView(look: state.robotWardrobe.look(for: pill),
                  mood: RobotMood(state.effectiveState),
                  paused: paused || state.mode == .hidden,
                  asleep: state.effectiveState == .sleeping,
                  patchLabel: RobotView.patchLabel(for: pill, wardrobe: state.robotWardrobe),
                  pointer: { [weak state] in
                      guard let state else { return nil }
                      let look = botLook(state: state, origin: nil)
                      return SIMD2(Float(look.x) * 1.5, Float(look.y) * 1.5)
                  },
                  handle: handle)
            .onReceive(NotificationCenter.default.publisher(for: .triggerSlap)) { handle.react(to: $0) }
            .onReceive(NotificationCenter.default.publisher(for: .botBlink)) { handle.react(to: $0) }
            .onReceive(NotificationCenter.default.publisher(for: .botGreet)) { handle.react(to: $0) }
            .onReceive(NotificationCenter.default.publisher(for: .triggerEmote)) { handle.react(to: $0) }
    }
}

extension RobotView {
    /// The beanie's patch for `pill`'s robot: the initials of the agent it dresses, in its colour
    /// (a dark grey where that colour is too pale to read on the cream).
    static func patchLabel(for pill: String?, wardrobe: RobotWardrobe) -> (initials: String, colour: String) {
        let owner = pill.flatMap { RobotWardrobe.dressable($0) && wardrobe.looks[$0] != nil ? $0 : nil } ?? wardrobe.defaultPill
        guard let def = PillCatalog.definition(for: owner) else { return ("CC", "#C8714F") }
        let name = def.category == .workspace ? def.sessionSubtitle : def.name
        let colour = def.color
        let c = RobotColor.srgb(colour)
        let light = 0.2126 * c.x + 0.7152 * c.y + 0.0722 * c.z
        return (initials(name), light > 0.7 ? "#3B3F4A" : colour)
    }
}
