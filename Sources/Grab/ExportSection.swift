import SwiftUI
import AppKit

/// Export button, progress bar with Cancel, and the result row.
struct ExportSection: View {
    let downloader: Downloader
    /// Nil until a preview is loaded.
    let request: DownloadRequest?

    var body: some View {
        switch downloader.state {
        case .running(let percent, let status):
            running(percent: percent, status: status)
        case .stopping:
            VStack(alignment: .leading, spacing: 8) {
                Text("Stopping...").font(.caption).foregroundStyle(.secondary)
                Button("Cancel") {}
                    .buttonStyle(.glass)
                    .disabled(true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(12)
            .glassEffect(.regular, in: .rect(cornerRadius: 16))
        case .finished(let url):
            VStack(spacing: 8) {
                fileRow(title: "Saved", url: url)
                exportButton
            }
        case .duplicate(let url):
            VStack(spacing: 8) {
                fileRow(title: "Already downloaded", url: url)
                exportButton
            }
        case .failed(let message):
            VStack(spacing: 8) {
                Text(message)
                    .font(.caption).foregroundStyle(.red.opacity(0.85))
                    .lineLimit(3)
                    .frame(maxWidth: .infinity, alignment: .leading)
                exportButton
            }
        case .cancelled:
            VStack(spacing: 8) {
                Text("Cancelled.").font(.caption).foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                exportButton
            }
        case .idle:
            exportButton
        }
    }

    private var exportButton: some View {
        Button {
            if let request { downloader.start(request) }
        } label: {
            Text("Export").frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
        .disabled(request == nil || downloader.isBusy)
    }

    private func running(percent: Double?, status: String) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if let percent {
                ProgressView(value: percent, total: 100)
            } else {
                ProgressView().progressViewStyle(.linear)
            }
            HStack {
                Text(percent.map { "\(status.replacingOccurrences(of: "...", with: "")) \(Int($0))%" } ?? status)
                    .font(.caption).foregroundStyle(.secondary)
                Spacer()
                Button("Cancel") { downloader.cancel() }
                    .buttonStyle(.glass)
            }
            if downloader.queuedCount > 0 {
                Text("\(downloader.queuedCount) waiting")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    private func fileRow(title: String, url: URL) -> some View {
        HStack(spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.callout.weight(.semibold))
                Text(url.lastPathComponent)
                    .font(.caption).foregroundStyle(.secondary)
                    .lineLimit(1).truncationMode(.middle)
            }
            Spacer(minLength: 0)
            Button("Show in Finder") {
                guard FileAccess.isUserFile(url) else { return }
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
            .buttonStyle(.glass)
        }
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }
}
