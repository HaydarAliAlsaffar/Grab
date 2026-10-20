import Foundation
import Observation

/// Runs `brew install yt-dlp ffmpeg` and reports short progress text.
@MainActor
@Observable
final class Installer {
    enum State: Equatable {
        case idle
        case installing(String)
        case failed(String)
        case done
    }

    private(set) var state: State = .idle
    /// Latest tool detection result. Call refresh() to re-check.
    private(set) var tools = Tools.detect()
    @ObservationIgnored private let runner = BrewRunner()

    func refresh() {
        tools = Tools.detect()
    }

    func install() {
        if case .installing = state { return }
        refresh()
        guard let brew = tools.brew else {
            state = .failed("Homebrew was not found.")
            return
        }
        state = .installing("Starting...")
        let started = runner.run(
            brew: brew, arguments: ["install", "yt-dlp", "ffmpeg"], skipAutoUpdate: true,
            onLine: { [weak self] line in self?.updateProgress(line) },
            onExit: { [weak self] status in self?.finish(status: status) })
        if !started { state = .failed("Could not start Homebrew.") }
    }

    private func updateProgress(_ line: String) {
        if case .installing = state { state = .installing(line) }
    }

    private func finish(status: Int32) {
        refresh()
        if tools.hasAll {
            state = .done
        } else {
            state = .failed(status != 0 ? "Homebrew reported an error." : "The tools were not found after install.")
        }
    }
}
