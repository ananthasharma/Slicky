import AppKit
import SwiftUI

struct NotepadView: View {
    @ObservedObject var model: NotepadModel

    static let size = CGSize(width: 236, height: 176)

    private static let paper = Color(red: 0.99, green: 0.975, blue: 0.93)
    private static let rule = Color(red: 0.72, green: 0.80, blue: 0.88)
    private static let margin = Color(red: 0.86, green: 0.45, blue: 0.44)
    private static let ink = Color(red: 0.13, green: 0.17, blue: 0.36)

    private static let hand = Font.custom("Bradley Hand", size: 16).weight(.bold)
    private static let handSmall = Font.custom("Bradley Hand", size: 12).weight(.bold)

    private var sheetRect: CGRect {
        CGRect(x: 8, y: 20, width: Self.size.width - 16, height: Self.size.height - 30)
    }

    var body: some View {
        ZStack(alignment: .topLeading) {
            sheet(showingNew: true)

            if model.tear < 1 {
                sheet(showingNew: false)
                    .mask(TornEdge(ragged: model.tear > 0)
                        .path(in: sheetRect).fill(style: FillStyle()))
                    .offset(x: model.tear * 46 * model.tearDirection, y: model.tear * 150)
                    .rotationEffect(.degrees(model.tear * 22 * model.tearDirection), anchor: .top)
                    .opacity(1 - model.tear * 0.9)
            }

            rings
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .rotationEffect(.degrees(-1.6))
        .shadow(color: .black.opacity(0.3), radius: 11, x: 0, y: 5)
    }

    private func sheet(showingNew: Bool) -> some View {
        ZStack(alignment: .topLeading) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Self.paper)
                .frame(width: sheetRect.width, height: sheetRect.height)
                .overlay(alignment: .topLeading) { ruling }
                .overlay(RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(.black.opacity(0.10), lineWidth: 1))
            content(showingNew: showingNew)
                .frame(width: sheetRect.width, height: sheetRect.height, alignment: .topLeading)
        }
        .offset(x: sheetRect.minX, y: sheetRect.minY)
    }

    private var ruling: some View {
        ZStack(alignment: .topLeading) {
            ForEach(1..<5) { line in
                Rectangle().fill(Self.rule.opacity(0.55))
                    .frame(height: 1)
                    .offset(y: CGFloat(line) * 29 + 4)
            }
            Rectangle().fill(Self.margin.opacity(0.5))
                .frame(width: 1)
                .offset(x: 28)
        }
        .frame(width: sheetRect.width, height: sheetRect.height, alignment: .topLeading)
        .clipped()
    }

    private var rings: some View {
        HStack(spacing: 20) {
            ForEach(0..<6, id: \.self) { _ in
                Capsule()
                    .stroke(LinearGradient(colors: [Color(white: 0.86), Color(white: 0.45)],
                                           startPoint: .top, endPoint: .bottom),
                            lineWidth: 3)
                    .frame(width: 10, height: 24)
            }
        }
        .frame(width: Self.size.width, alignment: .center)
        .offset(y: 9)
    }

    private func content(showingNew: Bool) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 6) {
                if let icon = model.icon {
                    Image(nsImage: icon).resizable().frame(width: 16, height: 16)
                }
                Text("on \(model.slot.label)…")
                    .font(Self.handSmall)
                    .foregroundStyle(Self.ink.opacity(0.55))
            }
            .padding(.leading, 36)
            .padding(.top, 10)

            entry(showingNew: showingNew)
                .padding(.leading, 36)
                .padding(.trailing, 12)
                .padding(.top, 6)

            Spacer(minLength: 0)
        }
    }

    private func entry(showingNew: Bool) -> some View {
        let text = showingNew ? model.newEntry : model.oldEntry
        return Text(text.isEmpty ? "—" : text)
            .font(Self.hand)
            .foregroundStyle(Self.ink.opacity(text.isEmpty ? 0.3 : 0.95))
            .lineLimit(1)
            .mask(alignment: .leading) {
                Rectangle().scaleEffect(x: showingNew ? model.ink : 1, anchor: .leading)
            }
            .overlay {
                if !showingNew, !text.isEmpty, model.scratch > 0 {
                    GeometryReader { proxy in
                        Scribble(width: proxy.size.width + 10)
                            .trim(from: 0, to: model.scratch)
                            .stroke(Self.ink.opacity(0.85),
                                    style: StrokeStyle(lineWidth: 2.5, lineCap: .round,
                                                       lineJoin: .round))
                            .offset(x: -5)
                    }
                }
            }
            .frame(height: 24, alignment: .leading)
    }
}

struct Scribble: Shape {
    let width: CGFloat

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let midY = rect.midY
        path.move(to: CGPoint(x: 0, y: midY + 4))
        var x: CGFloat = 0
        var up = true
        while x < width {
            x += 13
            path.addQuadCurve(to: CGPoint(x: min(x, width), y: midY + (up ? -5 : 5)),
                              control: CGPoint(x: x - 7, y: midY + (up ? -9 : 9)))
            up.toggle()
        }
        path.addLine(to: CGPoint(x: width, y: midY + 1))
        while x > 0 {
            x -= 17
            path.addQuadCurve(to: CGPoint(x: max(x, 0), y: midY + (up ? 3 : -3)),
                              control: CGPoint(x: x + 9, y: midY + (up ? 7 : -7)))
            up.toggle()
        }
        return path
    }
}

struct TornEdge: Shape {
    let ragged: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard ragged else {
            path.addRoundedRect(in: rect, cornerSize: CGSize(width: 4, height: 4))
            return path
        }
        let teeth = 24
        let step = rect.width / CGFloat(teeth)
        path.move(to: CGPoint(x: rect.minX, y: rect.minY + 5))
        for tooth in 0...teeth {
            let x = rect.minX + CGFloat(tooth) * step
            let wobble = sin(Double(tooth) * 2.399) * 3.2 + cos(Double(tooth) * 1.117) * 2.1
            path.addLine(to: CGPoint(x: x, y: rect.minY + 5 + wobble))
        }
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}
