import AppKit
import SwiftUI

struct RGB: Codable, Hashable {
    var r: Double
    var g: Double
    var b: Double

    init(_ r: Double, _ g: Double, _ b: Double) {
        self.r = r
        self.g = g
        self.b = b
    }

    init(color: Color) {
        let ns = NSColor(color).usingColorSpace(.sRGB) ?? .white
        self.init(Double(ns.redComponent), Double(ns.greenComponent), Double(ns.blueComponent))
    }

    var color: Color { Color(.sRGB, red: r, green: g, blue: b, opacity: 1) }

    func lighter(_ t: Double) -> RGB {
        RGB(r + (1 - r) * t, g + (1 - g) * t, b + (1 - b) * t)
    }

    func darker(_ t: Double) -> RGB {
        RGB(r * (1 - t), g * (1 - t), b * (1 - t))
    }

    /// Rough perceived brightness, for deciding if a shell reads as dark.
    var luminance: Double { 0.2126 * r + 0.7152 * g + 0.0722 * b }
}

struct Palette: Codable, Hashable {
    var name: String
    var shell: RGB
    var accent: RGB
    var glow: RGB
    var outline: RGB
    var visor: RGB

    // Derived ramps, so one shell colour drives every panel on the robot.
    var shellGradient: Gradient {
        Gradient(colors: [shell.lighter(0.80).color, shell.color, shell.darker(0.24).color])
    }
    var jointGradient: Gradient {
        Gradient(colors: [shell.darker(0.08).color, shell.darker(0.30).color])
    }
    var limbGradient: Gradient {
        Gradient(colors: [shell.lighter(0.35).color, shell.darker(0.22).color])
    }
    var visorGradient: Gradient {
        Gradient(colors: [visor.lighter(0.10).color, visor.color])
    }
    var plateGradient: Gradient {
        Gradient(colors: [visor.lighter(0.12).color, visor.lighter(0.01).color])
    }
    /// Highlights read as white on a light shell and as a soft glow on a dark one.
    var sheen: Color {
        shell.luminance > 0.45 ? .white.opacity(0.6) : glow.lighter(0.4).color.opacity(0.35)
    }

    static let chrome = Palette(
        name: "Chrome",
        shell: RGB(0.85, 0.88, 0.93), accent: RGB(0.35, 0.42, 1.00),
        glow: RGB(0.32, 0.90, 1.00), outline: RGB(0.09, 0.11, 0.15),
        visor: RGB(0.06, 0.08, 0.12))

    static let midnight = Palette(
        name: "Midnight",
        shell: RGB(0.28, 0.31, 0.41), accent: RGB(0.56, 0.46, 1.00),
        glow: RGB(0.55, 0.95, 1.00), outline: RGB(0.04, 0.05, 0.09),
        visor: RGB(0.05, 0.06, 0.11))

    static let sunset = Palette(
        name: "Sunset",
        shell: RGB(0.97, 0.85, 0.74), accent: RGB(1.00, 0.44, 0.24),
        glow: RGB(1.00, 0.72, 0.26), outline: RGB(0.24, 0.10, 0.08),
        visor: RGB(0.17, 0.07, 0.07))

    static let mint = Palette(
        name: "Mint",
        shell: RGB(0.83, 0.94, 0.89), accent: RGB(0.08, 0.72, 0.55),
        glow: RGB(0.36, 1.00, 0.76), outline: RGB(0.04, 0.16, 0.13),
        visor: RGB(0.03, 0.12, 0.10))

    static let grape = Palette(
        name: "Grape",
        shell: RGB(0.89, 0.85, 0.97), accent: RGB(0.55, 0.30, 0.92),
        glow: RGB(0.86, 0.56, 1.00), outline: RGB(0.13, 0.07, 0.20),
        visor: RGB(0.09, 0.05, 0.16))

    static let cherry = Palette(
        name: "Cherry",
        shell: RGB(0.99, 0.88, 0.89), accent: RGB(0.90, 0.20, 0.35),
        glow: RGB(1.00, 0.46, 0.56), outline: RGB(0.20, 0.06, 0.09),
        visor: RGB(0.14, 0.04, 0.07))

    static let gold = Palette(
        name: "Gold",
        shell: RGB(0.96, 0.89, 0.68), accent: RGB(0.84, 0.61, 0.14),
        glow: RGB(1.00, 0.86, 0.42), outline: RGB(0.20, 0.14, 0.04),
        visor: RGB(0.13, 0.09, 0.03))

    static let presets: [Palette] = [chrome, midnight, sunset, mint, grape, cherry, gold]
}
