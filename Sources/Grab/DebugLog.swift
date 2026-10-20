import Foundation

/// Private diagnostic log at ~/Library/Logs/Grab/grab.log. Never shown in the UI.
enum DebugLog {
    private static let maxBytes = 1_000_000

    /// Appends one entry: a timestamped title line, the lines, then a blank line.
    /// Never throws. Errors are ignored.
    nonisolated static func write(_ title: String, lines: [String]) {
        let fm = FileManager.default
        guard let library = fm.urls(for: .libraryDirectory, in: .userDomainMask).first else { return }
        let dir = library.appendingPathComponent("Logs/Grab", isDirectory: true)
        let file = dir.appendingPathComponent("grab.log")
        try? fm.createDirectory(at: dir, withIntermediateDirectories: true)

        // Keep the file small: start over once it grows past the limit.
        let size = (try? fm.attributesOfItem(atPath: file.path)[.size] as? Int) ?? 0
        if size > maxBytes { try? Data().write(to: file) }

        let stamp = ISO8601DateFormatter().string(from: Date())
        let text = ([stamp + " " + title] + lines + ["", ""]).joined(separator: "\n")
        guard let data = text.data(using: .utf8) else { return }
        if !fm.fileExists(atPath: file.path) { fm.createFile(atPath: file.path, contents: nil) }
        guard let handle = try? FileHandle(forWritingTo: file) else { return }
        defer { try? handle.close() }
        _ = try? handle.seekToEnd()
        try? handle.write(contentsOf: data)
    }

    /// Lines of yt-dlp output, empty ones dropped.
    nonisolated static func lines(of data: Data) -> [String] {
        String(decoding: data, as: UTF8.self)
            .split(whereSeparator: \.isNewline).map(String.init)
    }
}
