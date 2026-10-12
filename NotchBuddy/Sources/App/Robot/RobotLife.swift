import Foundation
import simd

// What the robot does whatever it wears: eases into each mood's face and pose, blinks, looks at
// the pointer and about on its own, nods off, starts awake, and hovers. Ported from beeprio-notch
// (rig/life.ts, rig/face.ts, robot/ears/*.ts). The renderer steps it once a frame and draws what
// it says.

/// One stroke of an eye or the mouth, in face-canvas pixels: `len` between its round ends,
/// `width` its thickness, `angle` from the horizontal, `bend` how far its middle bows (negative up).
struct RobotStroke: Equatable {
    var len: Float
    var width: Float
    var angle: Float
    var bend: Float = 0
}

enum RobotEmote: Int32 {
    case none = 0, dots, alert, sweat, check, zzz
}

enum RobotEyes {
    case open, narrow, wide, happy, closed, cross

    var strokes: [RobotStroke] {
        let deg = Float.pi / 180
        switch self {
        case .open:   return Array(repeating: RobotStroke(len: 54, width: 78, angle: 90 * deg), count: 2)
        case .narrow: return Array(repeating: RobotStroke(len: 88, width: 36, angle: 0), count: 2)
        case .wide:   return Array(repeating: RobotStroke(len: 0.01, width: 144, angle: 90 * deg), count: 2)
        case .happy:  return Array(repeating: RobotStroke(len: 120, width: 36, angle: 0, bend: -48), count: 2)
        case .closed: return Array(repeating: RobotStroke(len: 100, width: 14, angle: 0, bend: 10), count: 2)
        case .cross:  return [RobotStroke(len: 140, width: 30, angle: 45 * deg), RobotStroke(len: 140, width: 30, angle: -45 * deg)]
        }
    }
}

private struct Look {
    var eyes: RobotEyes
    var mouth: (len: Float, width: Float, wave: Float) = (0.01, 0, 0)
    var emote: RobotEmote = .none
    var lean: Float = 0, sink: Float = 0, tilt: Float = 0
}

private let O_MOUTH: (len: Float, width: Float, wave: Float) = (0.01, 52, 0)
private let WAVY_MOUTH: (len: Float, width: Float, wave: Float) = (160, 16, 12)

private func look(_ mood: RobotMood) -> Look {
    switch mood {
    case .idle:     return Look(eyes: .open)
    case .working:  return Look(eyes: .narrow, emote: .dots, lean: 0.16)
    case .needsYou: return Look(eyes: .wide, mouth: O_MOUTH, emote: .alert, lean: -0.12, tilt: 0.16)
    case .error:    return Look(eyes: .cross, mouth: WAVY_MOUTH, emote: .sweat, lean: 0.22, sink: 0.12, tilt: -0.08)
    case .done:     return Look(eyes: .happy, emote: .check)
    }
}

/// Seconds of a still pointer before it nods off.
private let DOZE: Double = 15

final class RobotLife {
    private(set) var mood: RobotMood = .idle
    /// Seconds since this robot was made, as it has run (pauses don't count).
    private(set) var t: Double = 0

    // Face, in face-canvas pixels.
    private(set) var eyes = RobotEyes.open.strokes
    private(set) var mouth: (len: Float, width: Float, wave: Float) = (0.01, 0, 0)
    private(set) var gaze = SIMD2<Float>(0, 0)
    private(set) var emote: RobotEmote = .none
    private(set) var emoteAlpha: Float = 0
    /// How open the eyes are this frame, 1 wide open.
    private(set) var lid: Float = 1
    /// The mood's light, eased toward it (sRGB).
    private(set) var glow = RobotMood.idle.glow

    // Pose.
    private(set) var lean: Float = 0, sink: Float = 0, tilt: Float = 0, doze: Float = 0
    private(set) var yaw: Float = 0, pitch: Float = 0
    // Where the hover, the mood and a start put the bot this frame.
    private(set) var hoverY: Float = 0, roll: Float = 0, nod: Float = 0, shake: Float = 0

    // Ears: how bright they glow, the hatch's push and spin, the grille's push and columns, the dial's pointer.
    private(set) var earLight: Float = 1
    private var earLit: Float = 1
    private(set) var hatchOut: Float = 0, hatchSpin: Float = 0
    private(set) var grilleOut: Float = 0
    private(set) var grilleLevels = [Float](repeating: 0, count: 9)
    private(set) var dialPoint: Float = 0

    private var since: Double = 0
    private var moved: Double = 0
    private var startle: Double = -1
    private var blinkAt: Double = 2
    private var blink: Double = -1
    private var glance = SIMD2<Float>(0, 0)
    private var glanceAt: Double = 0
    private var pointer = SIMD2<Float>(0, 0)
    /// A look Coucou asks for a moment (an emote), and until when.
    private var override: (eyes: RobotEyes, until: Double)?
    /// Asleep whatever the pointer does (Coucou's sleeping state).
    var forceDoze = false

    /// True while it is easing or moving fast enough to need every frame.
    var lively: Bool {
        t - since < 1.2 || t - moved < 1.5 || t - startle < 0.8 || blink >= 0
            || override != nil || abs(emoteAlpha - (emote == .none ? 0 : 1)) > 0.01
    }
    var dozing: Bool { doze > 0.5 }

    func setMood(_ next: RobotMood) {
        guard next != mood else { return }
        mood = next
        since = t
    }

    /// Where the pointer is, about −1.5…1.5 each way from the bot, y up.
    func point(_ p: SIMD2<Float>) {
        let p = simd_clamp(p, SIMD2(repeating: -1.5), SIMD2(repeating: 1.5))
        guard simd_distance(p, pointer) > 0.002 else { return }
        if mood == .idle && t - moved > DOZE { startle = t }
        moved = t
        pointer = p
    }

    /// A slap or a poke: it starts awake, with a shake.
    func jolt() { startle = t; moved = t }
    func blinkNow() { blink = 0 }
    /// Eyes `eyes` for `seconds`.
    func show(_ eyes: RobotEyes, for seconds: Double) { override = (eyes, t + seconds) }

    func step(_ rawDt: Double) {
        let dt = Float(min(max(rawDt, 1e-3), 0.05))
        t += Double(dt)
        let m = look(mood)
        func ease(_ k: Float) -> Float { 1 - exp(-dt * k) }
        let still = t - moved
        let dozing = forceDoze || (mood == .idle && still > DOZE)
        let startled = t - startle < 0.6
        if let o = override, t > o.until { override = nil }

        lean += (m.lean - lean) * ease(6)
        sink += (m.sink - sink) * ease(6)
        tilt += (m.tilt - tilt) * ease(6)
        doze += ((dozing ? 1 : 0) - doze) * ease(2)
        glow += (mood.glow - glow) * ease(4)

        // The face eases toward the mood's, or sleep's, or a start's.
        let k = ease(10)
        let target = (startled ? RobotEyes.wide : dozing ? .closed : override?.eyes ?? m.eyes).strokes
        for i in 0..<2 { RobotLife.ease(&eyes[i], to: target[i], k) }
        let mo = dozing || startled ? (0.01, 0, 0) : m.mouth
        mouth.len += (mo.0 - mouth.len) * k
        mouth.width += (mo.1 - mouth.width) * k
        mouth.wave += (mo.2 - mouth.wave) * k
        let want: RobotEmote = dozing ? .zzz : startled ? .none : m.emote
        if want != emote {
            emoteAlpha = max(0, emoteAlpha - dt * 6)
            if emoteAlpha == 0 { emote = want }
        } else if want != .none {
            emoteAlpha = min(1, emoteAlpha + dt * 4)
        }

        // The eyes follow the pointer; left alone, they look about on their own.
        if still > 3 && t > glanceAt {
            glance = SIMD2(Float.random(in: -0.8...0.8), Float.random(in: -0.5...0.5))
            glanceAt = t + Double.random(in: 1.5...4)
        }
        let at = dozing ? SIMD2<Float>(0, -0.4) : still > 3 ? glance : pointer
        gaze.x += (at.x * 46 - gaze.x) * ease(8)
        gaze.y += (-at.y * 28 - gaze.y) * ease(8)

        // Blink every few seconds, but not in its sleep.
        lid = 1
        if blink < 0 && t > blinkAt && !dozing { blink = 0 }
        if blink >= 0 {
            blink += Double(dt)
            let p = Float(blink / 0.18)
            lid = p < 1 ? 1 - sin(p * .pi) : 1
            if p >= 1 { blink = -1; blinkAt = t + Double.random(in: 2.5...5.5) }
        }

        // Hover, then what the mood adds on top. A robot: it moves, but never squashes or stretches.
        let sinceMood = Float(t - since)
        let tf = Float(t)
        hoverY = sin(tf * (2 - doze)) * 0.06 * (1 - 0.5 * doze) - sink
        roll = 0; nod = 0; shake = 0
        if mood == .working { nod = sin(tf * 7) * 0.035 }
        if mood == .needsYou {
            let p = sinceMood.truncatingRemainder(dividingBy: 3)
            if p < 0.6 { hoverY += sin(p / 0.6 * .pi) * 0.3 }
        }
        if mood == .done { roll = sin(tf * 3.2) * 0.12; hoverY += abs(sin(tf * 3.2)) * 0.08 }
        if sinceMood < 0.6 {
            let p = sinceMood / 0.6
            if mood == .done { hoverY += sin(p * .pi) * 0.5 }
            if mood == .error { shake = sin(p * .pi * 6) * (1 - p) * 0.1 }
        }
        if startled {
            let p = Float((t - startle) / 0.6)
            hoverY += sin(p * .pi) * 0.18
            shake += sin(p * .pi * 8) * (1 - p) * 0.05
        }
        // The head turns a little toward the pointer; the eyes do most of the looking.
        yaw += (pointer.x * 0.18 - yaw) * ease(3)
        pitch += (-pointer.y * 0.1 - pitch) * ease(3)

        // Ears: breathing at rest, bright while it works, pulsing when it needs you, dim and
        // flickering on an error, dim in its sleep.
        let light: (Float, Bool, Bool, Bool) = dozing ? (0.15, false, false, false) : {
            switch mood {
            case .idle:     return (0.6, true, false, false)
            case .working:  return (1, false, false, false)
            case .needsYou: return (1.3, false, true, false)
            case .error:    return (0.3, false, false, true)
            case .done:     return (1.1, false, false, false)
            }
        }()
        earLit += (light.0 - earLit) * ease(6)
        earLight = earLit
        if light.1 { earLight *= 0.7 + 0.3 * sin(tf * 1.5) }
        if light.2 { earLight *= 0.75 + 0.25 * sin(tf * 8) }
        if light.3 && Float.random(in: 0...1) < 0.1 { earLight *= 0.2 }

        let hatch: (out: Float, spin: Float) = dozing ? (0, 0.2) : {
            switch mood {
            case .idle:     return (0, 0.6)
            case .working:  return (0.03, 5)
            case .needsYou: return (0.12, 2)
            case .error:    return (0, 0)
            case .done:     return (0.06, 3)
            }
        }()
        hatchOut += (hatch.out - hatchOut) * ease(6)
        hatchSpin += dt * hatch.spin

        grilleOut += ((mood == .needsYou && !dozing ? 0.05 : 0) - grilleOut) * ease(6)
        for c in 0..<9 {
            let fc = Float(c)
            let level: Float = dozing ? 1 : {
                switch mood {
                case .idle:     return 2.5 + 1.5 * sin(tf * 1.6 + fc * 0.8)
                case .working:  return 2 + 7 * abs(sin(tf * 7.3 + fc * 1.7) * sin(tf * 3.1 + fc * 0.9))
                case .needsYou: return 9 * (0.55 + 0.45 * sin(tf * 8))
                case .error:    return 1 + (Float.random(in: 0...1) < 0.1 ? 2 : 0)
                case .done:     return 4.5 + 4.5 * sin(tf * 5 - fc * 0.7)
                }
            }()
            grilleLevels[c] += (level - grilleLevels[c]) * ease(12)
        }

        let sweep: Float = 2.4
        let point: Float = dozing ? -sweep : {
            switch mood {
            case .idle:     return 0
            case .working:  return 1.1 * sin(tf * 2.2)
            case .needsYou: return sweep - 0.05 + 0.05 * sin(tf * 20)
            case .error:    return -sweep
            case .done:     return sweep * 0.75
            }
        }()
        dialPoint += (point - dialPoint) * ease(mood == .working ? 10 : 5)
    }

    /// Ease stroke `s` toward `to` the short way round: a line turned half a turn is the same line, bowed the other way.
    private static func ease(_ s: inout RobotStroke, to: RobotStroke, _ k: Float) {
        let turns = (s.angle - to.angle) / .pi
        let n = turns.rounded()
        s.angle += (to.angle + n * .pi - s.angle) * k
        s.len += (to.len - s.len) * k
        s.width += (to.width - s.width) * k
        let odd = Int(n) % 2 != 0
        s.bend += ((odd ? -to.bend : to.bend) - s.bend) * k
    }
}
