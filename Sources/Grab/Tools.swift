import Foundation

/// Locations of the external tools Grab depends on.
/// Only fixed Homebrew directories are checked. No PATH lookup, no shell.
struct Tools: Equatable, Sendable {
    let ytDlp: URL?
    let ffmpeg: URL?
    let brew: URL?

    static let searchDirectories = ["/opt/homebrew/bin", "/usr/local/bin"]

    var hasAll: Bool { ytDlp != nil && ffmpeg != nil }

    /// Human readable names of the tools that are not installed.
    var missing: [String] {
        var names: [String] = []
        if ytDlp == nil { names.append("yt-dlp") }
        if ffmpeg == nil { names.append("ffmpeg") }
        return names
    }

    static func detect() -> Tools {
        Tools(
            ytDlp: locate("yt-dlp"),
            ffmpeg: locate("ffmpeg"),
            brew: locate("brew")
        )
    }

    static func locate(_ name: String) -> URL? {
        let fm = FileManager.default
        for dir in searchDirectories {
            let path = dir + "/" + name
            if fm.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }
}
