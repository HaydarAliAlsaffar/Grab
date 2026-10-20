import SwiftUI
import AppKit

/// Save folder row with Choose and Reset.
struct SaveFolderSection: View {
    @AppStorage(Settings.Key.saveFolder) private var path = Settings.Default.saveFolder
    @State private var message: String?

    var body: some View {
        Section("Save folder") {
            LabeledContent {
                HStack {
                    Button("Choose") { choose() }
                    Button("Reset") { path = Settings.Default.saveFolder; message = nil }
                        .disabled(path == Settings.Default.saveFolder)
                }
            } label: {
                Text((path as NSString).abbreviatingWithTildeInPath)
                    .lineLimit(1).truncationMode(.middle)
            }
            if let message {
                Text(message).font(.caption).foregroundStyle(.red)
            }
        }
    }

    private func choose() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.allowsMultipleSelection = false
        NSApp.activate()
        guard panel.runModal() == .OK, let url = panel.url else { return }
        if Self.isAllowed(url) {
            path = url.standardizedFileURL.path
            message = nil
        } else {
            message = "Pick a folder inside your home folder or on a drive."
        }
    }

    /// Refuses broad folders: the resolved path needs at least 3 parts below "/".
    static func isAllowed(_ url: URL) -> Bool {
        let parts = url.resolvingSymlinksInPath().standardizedFileURL.pathComponents.filter { $0 != "/" }
        return parts.count >= 3
    }
}

/// yt-dlp version, last check time, and the update button.
struct DownloaderSection: View {
    let updater: Updater

    var body: some View {
        Section("Downloader") {
            LabeledContent("yt-dlp") {
                Text(updater.versionChecked ? (updater.version ?? "Not found") : "Checking...").foregroundStyle(.secondary)
            }
            LabeledContent("Last checked") {
                Text(lastChecked).foregroundStyle(.secondary)
            }
            LabeledContent {
                Button("Update Downloader") { updater.update() }.disabled(updater.isRunning)
            } label: {
                status
            }
        }
        .task { await updater.refreshVersion() }
    }

    @ViewBuilder private var status: some View {
        switch updater.state {
        case .idle:
            EmptyView()
        case .running(let line):
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(line).font(.caption).foregroundStyle(.secondary).lineLimit(1)
            }
        case .done:
            Text("Up to date.")
                .font(.caption).foregroundStyle(.secondary)
        case .failed(let message):
            Text(message).font(.caption).foregroundStyle(.red)
        }
    }

    private var lastChecked: String {
        guard let date = updater.lastCheck else { return "Never" }
        return RelativeDateTimeFormatter().localizedString(for: date, relativeTo: Date())
    }
}
