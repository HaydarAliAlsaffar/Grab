import Foundation

/// Runs one Homebrew command with a fixed argument list (no shell) and reports the
/// latest output line. Shared by the installer and the yt-dlp updater.
@MainActor
final class BrewRunner {
    private var process: Process?
    private var pipe: Pipe?

    /// Starts brew. `onLine` gets short progress text, `onExit` the exit status.
    /// Returns false if the process could not be started.
    func run(brew: URL, arguments: [String], skipAutoUpdate: Bool,
             onLine: @escaping @MainActor (String) -> Void,
             onExit: @escaping @MainActor (Int32) -> Void) -> Bool {
        let process = Process()
        process.executableURL = brew
        process.arguments = arguments
        var env = ProcessInfo.processInfo.environment
        if skipAutoUpdate { env["HOMEBREW_NO_AUTO_UPDATE"] = "1" }
        env["NONINTERACTIVE"] = "1"
        process.environment = env
        process.standardInput = FileHandle.nullDevice

        // One pipe for both stdout and stderr.
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe

        pipe.fileHandleForReading.readabilityHandler = { handle in
            let data = handle.availableData
            if data.isEmpty {
                handle.readabilityHandler = nil
                return
            }
            guard let line = BrewRunner.lastLine(of: data) else { return }
            Task { @MainActor in onLine(line) }
        }

        process.terminationHandler = { [weak self] proc in
            let status = proc.terminationStatus
            Task { @MainActor in
                self?.cleanUp()
                onExit(status)
            }
        }

        do {
            try process.run()
            self.process = process
            self.pipe = pipe
            return true
        } catch {
            pipe.fileHandleForReading.readabilityHandler = nil
            return false
        }
    }

    private func cleanUp() {
        pipe?.fileHandleForReading.readabilityHandler = nil
        process?.terminationHandler = nil
        pipe = nil
        process = nil
    }

    /// Last non-empty line of a chunk of output, trimmed and shortened.
    nonisolated private static func lastLine(of data: Data) -> String? {
        let text = String(decoding: data, as: UTF8.self)
        let line = text
            .split(whereSeparator: { $0 == "\n" || $0 == "\r" })
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last { !$0.isEmpty }
        guard let line else { return nil }
        return line.count > 80 ? String(line.prefix(80)) + "..." : line
    }
}
