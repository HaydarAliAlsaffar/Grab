import AppKit
import Observation

/// Handles a global shortcut press: clipboard link, info fetch, then the download queue.
@MainActor
@Observable
final class ShortcutActions {
    enum Kind { case video, audio }

    /// True while a shortcut press is loading link info. The menu bar icon shows it.
    private(set) var isFetching = false
    @ObservationIgnored private var pending: Task<Void, Never>?
    @ObservationIgnored private let downloader: Downloader
    @ObservationIgnored private let notifier: Notifier

    init(downloader: Downloader, notifier: Notifier) {
        self.downloader = downloader
        self.notifier = notifier
    }

    func handle(_ kind: Kind) {
        // Only the plain string is read from the clipboard.
        let raw = NSPasteboard.general.string(forType: .string) ?? ""
        let text = String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(InfoFetcher.maxLinkLength))
        guard let url = InfoFetcher.parse(text) else {
            notifier.info("Copy a link first", body: "")
            return
        }
        // Chain presses so fetches and enqueues happen in press order.
        pending = Task { [prev = pending] in
            await prev?.value
            await process(kind, url: url)
        }
    }

    private func process(_ kind: Kind, url: URL) async {
        isFetching = true
        defer { isFetching = false }
        let result = await InfoFetcher.fetchInfo(url: url)
        switch result {
        case .failure(let error):
            if error.message == InfoFetcher.playlistError {
                notifier.info("Playlists are not supported", body: "")
            } else {
                let body = ProcessOutput.detail(of: error.message, droppingPrefix: InfoFetcher.genericError)
                notifier.info("Could not load that link", body: body)
            }
        case .success(let info):
            downloader.enqueue(request(for: kind, url: url, info: info))
        }
    }

    private func request(for kind: Kind, url: URL, info: VideoInfo) -> DownloadRequest {
        let videoFormat = Settings.defaultVideoFormat
        let quality: Quality = kind == .video ? .height(Settings.defaultHeight) : .audioOnly
        var request = DownloadRequest(url: url, title: info.displayTitle, quality: quality, videoFormat: videoFormat,
                                      audioFormat: Settings.defaultAudioFormat, saveFolder: Settings.saveFolderURL)
        request.skipSponsors = Settings.skipSponsors && info.isYouTube
        if case .height(let h) = quality, videoFormat == .mov {
            request.needsRecode = !info.hasPlayableVideo(atOrBelow: h)
        }
        return request
    }
}
