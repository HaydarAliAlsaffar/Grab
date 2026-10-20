import Foundation
import Carbon.HIToolbox

/// Keys and defaults for values stored with @AppStorage. The app's stored settings.
enum Settings {
    enum Key {
        static let saveFolder = "saveFolder"
        static let defaultHeight = "defaultHeight"
        static let defaultVideoFormat = "defaultVideoFormat"
        static let defaultAudioFormat = "defaultAudioFormat"
        static let skipSponsors = "skipSponsors"
        static let videoHotKeyCode = "videoHotKeyCode"
        static let videoHotKeyModifiers = "videoHotKeyModifiers"
        static let audioHotKeyCode = "audioHotKeyCode"
        static let audioHotKeyModifiers = "audioHotKeyModifiers"
        static let lastUpdateCheck = "lastUpdateCheck"
        static let recentDownloads = "recentDownloads"
    }

    enum Default {
        static let saveFolder: String =
            FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask).first?.path
            ?? NSHomeDirectory() + "/Downloads"
        static let height = 1080
        static let videoFormatValue = VideoFormat.mp4
        static let audioFormatValue = AudioFormat.m4a
        static let videoFormat = videoFormatValue.rawValue
        static let audioFormat = audioFormatValue.rawValue
        static let skipSponsors = false
        static let videoHotKeyCode = kVK_ANSI_D
        static let audioHotKeyCode = kVK_ANSI_A
        /// Control-Option-Command, as a Carbon modifier mask.
        static let hotKeyModifiers = controlKey | optionKey | cmdKey
    }

    /// An Int stored in UserDefaults, or the default when it was never set.
    private static func int(_ key: String, default value: Int) -> Int {
        UserDefaults.standard.object(forKey: key) as? Int ?? value
    }

    static var videoHotKey: (code: Int, modifiers: Int) {
        (int(Key.videoHotKeyCode, default: Default.videoHotKeyCode),
         int(Key.videoHotKeyModifiers, default: Default.hotKeyModifiers))
    }

    static var audioHotKey: (code: Int, modifiers: Int) {
        (int(Key.audioHotKeyCode, default: Default.audioHotKeyCode),
         int(Key.audioHotKeyModifiers, default: Default.hotKeyModifiers))
    }

    /// The save folder as a URL. Falls back to the default when unset or empty.
    static var saveFolderURL: URL {
        let path = UserDefaults.standard.string(forKey: Key.saveFolder) ?? ""
        return URL(fileURLWithPath: path.isEmpty ? Default.saveFolder : path, isDirectory: true)
    }

    static var skipSponsors: Bool {
        UserDefaults.standard.object(forKey: Key.skipSponsors) as? Bool ?? Default.skipSponsors
    }

    /// When the weekly yt-dlp update last finished. Nil if never.
    static var lastUpdateCheck: Date? {
        get { UserDefaults.standard.object(forKey: Key.lastUpdateCheck) as? Date }
        set { UserDefaults.standard.set(newValue, forKey: Key.lastUpdateCheck) }
    }

    static var defaultHeight: Int {
        let h = UserDefaults.standard.integer(forKey: Key.defaultHeight)
        return h > 0 ? h : Default.height
    }

    static var defaultVideoFormat: VideoFormat {
        VideoFormat(rawValue: UserDefaults.standard.string(forKey: Key.defaultVideoFormat) ?? "") ?? Default.videoFormatValue
    }

    static var defaultAudioFormat: AudioFormat {
        AudioFormat(rawValue: UserDefaults.standard.string(forKey: Key.defaultAudioFormat) ?? "") ?? Default.audioFormatValue
    }
}
