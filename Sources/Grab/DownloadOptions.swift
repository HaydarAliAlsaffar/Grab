import Foundation

enum VideoFormat: String, CaseIterable, Sendable {
    case mp4, mov
    var displayName: String { rawValue.uppercased() }
}

enum AudioFormat: String, CaseIterable, Sendable {
    case m4a, mp3
    var displayName: String { rawValue.uppercased() }
}

enum Quality: Hashable, Sendable {
    case height(Int)
    case audioOnly

    var label: String {
        switch self {
        case .height(let h): "\(h)p"
        case .audioOnly: "Audio only"
        }
    }
}

struct DownloadRequest: Sendable {
    /// The validated link (http or https).
    let url: URL
    /// Shown in Recent and notifications.
    let title: String
    let quality: Quality
    let videoFormat: VideoFormat
    let audioFormat: AudioFormat
    let saveFolder: URL
    /// True when MOV was chosen but the picked height has no MOV-friendly codec.
    var needsRecode = false
    /// Cut sponsor segments (YouTube only).
    var skipSponsors = false
    /// Nil downloads the whole video.
    var trim: TrimRange?
}
