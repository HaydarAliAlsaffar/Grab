import Foundation

/// A start and end time in seconds for a trimmed download.
struct TrimRange: Sendable, Equatable {
    /// The smallest clip yt-dlp is asked for.
    static let minLength = 1.0

    var start: Double
    var end: Double

    var length: Double { end - start }

    /// Largest time accepted, matching the parser and formatter.
    static let maxSeconds = 1_000_000.0

    /// Both ends rounded to tenths of a second. Text, file label and yt-dlp argument all use these.
    var rounded: TrimRange {
        TrimRange(start: Self.tenth(start), end: Self.tenth(end))
    }

    /// Whole tenths of a second, so length checks avoid floating point error.
    static func tenthCount(_ value: Double) -> Int { Int((value * 10).rounded()) }

    static func tenth(_ value: Double) -> Double { (value * 10).rounded() / 10 }

    /// Finite, in 0..<1,000,000 and at least `minLength` long, judged after rounding to tenths.
    var isValid: Bool {
        let r = rounded
        return r.start.isFinite && r.end.isFinite && r.start >= 0 && r.end < Self.maxSeconds && r.start < Self.maxSeconds
            && Self.tenthCount(r.end) - Self.tenthCount(r.start) >= Self.tenthCount(Self.minLength)
    }

    /// Both ends moved into 0...duration. May leave an invalid range if the video is too short.
    func clamped(to duration: Double) -> TrimRange {
        guard duration.isFinite, duration > 0, start.isFinite, end.isFinite else {
            return TrimRange(start: 0, end: 0)
        }
        return TrimRange(start: min(max(start, 0), duration), end: min(max(end, 0), duration))
    }

    /// The `--download-sections` value, for example "*12.5-83". Built only from numbers.
    var sectionArgument: String {
        let r = rounded
        return "*\(Self.number(r.start))-\(Self.number(r.end))"
    }

    /// For file names, e.g. "0.10-0.15". Colons become dots. Built only from numbers.
    var fileLabel: String {
        let r = rounded
        let a = Self.format(r.start, tenths: true).replacingOccurrences(of: ":", with: ".")
        let b = Self.format(r.end, tenths: true).replacingOccurrences(of: ":", with: ".")
        return "\(a)-\(b)"
    }

    /// Whole seconds, or one decimal when there is a fraction.
    private static func number(_ seconds: Double) -> String {
        guard seconds.isFinite, seconds >= 0, seconds < maxSeconds else { return "0" }
        let rounded = tenth(seconds)
        return rounded == rounded.rounded()
            ? String(Int(rounded))
            : String(format: "%.1f", rounded)
    }

    // MARK: - Time text

    /// "83", "1:23" or "1:02:03", with optional decimals on the seconds (".5").
    /// Returns nil for anything else.
    static func parse(_ text: String) -> Double? {
        let parts = text.trimmingCharacters(in: .whitespaces).split(separator: ":", omittingEmptySubsequences: false)
        guard (1...3).contains(parts.count) else { return nil }
        var total = 0.0
        for (i, part) in parts.enumerated() {
            let isLast = i == parts.count - 1
            guard isPlainNumber(part, allowDecimals: isLast), let value = Double(part) else { return nil }
            // Minutes and seconds below 60 once an hour or minute part is present.
            if i > 0 && value >= 60 { return nil }
            total = total * 60 + value
        }
        return total.isFinite && total < Self.maxSeconds ? total : nil
    }

    /// Digits only, plus one optional ".digits" part. No signs, no exponents.
    private static func isPlainNumber(_ s: Substring, allowDecimals: Bool) -> Bool {
        let pieces = s.split(separator: ".", omittingEmptySubsequences: false)
        guard pieces.count == 1 || (allowDecimals && pieces.count == 2) else { return false }
        guard let whole = pieces.first, !whole.isEmpty || pieces.count == 2 else { return false }
        return pieces.allSatisfy { $0.allSatisfy { $0.isASCII && $0.isNumber } }
            && !(pieces.count == 2 && whole.isEmpty && pieces[1].isEmpty)
    }

    /// "m:ss" or "h:mm:ss". `tenths` adds one decimal when there is a fraction.
    static func format(_ seconds: Double, tenths: Bool = false) -> String {
        guard seconds.isFinite, seconds >= 0, seconds < maxSeconds else { return "0:00" }
        let value = tenths ? (seconds * 10).rounded() / 10 : seconds.rounded()
        let whole = Int(value)
        let h = whole / 3600, m = (whole % 3600) / 60, s = whole % 60
        var text = h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
        if tenths, value != value.rounded(.down) {
            text += "." + String(Int(((value - value.rounded(.down)) * 10).rounded()))
        }
        return text
    }
}
