import SwiftUI

struct RobotView: View {
    @ObservedObject var model: PetModel
    var frozenTime: Double?
    var showsPadding = true
    var palette: Palette = .chrome

    /// The canvas is deliberately larger than the robot so stretch, raised
    /// arms and thruster flames never clip at the window edge.
    static let designSize = CGSize(width: 176, height: 270)
    /// Where the robot's own 160 x 200 box sits inside that canvas.
    static let contentOffset = CGSize(width: 8, height: 44)
    static let padding = NSEdgeInsets(top: 44, left: 8, bottom: 36, right: 8)

    private enum L {
        static let antenna = CGPoint(x: 80, y: 16)
        static let headRect = CGRect(x: 42, y: 32, width: 76, height: 62)
        static let visorRect = CGRect(x: 52, y: 45, width: 56, height: 37)
        static let eyeY = 60.5
        static let mouthY = 74.0
        static let torsoRect = CGRect(x: 46, y: 94, width: 68, height: 62)
        static let core = CGPoint(x: 80, y: 125)
        static let shoulderY = 108.0
        static let shoulderX = 37.0
        static let legTop = 152.0
        static let legBottom = 176.0
        static let feetY = 186.0
        static let groundY = 190.0
    }

    var body: some View {
        if let frozenTime {
            canvas(at: frozenTime)
        } else {
            // Full rate only while something lively is happening; a gentle
            // breathing idle reads fine at 20fps and costs a third as much.
            let lively = model.phase != nil || model.held || model.beckoning
                || model.excitement > 0.01 || model.waving > 0.01
                || model.badgeLife > 0 || !model.pulses.isEmpty
                || model.pressed || model.anticipating
                || model.presenting || model.eating > 0
            let interval = lively ? 1.0 / 60.0 : 1.0 / (Debug.idleFPS ?? 15)
            TimelineView(.animation(minimumInterval: interval, paused: model.paused)) { timeline in
                canvas(at: timeline.date.timeIntervalSinceReferenceDate)
            }
        }
    }

    private func canvas(at time: Double) -> some View {
        let pose = Pose.make(time: time, model.snapshot)
        let look = model.look
        let badge = model.badge
        let badgeLife = model.badgeLife
        let pulses = model.pulses
        let eating = model.eating
        let eatSide = model.eatSide
        let canvasSize = showsPadding ? Self.designSize : CGSize(width: 160, height: 200)
        let offset = showsPadding ? Self.contentOffset : .zero
        return Canvas(rendersAsynchronously: false) { ctx, size in
            let s = min(size.width / canvasSize.width, size.height / canvasSize.height)
            ctx.scaleBy(x: s, y: s)
            ctx.translateBy(x: offset.width, y: offset.height)
            draw(&ctx, pose: pose, look: look, time: time)
            drawPulses(&ctx, pulses: pulses)
            drawScrap(&ctx, eating: eating, side: eatSide, palette: palette)
            drawBadge(&ctx, image: badge, life: badgeLife)
        }
    }

    // MARK: - Drawing

    private func draw(_ ctx: inout GraphicsContext, pose: Pose, look: CGPoint, time: Double) {
        drawShadow(&ctx, pose: pose)

        ctx.drawLayer { body in
            // Squash and stretch pivot on the feet so the robot never sinks.
            body.translateBy(x: 80, y: L.groundY)
            body.scaleBy(x: pose.squashX, y: pose.squashY)
            body.translateBy(x: -80, y: -L.groundY + pose.bob)

            drawThruster(&body, pose: pose, time: time)
            drawLegs(&body, pose: pose)
            drawArm(&body, pose: pose, side: -1)
            drawArm(&body, pose: pose, side: 1)
            drawTorso(&body, time: time)
            drawHead(&body, pose: pose, look: look)
        }
    }

    private func drawPulses(_ ctx: inout GraphicsContext, pulses: [Double]) {
        let centre = CGPoint(x: 80, y: 118)
        for life in pulses {
            let grown = 1 - life
            let radius = 26 + grown * 50
            let rect = CGRect(x: centre.x - radius, y: centre.y - radius * 0.82,
                              width: radius * 2, height: radius * 1.64)
            ctx.stroke(Path(ellipseIn: rect),
                       with: .color(palette.glow.color.opacity(life * 0.55)),
                       lineWidth: 2 + life * 2.5)
        }
    }

    private func drawScrap(_ ctx: inout GraphicsContext, eating: Double,
                           side: Double, palette: Palette) {
        guard eating > 0 else { return }
        let chew = 1 - eating                       // 0 → 1
        let mouth = CGPoint(x: 80, y: 72)

        if chew < 0.9 {
            let travel = min(1, chew / 0.9)
            let eased = travel * travel * (3 - 2 * travel)
            let start = CGPoint(x: 80 + side * 84, y: 18)
            let centre = CGPoint(x: start.x + (mouth.x - start.x) * eased,
                                 y: start.y + (mouth.y - start.y) * eased)
            let scale = 1 - 0.72 * eased
            let width = 54.0 * scale
            let height = 40.0 * scale

            ctx.drawLayer { layer in
                layer.translateBy(x: centre.x, y: centre.y)
                layer.rotate(by: .degrees(-side * (18 + eased * 190)))
                let rect = CGRect(x: -width / 2, y: -height / 2, width: width, height: height)
                var page = Path()
                page.move(to: CGPoint(x: rect.minX, y: rect.minY + 3))
                for tooth in 0...8 {
                    let x = rect.minX + rect.width * Double(tooth) / 8
                    page.addLine(to: CGPoint(x: x, y: rect.minY + 3 + sin(Double(tooth) * 2.4) * 2.4))
                }
                page.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
                page.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
                page.closeSubpath()
                layer.fill(page, with: .color(Color(red: 0.99, green: 0.97, blue: 0.92)))
                layer.stroke(page, with: .color(.black.opacity(0.25)), lineWidth: 1.2)
                var mark = Path()
                mark.move(to: CGPoint(x: rect.minX + 8, y: rect.midY))
                mark.addLine(to: CGPoint(x: rect.maxX - 8, y: rect.midY))
                layer.stroke(mark, with: .color(Color(red: 0.13, green: 0.17, blue: 0.36)
                                                    .opacity(0.6)),
                             style: StrokeStyle(lineWidth: 2 * scale, lineCap: .round))
            }
        }

        if chew > 0.86 {
            let burst = (chew - 0.86) / 0.14
            for index in 0..<4 {
                let angle = Double(index) * 1.7 + 0.6
                let distance = burst * 22
                let dot = CGPoint(x: mouth.x + cos(angle) * distance,
                                  y: mouth.y + sin(angle) * distance * 0.7)
                let size = 3.4 * (1 - burst)
                ctx.fill(Path(ellipseIn: CGRect(x: dot.x - size, y: dot.y - size,
                                                width: size * 2, height: size * 2)),
                         with: .color(Color(red: 0.99, green: 0.97, blue: 0.92)
                                        .opacity(1 - burst)))
            }
        }
    }

    private func drawBadge(_ ctx: inout GraphicsContext, image: NSImage?, life: Double) {
        guard let image, life > 0 else { return }
        let shown = 1 - life                       // 0 at pop-in, 1 at fade-out
        let pop: Double
        if shown < 0.12 {
            let u = shown / 0.12
            pop = 0.35 + 1.75 * u - 0.6 * u * u    // overshoot, then settle
        } else {
            pop = 1
        }
        let rise = shown > 0.78 ? (shown - 0.78) / 0.22 : 0
        let fade = 1 - rise
        guard fade > 0.01 else { return }

        let side = 40.0 * pop
        let centre = CGPoint(x: 80, y: -12 - rise * 26)
        let rect = CGRect(x: centre.x - side / 2, y: centre.y - side / 2,
                          width: side, height: side)

        ctx.drawLayer { layer in
            layer.opacity = fade
            let halo = rect.insetBy(dx: -10, dy: -10)
            layer.fill(Path(ellipseIn: halo), with: .radialGradient(
                Gradient(colors: [palette.glow.color.opacity(0.45),
                                  palette.glow.color.opacity(0)]),
                center: centre, startRadius: 2, endRadius: halo.width / 2))
            layer.draw(layer.resolve(Image(nsImage: image)), in: rect)
        }
    }

    private func drawShadow(_ ctx: inout GraphicsContext, pose: Pose) {
        let w = 76 * pose.shadow
        let h = 16 * pose.shadow
        let center = CGPoint(x: 80, y: L.groundY + 1)
        ctx.opacity = 0.30 * max(0.2, pose.shadow)
        ctx.fill(Path(ellipseIn: CGRect(x: center.x - w / 2, y: center.y - h / 2,
                                        width: w, height: h)),
                 with: .radialGradient(Gradient(colors: [.black, .black.opacity(0)]),
                                       center: center, startRadius: 0, endRadius: w / 2))
        ctx.opacity = 1
    }

    private func drawThruster(_ ctx: inout GraphicsContext, pose: Pose, time: Double) {
        guard pose.thrust > 0.02 else { return }
        let flicker = 1 + sin(time * 34) * 0.12
        for x in [64.0, 96.0] {
            let top = L.feetY - 4
            let len = 32 * pose.thrust * flicker
            ctx.fill(flame(at: x, top: top, width: 11, length: len),
                     with: .linearGradient(
                        Gradient(colors: [palette.glow.color.opacity(0.9), palette.accent.color.opacity(0)]),
                        startPoint: CGPoint(x: x, y: top), endPoint: CGPoint(x: x, y: top + len)))
            ctx.fill(flame(at: x, top: top, width: 5.5, length: len * 0.62),
                     with: .linearGradient(
                        Gradient(colors: [.white.opacity(0.95), palette.glow.color.opacity(0)]),
                        startPoint: CGPoint(x: x, y: top),
                        endPoint: CGPoint(x: x, y: top + len * 0.62)))
        }
    }

    private func flame(at x: Double, top: Double, width: Double, length: Double) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: x - width, y: top))
        path.addQuadCurve(to: CGPoint(x: x, y: top + length),
                          control: CGPoint(x: x - width * 0.8, y: top + length * 0.6))
        path.addQuadCurve(to: CGPoint(x: x + width, y: top),
                          control: CGPoint(x: x + width * 0.8, y: top + length * 0.6))
        path.closeSubpath()
        return path
    }

    private func drawLegs(_ ctx: inout GraphicsContext, pose: Pose) {
        for x in [64.0, 96.0] {
            let bottom = L.legBottom - 16 * pose.legTuck
            let leg = Path(roundedRect: CGRect(x: x - 8, y: L.legTop, width: 16,
                                               height: bottom - L.legTop), cornerRadius: 8)
            paint(&ctx, leg, .linearGradient(palette.jointGradient,
                startPoint: CGPoint(x: x - 8, y: 0), endPoint: CGPoint(x: x + 8, y: 0)),
                lineWidth: 2.5)

            let footY = bottom - 2
            let foot = Path(roundedRect: CGRect(x: x - 16, y: footY, width: 32, height: 14),
                            cornerRadius: 7)
            paint(&ctx, foot, .linearGradient(
                Gradient(colors: [palette.accent.color, palette.accent.color.opacity(0.72)]),
                startPoint: CGPoint(x: x, y: footY), endPoint: CGPoint(x: x, y: footY + 14)))
        }
    }

    /// `pose.armAngle` is degrees of lift: 0 hangs straight down, 180 points
    /// straight up. The sign flip mirrors it for the left side.
    private func drawArm(_ ctx: inout GraphicsContext, pose: Pose, side: Double) {
        let pivot = CGPoint(x: 80 + side * L.shoulderX, y: L.shoulderY)
        var lift = pose.armAngle
        if let wave = pose.waveAngle, side > 0 { lift = wave }

        paint(&ctx, Path(ellipseIn: CGRect(x: pivot.x - 10, y: pivot.y - 10,
                                           width: 20, height: 20)),
              .linearGradient(palette.jointGradient, startPoint: CGPoint(x: pivot.x - 10, y: pivot.y - 10),
                              endPoint: CGPoint(x: pivot.x + 10, y: pivot.y + 10)),
              lineWidth: 2.5)

        ctx.drawLayer { layer in
            layer.translateBy(x: pivot.x, y: pivot.y)
            layer.rotate(by: .degrees(-side * lift))
            let arm = Path(roundedRect: CGRect(x: -7, y: -6, width: 14, height: 40),
                           cornerRadius: 7)
            paint(&layer, arm, .linearGradient(palette.limbGradient,
                startPoint: CGPoint(x: -7, y: 0), endPoint: CGPoint(x: 7, y: 0)),
                lineWidth: 2.5)
            let hand = Path(ellipseIn: CGRect(x: -9.5, y: 26, width: 19, height: 19))
            paint(&layer, hand, .radialGradient(
                Gradient(colors: [palette.accent.color.opacity(0.98), palette.accent.color.opacity(0.68)]),
                center: CGPoint(x: -3, y: 31), startRadius: 1, endRadius: 16))
        }
    }

    private func drawTorso(_ ctx: inout GraphicsContext, time: Double) {
        let r = L.torsoRect
        paint(&ctx, Path(roundedRect: r, cornerRadius: 22), .linearGradient(palette.shellGradient,
            startPoint: CGPoint(x: r.minX + 6, y: r.minY), endPoint: CGPoint(x: r.maxX, y: r.maxY)))

        let plate = CGRect(x: 57, y: 105, width: 46, height: 40)
        ctx.fill(Path(roundedRect: plate, cornerRadius: 15), with: .linearGradient(
            palette.plateGradient,
            startPoint: CGPoint(x: plate.minX, y: plate.minY),
            endPoint: CGPoint(x: plate.maxX, y: plate.maxY)))

        let pulse = 0.75 + 0.25 * sin(time * 2.6)
        ctx.fill(Path(ellipseIn: CGRect(x: L.core.x - 17, y: L.core.y - 17,
                                        width: 34, height: 34)),
                 with: .radialGradient(
                    Gradient(colors: [palette.glow.color.opacity(0.75 * pulse), palette.glow.color.opacity(0)]),
                    center: L.core, startRadius: 1, endRadius: 17))
        ctx.fill(Path(ellipseIn: CGRect(x: L.core.x - 9, y: L.core.y - 9, width: 18, height: 18)),
                 with: .radialGradient(Gradient(colors: [.white, palette.glow.color, palette.accent.color]),
                                       center: L.core, startRadius: 0, endRadius: 10))

        var sheen = Path()
        sheen.move(to: CGPoint(x: 55, y: 142))
        sheen.addQuadCurve(to: CGPoint(x: 58, y: 104), control: CGPoint(x: 51, y: 120))
        ctx.stroke(sheen, with: .color(palette.sheen),
                   style: StrokeStyle(lineWidth: 4, lineCap: .round))
    }

    private func drawHead(_ ctx: inout GraphicsContext, pose: Pose, look: CGPoint) {
        paint(&ctx, Path(roundedRect: CGRect(x: 69, y: 84, width: 22, height: 18),
                         cornerRadius: 6),
              .linearGradient(palette.jointGradient, startPoint: CGPoint(x: 69, y: 84),
                              endPoint: CGPoint(x: 91, y: 102)), lineWidth: 2.5)

        drawAntenna(&ctx, pose: pose)

        let head = Path(roundedRect: L.headRect, cornerRadius: 24)
        paint(&ctx, head, .linearGradient(palette.shellGradient,
            startPoint: CGPoint(x: L.headRect.minX + 8, y: L.headRect.minY),
            endPoint: CGPoint(x: L.headRect.maxX, y: L.headRect.maxY)))

        for x in [40.0, 120.0] {
            paint(&ctx, Path(roundedRect: CGRect(x: x - 7, y: 54, width: 14, height: 20),
                             cornerRadius: 6), .color(palette.accent.color), lineWidth: 2.5)
        }

        let visor = Path(roundedRect: L.visorRect, cornerRadius: 17)
        paint(&ctx, visor, .linearGradient(palette.visorGradient,
            startPoint: CGPoint(x: L.visorRect.minX, y: L.visorRect.minY),
            endPoint: CGPoint(x: L.visorRect.maxX, y: L.visorRect.maxY)))

        drawFace(&ctx, pose: pose, look: look)

        var glare = Path()
        glare.move(to: CGPoint(x: 60, y: 77))
        glare.addLine(to: CGPoint(x: 72, y: 49))
        glare.addLine(to: CGPoint(x: 80, y: 49))
        glare.addLine(to: CGPoint(x: 68, y: 77))
        glare.closeSubpath()
        ctx.opacity = 0.10
        ctx.fill(glare, with: .color(.white))
        ctx.opacity = 1
    }

    private func drawAntenna(_ ctx: inout GraphicsContext, pose: Pose) {
        let bend = pose.antennaBend
        let tip = CGPoint(x: L.antenna.x + bend, y: L.antenna.y)
        var stalk = Path()
        stalk.move(to: CGPoint(x: 80, y: 38))
        stalk.addQuadCurve(to: tip, control: CGPoint(x: 80 + bend * 0.3, y: 26))
        ctx.stroke(stalk, with: .color(palette.outline.color),
                   style: StrokeStyle(lineWidth: 4.5, lineCap: .round))

        let halo = 0.55 + pose.glowBoost * 0.45
        ctx.fill(Path(ellipseIn: CGRect(x: tip.x - 16 - pose.glowBoost * 6,
                                        y: tip.y - 16 - pose.glowBoost * 6,
                                        width: 32 + pose.glowBoost * 12,
                                        height: 32 + pose.glowBoost * 12)),
                 with: .radialGradient(
                    Gradient(colors: [palette.glow.color.opacity(halo),
                                      palette.glow.color.opacity(0)]),
                    center: tip, startRadius: 2, endRadius: 16 + pose.glowBoost * 6))
        paint(&ctx, Path(ellipseIn: CGRect(x: tip.x - 7.5, y: tip.y - 7.5,
                                           width: 15, height: 15)),
              .radialGradient(Gradient(colors: [.white, palette.glow.color]),
                              center: CGPoint(x: tip.x - 2, y: tip.y - 2),
                              startRadius: 0, endRadius: 10), lineWidth: 2.5)
    }

    private func drawFace(_ ctx: inout GraphicsContext, pose: Pose, look: CGPoint) {
        let dx = max(-1, min(1, look.x)) * 3.4
        let dy = max(-1, min(1, look.y)) * 2.6
        let happy = pose.smile > 0.45

        if pose.notify && !happy {
            drawNotifyEyes(&ctx, dx: dx, dy: dy)
        } else {
            for x in [66.0, 94.0] {
                let center = CGPoint(x: x + dx, y: L.eyeY + dy)
                if happy {
                    var arc = Path()
                    arc.move(to: CGPoint(x: center.x - 8.5, y: center.y + 4))
                    arc.addQuadCurve(to: CGPoint(x: center.x + 8.5, y: center.y + 4),
                                     control: CGPoint(x: center.x, y: center.y - 11))
                    ctx.stroke(arc, with: .color(palette.glow.color),
                               style: StrokeStyle(lineWidth: 4.5, lineCap: .round))
                } else {
                    let h = max(2.5, 18 * pose.eyeOpen)
                    let rect = CGRect(x: center.x - 8.5, y: center.y - h / 2, width: 17, height: h)
                    ctx.fill(Path(ellipseIn: rect.insetBy(dx: -7, dy: -7)), with: .radialGradient(
                        Gradient(colors: [palette.glow.color.opacity(0.55),
                                          palette.glow.color.opacity(0)]),
                        center: center, startRadius: 2, endRadius: 15))
                    ctx.fill(Path(roundedRect: rect, cornerRadius: 8.5), with: .linearGradient(
                        Gradient(colors: [.white, palette.glow.color]),
                        startPoint: CGPoint(x: center.x, y: rect.minY),
                        endPoint: CGPoint(x: center.x, y: rect.maxY)))
                    if pose.eyeOpen > 0.55 {
                        let pr = 3.8
                        ctx.fill(Path(ellipseIn: CGRect(x: center.x - pr + dx * 0.7,
                                                        y: center.y - pr + dy * 0.7,
                                                        width: pr * 2, height: pr * 2)),
                                 with: .color(palette.visor.color.opacity(0.92)))
                    }
                }
            }
        }

        var mouth = Path()
        if pose.openMouth {
            mouth.addEllipse(in: CGRect(x: 73, y: L.mouthY - 5, width: 14, height: 12))
            ctx.fill(mouth, with: .color(palette.glow.color.opacity(0.85)))
        } else {
            let curve = 4 + pose.smile * 7
            mouth.move(to: CGPoint(x: 70, y: L.mouthY))
            mouth.addQuadCurve(to: CGPoint(x: 90, y: L.mouthY),
                               control: CGPoint(x: 80, y: L.mouthY + curve))
            ctx.stroke(mouth, with: .color(palette.glow.color.opacity(0.9)),
                       style: StrokeStyle(lineWidth: 3.5, lineCap: .round))
        }
    }

    /// Update-waiting face:  >  on the left, which is the only eye that tracks
    /// the pointer, and a steady  _  on the right.
    private func drawNotifyEyes(_ ctx: inout GraphicsContext, dx: Double, dy: Double) {
        let style = StrokeStyle(lineWidth: 4.5, lineCap: .round, lineJoin: .round)
        let glow = palette.glow.color

        let tip = CGPoint(x: 66 + dx * 1.4, y: L.eyeY + dy * 1.4)
        var chevron = Path()
        chevron.move(to: CGPoint(x: tip.x - 5.5, y: tip.y - 8.5))
        chevron.addLine(to: CGPoint(x: tip.x + 5.5, y: tip.y))
        chevron.addLine(to: CGPoint(x: tip.x - 5.5, y: tip.y + 8.5))
        ctx.fill(Path(ellipseIn: CGRect(x: tip.x - 13, y: tip.y - 13, width: 26, height: 26)),
                 with: .radialGradient(Gradient(colors: [glow.opacity(0.5), glow.opacity(0)]),
                                       center: tip, startRadius: 2, endRadius: 13))
        ctx.stroke(chevron, with: .color(glow), style: style)

        var bar = Path()
        bar.move(to: CGPoint(x: 86, y: L.eyeY + 7))
        bar.addLine(to: CGPoint(x: 102, y: L.eyeY + 7))
        ctx.stroke(bar, with: .color(glow), style: style)
    }

    private func paint(_ ctx: inout GraphicsContext, _ path: Path,
                       _ shading: GraphicsContext.Shading, lineWidth: Double = 3) {
        ctx.fill(path, with: shading)
        ctx.stroke(path, with: .color(palette.outline.color.opacity(0.88)), lineWidth: lineWidth)
    }
}
