import SwiftUI

// MARK: - Wardrobe

struct WardrobeView: View {
    @ObservedObject var state: AppState
    @State private var hoveredOutfit: Outfit? = nil

    private let columns = Array(repeating: GridItem(.fixed(30), spacing: 5), count: 14)

    private var headerRight: String {
        // Hover takes priority: show hovered outfit name
        if let h = hoveredOutfit {
            if h == .auto {
                let seasonal = Outfit.seasonal(for: Date(), calendar: .current)
                let name = seasonal == .none ? "None" : seasonal.displayName
                return "Auto · follows the seasons (now: \(name))"
            }
            return h.displayName
        }
        // Fall back to current selection
        let sel = state.mochiOutfitSelection
        if sel == .auto {
            let seasonal = Outfit.seasonal(for: Date(), calendar: .current)
            let name = seasonal == .none ? "None" : seasonal.displayName
            return "Auto · \(name)"
        }
        return sel.displayName
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Header
            HStack(spacing: 6) {
                Text("Wardrobe")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Color(hex: "#F5F6F8"))
                Spacer(minLength: 4)
                Text(headerRight)
                    .font(.system(size: 11))
                    .foregroundColor(Color(hex: "#8E939C"))
                    .lineLimit(1)
            }
            .padding(.top, 6)
            .padding(.horizontal, 10)

            // Grid
            let allOutfits = Outfit.allCases.filter { $0 != .auto }
            let withAuto = [Outfit.auto] + allOutfits
            ScrollView(.vertical, showsIndicators: false) {
                LazyVGrid(columns: columns, spacing: 5) {
                    ForEach(withAuto, id: \.rawValue) { outfit in
                        OutfitPillView(
                            outfit: outfit,
                            isSelected: state.mochiOutfitSelection == outfit,
                            isHovered: hoveredOutfit == outfit,
                            onHover: { h in
                                hoveredOutfit = h ? outfit : nil
                                if h {
                                    // Preview on main Mochi
                                    let preview: Outfit = outfit == .auto
                                        ? Outfit.seasonal(for: Date(), calendar: .current)
                                        : outfit
                                    state.wardrobePreviewOutfit = preview
                                } else if hoveredOutfit == nil {
                                    state.wardrobePreviewOutfit = nil
                                }
                            },
                            onTap: {
                                guard state.mochiOutfitSelection != outfit else { return }
                                state.mochiOutfitSelection = outfit
                                SoundEngine.shared.play("pop")
                                NotificationCenter.default.post(name: .triggerEmote, object: BotEmote.proud)
                            },
                            seasonalOutfit: outfit == .auto ? state.resolvedOutfit : .none
                        )
                    }
                }
                .padding(.vertical, 6)
                .padding(.horizontal, 8)
            }
            .frame(maxHeight: .infinity)
            .mask(
                LinearGradient(
                    stops: [
                        .init(color: .white, location: 0),
                        .init(color: .white, location: 0.85),
                        .init(color: .clear, location: 1)
                    ],
                    startPoint: .top, endPoint: .bottom
                )
            )
        }
        .padding(.leading, 108)
        .padding(.trailing, 12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .onDisappear {
            state.wardrobePreviewOutfit = nil
            hoveredOutfit = nil
        }
        .onExitCommand {
            withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                state.view = .overview
            }
        }
    }
}

struct OutfitPillView: View {
    let outfit: Outfit
    let isSelected: Bool
    let isHovered: Bool
    let onHover: (Bool) -> Void
    let onTap: () -> Void
    var seasonalOutfit: Outfit = .none

    var body: some View {
        Canvas { context, size in
            drawOutfitIcon(context: context, size: size, outfit: outfit, seasonal: seasonalOutfit)
        }
        .frame(width: 30, height: 30)
        .background(
            RoundedRectangle(cornerRadius: 7)
                .fill(isHovered ? Color.white.opacity(0.10) : Color.white.opacity(0.06))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 7)
                .stroke(isSelected ? Color.white.opacity(0.40) : Color.white.opacity(0.08), lineWidth: 1)
        )
        .onHover { onHover($0) }
        .onTapGesture { onTap() }
    }
}

private func drawOutfitIcon(context: GraphicsContext, size: CGSize, outfit: Outfit, seasonal: Outfit = .none) {
    let W = size.width, H = size.height
    let cx = W / 2, cy = H / 2
    let R: CGFloat = 6.5   // small scale for icon

    switch outfit {
    case .auto:
        let iconR: CGFloat = 10.0
        let rx = iconR * 1.14, ry = iconR * 0.88
        let mH = MochiH(R: iconR, yaw: 0, pitch: 0)
        let bodyPath = mochiOutfitPath(rx, ry)
        let iconCY = cy + iconR * 0.62

        // Draw the seasonal outfit behind body
        if seasonal != .none && seasonal != .auto {
            drawOutfitBehindStatic(context: context, outfit: seasonal, H: mH,
                                   cx: cx, cy: iconCY, tilt: 0, sx: 1, sy: 1,
                                   roll: 0, morph: 0, isMini: false)
        }
        // Body
        var ctx = context
        ctx.translateBy(x: cx, y: iconCY)
        ctx.fill(bodyPath, with: .linearGradient(
            Gradient(colors: [Color(red: 0.929, green: 0.929, blue: 0.937),
                              Color(red: 0.769, green: 0.773, blue: 0.792)]),
            startPoint: CGPoint(x: rx*0.7, y: -ry*0.85),
            endPoint:   CGPoint(x: -rx*0.8, y: ry*0.9)
        ))
        ctx.fill(bodyPath, with: .radialGradient(
            Gradient(stops: [.init(color: .clear, location: 0.6),
                             .init(color: Color.black.opacity(0.2), location: 1)]),
            center: .zero, startRadius: iconR*0.15, endRadius: iconR*1.25
        ))
        // Eyes
        var eyeCtx = ctx; eyeCtx.clip(to: bodyPath)
        let ink = Color(red: 0.102, green: 0.082, blue: 0.071)
        for f in mEyeFrames(mH) {
            guard f.visible else { continue }
            var ec = eyeCtx; ec.translateBy(x: f.x, y: f.y); ec.scaleBy(x: f.fx, y: f.fy)
            let hh = max(f.h, f.w*0.3)
            var pill = Path()
            pill.addRoundedRect(in: CGRect(x: -f.w/2, y: -hh/2, width: f.w, height: hh),
                                cornerSize: CGSize(width: min(f.w/2,hh/2), height: min(f.w/2,hh/2)))
            ec.fill(pill, with: .color(ink))
        }
        // Front outfit
        if seasonal != .none && seasonal != .auto {
            drawOutfitFrontStatic(context: context, outfit: seasonal, H: mH,
                                  cx: cx, cy: iconCY, tilt: 0, sx: 1, sy: 1,
                                  roll: 0, morph: 0, isMini: false)
        }
        // AUTO badge at bottom
        var badgeCtx = context
        let badgeCY = iconCY + ry * 0.72
        badgeCtx.translateBy(x: cx, y: badgeCY)
        let bw: CGFloat = 14, bh: CGFloat = 6.5
        var badge = Path()
        badge.addRoundedRect(in: CGRect(x: -bw/2, y: -bh/2, width: bw, height: bh),
                             cornerSize: CGSize(width: bh/2, height: bh/2))
        badgeCtx.fill(badge, with: .color(Color.black.opacity(0.60)))
        badgeCtx.draw(Text("AUTO").font(.system(size: 4.2, weight: .semibold)).foregroundColor(.white),
                      at: .zero)

    case .none:
        var ctx = context
        ctx.translateBy(x: cx, y: cy)
        // Circle with diagonal slash (⊘)
        var circle = Path()
        circle.addEllipse(in: CGRect(x: -R * 0.82, y: -R * 0.82, width: R * 1.64, height: R * 1.64))
        ctx.stroke(circle, with: .color(Color(hex: "#454850")), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))
        var slash = Path()
        slash.move(to:    CGPoint(x: -R * 0.56, y:  R * 0.56))
        slash.addLine(to: CGPoint(x:  R * 0.56, y: -R * 0.56))
        ctx.stroke(slash, with: .color(Color(hex: "#454850")), style: StrokeStyle(lineWidth: 1.4, lineCap: .round))

    default:
        // Small Mochi wearing the outfit
        let iconR: CGFloat = 10.0
        let rx = iconR * 1.14, ry = iconR * 0.88
        let mH = MochiH(R: iconR, yaw: 0, pitch: 0)
        let bodyPath = mochiOutfitPath(rx, ry)
        let iconCY = cy + iconR * 0.62

        // Draw outfit behind
        drawOutfitBehindStatic(context: context, outfit: outfit, H: mH,
                               cx: cx, cy: iconCY, tilt: 0, sx: 1, sy: 1,
                               roll: 0, morph: 0, isMini: false)

        // Draw body
        var ctx = context
        ctx.translateBy(x: cx, y: iconCY)
        let pumpkin = outfit == .pumpkin
        let top = pumpkin ? Color(hex: "#FFA94D") : Color(red: 0.929, green: 0.929, blue: 0.937)
        let bot = pumpkin ? Color(hex: "#E8590C") : Color(red: 0.769, green: 0.773, blue: 0.792)
        ctx.fill(bodyPath, with: .linearGradient(
            Gradient(colors: [top, bot]),
            startPoint: CGPoint(x: rx * 0.7, y: -ry * 0.85),
            endPoint:   CGPoint(x: -rx * 0.8, y: ry * 0.9)
        ))
        ctx.fill(bodyPath, with: .radialGradient(
            Gradient(stops: [
                .init(color: .clear, location: 0),
                .init(color: .clear, location: 0.6),
                .init(color: Color.black.opacity(0.2), location: 1)
            ]),
            center: .zero, startRadius: iconR * 0.15, endRadius: iconR * 1.25
        ))
        ctx.fill(bodyPath, with: .radialGradient(
            Gradient(stops: [
                .init(color: Color.white.opacity(0.55), location: 0),
                .init(color: .clear, location: 1)
            ]),
            center: CGPoint(x: rx * 0.34, y: -ry * 0.46),
            startRadius: 0, endRadius: iconR * 0.42
        ))

        // Draw eyes
        var eyeCtx = ctx
        eyeCtx.clip(to: bodyPath)
        let ink = Color(red: 0.102, green: 0.082, blue: 0.071)
        for f in mEyeFrames(mH) {
            guard f.visible else { continue }
            var ec = eyeCtx
            ec.translateBy(x: f.x, y: f.y)
            ec.scaleBy(x: f.fx, y: f.fy)
            let hh = max(f.h, f.w * 0.3)
            var pill = Path()
            pill.addRoundedRect(
                in: CGRect(x: -f.w / 2, y: -hh / 2, width: f.w, height: hh),
                cornerSize: CGSize(width: min(f.w / 2, hh / 2), height: min(f.w / 2, hh / 2))
            )
            ec.fill(pill, with: .color(ink))
        }

        // Draw outfit front
        drawOutfitFrontStatic(context: context, outfit: outfit, H: mH,
                              cx: cx, cy: iconCY, tilt: 0, sx: 1, sy: 1,
                              roll: 0, morph: 0, isMini: false)
    }
}
