import AppKit
import Security

struct Release: Equatable, Identifiable {
    var id: String { tag }
    let tag: String
    let version: String
    let page: URL
    let asset: URL?
    let notes: String
}

enum UpdateError: LocalizedError {
    case network(Int)
    case noRelease
    case unpackFailed
    case notAnApp
    case wrongIdentity
    case badSignature
    case wrongTeam(String)
    case notWritable(String)

    var errorDescription: String? {
        switch self {
        case .network(let code): return "GitHub answered with status \(code)."
        case .noRelease: return "No published release to compare against."
        case .unpackFailed: return "The download could not be unpacked."
        case .notAnApp: return "The download didn't contain Slicky.app."
        case .wrongIdentity: return "The downloaded app isn't Slicky."
        case .badSignature: return "The downloaded app failed signature validation."
        case .wrongTeam(let team):
            return "The download is signed by \(team), not by this app's developer."
        case .notWritable(let path): return "No permission to replace \(path)."
        }
    }
}

@MainActor
final class Updater: ObservableObject {
    static let shared = Updater()
    static let repository = ProcessInfo.processInfo.environment["SLICKY_REPO"]
        ?? "ananthasharma/Slicky"

    enum Status: Equatable {
        case idle
        case checking
        case upToDate
        case available(Release)
        case downloading
        case installing
        case failed(String)
    }

    @Published private(set) var status: Status = .idle
    @Published private(set) var lastChecked: Date?

    var currentVersion: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    var availableRelease: Release? {
        if case .available(let release) = status { return release }
        return nil
    }

    var isBusy: Bool {
        switch status {
        case .checking, .downloading, .installing: return true
        default: return false
        }
    }

    // MARK: - Checking

    /// `announce: false` is the quiet check at launch — any failure is dropped
    /// on the floor rather than shown.
    func check(announce: Bool) async {
        if case .installing = status { return }
        status = .checking
        do {
            let release = try await latestRelease()
            lastChecked = Date()
            if Self.isNewer(release.version, than: currentVersion) {
                status = .available(release)
                PetController.shared.updateBecameAvailable()
                Debug.log("update available: \(release.version) (running \(currentVersion))")
            } else {
                status = .upToDate
            }
        } catch {
            Debug.log("update check failed: \(error.localizedDescription)")
            status = announce ? .failed(error.localizedDescription) : .idle
        }
    }

    private func latestRelease() async throws -> Release {
        let endpoint = URL(string:
            "https://api.github.com/repos/\(Self.repository)/releases/latest")!
        var request = URLRequest(url: endpoint)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Slicky/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 12

        let (data, response) = try await URLSession.shared.data(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw code == 404 ? UpdateError.noRelease : UpdateError.network(code) }

        let payload = try JSONDecoder().decode(GitHubRelease.self, from: data)
        guard let page = URL(string: payload.html_url) else { throw UpdateError.noRelease }
        // Prefer an asset that looks like the app itself over sidecars (dSYMs).
        let zips = payload.assets.filter { $0.name.lowercased().hasSuffix(".zip") }
        let preferred = zips.first { $0.name.lowercased().contains("slicky") } ?? zips.first
        let zip = preferred.flatMap { URL(string: $0.browser_download_url) }

        return Release(tag: payload.tag_name,
                       version: payload.tag_name.trimmingCharacters(
                           in: CharacterSet(charactersIn: "vV ")),
                       page: page,
                       asset: zip,
                       notes: (payload.body ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
    }

    private struct GitHubRelease: Decodable {
        let tag_name: String
        let html_url: String
        let body: String?
        let assets: [Asset]

        struct Asset: Decodable {
            let name: String
            let browser_download_url: String
        }
    }

    /// Numeric, component-wise: 1.10 beats 1.9.
    static func isNewer(_ candidate: String, than current: String) -> Bool {
        let new = components(candidate), old = components(current)
        for index in 0..<max(new.count, old.count) {
            let a = index < new.count ? new[index] : 0
            let b = index < old.count ? old[index] : 0
            if a != b { return a > b }
        }
        return false
    }

    private static func components(_ version: String) -> [Int] {
        version.trimmingCharacters(in: CharacterSet(charactersIn: "vV "))
            .split(separator: ".")
            .map { Int($0.prefix { $0.isNumber }) ?? 0 }
    }

    // MARK: - Installing

    func install(_ release: Release) async {
        guard let asset = release.asset else {
            NSWorkspace.shared.open(release.page)
            return
        }
        status = .downloading
        do {
            let archive = try await download(asset)
            status = .installing
            let staging = try FileManager.default.url(
                for: .itemReplacementDirectory, in: .userDomainMask,
                appropriateFor: Bundle.main.bundleURL, create: true)
            try unpack(archive, into: staging)
            let app = try locateApp(in: staging)
            try validate(app)
            try swapAndRelaunch(with: app, staging: staging)
        } catch {
            status = .failed(error.localizedDescription)
        }
    }

    private func download(_ url: URL) async throws -> URL {
        var request = URLRequest(url: url)
        request.setValue("Slicky/\(currentVersion)", forHTTPHeaderField: "User-Agent")
        request.timeoutInterval = 120
        let (file, response) = try await URLSession.shared.download(for: request)
        let code = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard code == 200 else { throw UpdateError.network(code) }
        return file
    }

    private func unpack(_ archive: URL, into directory: URL) throws {
        let ditto = Process()
        ditto.executableURL = URL(fileURLWithPath: "/usr/bin/ditto")
        ditto.arguments = ["-x", "-k", archive.path, directory.path]
        try ditto.run()
        ditto.waitUntilExit()
        guard ditto.terminationStatus == 0 else { throw UpdateError.unpackFailed }
    }

    private func locateApp(in directory: URL) throws -> URL {
        let manager = FileManager.default
        let entries = (try? manager.contentsOfDirectory(at: directory,
                                                        includingPropertiesForKeys: nil)) ?? []
        if let app = entries.first(where: { $0.pathExtension == "app" }) { return app }
        for entry in entries where entry.hasDirectoryPath {
            let nested = (try? manager.contentsOfDirectory(at: entry,
                                                           includingPropertiesForKeys: nil)) ?? []
            if let app = nested.first(where: { $0.pathExtension == "app" }) { return app }
        }
        throw UpdateError.notAnApp
    }

    private func validate(_ app: URL) throws {
        guard let bundle = Bundle(url: app),
              bundle.bundleIdentifier == Bundle.main.bundleIdentifier else {
            throw UpdateError.wrongIdentity
        }

        let codesign = Process()
        codesign.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        codesign.arguments = ["--verify", "--strict", app.path]
        codesign.standardOutput = FileHandle.nullDevice
        codesign.standardError = FileHandle.nullDevice
        try codesign.run()
        codesign.waitUntilExit()
        guard codesign.terminationStatus == 0 else { throw UpdateError.badSignature }

        // A valid signature only proves the bundle wasn't tampered with after
        // signing — anyone can sign a bundle claiming this identifier. When the
        // running copy is properly signed, insist the download carries the same
        // team. Ad-hoc dev builds have no team and skip the check.
        if let expected = Self.teamIdentifier(of: Bundle.main.bundleURL) {
            let found = Self.teamIdentifier(of: app)
            guard found == expected else {
                throw UpdateError.wrongTeam(found ?? "nobody")
            }
        }
    }

    private static func teamIdentifier(of bundle: URL) -> String? {
        var code: SecStaticCode?
        guard SecStaticCodeCreateWithPath(bundle as CFURL, [], &code) == errSecSuccess,
              let code else { return nil }
        var information: CFDictionary?
        let flags = SecCSFlags(rawValue: kSecCSSigningInformation)
        guard SecCodeCopySigningInformation(code, flags, &information) == errSecSuccess,
              let details = information as? [String: Any] else { return nil }
        return details[kSecCodeInfoTeamIdentifier as String] as? String
    }

    private func swapAndRelaunch(with app: URL, staging: URL) throws {
        let target = Bundle.main.bundleURL
        let parent = target.deletingLastPathComponent()
        guard FileManager.default.isWritableFile(atPath: parent.path) else {
            throw UpdateError.notWritable(parent.path)
        }

        func quoted(_ url: URL) -> String {
            "\"" + url.path.replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
                .replacingOccurrences(of: "$", with: "\\$") + "\""
        }

        let script = """
        #!/bin/sh
        PID=\(ProcessInfo.processInfo.processIdentifier)
        TARGET=\(quoted(target))
        NEW=\(quoted(app))
        STAGING=\(quoted(staging))
        BACKUP="$TARGET.old"
        while kill -0 "$PID" 2>/dev/null; do sleep 0.2; done
        rm -rf "$BACKUP"
        if mv "$TARGET" "$BACKUP"; then
            if ditto "$NEW" "$TARGET"; then
                rm -rf "$BACKUP"
            else
                rm -rf "$TARGET"
                mv "$BACKUP" "$TARGET"
            fi
        fi
        open "$TARGET"
        rm -rf "$STAGING"
        """

        let scriptURL = staging.appendingPathComponent("slicky-update.sh")
        try script.write(to: scriptURL, atomically: true, encoding: .utf8)

        let shell = Process()
        shell.executableURL = URL(fileURLWithPath: "/bin/sh")
        shell.arguments = [scriptURL.path]
        try shell.run()

        Debug.log("relaunching into the new build")
        NSApp.terminate(nil)
    }
}
