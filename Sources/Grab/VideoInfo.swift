import Foundation

/// Subset of the JSON printed by `yt-dlp -J`. Untrusted input, so every field
/// is decoded leniently: a wrong-typed value becomes nil instead of failing.
struct VideoInfo: Sendable, Equatable {
    struct Format: Sendable, Equatable {
        let height: Int?
        let vcodec: String?
    }

    let title: String?
    let duration: Double?
    let thumbnail: String?
    let type: String?
    let extractorKey: String?
    let formats: [Format]?
    private let uploaderName: String?
    private let channel: String?
    private let uploaderID: String?

    var isPlaylist: Bool { type == "playlist" }

    /// True for YouTube links (extractor key starts with "Youtube"). SponsorBlock only covers these.
    var isYouTube: Bool { extractorKey?.lowercased().hasPrefix("youtube") ?? false }

    var displayTitle: String {
        let t = title?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return t.isEmpty ? "Untitled" : t
    }

    /// uploader, falling back to channel, then uploader_id.
    var uploader: String? {
        for candidate in [uploaderName, channel, uploaderID] {
            if let c = candidate?.trimmingCharacters(in: .whitespacesAndNewlines), !c.isEmpty {
                return c
            }
        }
        return nil
    }

    /// Distinct video heights from 2160 down to 480. Only vcodec "none" is excluded.
    var availableHeights: [Int] {
        let heights = (formats ?? []).compactMap { f -> Int? in
            guard let h = f.height, (480...2160).contains(h), f.vcodec != "none" else { return nil }
            return h
        }
        return Array(Set(heights)).sorted(by: >)
    }

    /// True when a format at the height `-f` will pick (largest available <= height)
    /// has a codec MOV can hold without re-encoding. Unknown heights count as playable.
    func hasPlayableVideo(atOrBelow height: Int) -> Bool {
        guard let target = availableHeights.first(where: { $0 <= height }) else { return true }
        let prefixes = ["avc1", "h264", "hvc1", "hev1", "h265"]
        return (formats ?? []).contains { f in
            guard f.height == target, let v = f.vcodec?.lowercased() else { return false }
            return prefixes.contains { v.hasPrefix($0) }
        }
    }

    /// Thumbnail URL, only if it is http or https.
    var thumbnailURL: URL? {
        guard let thumbnail, let url = URL(string: thumbnail),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https" else { return nil }
        return url
    }

    /// "12:34" or "1:02:03". Nil when the duration is missing or invalid.
    var formattedDuration: String? {
        guard let duration, duration.isFinite, duration >= 0, duration < TrimRange.maxSeconds else { return nil }
        return TrimRange.format(duration)
    }
}

fileprivate struct DecodeKey: CodingKey {
    var stringValue: String
    var intValue: Int? { nil }
    init(_ s: String) { stringValue = s }
    init?(stringValue: String) { self.stringValue = stringValue }
    init?(intValue: Int) { nil }
}

extension VideoInfo: Decodable {
    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: DecodeKey.self)
        title = c.string("title")
        uploaderName = c.string("uploader")
        channel = c.string("channel")
        uploaderID = c.string("uploader_id")
        duration = c.number("duration")
        thumbnail = c.string("thumbnail")
        type = c.string("_type")
        extractorKey = c.string("extractor_key")
        // Decode each format on its own so one odd entry cannot blank the rest.
        if var list = try? c.nestedUnkeyedContainer(forKey: DecodeKey("formats")) {
            var result: [Format] = []
            while !list.isAtEnd {
                if let f = try? list.nestedContainer(keyedBy: DecodeKey.self) {
                    let h = f.number("height")
                    result.append(Format(height: h.map { Int($0) }, vcodec: f.string("vcodec")))
                } else {
                    _ = try? list.decode(Skip.self)
                }
            }
            formats = result
        } else {
            formats = nil
        }
    }

    private struct Skip: Decodable {
        init(from decoder: Decoder) throws {}
    }
}

fileprivate extension KeyedDecodingContainer where K == DecodeKey {
    func string(_ key: String) -> String? {
        try? decodeIfPresent(String.self, forKey: DecodeKey(key))
    }

    /// Accepts Int or Double. Non-finite or huge values become nil.
    func number(_ key: String) -> Double? {
        let k = DecodeKey(key)
        if let d = try? decodeIfPresent(Double.self, forKey: k), d.isFinite, abs(d) < 1e9 { return d }
        return nil
    }
}
