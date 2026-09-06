import AppKit
import ServiceManagement
import SwiftUI
import UniformTypeIdentifiers

final class SettingsWindowController: NSWindowController {
    init(controller: PetController) {
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 520, height: 560),
            styleMask: [.titled, .closable],
            backing: .buffered, defer: false)
        window.title = "Slicky"
        window.isReleasedWhenClosed = false
        window.center()
        window.contentViewController = NSHostingController(
            rootView: SettingsView(controller: controller))
        super.init(window: window)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) { fatalError() }
}

// MARK: - Window

struct SettingsView: View {
    @ObservedObject var controller: PetController

    enum Tab: Hashable, CaseIterable { case apps, look, behaviour, about }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            // A plain segmented control rather than TabView: on recent macOS a
            // SwiftUI TabView hoists its tabs into the title bar and collapses
            // them into an overflow menu, which is not what a settings window
            // should look like.
            Picker("", selection: $controller.settingsTab) {
                Text("Apps").tag(Tab.apps)
                Text("Look").tag(Tab.look)
                Text("Behaviour").tag(Tab.behaviour)
                Text("About Slicky").tag(Tab.about)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .padding(.horizontal, 18)
            .padding(.vertical, 12)

            Divider()

            page
                .padding(.horizontal, 18)
                .padding(.vertical, 14)
                .frame(maxHeight: .infinity, alignment: .top)

            Divider()
            footer
        }
        .frame(width: 520, height: 580)
    }

    @ViewBuilder private var page: some View {
        switch controller.settingsTab {
        case .apps: AppsTab(controller: controller)
        case .look: LookTab(controller: controller)
        case .behaviour: BehaviourTab(controller: controller)
        case .about: AboutTab(controller: controller)
        }
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button {
                SettingsControls.open(SettingsControls.coffee)
            } label: {
                Label("Buy me a coffee", systemImage: "cup.and.saucer.fill")
            }
            .help("I love coffee. Who doesn't.")

            Button {
                SettingsControls.open(SettingsControls.repo)
            } label: {
                Label("Star him on GitHub", systemImage: "star.fill")
            }
            .help("It costs you one click and makes his day")

            Spacer()
            Button("Quit Slicky") { NSApp.terminate(nil) }
        }
        .controlSize(.small)
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }

    private var header: some View {
        HStack(spacing: 12) {
            RobotView(model: controller.model, palette: controller.config.palette)
                .frame(width: 48, height: 74)
            VStack(alignment: .leading, spacing: 1) {
                Text("Slicky").font(.headline)
                Text("Version \(SettingsControls.version) · drag him anywhere, "
                     + "right-click for the menu")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            Spacer()
            Button("Jump") { controller.hop() }
            Button("Say hi") { controller.wave() }
            Button("Selfie") { controller.takeSelfie() }
        }
        .padding(.horizontal, 18)
        .padding(.vertical, 10)
    }
}

// MARK: - Tabs

struct AppsTab: View {
    @ObservedObject var controller: PetController

    var body: some View {
        SettingsPage {
            SettingsCard("Click actions") {
                AppRow(title: "Single click", action: $controller.config.singleClick)
                Divider()
                AppRow(title: "Double click", action: $controller.config.doubleClick)
                Divider()
                Label("Drag any app onto the robot to bind it — he'll ask which gesture.",
                      systemImage: "hand.draw")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            SettingsCard("Right-click menu") {
                if controller.config.menuApps.isEmpty {
                    Text("No extra apps yet.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                ScrollView {
                    VStack(spacing: 8) {
                        ForEach(controller.config.menuApps) { app in
                            HStack(spacing: 10) {
                                Image(nsImage: app.icon).resizable().frame(width: 18, height: 18)
                                Text(app.name)
                                if app.resolvedURL == nil {
                                    Text("missing").foregroundStyle(.red).font(.caption)
                                }
                                Spacer()
                                Button {
                                    controller.config.menuApps.removeAll { $0.id == app.id }
                                } label: {
                                    Image(systemName: "minus.circle.fill")
                                }
                                .buttonStyle(.plain)
                                .foregroundStyle(.secondary)
                            }
                        }
                    }
                }
                .frame(maxHeight: 132)

                Button("Add App…") {
                    if let picked = SettingsControls.pickApp() {
                        controller.config.menuApps.append(picked)
                    }
                }
            }
        }
    }
}

struct LookTab: View {
    @ObservedObject var controller: PetController

    var body: some View {
        SettingsPage {
            SettingsCard("Presets") {
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 78), spacing: 10)], spacing: 10) {
                    ForEach(Palette.presets, id: \.name) { preset in
                        PaletteChip(palette: preset,
                                    selected: controller.config.palette == preset) {
                            controller.config.palette = preset
                        }
                    }
                }
                Text("Sunflower, Linen and Sky are seeing summer off.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            SettingsCard("Custom colours") {
                ColorPicker("Shell", selection: colour(\.shell), supportsOpacity: false)
                ColorPicker("Accent", selection: colour(\.accent), supportsOpacity: false)
                ColorPicker("Glow", selection: colour(\.glow), supportsOpacity: false)
                DisclosureGroup("More colours") {
                    ColorPicker("Outline", selection: colour(\.outline), supportsOpacity: false)
                    ColorPicker("Screen", selection: colour(\.visor), supportsOpacity: false)
                }
            }

            SettingsCard("Size") {
                MarkedSlider(label: "Size", value: $controller.config.scale,
                             range: 0.45...1.6, stops: MarkedSlider.fish,
                             tolerance: 0.025) { String(format: "%.2f×", $0) }
                Text("Sizes are fish. He is aware, and has made peace with it.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func colour(_ keyPath: WritableKeyPath<Palette, RGB>) -> Binding<Color> {
        Binding(get: { controller.config.palette[keyPath: keyPath].color },
                set: { newValue in
                    controller.config.palette[keyPath: keyPath] = RGB(color: newValue)
                    controller.config.palette.name = "Custom"
                })
    }
}

struct BehaviourTab: View {
    @ObservedObject var controller: PetController
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var loginError: String?
    @State private var accessibilityTrusted = TypingWatcher.isTrusted

    var body: some View {
        SettingsPage {
            SettingsCard("Hopping") {
                Toggle("Hop around on its own", isOn: $controller.config.wander)
                LabeledSlider(label: "Hop every", value: $controller.config.interval,
                              range: 5...180, unit: "s", prefix: "~")
                Toggle("Randomise the wait, ±π", isOn: $controller.config.randomizeInterval)
                Text(controller.config.randomizeInterval
                     ? String(format: "About %.0f seconds, give or take a π. "
                              + "π isn't just a good reason, it's a great reason.",
                              controller.config.interval)
                     : String(format: "Exactly %.0f seconds, every time, like a "
                              + "metronome with a face.", controller.config.interval))
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Divider()
                Toggle("Sometimes walk instead of hopping", isOn: $controller.config.walks)
                Text("He only walks sideways. Stairs are a problem for a later version.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                Divider()
                MarkedSlider(label: "Hop distance", value: $controller.config.hopDistance,
                             range: 80...900, stops: MarkedSlider.planets,
                             tolerance: 12) { String(format: "%.0fpt", $0) }
                Text("Named for places he will never visit. Trips scale with his "
                     + "size, so a Guppy goes a shorter way than a Whale does.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }

            SettingsCard("On screen") {
                Toggle("Eyes follow the pointer", isOn: $controller.config.followCursor)
                Toggle("Stay above full-screen apps", isOn: $controller.config.aboveEverything)
                Divider()
                Toggle("Get out of the way when I'm typing",
                       isOn: $controller.config.dodgeTyping)
                    .onChange(of: controller.config.dodgeTyping) { _, enabled in
                        if enabled { TypingWatcher.requestTrust() }
                        accessibilityTrusted = TypingWatcher.isTrusted
                    }
                if controller.config.dodgeTyping {
                    if accessibilityTrusted {
                        Text("He hops aside when the text cursor ends up under him. "
                             + "Only the fact that you typed is used — never what.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    } else {
                        Text("Needs Accessibility access: the text cursor's position "
                             + "is only readable through it.")
                            .font(.callout)
                            .foregroundStyle(.orange)
                            .fixedSize(horizontal: false, vertical: true)
                        HStack {
                            Button("Open Accessibility Settings") {
                                TypingWatcher.openAccessibilitySettings()
                            }
                            Button("Re-check") { accessibilityTrusted = TypingWatcher.isTrusted }
                        }
                    }
                }
            }

            SettingsCard("Startup") {
                Toggle("Launch at login", isOn: $launchAtLogin)
                    .onChange(of: launchAtLogin) { _, enabled in setLaunchAtLogin(enabled) }
                if let loginError {
                    Text(loginError).font(.callout).foregroundStyle(.red)
                } else {
                    Text("Move Slicky.app to /Applications before turning this on.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .onAppear { accessibilityTrusted = TypingWatcher.isTrusted }
    }

    private func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            loginError = nil
        } catch {
            loginError = "Couldn't update login item: \(error.localizedDescription)"
            launchAtLogin = SMAppService.mainApp.status == .enabled
        }
    }
}

struct AboutTab: View {
    @ObservedObject var controller: PetController
    @ObservedObject private var updater = Updater.shared

    private var statusText: String {
        switch updater.status {
        case .idle: return "Version \(updater.currentVersion)."
        case .checking: return "Checking for updates…"
        case .upToDate: return "Version \(updater.currentVersion) — you're up to date."
        case .available(let release): return "Version \(release.version) is available."
        case .downloading: return "Downloading the new version…"
        case .installing: return "Installing — Slicky will restart."
        case .failed(let reason): return "Couldn't check: \(reason)"
        }
    }

    private var statusIsError: Bool {
        if case .failed = updater.status { return true }
        return false
    }

    var body: some View {
        SettingsPage {
            SettingsCard("Slicky \(SettingsControls.version)") {
                Text("A small robot that lives on your desktop, hops around when "
                     + "he feels like it, and opens the apps you hand him.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                Text("Source, issues and the longer story are on GitHub — the "
                     + "button below stars him, which he pretends not to care about.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            SettingsCard("Updates") {
                HStack(spacing: 10) {
                    Text(statusText)
                        .font(.callout)
                        .foregroundStyle(statusIsError ? AnyShapeStyle(.red)
                                                       : AnyShapeStyle(.secondary))
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 8)
                    if updater.isBusy { ProgressView().controlSize(.small) }
                    Button("Check Now") {
                        Task { await updater.check(announce: true) }
                    }
                    .disabled(updater.isBusy)
                }
                if let release = updater.availableRelease {
                    if !release.notes.isEmpty {
                        Text(release.notes)
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .lineLimit(4)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    HStack {
                        Button("Install and Restart") {
                            Task { await updater.install(release) }
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(updater.isBusy)
                        Button("Release Notes") { NSWorkspace.shared.open(release.page) }
                        Spacer()
                        Button("Not Now") { controller.updateInstalledOrDismissed() }
                    }
                }
            }

        }
    }
}

// MARK: - Shared pieces

struct SettingsPage<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) { content }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(4)
        }
    }
}

struct SettingsCard<Content: View>: View {
    let title: String
    @ViewBuilder var content: Content

    init(_ title: String, @ViewBuilder content: () -> Content) {
        self.title = title
        self.content = content()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased())
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 10) { content }
                .padding(14)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(.quaternary.opacity(0.35), in: RoundedRectangle(cornerRadius: 10))
        }
    }
}

struct AppRow: View {
    let title: String
    @Binding var action: AppAction?

    var body: some View {
        HStack(spacing: 10) {
            Text(title).frame(width: 88, alignment: .leading)
            if let app = action {
                Image(nsImage: app.icon).resizable().frame(width: 20, height: 20)
                Text(app.name)
                if app.resolvedURL == nil {
                    Text("missing").foregroundStyle(.red).font(.caption)
                }
            } else {
                Text("Nothing yet").foregroundStyle(.secondary)
            }
            Spacer()
            Button("Choose…") {
                if let picked = SettingsControls.pickApp() { action = picked }
            }
            if action != nil {
                Button("Clear") { action = nil }
            }
        }
    }
}

/// Free anywhere along the line, but a few points on it have names, and the
/// name lights up when he lands on one.
struct MarkedSlider: View {
    struct Stop: Identifiable {
        var id: String { name }
        let name: String
        let value: Double
    }

    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let stops: [Stop]
    let tolerance: Double
    let format: (Double) -> String

    private var landedOn: Stop? {
        stops.first { abs(value - $0.value) < tolerance }
    }

    private func fraction(_ stop: Stop) -> Double {
        (stop.value - range.lowerBound) / (range.upperBound - range.lowerBound)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 10) {
                Text(label).frame(width: 88, alignment: .leading)
                Slider(value: $value, in: range)
                Text(landedOn?.name ?? format(value))
                    .font(.callout)
                    .monospacedDigit()
                    .lineLimit(1)
                    .frame(width: 80, alignment: .trailing)
                    .foregroundStyle(landedOn == nil
                                     ? AnyShapeStyle(.secondary)
                                     : AnyShapeStyle(Color.accentColor))
            }
            GeometryReader { proxy in
                // The thumb keeps its centre inside the track by about its own
                // radius, so the names line up with where it can actually stop.
                let inset = 9.0
                let span = max(1, proxy.size.width - inset * 2)
                ForEach(stops) { stop in
                    let hit = landedOn?.name == stop.name
                    Button(stop.name) { value = stop.value }
                        .buttonStyle(.plain)
                        .font(.caption.weight(hit ? .bold : .regular))
                        .foregroundStyle(hit ? AnyShapeStyle(Color.accentColor)
                                             : AnyShapeStyle(.secondary))
                        .fixedSize()
                        .position(x: inset + span * fraction(stop), y: 8)
                }
            }
            .frame(height: 17)
            .padding(.leading, 98)      // clear the label column
            .padding(.trailing, 90)     // stop before the readout
        }
    }

    static let fish: [Stop] = [
        Stop(name: "Guppy", value: 0.55),
        Stop(name: "Trout", value: 0.90),
        Stop(name: "Mermaid", value: 1.20),
        Stop(name: "Whale", value: 1.50),
    ]

    /// Places from the Guide, in rough order of how far you'd have to go.
    static let planets: [Stop] = [
        Stop(name: "Traal", value: 140),
        Stop(name: "Damogran", value: 320),
        Stop(name: "Krikkit", value: 550),
        Stop(name: "Magrathea", value: 820),
    ]
}

struct LabeledSlider: View {
    let label: String
    @Binding var value: Double
    let range: ClosedRange<Double>
    let unit: String
    var decimals: Int = 0
    var prefix: String = ""

    var body: some View {
        HStack(spacing: 10) {
            Text(label).frame(width: 88, alignment: .leading)
            Slider(value: $value, in: range)
            Text(String(format: "\(prefix)%.\(decimals)f\(unit)", value))
                .monospacedDigit()
                .frame(width: 52, alignment: .trailing)
                .foregroundStyle(.secondary)
        }
    }
}

struct PaletteChip: View {
    let palette: Palette
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 5) {
                ZStack {
                    RoundedRectangle(cornerRadius: 8)
                        .fill(LinearGradient(gradient: palette.shellGradient,
                                             startPoint: .topLeading, endPoint: .bottomTrailing))
                    HStack(spacing: 4) {
                        Circle().fill(palette.accent.color).frame(width: 9, height: 9)
                        Circle().fill(palette.glow.color).frame(width: 9, height: 9)
                    }
                }
                .frame(height: 34)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(selected ? Color.accentColor
                                               : palette.outline.color.opacity(0.35),
                                      lineWidth: selected ? 2.5 : 1)
                )
                Text(palette.name)
                    .font(.caption)
                    .foregroundStyle(selected ? .primary : .secondary)
            }
        }
        .buttonStyle(.plain)
    }
}

enum SettingsControls {
    static let repo = "https://github.com/ananthasharma/Slicky"
    static let coffee = "https://buymeacoffee.com/ananthasharma"

    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
    }

    static func open(_ address: String) {
        guard let url = URL(string: address) else { return }
        NSWorkspace.shared.open(url)
    }

    @MainActor
    static func pickApp() -> AppAction? {
        let panel = NSOpenPanel()
        panel.title = "Choose an app"
        panel.directoryURL = URL(fileURLWithPath: "/Applications")
        panel.allowedContentTypes = [.application]
        panel.allowsMultipleSelection = false
        panel.canChooseDirectories = false
        NSApp.activate(ignoringOtherApps: true)
        guard panel.runModal() == .OK, let url = panel.url else { return nil }
        return AppAction(url: url)
    }
}
