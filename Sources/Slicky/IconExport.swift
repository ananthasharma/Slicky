import AppKit
import SwiftUI

@MainActor
enum IconExport {
    static func run(to directory: URL) -> Int32 {
        let sizes = [16, 32, 64, 128, 256, 512, 1024]
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for size in sizes {
                guard let data = png(size: size) else {
                    FileHandle.standardError.write(Data("failed to render \(size)px\n".utf8))
                    return 1
                }
                try data.write(to: directory.appendingPathComponent("icon_\(size).png"))
            }
        } catch {
            FileHandle.standardError.write(Data("icon export failed: \(error)\n".utf8))
            return 1
        }
        return 0
    }

    static func preview(to file: URL, time: Double, phase: Double?, held: Bool,
                        excitement: Double, padded: Bool = false,
                        palette: Palette = .chrome, notify: Bool = false) -> Int32 {
        let model = PetModel()
        model.phase = phase
        model.held = held
        model.excitement = excitement
        model.updateAvailable = notify
        if let chew = ProcessInfo.processInfo.environment["SLICKY_EAT"].flatMap(Double.init) {
            model.eating = chew
            model.presenting = true
        }
        if ProcessInfo.processInfo.environment["SLICKY_BADGE"] != nil {
            let icon = NSWorkspace.shared.icon(forFile: "/Applications/Google Chrome.app")
            icon.size = NSSize(width: 44, height: 44)
            model.badge = icon
            model.badgeLife = Double(
                ProcessInfo.processInfo.environment["SLICKY_BADGE"] ?? "0.8") ?? 0.8
            model.pulses = [0.75, 0.45]
        }
        model.look = CGPoint(x: 0.2, y: 0.2)
        let renderer = ImageRenderer(content:
            RobotView(model: model, frozenTime: time, showsPadding: padded, palette: palette)
                .frame(width: padded ? 528 : 480, height: padded ? 810 : 600))
        renderer.scale = 2
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff),
              let data = rep.representation(using: .png, properties: [:]) else { return 1 }
        do { try data.write(to: file) } catch { return 1 }
        return 0
    }

    static func notepadSheet(to directory: URL) -> Int32 {
        let stages: [(String, (NotepadModel) -> Void)] = [
            ("1-scratching", { $0.phase = .scratching; $0.scratch = 0.8 }),
            ("2-tearing", { $0.phase = .tearing; $0.scratch = 1; $0.tear = 0.45 }),
            ("3-written", { $0.phase = .writing; $0.tear = 1; $0.ink = 1 }),
        ]
        do {
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for (name, configure) in stages {
                let model = NotepadModel()
                let icon = NSWorkspace.shared.icon(forFile: "/Applications/Google Chrome.app")
                icon.size = NSSize(width: 16, height: 16)
                model.slot = .click
                model.oldEntry = "Terminal"
                model.newEntry = "Google Chrome"
                model.icon = icon
                configure(model)
                let renderer = ImageRenderer(content:
                    NotepadView(model: model)
                        .padding(26)
                        .background(Color(red: 0.16, green: 0.17, blue: 0.20)))
                renderer.scale = 2
                guard let image = renderer.nsImage,
                      let tiff = image.tiffRepresentation,
                      let rep = NSBitmapImageRep(data: tiff),
                      let data = rep.representation(using: .png, properties: [:]) else { return 1 }
                try data.write(to: directory.appendingPathComponent("notepad-\(name).png"))
            }
        } catch { return 1 }
        return 0
    }

    private static func png(size: Int) -> Data? {
        let side = CGFloat(size)
        let model = PetModel()
        model.look = CGPoint(x: 0, y: 0.15)
        model.excitement = 1

        let content = ZStack {
            RoundedRectangle(cornerRadius: side * 0.2237, style: .continuous)
                .fill(LinearGradient(colors: [
                    Color(red: 0.16, green: 0.20, blue: 0.34),
                    Color(red: 0.06, green: 0.08, blue: 0.14),
                ], startPoint: .top, endPoint: .bottom))
                .overlay(
                    RoundedRectangle(cornerRadius: side * 0.2237, style: .continuous)
                        .strokeBorder(Color.white.opacity(0.12), lineWidth: max(1, side * 0.006))
                )
            RobotView(model: model, frozenTime: 0.35, showsPadding: false)
                .padding(side * 0.12)
        }
        .frame(width: side, height: side)

        let renderer = ImageRenderer(content: content)
        renderer.scale = 1
        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return nil }
        rep.size = NSSize(width: side, height: side)
        return rep.representation(using: .png, properties: [:])
    }
}
