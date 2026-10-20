import SwiftUI
import AppKit

/// Objects the app delegate needs, set by GrabApp before launch finishes.
@MainActor
enum Services {
    static var actions: ShortcutActions?
    static var updater: Updater?
    static let hotKeys = HotKeys()
}

/// Sets up notifications before anything can post one, and registers the global shortcuts.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationWillFinishLaunching(_ notification: Notification) {
        Notifier.shared.install()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        Services.hotKeys.onVideo = { Services.actions?.handle(.video) }
        Services.hotKeys.onAudio = { Services.actions?.handle(.audio) }
        Services.hotKeys.reload()
        startUpdateChecks()
    }

    /// Checks at launch, then every hour. The updater only runs when the last check is over a week old.
    private func startUpdateChecks() {
        Self.checkForUpdate()
        // The run loop keeps a scheduled timer alive for the life of the app.
        let timer = Timer.scheduledTimer(withTimeInterval: 3600, repeats: true) { _ in
            Task { @MainActor in AppDelegate.checkForUpdate() }
        }
        timer.tolerance = 300
    }

    private static func checkForUpdate() {
        Services.updater?.updateIfDue()
    }
}

@main
struct GrabApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var installer: Installer
    @State private var recents: RecentStore
    @State private var downloader: Downloader
    @State private var updater: Updater

    init() {
        let recents = RecentStore()
        let downloader = Downloader(recents: recents, notifier: .shared)
        _recents = State(initialValue: recents)
        _downloader = State(initialValue: downloader)
        let installer = Installer()
        _installer = State(initialValue: installer)
        let updater = Updater(downloader: downloader, installer: installer)
        _updater = State(initialValue: updater)
        Services.updater = updater
        Services.actions = ShortcutActions(downloader: downloader, notifier: .shared)
    }

    var body: some Scene {
        MenuBarExtra {
            PanelView(installer: installer, downloader: downloader, recents: recents)
        } label: {
            MenuBarLabel(downloader: downloader)
        }
        .menuBarExtraStyle(.window)

        SwiftUI.Settings { SettingsView(updater: updater) }
    }
}
