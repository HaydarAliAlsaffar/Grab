import SwiftUI
import AppKit
import QuickLookThumbnailing

/// Thumbnails by file path, so redraws do not regenerate them.
@MainActor
@Observable
final class ThumbnailCache {
    private(set) var images: [String: NSImage] = [:]
    @ObservationIgnored private var loading: Set<String> = []

    func load(_ url: URL) async {
        let path = url.path
        guard images[path] == nil, !loading.contains(path) else { return }
        loading.insert(path)
        defer { loading.remove(path) }
        let scale = NSScreen.main?.backingScaleFactor ?? 2
        let request = QLThumbnailGenerator.Request(fileAt: url, size: CGSize(width: 96, height: 54),
                                                   scale: scale, representationTypes: .thumbnail)
        let image: NSImage
        if let rep = try? await QLThumbnailGenerator.shared.generateBestRepresentation(for: request) {
            image = NSImage(cgImage: rep.cgImage, size: rep.cgImage.size(scale: scale))
        } else {
            image = NSWorkspace.shared.icon(forFile: path)
        }
        if images.count > 30 { images.removeAll() }
        images[path] = image
    }
}

private extension CGImage {
    func size(scale: CGFloat) -> NSSize { NSSize(width: CGFloat(width) / scale, height: CGFloat(height) / scale) }
}

/// The last downloads. Click to show in Finder, drag to share the file.
struct RecentSection: View {
    let store: RecentStore
    @State private var thumbnails = ThumbnailCache()
    @State private var hovered: UUID?

    var body: some View {
        let items = store.items
        VStack(alignment: .leading, spacing: 8) {
            Text("Recent").font(.subheadline.weight(.semibold))
            if items.isEmpty {
                Text("No downloads yet.").font(.callout).foregroundStyle(.secondary)
            } else {
                ForEach(items) { item in row(item) }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    private func row(_ item: RecentItem) -> some View {
        HStack(spacing: 8) {
            thumbnail(item.fileURL)
            Text(item.fileURL.lastPathComponent)
                .font(.callout)
                .lineLimit(1).truncationMode(.middle)
            Spacer(minLength: 0)
        }
        .padding(4)
        .background(.primary.opacity(hovered == item.id ? 0.08 : 0), in: .rect(cornerRadius: 8))
        .contentShape(.rect)
        .onHover { inside in
            if inside { hovered = item.id } else if hovered == item.id { hovered = nil }
        }
        .onTapGesture {
            guard FileAccess.isUserFile(item.fileURL) else { store.prune(); return }
            NSWorkspace.shared.activateFileViewerSelecting([item.fileURL])
        }
        .draggable(item.fileURL)
        .help("Show in Finder")
        .accessibilityAddTraits(.isButton)
        .task(id: item.fileURL.path) { await thumbnails.load(item.fileURL) }
    }

    @ViewBuilder
    private func thumbnail(_ url: URL) -> some View {
        Group {
            if let image = thumbnails.images[url.path] {
                Image(nsImage: image).resizable().scaledToFill()
            } else {
                Color.secondary.opacity(0.15)
            }
        }
        .frame(width: 48, height: 27)
        .clipShape(.rect(cornerRadius: 5))
    }
}
