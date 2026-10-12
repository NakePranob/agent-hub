import simd

// The robot's Metal shaders, compiled at launch from source (MTLDevice.makeLibrary(source:)).
// ponytail: source in a string rather than a .metal file: Xcode 26+ ships the Metal toolchain as a
// separate download, and a .metal file would fail the build wherever it isn't installed.
//
// Everything is lit from MatCaps baked once at launch (the lights and the camera never move
// relative to each other), the face is drawn in the glass's shader as distance fields, and the
// skin, the speaker grilles and the knit are worked out per pixel: no texture changes per frame.

/// Per frame. Mirrors `Frame` in the shader: keep the two in step.
struct RobotFrameUniforms {
    var viewProj = matrix_identity_float4x4
    var view = matrix_identity_float4x4
    var glow = SIMD4<Float>.zero       // the screen's light, linear; w its strength
    var earGlow = SIMD4<Float>.zero    // the ears' hue at full strength, linear; w how bright
    var grilleGlow = SIMD4<Float>.zero // the grille's lit holes, linear
    var face = SIMD4<Float>.zero       // x time, y emote alpha, z emote, w lid
    var eye0 = SIMD4<Float>.zero       // len, width, angle, bend
    var eye1 = SIMD4<Float>.zero
    var mouth = SIMD4<Float>.zero      // len, width, wave
    var gaze = SIMD4<Float>.zero
    var body = SIMD4<Float>.zero       // linear; w the skin
    var ink = SIMD4<Float>.zero
    var hat = SIMD4<Float>.zero
    var levels0 = SIMD4<Float>.zero    // the grille's nine columns
    var levels1 = SIMD4<Float>.zero
    var levels2 = SIMD4<Float>.zero
}

/// Per draw. Mirrors `Draw` in the shader.
struct RobotDrawUniforms {
    var model = matrix_identity_float4x4
    var material: Int32 = 0
    var pad0: Int32 = 0, pad1: Int32 = 0, pad2: Int32 = 0
}

enum RobotShaders {
    static let source = """
    #include <metal_stdlib>
    using namespace metal;

    struct Vertex { float4 position; float4 normal; float4 uv; };

    struct Frame {
        float4x4 viewProj;
        float4x4 view;
        float4 glow, earGlow, grilleGlow, face, eye0, eye1, mouth, gaze, body, ink, hat;
        float4 levels0, levels1, levels2;
    };

    struct Draw { float4x4 model; int material; int pad0, pad1, pad2; };

    struct VOut {
        float4 position [[position]];
        float3 local;
        float3 viewNormal;
        float3 viewPos;
        float2 uv;
    };

    vertex VOut robot_vertex(uint vid [[vertex_id]],
                             const device Vertex* vertices [[buffer(0)]],
                             constant Frame& f [[buffer(1)]],
                             constant Draw& d [[buffer(2)]]) {
        Vertex v = vertices[vid];
        float4 world = d.model * float4(v.position.xyz, 1);
        VOut o;
        o.position = f.viewProj * world;
        o.local = v.position.xyz;
        o.viewNormal = (f.view * float4((d.model * float4(v.normal.xyz, 0)).xyz, 0)).xyz;
        o.viewPos = (f.view * world).xyz;
        o.uv = v.uv.xy;
        return o;
    }

    // ---- the face, in face-canvas pixels (1024 wide, y down), as beeprio's canvas draws it ----

    constant float FACE_H = \(RobotShape.faceHeight);
    constant float VISOR_PITCH = \(RobotShape.visor.pitch);

    float sdSegment(float2 p, float2 a, float2 b) {
        float2 pa = p - a, ba = b - a;
        float h = clamp(dot(pa, ba) / max(dot(ba, ba), 1e-6), 0.0, 1.0);
        return length(pa - ba * h);
    }

    // A stroke: `s` = len, width, angle, bend; a line bowed by bend and rippled by wave.
    float sdStroke(float2 p, float4 s, float wave) {
        float c = cos(s.z), sn = sin(s.z);
        float2 q = float2(c * p.x + sn * p.y, -sn * p.x + c * p.y);
        float d = 1e9;
        float2 prev = float2(0);
        for (int i = 0; i <= 12; i++) {
            float u = float(i) / 12.0 - 0.5;
            float2 pt = float2(u * s.x, s.w * (1.0 - 4.0 * u * u) + wave * sin(u * M_PI_F * 4.0));
            if (i > 0) d = min(d, sdSegment(q, prev, pt));
            prev = pt;
        }
        return d - s.y * 0.5;
    }

    float sdUnevenCapsule(float2 p, float r1, float r2, float h) {
        p.x = abs(p.x);
        float b = (r1 - r2) / h, a = sqrt(1.0 - b * b);
        float k = dot(p, float2(-b, a));
        if (k < 0.0) return length(p) - r1;
        if (k > a * h) return length(p - float2(0.0, h)) - r2;
        return dot(p, float2(a, b)) - r1;
    }

    // How lit a shape is at distance d (canvas px): its fill, or the soft shadow it glows with.
    float lit(float d, float aa, float blur) {
        float fill = 1.0 - smoothstep(-aa, aa, d);
        float halo = 0.5 * exp(-max(d, 0.0) / max(blur * 0.5, 0.01));
        return max(fill, halo);
    }

    float rowAt(float pitch) { return FACE_H * (VISOR_PITCH - pitch) / (2.0 * VISOR_PITCH); }

    float emoteValue(float2 q, float kind, float t, float aa) {
        float v = 0.0;
        if (kind == 1.0) {          // three dots taking turns: working
            for (int i = 0; i < 3; i++) {
                float a = 0.3 + 0.7 * max(0.0, sin(t * 6.0 - float(i) * 0.9));
                v = max(v, a * lit(length(q - float2(float(i - 1) * 34.0, 0.0)) - 11.0, aa, 6.0));
            }
        } else if (kind == 2.0) {   // an exclamation mark: it needs you
            float a = 0.75 + 0.25 * sin(t * 8.0);
            float d = min(sdSegment(q, float2(0, -32), float2(0, 8)) - 10.0, length(q - float2(0, 28)) - 11.0);
            v = a * lit(d, aa, 6.0);
        } else if (kind == 3.0) {   // a drop of sweat sliding down: an error
            float y = fmod(t * 30.0, 50.0) - 25.0;
            float2 p = float2(q.x, (y + 6.0) - q.y);
            v = lit(sdUnevenCapsule(p, 13.0, 1.5, 28.0), aa, 6.0);
        } else if (kind == 4.0) {   // a tick: done
            float d = min(sdSegment(q, float2(-28, 0), float2(-8, 22)), sdSegment(q, float2(-8, 22), float2(30, -24))) - 8.0;
            v = lit(d, aa, 6.0);
        } else if (kind == 5.0) {   // Zs drifting up: asleep
            for (int i = 0; i < 2; i++) {
                float k = fract(t * 0.5 + float(i) * 0.5), s = 10.0 + 8.0 * float(i);
                float2 z = q - float2(float(i) * 34.0 - 10.0, 20.0 - k * 60.0);
                float d = min(min(sdSegment(z, float2(-s, -s), float2(s, -s)), sdSegment(z, float2(s, -s), float2(-s, s))),
                              sdSegment(z, float2(-s, s), float2(s, s))) - 4.0;
                v = max(v, sin(k * M_PI_F) * lit(d, aa, 6.0));
            }
        }
        return v;
    }

    float faceValue(float2 uv, constant Frame& f) {
        float2 p = float2(uv.x * 1024.0, (1.0 - uv.y) * FACE_H);
        float aa = max(fwidth(p.x), fwidth(p.y)) * 0.75 + 0.35;
        float v = 0.0;
        // The eyes, a size up and squeezed by the lid.
        float2 scale = float2(1.2, 1.2 * max(f.face.w, 0.08));
        for (int side = -1; side <= 1; side += 2) {
            float2 c = float2(512.0 + float(side) * 230.0 + f.gaze.x, rowAt(0.035) + f.gaze.y);
            float2 q = (p - c) / scale;
            float d = min(sdStroke(q, f.eye0, 0.0), sdStroke(q, f.eye1, 0.0)) * min(scale.x, scale.y);
            v = max(v, lit(d, aa, 14.0));
        }
        if (f.mouth.y > 0.5) {
            float2 c = float2(512.0 + f.gaze.x * 0.5, rowAt(-0.227) + f.gaze.y * 0.5);
            v = max(v, lit(sdStroke(p - c, float4(f.mouth.x, f.mouth.y, 0, 0), f.mouth.z), aa, 6.0));
        }
        if (f.face.z > 0.0 && f.face.y > 0.01) {
            v = max(v, f.face.y * emoteValue(p - float2(812.0, rowAt(0.36)), f.face.z, f.face.x, aa));
        }
        return pow(v, 2.2);   // the face canvas is sRGB, the light is linear
    }

    // ---- skins, worked out from the head's 1024×512 wrap like beeprio's skin canvas ----

    float skinInk(float2 uv, float skin) {
        float2 P = float2(uv.x * 1024.0, uv.y * 512.0);
        float2 w = max(fwidth(P), float2(1e-3));
        float row = 512.0 / 9.0;
        if (skin == 1.0) {          // stripes: every other row
            float i = floor(P.y / row), f = fract(P.y / row), aa = w.y / row;
            if (fmod(i, 2.0) != 1.0) return 0.0;
            return smoothstep(0.15 - aa, 0.15 + aa, f) * (1.0 - smoothstep(0.85 - aa, 0.85 + aa, f));
        }
        if (skin == 3.0) {          // checks: 16 round, 9 down
            float sx = clamp(sin(M_PI_F * P.x / 64.0) / (M_PI_F * w.x / 64.0), -1.0, 1.0);
            float sy = clamp(sin(M_PI_F * P.y / row) / (M_PI_F * w.y / row), -1.0, 1.0);
            return 0.5 + 0.5 * sx * sy;
        }
        if (skin == 2.0) {          // dots, spread and widened by latitude to stay round
            float i = floor(P.y / row), yc = (i + 0.5) * row;
            float across = max(cos((yc / 512.0 - 0.5) * M_PI_F), 0.05);
            float count = max(1.0, round(1024.0 / row * across));
            float step = 1024.0 / count, off = fmod(i, 2.0) * 0.5;
            float dx = P.x - (round(P.x / step - off) + off) * step;
            dx -= 1024.0 * round(dx / 1024.0);
            float d = length(float2(dx * across, P.y - yc)) - row * 0.28;
            float aa = length(w);
            return 1.0 - smoothstep(-aa, aa, d);
        }
        return 0.0;
    }

    // ---- knit, as a height for bump mapping: stockinette on the crown, rib on the cuff ----

    float knitHeight(float2 P, bool rib) {
        if (rib) return 0.4 + 0.6 * sin(M_PI_F * fract(P.x));
        float2 c = fract(P);
        float h = 0.0;
        for (int side = -1; side <= 1; side += 2) {
            float2 q = c - float2(0.5 + float(side) * 7.0 / 32.0, 0.5);
            float r = float(side) * -0.45, cs = cos(r), sn = sin(r);
            float2 e = float2(cs * q.x + sn * q.y, -sn * q.x + cs * q.y) / float2(6.5 / 32.0, 15.0 / 32.0);
            h = max(h, smoothstep(0.0, 0.7, 1.0 - length(e)));
        }
        return mix(0.70, 1.0, h);
    }

    float3 perturb(float3 pos, float3 n, float h, float amount, bool front) {
        float3 sx = dfdx(pos), sy = dfdy(pos);
        float3 r1 = cross(sy, n), r2 = cross(n, sx);
        float det = dot(sx, r1) * (front ? 1.0 : -1.0);
        float3 grad = sign(det) * (dfdx(h) * amount * r1 + dfdy(h) * amount * r2);
        return normalize(abs(det) * n - grad);
    }

    // three.js's NeutralToneMapping (Khronos PBR Neutral), as beeprio renders with.
    float3 neutral(float3 color) {
        const float start = 0.76, desat = 0.15;
        float x = min(color.r, min(color.g, color.b));
        float off = x < 0.08 ? x - 6.25 * x * x : 0.04;
        color -= off;
        float peak = max(color.r, max(color.g, color.b));
        if (peak < start) return color;
        const float d = 1.0 - start;
        float newPeak = 1.0 - d * d / (peak + d - start);
        color *= newPeak / peak;
        float g = 1.0 - 1.0 / (desat * (peak - newPeak) + 1.0);
        return mix(color, float3(newPeak), g);
    }

    fragment float4 robot_fragment(VOut in [[stage_in]],
                                   bool front [[front_facing]],
                                   constant Frame& f [[buffer(1)]],
                                   constant Draw& d [[buffer(2)]],
                                   texture2d<float> diffuseCap [[texture(0)]],
                                   texture2d<float> shellCap [[texture(1)]],
                                   texture2d<float> darkCap [[texture(2)]],
                                   texture2d<float> glassCap [[texture(3)]],
                                   texture2d<float> patchTex [[texture(4)]]) {
        constexpr sampler s(filter::linear, address::clamp_to_edge);
        // Every part is drawn from both sides: the side we see faces us, whichever way its triangles wind.
        float3 n = normalize(in.viewNormal);
        bool facing = dot(n, -in.viewPos) >= 0.0;
        if (!facing) n = -n;
        const float3 DARK = float3(0.0144, 0.0176, 0.0242);
        float3 albedo = float3(0.0), emit = float3(0.0), specular = float3(0.0);
        int cap = 3;   // 0 shell, 1 dark, 2 glass, 3 none
        float specScale = 1.0;

        switch (d.material) {
        case 0: {   // the head: the skin, with the screen's hole cut so its edge stays crisp
            float3 dir = normalize(in.local);
            float2 v = abs(float2(atan2(dir.x, dir.z), asin(dir.y))) / float2(\(RobotShape.visor.yaw), VISOR_PITCH);
            float e = asin(dir.y) >= 0.0 ? \(RobotShape.visor.top) : \(RobotShape.visor.bottom);
            if (pow(v.x, e) + pow(v.y, e) < 1.0) discard_fragment();
            albedo = mix(f.body.rgb, f.ink.rgb, skinInk(in.uv, f.body.w));
            cap = 0;
            break;
        }
        case 1: case 7: albedo = f.body.rgb; cap = 0; break;              // the lip, a dial's knob
        case 2: emit = f.glow.rgb * f.glow.w * faceValue(in.uv, f); cap = 2; break;   // the glass
        case 3: albedo = DARK; cap = 1; break;
        case 4: emit = f.earGlow.rgb * 1.4 * f.earGlow.w; cap = 1; break;  // an ear's light
        case 5: emit = f.earGlow.rgb * 3.5 * max(f.earGlow.w, 0.5); cap = 1; break;   // the bright notch
        case 6: {   // a speaker grille: holes punched in a plate, lit as an equaliser
            float2 g = float2(in.uv.x, 1.0 - in.uv.y) * 9.0;
            float2 cell = floor(g);
            bool inside = length(cell - 4.0) <= 4.2;
            float hole = inside ? 1.0 - smoothstep(0.30, 0.34, length(fract(g) - 0.5)) : 0.0;
            int c = int(clamp(cell.x, 0.0, 8.0));
            float level = c < 4 ? f.levels0[c] : c < 8 ? f.levels1[c - 4] : f.levels2[0];
            float on = (9.0 - cell.y <= level + 0.5) ? hole : 0.0;
            albedo = mix(float3(0.0423, 0.0497, 0.0648), float3(0.0033, 0.0040, 0.0052), hole);
            emit = f.grilleGlow.rgb * 1.6 * f.earGlow.w * on;
            cap = 1; specScale = 0.3;
            break;
        }
        case 8: case 9: {   // the beanie's crown and cuff: knit, fading out where it gets finer than a pixel
            bool rib = d.material == 9;
            float2 P = in.uv * (rib ? float2(80.0, 1.0) : float2(150.0, 28.0));
            float w = max(fwidth(P.x), rib ? 0.0 : fwidth(P.y));
            float fade = saturate((0.75 - w) / 0.5);
            float h = knitHeight(P, rib);
            n = perturb(in.viewPos, n, h, fade, facing == front);
            albedo = f.hat.rgb * mix(0.85, h, fade);
            break;
        }
        case 10: {  // the patch with the initials
            float4 c = patchTex.sample(s, in.uv);
            if (c.a < 0.5) discard_fragment();
            albedo = c.rgb;
            break;
        }
        case 11: albedo = f.hat.rgb; break;    // the knot
        }

        float2 cuv = float2(n.x * 0.49 + 0.5, 0.5 - n.y * 0.49);
        float3 light = diffuseCap.sample(s, cuv).rgb;
        if (cap == 0) specular = shellCap.sample(s, cuv).rgb;
        else if (cap == 1) specular = darkCap.sample(s, cuv).rgb;
        else if (cap == 2) specular = glassCap.sample(s, cuv).rgb;
        float3 color = albedo * light + specular * specScale + emit;
        return float4(neutral(color), 1.0);
    }
    """
}
