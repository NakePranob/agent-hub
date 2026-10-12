import AppKit
import Metal
import MetalKit
import simd

// The robot in Metal. One `RobotGPU` holds what every robot shares (the pipeline, the meshes, the
// MatCaps); each view has a `RobotRenderer` that steps its own life and draws it.

@MainActor
final class RobotGPU {
    static let shared: RobotGPU? = RobotGPU()

    let device: MTLDevice
    let queue: MTLCommandQueue
    let pipeline: MTLRenderPipelineState
    let depth: MTLDepthStencilState
    let vertices: MTLBuffer
    let indices: MTLBuffer
    let mesh: RobotMesh
    /// Light on a matte surface, and the gloss of the shell, the dark plastic and the glass.
    let diffuseCap, shellCap, darkCap, glassCap: MTLTexture
    private var patches: [String: MTLTexture] = [:]

    static let sampleCount = 4
    static let colorFormat = MTLPixelFormat.bgra8Unorm_srgb
    static let depthFormat = MTLPixelFormat.depth32Float

    private init?() {
        guard let device = MTLCreateSystemDefaultDevice(), let queue = device.makeCommandQueue() else { return nil }
        self.device = device
        self.queue = queue
        do {
            let library = try device.makeLibrary(source: RobotShaders.source, options: nil)
            let desc = MTLRenderPipelineDescriptor()
            desc.vertexFunction = library.makeFunction(name: "robot_vertex")
            desc.fragmentFunction = library.makeFunction(name: "robot_fragment")
            desc.colorAttachments[0].pixelFormat = Self.colorFormat
            desc.depthAttachmentPixelFormat = Self.depthFormat
            desc.rasterSampleCount = Self.sampleCount
            pipeline = try device.makeRenderPipelineState(descriptor: desc)
        } catch {
            NSLog("Robot: Metal pipeline failed: \(error)")
            return nil
        }
        let dd = MTLDepthStencilDescriptor()
        dd.depthCompareFunction = .less
        dd.isDepthWriteEnabled = true
        guard let depth = device.makeDepthStencilState(descriptor: dd) else { return nil }
        self.depth = depth

        mesh = RobotMesh.build()
        guard let vb = device.makeBuffer(bytes: mesh.vertices, length: MemoryLayout<RobotVertex>.stride * mesh.vertices.count),
              let ib = device.makeBuffer(bytes: mesh.indices, length: MemoryLayout<UInt32>.stride * mesh.indices.count)
        else { return nil }
        vertices = vb
        indices = ib

        let caps = RobotMatCaps(view: RobotCamera.viewRotation)
        guard let d = Self.texture(device, caps.diffuse, RobotMatCaps.size),
              let s = Self.texture(device, caps.shell, RobotMatCaps.size),
              let k = Self.texture(device, caps.dark, RobotMatCaps.size),
              let g = Self.texture(device, caps.glass, RobotMatCaps.size) else { return nil }
        diffuseCap = d; shellCap = s; darkCap = k; glassCap = g
    }

    private static func texture(_ device: MTLDevice, _ texels: [SIMD4<Float>], _ size: Int) -> MTLTexture? {
        let desc = MTLTextureDescriptor.texture2DDescriptor(pixelFormat: .rgba32Float, width: size, height: size, mipmapped: false)
        desc.usage = .shaderRead
        guard let t = device.makeTexture(descriptor: desc) else { return nil }
        texels.withUnsafeBytes {
            t.replace(region: MTLRegionMake2D(0, 0, size, size), mipmapLevel: 0,
                      withBytes: $0.baseAddress!, bytesPerRow: size * MemoryLayout<SIMD4<Float>>.stride)
        }
        return t
    }

    /// The beanie's patch: a cream label with `initials` in `colour`, drawn once per pair.
    func patch(initials: String, colour: String) -> MTLTexture? {
        let key = initials + colour
        if let t = patches[key] { return t }
        let w = 320, h = 180
        guard let ctx = CGContext(data: nil, width: w, height: h, bitsPerComponent: 8, bytesPerRow: w * 4,
                                  space: CGColorSpace(name: CGColorSpace.sRGB)!,
                                  bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return nil }
        ctx.translateBy(x: 0, y: CGFloat(h))
        ctx.scaleBy(x: 1, y: -1)
        let rect = CGPath(roundedRect: CGRect(x: 6, y: 6, width: 308, height: 168), cornerWidth: 34, cornerHeight: 34, transform: nil)
        ctx.addPath(rect)
        ctx.setFillColor(Self.color("#EFE8D6").cgColor)
        ctx.fillPath()
        ctx.addPath(rect)
        ctx.setLineWidth(10)
        ctx.setStrokeColor(Self.color("#3B3F4A").cgColor)
        ctx.strokePath()
        NSGraphicsContext.saveGraphicsState()
        NSGraphicsContext.current = NSGraphicsContext(cgContext: ctx, flipped: true)
        let attrs: [NSAttributedString.Key: Any] = [.font: NSFont.systemFont(ofSize: 104, weight: .bold),
                                                    .foregroundColor: Self.color(colour)]
        let text = NSAttributedString(string: initials, attributes: attrs)
        let size = text.size()
        text.draw(at: CGPoint(x: (CGFloat(w) - size.width) / 2, y: (CGFloat(h) - size.height) / 2 + 4))
        NSGraphicsContext.restoreGraphicsState()
        guard let image = ctx.makeImage() else { return nil }
        let t = try? MTKTextureLoader(device: device).newTexture(cgImage: image, options: [.SRGB: true])
        patches[key] = t
        return t
    }

    private static func color(_ hex: String) -> NSColor {
        let c = RobotColor.srgb(hex)
        return NSColor(srgbRed: CGFloat(c.x), green: CGFloat(c.y), blue: CGFloat(c.z), alpha: 1)
    }
}

/// The camera beeprio's stage sets up: up front on the left and a little above, backed off until
/// the whole head fits either way round.
enum RobotCamera {
    static let direction = simd_normalize(SIMD3<Float>(-3.2, 1.6, 9.2))
    static let fov: Float = 26 * .pi / 180

    static func view(aspect: Float, aim: Float) -> simd_float4x4 {
        let half = max(1.3, 1.45 / aspect) * 1.15
        let target = SIMD3<Float>(0, aim, 0)
        return lookAt(eye: target + direction * (half / tan(fov / 2)), target: target)
    }

    static func projection(aspect: Float) -> simd_float4x4 {
        let ys = 1 / tan(fov / 2), xs = ys / aspect, near: Float = 0.1, far: Float = 100
        let zs = far / (near - far)
        return simd_float4x4(columns: (SIMD4(xs, 0, 0, 0), SIMD4(0, ys, 0, 0), SIMD4(0, 0, zs, -1), SIMD4(0, 0, zs * near, 0)))
    }

    /// The view's rotation alone: the same whatever the aim, so the MatCaps are baked against it once.
    static var viewRotation: simd_float3x3 {
        let m = view(aspect: 1, aim: 0)
        return simd_float3x3(columns: (m.columns.0.xyz, m.columns.1.xyz, m.columns.2.xyz))
    }

    static func lookAt(eye: SIMD3<Float>, target: SIMD3<Float>) -> simd_float4x4 {
        let z = simd_normalize(eye - target)
        let x = simd_normalize(simd_cross(SIMD3(0, 1, 0), z))
        let y = simd_cross(z, x)
        return simd_float4x4(columns: (SIMD4(x.x, y.x, z.x, 0), SIMD4(x.y, y.y, z.y, 0), SIMD4(x.z, y.z, z.z, 0),
                                       SIMD4(-simd_dot(x, eye), -simd_dot(y, eye), -simd_dot(z, eye), 1)))
    }
}

/// The robot's lighting, baked once: beeprio's hemisphere, key and rim lights and its soft room,
/// seen on a ball from the camera. A surface looks its light up by its normal in view space.
struct RobotMatCaps {
    static let size = 128
    var diffuse: [SIMD4<Float>] = [], shell: [SIMD4<Float>] = [], dark: [SIMD4<Float>] = [], glass: [SIMD4<Float>] = []

    init(view: simd_float3x3) {
        let key = view * simd_normalize(SIMD3<Float>(-4, 5, 6))
        let rim = view * simd_normalize(SIMD3<Float>(4, 3, -5))
        let up = view * SIMD3<Float>(0, 1, 0)
        let window = view * simd_normalize(SIMD3<Float>(-0.35, 0.75, 0.55))
        let rimColour = SIMD3<Float>(0.62, 0.85, 1.0)
        let ground = SIMD3<Float>(0.27, 0.31, 0.38)
        let eye = SIMD3<Float>(0, 0, 1)
        func half(_ l: SIMD3<Float>) -> SIMD3<Float> { simd_normalize(l + eye) }
        let hk = half(key), hr = half(rim)
        let n = Self.size
        for y in 0..<n {
            for x in 0..<n {
                let u = (Float(x) + 0.5) / Float(n) * 2 - 1, v = 1 - (Float(y) + 0.5) / Float(n) * 2
                let r2 = u * u + v * v
                let nn = r2 >= 1 ? simd_normalize(SIMD3(u, v, 0)) : SIMD3(u, v, sqrt(1 - r2))
                let sky = 0.5 + 0.5 * simd_dot(nn, up)
                let hemi = ground + (SIMD3<Float>(repeating: 1) - ground) * sky
                let lambert = max(0, simd_dot(nn, key)), rimLambert = max(0, simd_dot(nn, rim))
                let d = hemi * 0.42 + SIMD3(repeating: 0.1) + SIMD3(repeating: 0.58 * lambert) + rimColour * (0.28 * rimLambert)
                diffuse.append(SIMD4(d, 1))

                // The room, reflected: a bright ceiling, a darker floor, and a window up front on the left.
                let refl = 2 * nn.z * nn - eye
                let fresnel = 0.04 + 0.96 * pow(1 - max(0, nn.z), 5)
                let height = simd_dot(refl, up)
                let room = 0.18 + 0.7 * smooth(-0.3, 0.9, height)
                let pane = smooth(0.955, 0.985, simd_dot(refl, window))
                func spot(_ h: SIMD3<Float>, _ power: Float) -> Float { pow(max(0, simd_dot(nn, h)), power) }
                let s = SIMD3<Float>(repeating: fresnel * room * 0.6 + spot(hk, 60) * 0.35 + spot(hk, 400) * 0.6 + pane * 0.25)
                    + rimColour * (spot(hr, 24) * 0.45)
                shell.append(SIMD4(s, 1))
                let k = SIMD3<Float>(repeating: fresnel * room * 0.8 + spot(hk, 160) * 0.5 + spot(hk, 900) * 0.9 + pane * 0.35)
                    + rimColour * (spot(hr, 40) * 0.5)
                dark.append(SIMD4(k, 1))
                let g = SIMD3<Float>(repeating: fresnel * room * 0.5 + spot(hk, 2400) * 3 + pane * 0.75 + 0.02)
                    + rimColour * (spot(hr, 120) * 0.6)
                glass.append(SIMD4(g, 1))
            }
        }
        func smooth(_ a: Float, _ b: Float, _ x: Float) -> Float {
            let t = min(max((x - a) / (b - a), 0), 1)
            return t * t * (3 - 2 * t)
        }
    }
}

/// One robot on one view: its life, what it wears, and how often it draws.
@MainActor
final class RobotRenderer: NSObject, MTKViewDelegate {
    let life = RobotLife()
    var look = RobotLook.standard
    /// The initials on the beanie's patch, and their colour.
    var patchLabel = (initials: "CC", colour: "#C8714F")
    /// Where the pointer is from the bot, about −1.5…1.5 each way, y up; nil when it doesn't follow it.
    var pointer: (@MainActor () -> SIMD2<Float>?)?
    private var last = CACurrentMediaTime()
    private var uniforms = RobotFrameUniforms()

    private let gpu: RobotGPU

    init(gpu: RobotGPU) {
        self.gpu = gpu
    }

    /// Steps the life by the time since the last frame, in steps of at most 50 ms so a slow frame
    /// rate doesn't slow the robot down.
    private func advance() {
        let now = CACurrentMediaTime()
        var left = min(now - last, 0.25)
        last = now
        while left > 0 {
            let dt = min(left, 0.05)
            life.step(dt)
            left -= dt
        }
    }

    /// Call when it starts drawing again, so there is no jump for the time it was paused.
    func resume() { last = CACurrentMediaTime() }

    /// Frames a second for what it is doing: every frame while it moves fast, fewer at rest.
    var framesPerSecond: Int {
        if life.lively { return 60 }
        if life.dozing { return 12 }
        return life.mood == .idle ? 24 : 30
    }

    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {}

    func draw(in view: MTKView) {
        if let p = pointer?() { life.point(p) }
        advance()
        let fps = framesPerSecond
        if view.preferredFramesPerSecond != fps { view.preferredFramesPerSecond = fps }

        guard let pass = view.currentRenderPassDescriptor, let drawable = view.currentDrawable,
              let buffer = gpu.queue.makeCommandBuffer(),
              let enc = buffer.makeRenderCommandEncoder(descriptor: pass) else { return }
        let size = view.drawableSize
        encode(enc, aspect: Float(max(size.width, 1) / max(size.height, 1)))
        enc.endEncoding()
        buffer.present(drawable)
        buffer.commit()
    }

    /// Draws this frame of the robot with `enc`, for a target `aspect` wide for its height.
    func encode(_ enc: MTLRenderCommandEncoder, aspect: Float) {
        let wearing = look.accessory == .beanie
        let viewM = RobotCamera.view(aspect: aspect, aim: wearing ? 0.25 : 0)
        fillUniforms(viewProj: RobotCamera.projection(aspect: aspect) * viewM, view: viewM)

        enc.setRenderPipelineState(gpu.pipeline)
        enc.setDepthStencilState(gpu.depth)
        enc.setCullMode(.none)
        enc.setVertexBuffer(gpu.vertices, offset: 0, index: 0)
        withUnsafeBytes(of: &uniforms) { raw in
            enc.setVertexBytes(raw.baseAddress!, length: raw.count, index: 1)
            enc.setFragmentBytes(raw.baseAddress!, length: raw.count, index: 1)
        }
        enc.setFragmentTexture(gpu.diffuseCap, index: 0)
        enc.setFragmentTexture(gpu.shellCap, index: 1)
        enc.setFragmentTexture(gpu.darkCap, index: 2)
        enc.setFragmentTexture(gpu.glassCap, index: 3)
        if wearing { enc.setFragmentTexture(gpu.patch(initials: patchLabel.initials, colour: patchLabel.colour), index: 4) }

        let m = gpu.mesh
        let head = headMatrix()
        func draw(_ r: RobotRange, _ material: RobotMaterial, _ model: simd_float4x4) {
            guard r.count > 0 else { return }
            var u = RobotDrawUniforms(model: model, material: material.rawValue)
            enc.setVertexBytes(&u, length: MemoryLayout<RobotDrawUniforms>.stride, index: 2)
            enc.setFragmentBytes(&u, length: MemoryLayout<RobotDrawUniforms>.stride, index: 2)
            enc.drawIndexedPrimitives(type: .triangle, indexCount: r.count, indexType: .uint32,
                                      indexBuffer: gpu.indices, indexBufferOffset: r.start * MemoryLayout<UInt32>.stride)
        }

        draw(m.head, .head, head)
        draw(m.lip, .lip, head)
        draw(m.gasket, .dark, head)
        draw(m.visor, .glass, head)
        for side: Float in [1, -1] {
            switch look.ears {
            case .hatch:
                let seat = head * seatMatrix(side, push: life.hatchOut)
                draw(m.hatchBase, .dark, seat)
                draw(m.hatchGlow, .glow, seat)
                draw(m.hatchSpark, .spark, seat * rotationZ(life.hatchSpin * side))
            case .grille:
                let seat = head * seatMatrix(side, push: life.grilleOut)
                draw(m.grilleBase, .dark, seat)
                draw(m.grilleFace, .grille, seat)
            case .dial:
                let seat = head * seatMatrix(side, push: 0)
                let turn = seat * rotationZ(life.dialPoint * side)
                draw(m.dialPlate, .dark, seat)
                draw(m.dialTicks, .glow, seat)
                draw(m.dialKnob, .knob, turn)
                draw(m.dialDark, .dark, turn)
                draw(m.dialPointer, .spark, turn)
            }
        }
        if wearing {
            draw(m.crown, .crown, head)
            if let cuff = m.cuff[look.ears] { draw(cuff, .cuff, head) }
            if let patch = m.patch[look.ears] { draw(patch, .patch, head) }
            draw(m.nub, .wool, head)
        }
    }

    private func fillUniforms(viewProj: simd_float4x4, view: simd_float4x4) {
        let l = life
        let skin: Float = [RobotSkin.plain: 0, .stripes: 1, .dots: 2, .checks: 3][look.skin] ?? 0
        let lin = { (s: SIMD3<Float>) in s.map { $0 <= 0.04045 ? $0 / 12.92 : pow(($0 + 0.055) / 1.055, 2.4) } }
        let hue = RobotColor.hue(l.glow)
        uniforms.viewProj = viewProj
        uniforms.view = view
        uniforms.glow = SIMD4(lin(l.glow), 4 * (1 - 0.65 * l.doze))
        uniforms.earGlow = SIMD4(RobotColor.hsl(hue, 1, 0.5), l.earLight)
        uniforms.grilleGlow = SIMD4(RobotColor.hsl(hue, 1, 0.55), 0)
        uniforms.face = SIMD4(Float(l.t), l.emoteAlpha, Float(l.emote.rawValue), l.lid)
        uniforms.eye0 = SIMD4(l.eyes[0].len, l.eyes[0].width, l.eyes[0].angle, l.eyes[0].bend)
        uniforms.eye1 = SIMD4(l.eyes[1].len, l.eyes[1].width, l.eyes[1].angle, l.eyes[1].bend)
        uniforms.mouth = SIMD4(l.mouth.len, l.mouth.width, l.mouth.wave, 0)
        uniforms.gaze = SIMD4(l.gaze.x, l.gaze.y, 0, 0)
        uniforms.body = SIMD4(RobotColor.linear(look.body), skin)
        uniforms.ink = SIMD4(RobotColor.linear(look.ink), 0)
        uniforms.hat = SIMD4(RobotColor.linear(look.hat), 0)
        let v = l.grilleLevels
        uniforms.levels0 = SIMD4(v[0], v[1], v[2], v[3])
        uniforms.levels1 = SIMD4(v[4], v[5], v[6], v[7])
        uniforms.levels2 = SIMD4(v[8], 0, 0, 0)
    }

    /// The head, where the hover, the mood and the gaze put it.
    private func headMatrix() -> simd_float4x4 {
        let l = life
        let bot = simd_float4x4(translation: SIMD3(l.shake, l.hoverY, 0)) * rotationZ(l.roll)
        let turn = simd_float4x4(simd_quatf(angle: l.lean + l.nod + l.pitch + l.doze * 0.12, axis: SIMD3(1, 0, 0)))
            * simd_float4x4(simd_quatf(angle: l.yaw, axis: SIMD3(0, 1, 0)))
            * rotationZ(l.tilt)
        return bot * turn
    }

    /// An ear's own frame on `side`, pushed `push` out of the head.
    private func seatMatrix(_ side: Float, push: Float) -> simd_float4x4 {
        let (at, out) = RobotShape.podSeat(side)
        return simd_float4x4(translation: at + out * push) * simd_float4x4(simd_quatf(from: SIMD3(0, 0, 1), to: out))
    }

    private func rotationZ(_ a: Float) -> simd_float4x4 { simd_float4x4(simd_quatf(angle: a, axis: SIMD3(0, 0, 1))) }
}

private extension SIMD4 where Scalar == Float {
    var xyz: SIMD3<Float> { SIMD3(x, y, z) }
}

private extension SIMD3 where Scalar == Float {
    func map(_ f: (Float) -> Float) -> SIMD3<Float> { SIMD3(f(x), f(y), f(z)) }
}
