import SwiftUI
import AppKit

struct PanelView: View {
    @Environment(\.openSettings) private var openSettings
    let installer: Installer
    let downloader: Downloader
    let recents: RecentStore
    @State private var fetcher = InfoFetcher()
    @State private var quality = Quality.audioOnly
    @State private var videoFormat = Settings.defaultVideoFormat
    @State private var audioFormat = Settings.defaultAudioFormat
    @State private var skipSponsors = Settings.skipSponsors
    @State private var trim = TrimState()

    private var loadedInfo: VideoInfo? {
        if case .loaded(let info) = fetcher.state { return info }
        return nil
    }

    /// Built only from a loaded preview and a validated link.
    private var request: DownloadRequest? {
        guard let info = loadedInfo, let text = fetcher.lastFetchedText,
              let url = InfoFetcher.parse(text) else { return nil }
        var request = DownloadRequest(url: url, title: info.displayTitle, quality: quality, videoFormat: videoFormat,
                                      audioFormat: audioFormat, saveFolder: Settings.saveFolderURL)
        if case .height(let h) = quality, videoFormat == .mov {
            request.needsRecode = !info.hasPlayableVideo(atOrBelow: h)
        }
        request.skipSponsors = skipSponsors && info.isYouTube
        request.trim = trim.range
        return request
    }

    var body: some View {
        GlassEffectContainer(spacing: 12) {
            VStack(spacing: 12) {
                HStack {
                    Text("Grab").font(.headline)
                    Spacer()
                    Button {
                        NSApp.activate()
                        openSettings()
                    } label: {
                        Image(systemName: "gear")
                    }
                    .buttonStyle(.glass)
                    .help("Settings")
                    .accessibilityLabel("Settings")
                }

                if installer.tools.hasAll {
                    LinkField(fetcher: fetcher)

                    if let info = loadedInfo {
                        OptionsView(info: info, quality: $quality,
                                    videoFormat: $videoFormat, audioFormat: $audioFormat,
                                    skipSponsors: $skipSponsors)
                        if TrimState.isTrimmable(info.duration) {
                            TrimView(trim: trim)
                        }
                    }

                    ExportSection(downloader: downloader, request: request)

                    RecentSection(store: recents)
                } else {
                    SetupCard(tools: installer.tools, installer: installer)
                }
            }
            .padding(12)
        }
        .onChange(of: fetcher.lastFetchedText) { _, _ in downloader.reset() }
        .onChange(of: loadedInfo) { _, info in trim.reset(duration: info?.duration) }
        .onAppear { installer.refresh() }
        .onReceive(NotificationCenter.default.publisher(for: NSWindow.didBecomeKeyNotification)) { _ in
            installer.refresh()
            recents.prune()
        }
        .frame(width: 360)
    }
}
