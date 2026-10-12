import AppKit
import SwiftUI

/// Settings → Character: dress each agent's robot. The robot on the island wears the look of the
/// pill in focus; a pill without one of its own, or one that isn't an agent, wears the default's.
struct CharacterSettingsView: View {
    @ObservedObject var state: AppState
    @State private var pill = RobotWardrobe.stored.defaultPill
    /// Only for the preview here: the island shows what its agent is doing.
    @State private var mood: RobotMood = .idle

    /// The places you code and the agents this build has, in the catalog's order.
    private var agents: [PillDefinition] {
        PillCatalog.available.filter { RobotWardrobe.dressable($0.id) }
    }

    private var wardrobe: RobotWardrobe { state.robotWardrobe }
    private var look: RobotLook { wardrobe.look(for: pill) }
    private var isDefault: Bool { wardrobe.defaultPill == pill }
    private var ownsLook: Bool { wardrobe.looks[pill] != nil }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            stage

            GroupBox(String(localized: "Agent")) {
                VStack(alignment: .leading, spacing: 10) {
                    Picker(String(localized: "Agent"), selection: $pill) {
                        ForEach(agents, id: \.id) { def in
                            Text(verbatim: Self.name(of: def)).tag(def.id)
                        }
                    }
                    .labelsHidden()
                    Toggle(String(localized: "Default robot for every other app"), isOn: Binding(
                        get: { isDefault },
                        set: { if $0 { dress { $0.defaultPill = pill } } }
                    ))
                    .disabled(isDefault)
                    Text(isDefault || ownsLook
                         ? String(localized: "Changes show on the island at once.")
                         : String(localized: "Wears the default robot until you dress it here."))
                        .font(.system(size: 11))
                        .foregroundColor(.secondary)
                }
                .padding(6)
                .frame(maxWidth: .infinity, alignment: .leading)
            }

            GroupBox(String(localized: "Wardrobe")) {
                VStack(alignment: .leading, spacing: 12) {
                    row(String(localized: "Pattern")) {
                        Picker("", selection: binding(\.skin)) {
                            ForEach(RobotSkin.allCases) { Text($0.title).tag($0) }
                        }
                    }
                    row(String(localized: "Ears")) {
                        Picker("", selection: binding(\.ears)) {
                            ForEach(RobotEars.allCases) { Text($0.title).tag($0) }
                        }
                    }
                    row(String(localized: "Accessory")) {
                        Picker("", selection: binding(\.accessory)) {
                            ForEach(RobotAccessory.allCases) { Text($0.title).tag($0) }
                        }
                    }
                    HStack(spacing: 18) {
                        colour(String(localized: "Body"), \.body)
                        if look.skin != .plain { colour(String(localized: "Pattern"), \.ink) }
                        if look.accessory == .beanie { colour(String(localized: "Hat"), \.hat) }
                        Spacer()
                        if look != .standard || (ownsLook && !isDefault) {
                            Button(String(localized: "Reset")) {
                                dress { w in
                                    if w.defaultPill == pill { w.looks[pill] = .standard } else { w.looks[pill] = nil }
                                }
                            }
                            .controlSize(.small)
                        }
                    }
                }
                .pickerStyle(.segmented)
                .padding(6)
            }
        }
    }

    /// The robot on a card like the island's, lit in the mood tried here.
    private var stage: some View {
        VStack(spacing: 10) {
            ZStack {
                RoundedRectangle(cornerRadius: 22)
                    .fill(Color(hex: "#161719"))
                    .overlay(
                        EllipticalGradient(
                            gradient: Gradient(stops: [
                                .init(color: Color(hex: mood.glowHex).opacity(0.35), location: 0),
                                .init(color: .clear, location: 0.72)
                            ]),
                            center: UnitPoint(x: 0.5, y: 1.5), startRadiusFraction: 0, endRadiusFraction: 2
                        )
                        .clipShape(RoundedRectangle(cornerRadius: 22))
                    )
                RobotView(look: look, mood: mood,
                          patchLabel: RobotView.patchLabel(for: pill, wardrobe: wardrobe))
                    .frame(width: 210, height: 210)
            }
            .frame(height: 220)
            Picker(String(localized: "Try a mood"), selection: $mood) {
                ForEach(RobotMood.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
        }
    }

    private func row<Content: View>(_ title: String, @ViewBuilder _ content: () -> Content) -> some View {
        HStack {
            Text(title).frame(width: 80, alignment: .leading)
            content().labelsHidden()
        }
    }

    private func colour(_ title: String, _ key: WritableKeyPath<RobotLook, String>) -> some View {
        ColorPicker(title, selection: Binding(
            get: { Color(hex: look[keyPath: key]) },
            set: { c in
                guard let hex = Self.hex(c) else { return }
                set(key, hex)
            }
        ), supportsOpacity: false)
        .font(.system(size: 12))
    }

    private func binding<T>(_ key: WritableKeyPath<RobotLook, T>) -> Binding<T> {
        Binding(get: { look[keyPath: key] }, set: { set(key, $0) })
    }

    /// Saves `pill`'s look with `key` changed: dressing a pill gives it a look of its own.
    private func set<T>(_ key: WritableKeyPath<RobotLook, T>, _ value: T) {
        dress { w in
            var l = w.look(for: pill)
            l[keyPath: key] = value
            w.looks[pill] = l
        }
    }

    private func dress(_ change: (inout RobotWardrobe) -> Void) {
        var w = state.robotWardrobe
        change(&w)
        state.robotWardrobe = w
    }

    private static func name(of def: PillDefinition) -> String {
        def.id == "integration_claude" ? "Claude Code" : def.name
    }

    private static func hex(_ c: Color) -> String? {
        guard let s = NSColor(c).usingColorSpace(.sRGB) else { return nil }
        let v = [s.redComponent, s.greenComponent, s.blueComponent].map { Int(($0 * 255).rounded()).clamped(0, 255) }
        return String(format: "#%02X%02X%02X", v[0], v[1], v[2])
    }
}

private extension Int {
    func clamped(_ lo: Int, _ hi: Int) -> Int { Swift.min(Swift.max(self, lo), hi) }
}
