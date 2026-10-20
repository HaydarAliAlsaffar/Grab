import Foundation
import Observation

/// Trim settings for the loaded video. Lives in PanelView.
@MainActor
@Observable
final class TrimState {
    var isOn = false
    private(set) var start = 0.0
    private(set) var end = 0.0
    private(set) var duration = 0.0

    /// Trim is offered only for videos of at least two seconds.
    static func isTrimmable(_ duration: Double?) -> Bool {
        guard let duration, duration.isFinite, duration >= 2, duration < TrimRange.maxSeconds else { return false }
        return true
    }

    /// Off, with the range set to the whole video.
    func reset(duration newDuration: Double?) {
        isOn = false
        duration = Self.isTrimmable(newDuration) ? newDuration ?? 0 : 0
        start = 0
        end = (duration * 10).rounded(.down) / 10
    }

    /// The range to download, or nil when trim is off or the range is not valid.
    var range: TrimRange? {
        guard isOn, duration > 0 else { return nil }
        let r = TrimRange(start: start, end: end).clamped(to: duration)
        return r.isValid ? r : nil
    }

    /// Moves the range. Values are clamped to the video and rounded to tenths,
    /// so the fields, file name and yt-dlp argument always agree. Invalid results are ignored.
    func setRange(start newStart: Double? = nil, end newEnd: Double? = nil) {
        let clamped = TrimRange(start: newStart ?? start, end: newEnd ?? end).clamped(to: duration)
        let lastTenth = (duration * 10).rounded(.down) / 10
        let candidate = TrimRange(start: TrimRange.tenth(clamped.start),
                                  end: min(TrimRange.tenth(clamped.end), lastTenth))
        guard candidate.isValid else { return }
        start = candidate.start
        end = candidate.end
    }

    /// Sets the start from typed text. Out-of-range values are rejected, not clamped. Returns the start now in effect (unchanged if rejected).
    func setStart(_ value: Double) -> Double {
        if (0...duration).contains(value) { setRange(start: value) }
        return start
    }

    func setEnd(_ value: Double) -> Double {
        if (0...duration).contains(value) { setRange(end: value) }
        return end
    }
}
