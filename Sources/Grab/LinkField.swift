import SwiftUI
import AppKit

struct LinkField: View {
    @Bindable var fetcher: InfoFetcher
    @State private var debounce: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Link").font(.subheadline.weight(.semibold))
            HStack(spacing: 8) {
                TextField("Paste a link", text: $fetcher.text)
                    .textFieldStyle(.roundedBorder)
                    .onSubmit { submit() }
                Button("Paste") { pasteFromClipboard() }
                    .buttonStyle(.glass)
            }
            status
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .onChange(of: fetcher.text) { _, newValue in scheduleFetch(newValue) }
        .onDisappear { debounce?.cancel() }
    }

    @ViewBuilder
    private var status: some View {
        switch fetcher.state {
        case .idle:
            EmptyView()
        case .loading:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Loading...").font(.caption).foregroundStyle(.secondary)
            }
        case .loaded(let info):
            PreviewCard(info: info)
        case .failed(let message):
            Text(message)
                .font(.caption).foregroundStyle(.red.opacity(0.85))
                .lineLimit(3)
        }
    }

    private func scheduleFetch(_ value: String) {
        debounce?.cancel()
        if value.count > InfoFetcher.maxLinkLength {
            fetcher.text = String(value.prefix(InfoFetcher.maxLinkLength))
            return
        }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        // Enter or Paste already handled this exact text (and may have set an error). Leave it.
        if trimmed == fetcher.lastFetchedText { return }
        if trimmed.isEmpty || !InfoFetcher.isLink(trimmed) {
            // Drop the old preview and any in-flight fetch. No error until Enter or Paste.
            fetcher.reset()
            return
        }
        debounce = Task {
            try? await Task.sleep(for: .milliseconds(400))
            if Task.isCancelled { return }
            fetcher.fetch(trimmed)
        }
    }

    private func submit() {
        debounce?.cancel()
        let trimmed = fetcher.text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Enter retries a failed fetch, but does not restart one that is loading or loaded.
        if trimmed == fetcher.lastFetchedText {
            switch fetcher.state {
            case .loading, .loaded: return
            case .idle, .failed: break
            }
        }
        fetcher.fetch(trimmed)
    }

    private func pasteFromClipboard() {
        guard let raw = NSPasteboard.general.string(forType: .string) else { return }
        debounce?.cancel()
        let trimmed = String(raw.trimmingCharacters(in: .whitespacesAndNewlines).prefix(InfoFetcher.maxLinkLength))
        // Fetch first so lastFetchedText is set before onChange sees the new text.
        fetcher.fetch(trimmed)
        fetcher.text = trimmed
    }
}
