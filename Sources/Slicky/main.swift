import AppKit

let arguments = CommandLine.arguments
let application = NSApplication.shared

if let index = arguments.firstIndex(of: "--export-icon"), index + 1 < arguments.count {
    application.setActivationPolicy(.prohibited)
    let destination = URL(fileURLWithPath: arguments[index + 1])
    exit(MainActor.assumeIsolated { IconExport.run(to: destination) })
}

if let index = arguments.firstIndex(of: "--preview"), index + 1 < arguments.count {
    application.setActivationPolicy(.prohibited)
    let destination = URL(fileURLWithPath: arguments[index + 1])
    let time = Double(arguments.first { $0.hasPrefix("t=") }?.dropFirst(2) ?? "") ?? 0
    let phase = Double(arguments.first { $0.hasPrefix("p=") }?.dropFirst(2) ?? "")
    let held = arguments.contains("held")
    let excitement = Double(arguments.first { $0.hasPrefix("e=") }?.dropFirst(2) ?? "") ?? 0
    exit(MainActor.assumeIsolated {
        let named = arguments.first { $0.hasPrefix("palette=") }?.dropFirst(8)
        let palette = Palette.presets.first { $0.name.lowercased() == named?.lowercased() }
            ?? Config.load().palette
        return IconExport.preview(to: destination, time: time, phase: phase, held: held,
                                  excitement: excitement, padded: arguments.contains("pad"),
                                  palette: palette, notify: arguments.contains("notify"))
    })
}

if let index = arguments.firstIndex(of: "--notepad-shot"), index + 1 < arguments.count {
    application.setActivationPolicy(.prohibited)
    let destination = URL(fileURLWithPath: arguments[index + 1])
    exit(MainActor.assumeIsolated { IconExport.notepadSheet(to: destination) })
}

if arguments.contains("--check-update") {
    application.setActivationPolicy(.prohibited)
    var finished = false
    Task { @MainActor in
        let updater = Updater.shared
        print("running \(updater.currentVersion), repo \(Updater.repository)")
        await updater.check(announce: true)
        switch updater.status {
        case .available(let release):
            print("update available: \(release.version) tag=\(release.tag)")
            print("  asset: \(release.asset?.lastPathComponent ?? "none (no .zip attached)")")
        case .upToDate: print("up to date")
        case .failed(let reason): print("check failed: \(reason)")
        default: print("status: \(updater.status)")
        }
        finished = true
    }
    // Keep servicing the main actor instead of blocking it.
    while !finished { RunLoop.main.run(until: Date().addingTimeInterval(0.05)) }
    exit(0)
}

if arguments.contains("--selfie") {
    application.setActivationPolicy(.prohibited)
    exit(MainActor.assumeIsolated {
        let config = Config.load()
        let pose = SelfiePose(phase: nil, held: false, look: CGPoint(x: 0.2, y: 0.1))
        switch Selfie.capture(pose: pose, palette: config.palette) {
        case .success(let url):
            print(url.path)
            return 0
        case .failure(let error):
            FileHandle.standardError.write(Data("selfie failed: \(error)\n".utf8))
            return 1
        }
    })
}

application.setActivationPolicy(.accessory)
let appDelegate = AppDelegate()
application.delegate = appDelegate
application.run()
