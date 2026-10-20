import Foundation
import Observation

/// Upgrades yt-dlp with `brew upgrade yt-dlp`, once a week in the background
/// or when asked from Settings.
@MainActor
@Observable
final class Updater {
    enum State: Equatable {
        case idle
        case running(String)
        case done
        case failed(String)
    }

    private(set) var state: State = .idle
    /// Installed yt-dlp version, nil until read.
    private(set) var version: String?
    /// False until the first version read has finished.
    private(set) var versionChecked = false
    private(set) var lastCheck: Date? = Settings.lastUpdateCheck
    @ObservationIgnored private let downloader: Downloader
    @ObservationIgnored private let runner = BrewRunner()
    @ObservationIgnored private var retry: Task<Void, Never>?
    private static let interval: TimeInterval = 7 * 24 * 3600
    private static let retryDelay: Duration = .seconds(600)

    @ObservationIgnored private let installer: Installer

    init(downloader: Downloader, installer: Installer) {
        self.downloader = downloader
        self.installer = installer
    }

    var isRunning: Bool {
        if case .running = state { return true }
        return false
    }

    /// True when the last successful check is missing or older than 7 days.
    var isDue: Bool {
        guard let last = Settings.lastUpdateCheck else { return true }
        return Date().timeIntervalSince(last) > Self.interval
    }

    /// Reads `yt-dlp --version` off the main actor.
    func refreshVersion() async {
        defer { versionChecked = true }
        guard let ytDlp = Tools.locate("yt-dlp") else { version = nil; return }
        version = await Task.detached { Updater.readVersion(ytDlp) }.value
    }

    /// The weekly check. Does nothing (and stores no timestamp) when no update is due,
    /// yt-dlp is not installed, or the first-launch install is running.
    func updateIfDue() {
        guard isDue, !isRunning, Tools.locate("yt-dlp") != nil, !isInstalling else { return }
        update()
    }

    private var isInstalling: Bool {
        if case .installing = installer.state { return true }
        return false
    }

    /// Starts the upgrade now, or in 10 minutes if a download is active or queued.
    func update() {
        guard !isRunning else { return }
        guard Tools.locate("yt-dlp") != nil, !isInstalling else {
            state = .failed("yt-dlp is not installed yet.")
            return
        }
        if downloader.isBusy || downloader.queuedCount > 0 {
            state = .running("Waiting for downloads...")
            retry?.cancel()
            retry = Task { [weak self] in
                try? await Task.sleep(for: Self.retryDelay)
                guard !Task.isCancelled else { return }
                self?.state = .idle
                self?.update()
            }
            return
        }
        retry?.cancel()
        guard let brew = Tools.locate("brew") else {
            state = .failed("Homebrew was not found.")
            return
        }
        state = .running("Starting...")
        let started = runner.run(
            brew: brew, arguments: ["upgrade", "yt-dlp"], skipAutoUpdate: false,
            onLine: { [weak self] line in
                guard let self, case .running = self.state else { return }
                self.state = .running(line)
            },
            onExit: { [weak self] status in self?.finish(status: status) })
        if !started { state = .failed("Could not start Homebrew.") }
    }

    private func finish(status: Int32) {
        Task {
            await refreshVersion()
            if status == 0 {
                Settings.lastUpdateCheck = Date()
                lastCheck = Settings.lastUpdateCheck
                state = .done
            } else {
                DebugLog.write("yt-dlp update failed", lines: ["brew exit \(status)"])
                state = .failed("The update failed.")
            }
        }
    }

    nonisolated private static func readVersion(_ ytDlp: URL) -> String? {
        let process = Process()
        process.executableURL = ytDlp
        process.arguments = ["--version"]
        process.standardInput = FileHandle.nullDevice
        let out = Pipe()
        process.standardOutput = out
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let data = out.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else { return nil }
        let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        return text.isEmpty || text.count > 40 ? nil : text
    }
}
