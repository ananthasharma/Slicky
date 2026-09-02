import AppKit
import SwiftUI

struct SelfiePose {
    var phase: Double?
    var held: Bool
    var look: CGPoint
}

enum SelfieError: LocalizedError {
    case renderFailed
    case encodeFailed

    var errorDescription: String? {
        switch self {
        case .renderFailed: return "The robot could not be rendered."
        case .encodeFailed: return "The image could not be written as a PNG."
        }
    }
}

@MainActor
enum Selfie {
    static func capture(pose: SelfiePose, palette: Palette) -> Result<URL, Error> {
        let model = PetModel()
        model.phase = pose.phase
        model.held = pose.held
        model.look = pose.look
        model.excitement = 1        // smile for the camera

        let renderer = ImageRenderer(content:
            RobotView(model: model, frozenTime: 0.42, showsPadding: true, palette: palette)
                .frame(width: 528, height: 810))
        renderer.scale = 3
        renderer.isOpaque = false

        guard let image = renderer.nsImage,
              let tiff = image.tiffRepresentation,
              let rep = NSBitmapImageRep(data: tiff) else { return .failure(SelfieError.renderFailed) }

        let cropped = trimmed(rep) ?? rep
        guard let png = cropped.representation(using: .png, properties: [:]) else {
            return .failure(SelfieError.encodeFailed)
        }

        do {
            let url = try destination()
            try png.write(to: url)
            return .success(url)
        } catch {
            return .failure(error)
        }
    }

    private static func trimmed(_ rep: NSBitmapImageRep) -> NSBitmapImageRep? {
        guard let pixels = rep.bitmapData,
              rep.bitsPerSample == 8,
              rep.samplesPerPixel == 4,
              let source = rep.cgImage else { return nil }

        let width = rep.pixelsWide
        let height = rep.pixelsHigh
        let stride = rep.bytesPerRow
        let step = rep.bitsPerPixel / 8
        let alphaOffset = rep.bitmapFormat.contains(.alphaFirst) ? 0 : step - 1

        var minX = width, minY = height, maxX = -1, maxY = -1
        for y in 0..<height {
            let row = pixels + y * stride
            for x in 0..<width where (row + x * step + alphaOffset).pointee > 8 {
                if x < minX { minX = x }
                if x > maxX { maxX = x }
                if y < minY { minY = y }
                if y > maxY { maxY = y }
            }
        }
        guard maxX >= minX, maxY >= minY else { return nil }

        // A few pixels of breathing room so the antialiased edge isn't sliced.
        let pad = 4
        let rect = CGRect(x: max(0, minX - pad), y: max(0, minY - pad),
                          width: min(width, maxX + pad + 1) - max(0, minX - pad),
                          height: min(height, maxY + pad + 1) - max(0, minY - pad))
        guard let cut = source.cropping(to: rect) else { return nil }
        return NSBitmapImageRep(cgImage: cut)
    }

    private static func destination() throws -> URL {
        let folder = FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("Downloads")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)

        let stamp = DateFormatter()
        stamp.dateFormat = "yyyy-MM-dd 'at' HH.mm.ss"
        let base = "Slicky selfie \(stamp.string(from: Date()))"

        var url = folder.appendingPathComponent("\(base).png")
        var counter = 2
        while FileManager.default.fileExists(atPath: url.path) {
            url = folder.appendingPathComponent("\(base) (\(counter)).png")
            counter += 1
        }
        return url
    }
}
