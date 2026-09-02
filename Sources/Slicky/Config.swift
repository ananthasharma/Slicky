import AppKit

struct AppAction: Codable, Identifiable, Hashable {
    var id = UUID()
    var name: String
    var path: String
    var bundleID: String?

    init(id: UUID = UUID(), name: String, path: String, bundleID: String? = nil) {
        self.id = id
        self.name = name
        self.path = path
        self.bundleID = bundleID
    }

    init?(url: URL) {
        guard let bundle = Bundle(url: url) else { return nil }
        let name = FileManager.default.displayName(atPath: url.path)
            .replacingOccurrences(of: ".app", with: "")
        self.init(name: name, path: url.path, bundleID: bundle.bundleIdentifier)
    }

    var url: URL { URL(fileURLWithPath: path) }

    var exists: Bool { FileManager.default.fileExists(atPath: path) }

    /// Falls back to the bundle identifier when the app has moved on disk.
    var resolvedURL: URL? {
        if exists { return url }
        if let id = bundleID {
            return NSWorkspace.shared.urlForApplication(withBundleIdentifier: id)
        }
        return nil
    }

    var icon: NSImage { icon(size: 16) }

    func icon(size: CGFloat) -> NSImage {
        let image = NSWorkspace.shared.icon(forFile: resolvedURL?.path ?? path)
        image.size = NSSize(width: size, height: size)
        return image
    }
}

struct Config: Codable {
    var singleClick: AppAction?
    var doubleClick: AppAction?
    var menuApps: [AppAction] = []

    var wander = true
    var interval: Double = 25
    var hopDistance: Double = 320
    var scale: Double = 0.9
    var aboveEverything = false
    var followCursor = true
    var palette: Palette = .chrome
    var dodgeTyping = false
    /// Add an unpredictable 0.1–3.14s on top of the hop interval.
    var randomizeInterval = true

    static let storageKey = "SlickyConfig"

    init() {}

    private enum CodingKeys: String, CodingKey {
        case singleClick, doubleClick, menuApps, wander, interval, hopDistance
        case scale, aboveEverything, followCursor, palette, dodgeTyping
        case randomizeInterval
    }

    /// Decoded field by field so a settings file written by an older build
    /// keeps its app bindings when new options appear.
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        func value<T: Decodable>(_ key: CodingKeys, _ fallback: T) -> T {
            (try? container.decodeIfPresent(T.self, forKey: key)) ?? fallback
        }
        singleClick = try? container.decodeIfPresent(AppAction.self, forKey: .singleClick)
        doubleClick = try? container.decodeIfPresent(AppAction.self, forKey: .doubleClick)
        menuApps = value(.menuApps, [])
        wander = value(.wander, true)
        interval = value(.interval, 25)
        hopDistance = value(.hopDistance, 320)
        scale = value(.scale, 0.9)
        aboveEverything = value(.aboveEverything, false)
        followCursor = value(.followCursor, true)
        palette = value(.palette, .chrome)
        dodgeTyping = value(.dodgeTyping, false)
        randomizeInterval = value(.randomizeInterval, true)
    }

    static func load() -> Config {
        guard let data = UserDefaults.standard.data(forKey: storageKey),
              let config = try? JSONDecoder().decode(Config.self, from: data)
        else { return .makeDefault() }
        return config
    }

    func save() {
        guard let data = try? JSONEncoder().encode(self) else { return }
        UserDefaults.standard.set(data, forKey: Self.storageKey)
    }

    /// First launch: wire up whichever of these common apps are installed.
    static func makeDefault() -> Config {
        var config = Config()
        config.singleClick = firstAvailable([
            "/System/Applications/Utilities/Terminal.app",
            "/Applications/iTerm.app",
            "/System/Applications/Launchpad.app",
        ])
        config.doubleClick = firstAvailable([
            "/Applications/Books.app",
            "/Applications/Safari.app",
            "/Applications/Google Chrome.app",
        ])
        config.menuApps = [
            "/System/Applications/Utilities/Activity Monitor.app",
            "/System/Applications/Notes.app",
            "/System/Applications/System Settings.app",
        ].compactMap { path in
            FileManager.default.fileExists(atPath: path)
                ? AppAction(url: URL(fileURLWithPath: path)) : nil
        }
        return config
    }

    private static func firstAvailable(_ paths: [String]) -> AppAction? {
        for path in paths where FileManager.default.fileExists(atPath: path) {
            if let action = AppAction(url: URL(fileURLWithPath: path)) { return action }
        }
        return nil
    }
}
