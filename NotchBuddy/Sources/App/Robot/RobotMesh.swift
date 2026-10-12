import Foundation
import simd

// The robot's shape as plain geometry, built once in code (beeprio-notch's robot/scene.ts,
// robot/head.ts, robot/ears/*.ts and accessories/beanie). Units: the head is about 2 wide, Y is
// up and the bot faces +Z. Tessellated for a bot a few hundred points tall at most: about a
// third of beeprio's triangles.

struct RobotVertex {
    var position: SIMD4<Float>   // xyz, w unused
    var normal: SIMD4<Float>     // xyz, w unused
    var uv: SIMD4<Float>         // xy, zw unused
}

/// What a part is painted with; the fragment shader switches on it.
enum RobotMaterial: Int32 {
    case head = 0, lip, glass, dark, glow, spark, grille, knob, crown, cuff, patch, wool
}

/// A run of indices in the shared index buffer.
struct RobotRange { var start: Int; var count: Int }

enum RobotShape {
    static let head = SIMD3<Float>(1.1, 0.95, 1.0)
    // The screen: half its width and height as angles on the head, and how its top and bottom halves curve.
    static let visor = (yaw: Float(0.84), pitch: Float(0.7), tilt: Float(0), top: Float(2), bottom: Float(2.5))
    static let lip = (r: Float(0.035), depth: Float(0.025), dome: Float(0.025))
    /// The ball the hatch ears are curved to.
    static let curve: Float = 0.83
    /// The face canvas the eyes are drawn on, as tall as the screen is for 1024 wide.
    static let faceHeight: Float = {
        let width: Float = 1024
        return (width * visor.pitch * head.y / (visor.yaw * head.x)).rounded()
    }()

    static func surfaceNormal(_ p: SIMD3<Float>) -> SIMD3<Float> {
        simd_normalize(p / (head * head))
    }

    /// The point on the head along `dir`, `lift` out along the surface's normal.
    static func onHead(_ dir: SIMD3<Float>, _ lift: Float) -> SIMD3<Float> {
        let p = dir / simd_length(dir / head)
        return p + surfaceNormal(p) * lift
    }

    /// Where the pod on `side` (1 is +X) sits, and the way it faces.
    static func podSeat(_ side: Float) -> (at: SIMD3<Float>, out: SIMD3<Float>) {
        let at = onHead(simd_normalize(SIMD3(side, -0.06, 0.12)), 0)
        return (at, surfaceNormal(at))
    }

    static func squircle(_ a: Float, _ n: Float) -> SIMD2<Float> {
        let c = cos(a), s = sin(a)
        return SIMD2(copysign(pow(abs(c), 2 / n), c), copysign(pow(abs(s), 2 / n), s))
    }

    /// The screen's edge at angle `a`, as yaw and pitch from its centre.
    static func visorEdge(_ a: Float) -> SIMD2<Float> {
        squircle(a, sin(a) >= 0 ? visor.top : visor.bottom) * SIMD2(visor.yaw, visor.pitch)
    }

    static func visorPoint(_ yaw: Float, _ pitch: Float, _ lift: Float) -> SIMD3<Float> {
        let p = pitch + visor.tilt
        return onHead(SIMD3(sin(yaw) * cos(p), sin(p), cos(yaw) * cos(p)), lift)
    }

    /// The point `across` the screen's edge at angle `a` (negative into the screen), `up` off the head.
    static func rimPoint(_ a: Float, _ across: Float, _ up: Float) -> SIMD3<Float> {
        let e = visorEdge(a)
        let p = visorPoint(e.x, e.y, 0)
        let e1 = visorEdge(a + 1e-3), e0 = visorEdge(a - 1e-3)
        let along = visorPoint(e1.x, e1.y, 0) - visorPoint(e0.x, e0.y, 0)
        let n = p / (head * head)
        return onHead(p + simd_normalize(simd_cross(along, n)) * across, up)
    }

    /// The lip's cross-section as (across, up), `s` from the bottom of the recess (0) out to the shell (1).
    static func lipProfile(_ s: Float) -> SIMD2<Float> {
        let r = lip.r, depth = lip.depth
        let arcs = [depth - r, Float.pi * r / 2, 0.01]
        var d = s * (arcs[0] + arcs[1] + arcs[2])
        if d < arcs[0] { return SIMD2(-r, d - depth) }
        d -= arcs[0]
        if d < arcs[1] { let a = Float.pi - d / r; return SIMD2(r * cos(a), r * sin(a) - r) }
        d -= arcs[1]
        return SIMD2(d, -0.1 * d)
    }

    // ---- the beanie's fit (accessories/beanie/fit.ts) ----
    static let hatFront = SIMD3<Float>(0, 0.68, head.z * sqrt(1 - pow(0.68 / head.y, 2)))
    static let hatBack = SIMD3<Float>(0, 0.15, -head.z * sqrt(1 - pow(0.15 / head.y, 2)))
    static let hatCentre = (hatFront + hatBack) * 0.5
    static let hatAhead = simd_normalize(hatFront - hatBack)
    /// The hat's own up, leaning back.
    static let hatAxis = simd_cross(hatAhead, SIMD3<Float>(1, 0, 0))
    static func hatOut(_ a: Float) -> SIMD3<Float> { SIMD3(cos(a), 0, 0) + hatAhead * sin(a) }

    /// How far the head reaches along `hatOut(a)` from `height` up the hat's axis.
    static func reach(_ a: Float, _ height: Float) -> Float {
        let d = hatOut(a), o = hatCentre + hatAxis * height
        func s(_ u: SIMD3<Float>, _ w: SIMD3<Float>) -> Float { simd_reduce_add(u * w / (head * head)) }
        let qa = s(d, d), qb = 2 * s(o, d), qc = s(o, o) - 1
        let disc = qb * qb - 4 * qa * qc
        return disc > 0 ? max(0, (-qb + sqrt(disc)) / (2 * qa)) : 0
    }

    /// The cuff at `a` round the hat and `v` up it, lifted `lift`, its foot `brim` off the head at the sides.
    static func cuffAt(_ a: Float, _ v: Float, lift: Float = 0, brim: Float = 0.045) -> SIMD3<Float> {
        let edge = -0.16 * pow(cos(a), 2)
        let height = edge + 0.3 * v * (1 + 0.06 * sin(3 * a + 1))
        let r = (reach(a, edge) + reach(a, height)) / 2
            + (0.115 + 0.01 * sin(5 * a + 2)) * pow(sin(.pi * v), 0.3)
            + 0.025 * v + brim * pow(cos(a), 8) * pow(1 - v, 2) + lift
        return hatCentre + hatAxis * height + hatOut(a) * r
    }

    /// The crown through the baked grid, Catmull–Rom both ways: `a` round it in radians, `v` up it.
    static func crownAt(_ a: Float, _ v: Float) -> SIMD3<Float> {
        let cols = RobotCrown.columns, rows = RobotCrown.rows
        func point(_ i: Int, _ k: Int) -> SIMD3<Float> {
            let j = k >= rows ? cols * rows : max(k, 0) * cols + ((i % cols) + cols) % cols
            return SIMD3(RobotCrown.grid[j * 3], RobotCrown.grid[j * 3 + 1], RobotCrown.grid[j * 3 + 2])
        }
        func spline(_ p: [SIMD3<Float>], _ t: Float) -> SIMD3<Float> {
            let t2 = t * t, t3 = t2 * t
            return p[0] * (-0.5 * t3 + t2 - 0.5 * t) + p[1] * (1.5 * t3 - 2.5 * t2 + 1)
                + p[2] * (-1.5 * t3 + 2 * t2 + 0.5 * t) + p[3] * (0.5 * t3 - 0.5 * t2)
        }
        let x = a / (2 * .pi) * Float(cols), y = min(v, 1) * Float(rows)
        let i = Int(floor(x)), k = min(Int(floor(y)), rows - 1)
        let ring = (-1...2).map { di in spline((-1...2).map { dk in point(i + di, k + dk) }, y - Float(k)) }
        return spline(ring, x - Float(i))
    }
    static let patchSpot = Float.pi / 2 + 0.4
}

/// Accumulates every part into one vertex and one index buffer.
final class RobotMeshBuilder {
    private(set) var vertices: [RobotVertex] = []
    private(set) var indices: [UInt32] = []

    private func add(_ p: SIMD3<Float>, _ n: SIMD3<Float>, _ uv: SIMD2<Float> = .zero) -> UInt32 {
        vertices.append(RobotVertex(position: SIMD4(p, 1), normal: SIMD4(n, 0), uv: SIMD4(uv.x, uv.y, 0, 0)))
        return UInt32(vertices.count - 1)
    }

    /// A grid `cols` × `rows` over `point(i, k)`: wrapping round when `wrap`; normals from `normal`, or
    /// worked out from the faces when nil.
    @discardableResult
    func grid(cols: Int, rows: Int, wrap: Bool,
              point: (Int, Int) -> SIMD3<Float>,
              uv: (Int, Int) -> SIMD2<Float> = { _, _ in .zero },
              normal: ((Int, Int) -> SIMD3<Float>)? = nil) -> RobotRange {
        let base = vertices.count, start = indices.count
        let width = wrap ? cols : cols + 1
        for k in 0...rows {
            for i in 0..<width {
                _ = add(point(i, k), normal?(i, k) ?? .zero, uv(i, k))
            }
        }
        func at(_ i: Int, _ k: Int) -> UInt32 { UInt32(base + k * width + (wrap ? i % cols : i)) }
        for k in 0..<rows {
            for i in 0..<cols {
                let a = at(i, k), b = at(i + 1, k), c = at(i + 1, k + 1), d = at(i, k + 1)
                indices += [a, b, c, a, c, d]
            }
        }
        if normal == nil { smoothNormals(from: start, vertexBase: base) }
        return RobotRange(start: start, count: indices.count - start)
    }

    /// Per-vertex normals from the area of the faces round each, for the indices from `start`;
    /// vertices that sit on the same spot share theirs.
    private func smoothNormals(from start: Int, vertexBase: Int) {
        var acc = [SIMD3<Float>](repeating: .zero, count: vertices.count - vertexBase)
        for t in stride(from: start, to: indices.count, by: 3) {
            let ia = Int(indices[t]), ib = Int(indices[t + 1]), ic = Int(indices[t + 2])
            let a = vertices[ia].position.xyz, b = vertices[ib].position.xyz, c = vertices[ic].position.xyz
            let n = simd_cross(b - a, c - a)
            for i in [ia, ib, ic] { acc[i - vertexBase] += n }
        }
        // Weld by position, so a polar grid's centre and a sheet's seam come out smooth.
        var welded: [SIMD3<Int32>: SIMD3<Float>] = [:]
        func key(_ p: SIMD3<Float>) -> SIMD3<Int32> { SIMD3<Int32>((p * 1e4).rounded(.toNearestOrEven)) }
        for (i, n) in acc.enumerated() { welded[key(vertices[vertexBase + i].position.xyz), default: .zero] += n }
        for i in 0..<acc.count {
            let n = welded[key(vertices[vertexBase + i].position.xyz)] ?? .zero
            let l = simd_length(n)
            vertices[vertexBase + i].normal = SIMD4(l > 0 ? n / l : SIMD3(0, 0, 1), 0)
        }
    }

    /// Appends `range`'s triangles again with every vertex moved by `m`, for parts made of copies.
    func transformed(_ make: () -> RobotRange, _ m: simd_float4x4) -> RobotRange {
        let vBase = vertices.count
        let r = make()
        for i in vBase..<vertices.count {
            let p = m * SIMD4(vertices[i].position.xyz, 1)
            let n = m * SIMD4(vertices[i].normal.xyz, 0)
            vertices[i].position = SIMD4(p.xyz, 1)
            vertices[i].normal = SIMD4(simd_normalize(n.xyz), 0)
        }
        return r
    }

    // ---- primitives, each about +Z unless said ----

    /// A cap of the ball of radius `r` centred at z = `centreZ`, out to `size` from the Z axis.
    func cap(r: Float, size: Float, centreZ: Float, segments: Int = 40, rings: Int = 6) -> RobotRange {
        let top = asin(min(1, size / r))
        return grid(cols: segments, rows: rings, wrap: true, point: { i, k in
            let th = top * Float(k) / Float(rings), ph = 2 * .pi * Float(i) / Float(segments)
            return SIMD3(r * sin(th) * cos(ph), r * sin(th) * sin(ph), centreZ + r * cos(th))
        }, normal: { i, k in
            let th = top * Float(k) / Float(rings), ph = 2 * .pi * Float(i) / Float(segments)
            return SIMD3(sin(th) * cos(ph), sin(th) * sin(ph), cos(th))
        })
    }

    /// A torus round the Z axis at z, `arc` radians of it from +X.
    func torus(radius: Float, tube: Float, z: Float, arc: Float = 2 * .pi, segments: Int = 48, sides: Int = 6) -> RobotRange {
        let whole = arc >= 2 * .pi - 1e-4
        return grid(cols: segments, rows: sides, wrap: whole ? true : false, point: { i, k in
            let u = arc * Float(i) / Float(segments), v = 2 * .pi * Float(k) / Float(sides)
            return SIMD3((radius + tube * cos(v)) * cos(u), (radius + tube * cos(v)) * sin(u), z + tube * sin(v))
        }, normal: { i, k in
            let u = arc * Float(i) / Float(segments), v = 2 * .pi * Float(k) / Float(sides)
            return SIMD3(cos(v) * cos(u), cos(v) * sin(u), sin(v))
        })
    }

    /// A cylinder along Z from z0 (radius r0) to z1 (radius r1), with its end at z1 closed.
    func cylinder(r0: Float, r1: Float, z0: Float, z1: Float, segments: Int = 40) -> RobotRange {
        let start = indices.count
        _ = grid(cols: segments, rows: 1, wrap: true, point: { i, k in
            let a = 2 * .pi * Float(i) / Float(segments), r = k == 0 ? r0 : r1
            return SIMD3(r * cos(a), r * sin(a), k == 0 ? z0 : z1)
        }, normal: { i, _ in
            let a = 2 * .pi * Float(i) / Float(segments)
            return simd_normalize(SIMD3(cos(a), sin(a), (r0 - r1) / (z1 - z0)))
        })
        _ = disc(radius: r1, z: z1, segments: segments)
        return RobotRange(start: start, count: indices.count - start)
    }

    /// A flat disc facing +Z, its UVs across its square.
    func disc(radius: Float, z: Float, segments: Int = 40, rings: Int = 1) -> RobotRange {
        grid(cols: segments, rows: rings, wrap: true, point: { i, k in
            let a = 2 * .pi * Float(i) / Float(segments), r = radius * Float(k) / Float(rings)
            return SIMD3(r * cos(a), r * sin(a), z)
        }, uv: { i, k in
            let a = 2 * .pi * Float(i) / Float(segments), r = Float(k) / Float(rings)
            return SIMD2(0.5 + 0.5 * r * cos(a), 0.5 + 0.5 * r * sin(a))
        }, normal: { _, _ in SIMD3(0, 0, 1) })
    }

    /// A box centred at `c`, sides `s`.
    func box(_ s: SIMD3<Float>, at c: SIMD3<Float>) -> RobotRange {
        let start = indices.count
        let h = s / 2
        for axis in 0..<3 {
            for sign: Float in [-1, 1] {
                var n = SIMD3<Float>.zero; n[axis] = sign
                let u = (axis + 1) % 3, v = (axis + 2) % 3
                var corners: [UInt32] = []
                for (du, dv): (Float, Float) in [(-1, -1), (1, -1), (1, 1), (-1, 1)] {
                    var p = c; p[axis] += sign * h[axis]; p[u] += du * h[u]; p[v] += dv * h[v]
                    corners.append(add(p, n))
                }
                indices += [corners[0], corners[1], corners[2], corners[0], corners[2], corners[3]]
            }
        }
        return RobotRange(start: start, count: indices.count - start)
    }

    /// A tube of radius `r` along the closed path `path`.
    func tube(_ path: [SIMD3<Float>], r: Float, sides: Int = 6) -> RobotRange {
        let n = path.count
        return grid(cols: n, rows: sides, wrap: true, point: { i, k in
            let (p, a, b) = frame(path, i)
            let v = 2 * .pi * Float(k) / Float(sides)
            return p + (a * cos(v) + b * sin(v)) * r
        }, normal: { i, k in
            let (_, a, b) = frame(path, i)
            let v = 2 * .pi * Float(k) / Float(sides)
            return a * cos(v) + b * sin(v)
        })
        func frame(_ path: [SIMD3<Float>], _ i: Int) -> (SIMD3<Float>, SIMD3<Float>, SIMD3<Float>) {
            let p = path[i % n], t = simd_normalize(path[(i + 1) % n] - path[(i + n - 1) % n])
            let a = simd_normalize(simd_cross(t, p))
            return (p, a, simd_cross(t, a))
        }
    }
}

private extension SIMD4 where Scalar == Float {
    var xyz: SIMD3<Float> { SIMD3(x, y, z) }
}

/// Every part of the robot, built once into one pair of buffers.
struct RobotMesh {
    var vertices: [RobotVertex]
    var indices: [UInt32]

    // On the head.
    var head, visor, lip, gasket: RobotRange
    // Built in an ear's own frame (Z out of the head), drawn once each side.
    var hatchBase, hatchGlow, hatchSpark: RobotRange
    var grilleBase, grilleFace: RobotRange
    var dialPlate, dialTicks, dialKnob, dialDark, dialPointer: RobotRange
    // The beanie: the crown and knot, and the cuff and patch for each style of ears it rests on.
    var crown, nub: RobotRange
    var cuff: [RobotEars: RobotRange]
    var patch: [RobotEars: RobotRange]

    static func build() -> RobotMesh {
        let b = RobotMeshBuilder()
        let S = RobotShape.self
        let V = S.visor, L = S.lip

        // The head: a UV sphere scaled to the head, its UVs the skin's wrap (u round from −X, v down from the top).
        let head = b.grid(cols: 64, rows: 40, wrap: false, point: { i, k in
            let ph = 2 * Float.pi * Float(i) / 64, th = Float.pi * Float(k) / 40
            return SIMD3(-cos(ph) * sin(th), cos(th), sin(ph) * sin(th)) * S.head
        }, uv: { i, k in SIMD2(Float(i) / 64, Float(k) / 40) }, normal: { i, k in
            let ph = 2 * Float.pi * Float(i) / 64, th = Float.pi * Float(k) / 40
            return S.surfaceNormal(SIMD3(-cos(ph) * sin(th), cos(th), sin(ph) * sin(th)) * S.head)
        })

        // The glass: the head's own curve, sunk into the recess and domed in the middle, UVs across the face canvas.
        let visor = b.grid(cols: 96, rows: 12, wrap: true, point: { i, k in
            let s = Float(k) / 12, e = S.visorEdge(2 * .pi * Float(i) / 96)
            return S.visorPoint(s * e.x, s * e.y, 0.006 - L.depth + L.dome * pow(1 - s * s, 0.6))
        }, uv: { i, k in
            let s = Float(k) / 12, e = S.visorEdge(2 * .pi * Float(i) / 96)
            return SIMD2(0.5 + s * e.x / (2 * V.yaw), 0.5 + s * e.y / (2 * V.pitch))
        })
        let lip = b.grid(cols: 96, rows: 8, wrap: true, point: { i, k in
            let p = S.lipProfile(Float(k) / 8)
            return S.rimPoint(2 * .pi * Float(i) / 96, p.x, p.y)
        })
        let gasket = b.tube((0..<96).map { S.rimPoint(2 * .pi * Float($0) / 96, -L.r, 0.01 - L.depth) }, r: 0.008)

        // Hatch ears: a dark rim, lit inside, a dark ring and middle, and a bright notch running round.
        let c = S.curve
        func ringZ(_ r: Float, _ size: Float) -> Float { sqrt(r * r - size * size) - c }
        let hatchBaseStart = b.indices.count
        _ = b.cylinder(r0: 0.3, r1: 0.3, z0: -0.36, z1: -0.06)
        _ = b.cap(r: c + 0.01, size: 0.355, centreZ: -c)
        _ = b.torus(radius: 0.353, tube: 0.016, z: ringZ(c + 0.004, 0.353))
        _ = b.torus(radius: 0.132, tube: 0.012, z: ringZ(c + 0.02, 0.132), segments: 32)
        _ = b.cap(r: c + 0.02, size: 0.128, centreZ: -c, segments: 24, rings: 3)
        let hatchBase = RobotRange(start: hatchBaseStart, count: b.indices.count - hatchBaseStart)
        let hatchGlow = b.cap(r: c + 0.016, size: 0.25, centreZ: -c, segments: 40, rings: 4)
        let hatchSpark = b.torus(radius: 0.19, tube: 0.01, z: ringZ(c + 0.019, 0.19), arc: 1, segments: 12)

        // Speaker ears: a dark housing with a rim, and a grille the shader punches and lights.
        let grilleStart = b.indices.count
        _ = b.cylinder(r0: 0.3, r1: 0.3, z0: -0.36, z1: -0.06)
        _ = b.cylinder(r0: 0.34, r1: 0.33, z0: -0.09, z1: 0.03)
        _ = b.torus(radius: 0.31, tube: 0.03, z: 0.03)
        let grilleBase = RobotRange(start: grilleStart, count: b.indices.count - grilleStart)
        let grilleFace = b.disc(radius: 0.29, z: 0.035)

        // Dial ears: a dark plate with a scale of lit ticks, and a knob in the body's colour with a pointer.
        let dialPlate = b.cap(r: 0.84, size: 0.34, centreZ: -0.83)
        let tickStart = b.indices.count
        for i in 0..<11 {
            let th = -2.4 + 4.8 * Float(i) / 10
            _ = b.transformed({ b.box(SIMD3(0.018, 0.05, 0.01), at: SIMD3(0, 0.28, -0.025)) },
                              simd_float4x4(simd_quatf(angle: th, axis: SIMD3(0, 0, 1))))
        }
        let dialTicks = RobotRange(start: tickStart, count: b.indices.count - tickStart)
        let dialKnob = b.cylinder(r0: 0.2, r1: 0.18, z0: 0.01, z1: 0.15, segments: 32)
        let dialDark = b.torus(radius: 0.192, tube: 0.012, z: 0.08, segments: 32)
        let dialPointer = b.box(SIMD3(0.03, 0.13, 0.012), at: SIMD3(0, 0.09, 0.152))

        // The beanie: its crown as the bake draped it, a knot on top, and a cuff and patch for each brim.
        let crown = b.grid(cols: 64, rows: 24, wrap: false, point: { i, k in
            S.crownAt(2 * .pi * Float(i) / 64, Float(k) / 24)
        }, uv: { i, k in SIMD2(Float(i) / 64, Float(k) / 24) })
        let tip = S.crownAt(0, 1)
        let knot = simd_float4x4(translation: tip) * simd_float4x4(simd_quatf(from: SIMD3(0, 0, 1), to: S.hatAxis))
            * simd_float4x4(diagonal: SIMD4(1, 1, 0.8, 1))
        let nub = b.transformed({ b.cap(r: 0.075, size: 0.075, centreZ: 0, segments: 16, rings: 5) }, knot)
        // Its underside: the same cap turned over.
        _ = b.transformed({ b.cap(r: 0.075, size: 0.075, centreZ: 0, segments: 16, rings: 5) },
                          knot * simd_float4x4(simd_quatf(angle: .pi, axis: SIMD3(1, 0, 0))))
        let nubRange = RobotRange(start: nub.start, count: b.indices.count - nub.start)
        var cuff: [RobotEars: RobotRange] = [:], patch: [RobotEars: RobotRange] = [:]
        for ears in RobotEars.allCases {
            cuff[ears] = b.grid(cols: 96, rows: 8, wrap: false, point: { i, k in
                S.cuffAt(2 * .pi * Float(i) / 96, Float(k) / 8, brim: ears.brim)
            }, uv: { i, k in SIMD2(Float(i) / 96, Float(k) / 8) })
            patch[ears] = b.grid(cols: 10, rows: 6, wrap: false, point: { i, k in
                S.cuffAt(S.patchSpot - 0.17 + 0.34 * Float(i) / 10, 0.2 + 0.65 * Float(k) / 6, lift: 0.012, brim: ears.brim)
            }, uv: { i, k in SIMD2(1 - Float(i) / 10, 1 - Float(k) / 6) })
        }

        return RobotMesh(vertices: b.vertices, indices: b.indices,
                         head: head, visor: visor, lip: lip, gasket: gasket,
                         hatchBase: hatchBase, hatchGlow: hatchGlow, hatchSpark: hatchSpark,
                         grilleBase: grilleBase, grilleFace: grilleFace,
                         dialPlate: dialPlate, dialTicks: dialTicks, dialKnob: dialKnob, dialDark: dialDark,
                         dialPointer: dialPointer, crown: crown, nub: nubRange, cuff: cuff, patch: patch)
    }
}

extension simd_float4x4 {
    init(translation t: SIMD3<Float>) {
        self = matrix_identity_float4x4
        columns.3 = SIMD4(t, 1)
    }
}
