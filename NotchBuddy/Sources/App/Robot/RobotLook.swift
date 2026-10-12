import Foundation
import simd

// The robot: what it can wear, how each agent dresses it, and the mood it shows. Ported from
// beeprio-notch (entities/bot/model): one model, four skins, three styles of ears, a beanie.

enum RobotSkin: String, Codable, CaseIterable, Identifiable {
    case plain, stripes, dots, checks
    var id: String { rawValue }
    var title: String {
        switch self {
        case .plain:   return String(localized: "Plain")
        case .stripes: return String(localized: "Stripes")
        case .dots:    return String(localized: "Dots")
        case .checks:  return String(localized: "Checks")
        }
    }
}

enum RobotEars: String, Codable, CaseIterable, Identifiable {
    case hatch, grille, dial
    var id: String { rawValue }
    var title: String {
        switch self {
        case .hatch:  return String(localized: "Ring")
        case .grille: return String(localized: "Speaker")
        case .dial:   return String(localized: "Dial")
        }
    }
    /// How far the ears stand off the head at their top, where the beanie's cuff comes down on them.
    var brim: Float {
        switch self {
        case .hatch:  return 0.045
        case .grille: return 0.07
        case .dial:   return 0.16
        }
    }
}

enum RobotAccessory: String, Codable, CaseIterable, Identifiable {
    case none, beanie
    var id: String { rawValue }
    var title: String {
        switch self {
        case .none:   return String(localized: "None")
        case .beanie: return String(localized: "Beanie")
        }
    }
}

/// How one agent's robot is dressed. Colours are "#RRGGBB".
struct RobotLook: Codable, Equatable {
    var skin: RobotSkin = .plain
    var ears: RobotEars = .hatch
    var accessory: RobotAccessory = .none
    var body = "#F6F7F9"
    var ink = "#5FDCFF"
    var hat = "#4A4F66"

    static let standard = RobotLook()

    init() {}

    /// A saved look, whatever is missing or unreadable in it back to the standard one: the
    /// defaults can be edited by hand.
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let hex = { (key: CodingKeys, fallback: String) -> String in
            let v = (try? c.decode(String.self, forKey: key)) ?? fallback
            return RobotLook.isHex(v) ? v : fallback
        }
        skin = (try? c.decode(RobotSkin.self, forKey: .skin)) ?? .plain
        ears = (try? c.decode(RobotEars.self, forKey: .ears)) ?? .hatch
        accessory = (try? c.decode(RobotAccessory.self, forKey: .accessory)) ?? .none
        body = hex(.body, RobotLook.standard.body)
        ink = hex(.ink, RobotLook.standard.ink)
        hat = hex(.hat, RobotLook.standard.hat)
    }

    static func isHex(_ s: String) -> Bool {
        s.count == 7 && s.first == "#" && s.dropFirst().allSatisfy(\.isHexDigit)
    }
}

/// Every agent's robot, kept in UserDefaults. A pill without a look of its own wears the
/// default one: the robot of the agent the user set as the default in Settings → Character.
struct RobotWardrobe: Codable, Equatable {
    /// The look of each agent pill the user dressed, by pill ID.
    var looks: [String: RobotLook] = [:]
    /// The pill whose look every other pill wears.
    var defaultPill = "integration_claude"

    static let key = "robotWardrobe"

    static var stored: RobotWardrobe {
        get {
            guard let data = UserDefaults.standard.data(forKey: key),
                  let saved = try? JSONDecoder().decode(RobotWardrobe.self, from: data) else { return RobotWardrobe() }
            return saved
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) { UserDefaults.standard.set(data, forKey: key) }
        }
    }

    /// The look `pill` wears: its own if the user dressed it and it's an agent, else the default's.
    func look(for pill: String?) -> RobotLook {
        if let pill, RobotWardrobe.dressable(pill), let own = looks[pill] { return own }
        return looks[defaultPill] ?? .standard
    }

    /// Whether a pill gets a robot of its own: the places you code and the agents. Services
    /// and chat providers wear the default one.
    static func dressable(_ pill: String) -> Bool {
        guard let def = PillCatalog.all.first(where: { $0.id == pill }) else { return false }
        return def.category == .workspace || def.category == .agent
    }
}

/// What the robot's face and pose say, from beeprio's five moods.
enum RobotMood: String, CaseIterable, Identifiable {
    case idle, working, needsYou, error, done
    var id: String { rawValue }

    var title: String {
        switch self {
        case .idle:     return String(localized: "Idle")
        case .working:  return String(localized: "Working")
        case .needsYou: return String(localized: "Waiting for you")
        case .error:    return String(localized: "Error")
        case .done:     return String(localized: "Done")
        }
    }

    /// The screen's and the ears' light.
    var glow: SIMD3<Float> {
        switch self {
        case .idle:     return RobotColor.srgb("#3AA8FF")
        case .working:  return RobotColor.srgb("#62A8FF")
        case .needsYou: return RobotColor.srgb("#FFB547")
        case .error:    return RobotColor.srgb("#FF5A6A")
        case .done:     return RobotColor.srgb("#4FF0A8")
        }
    }

    var glowHex: String {
        switch self {
        case .idle:     return "#3AA8FF"
        case .working:  return "#62A8FF"
        case .needsYou: return "#FFB547"
        case .error:    return "#FF5A6A"
        case .done:     return "#4FF0A8"
        }
    }

    /// Coucou's states, folded into the robot's five.
    init(_ state: BotState) {
        switch state {
        case .idle, .sleeping:                 self = .idle
        case .working, .thinking, .searching:  self = .working
        case .approval, .question:             self = .needsYou
        case .error, .ratelimit, .dizzy:       self = .error
        case .finished:                        self = .done
        }
    }
}

enum RobotColor {
    /// "#RRGGBB" as sRGB components 0…1.
    static func srgb(_ hex: String) -> SIMD3<Float> {
        let v = UInt32(hex.dropFirst(), radix: 16) ?? 0xFFFFFF
        return SIMD3(Float((v >> 16) & 0xFF), Float((v >> 8) & 0xFF), Float(v & 0xFF)) / 255
    }

    static func linear(_ hex: String) -> SIMD3<Float> {
        srgb(hex).map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
    }

    /// The hue of an sRGB colour, 0…1.
    static func hue(_ c: SIMD3<Float>) -> Float {
        let mx = c.max(), d = mx - c.min()
        guard d > 0 else { return 0 }
        var h: Float
        if mx == c.x { h = ((c.y - c.z) / d).truncatingRemainder(dividingBy: 6) }
        else if mx == c.y { h = (c.z - c.x) / d + 2 }
        else { h = (c.x - c.y) / d + 4 }
        h /= 6
        return h < 0 ? h + 1 : h
    }

    /// Full-strength `hue` at lightness `l`, linear.
    static func hsl(_ h: Float, _ s: Float, _ l: Float) -> SIMD3<Float> {
        let a = s * min(l, 1 - l)
        func f(_ n: Float) -> Float {
            let k = (n + h * 12).truncatingRemainder(dividingBy: 12)
            return l - a * max(-1, min(k - 3, 9 - k, 1))
        }
        return SIMD3(f(0), f(8), f(4)).map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) }
    }
}

private extension SIMD3 where Scalar == Float {
    func map(_ f: (Float) -> Float) -> SIMD3<Float> { SIMD3(f(x), f(y), f(z)) }
}
