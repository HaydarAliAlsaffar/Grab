import Foundation

enum ProcessOutput {
    /// `message` without a leading `prefix`, trimmed. Empty when nothing is left.
    static func detail(of message: String, droppingPrefix prefix: String) -> String {
        var body = message.trimmingCharacters(in: .whitespacesAndNewlines)
        if body.hasPrefix(prefix) { body = String(body.dropFirst(prefix.count)) }
        return body.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `fallback` plus a cleaned first ERROR line from yt-dlp stderr.
    /// Never returns paths, tracebacks, or long text.
    static func message(fromStderr data: Data, fallback: String) -> String {
        let text = String(decoding: data, as: UTF8.self)
        if text.contains("Traceback") { return fallback }
        let line = text.split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .first { $0.hasPrefix("ERROR:") }
        guard let line else { return fallback }
        var detail = String(line.dropFirst("ERROR:".count)).trimmingCharacters(in: .whitespaces)
        // Strip a leading "[extractor] id: " tag.
        detail = detail.replacingOccurrences(of: #"^\[[^\]]+\] \S+: "#, with: "", options: .regularExpression)
        // Cut at the first " Please report" or ";".
        if let r = detail.range(of: " Please report") { detail = String(detail[..<r.lowerBound]) }
        if let r = detail.range(of: ";") { detail = String(detail[..<r.lowerBound]) }
        // Cut at " Use --" so hints like "Use --list-formats" never reach the UI.
        if let r = detail.range(of: " Use --") { detail = String(detail[..<r.lowerBound]) }
        detail = detail.replacingOccurrences(of: "\u{2014}", with: " - ")
            .replacingOccurrences(of: "\u{2013}", with: " - ")
            .trimmingCharacters(in: .whitespaces)
        // Never show anything that looks like a local path.
        for marker in ["/Users/", "/opt/", "/private/", "/Library/", "/var/"] where detail.contains(marker) {
            return fallback
        }
        if detail.isEmpty { return fallback }
        if detail.count > 120 { detail = String(detail.prefix(120)) + "..." }
        return fallback + " " + detail
    }
}
