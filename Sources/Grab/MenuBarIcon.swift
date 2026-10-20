import SwiftUI
import AppKit

/// A small ring that fills as the download progresses.
private struct RingView: View {
    let fraction: Double

    var body: some View {
        ZStack {
            Circle().stroke(Color.black.opacity(0.25), lineWidth: 2)
            Circle()
                .trim(from: 0, to: fraction)
                .stroke(Color.black, style: StrokeStyle(lineWidth: 2, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Image(systemName: "arrow.down")
                .font(.system(size: 7, weight: .bold))
                .foregroundStyle(Color.black)
        }
        .padding(1)
        .frame(width: 18, height: 18)
    }
}

/// Picks the menu bar icon for a download state and caches the rendered ring.
@MainActor
final class MenuBarIcon {
    private var lastPercent: Double?
    private var cached: NSImage?

    /// The ring for a known percent, otherwise nil.
    func ring(for state: Downloader.State) -> NSImage? {
        guard case .running(let percent?, _) = state else {
            lastPercent = nil
            cached = nil
            return nil
        }
        // Re-render only when the percent moved by at least 2 points.
        if let lastPercent, let cached, abs(percent - lastPercent) < 2, percent < 100 { return cached }
        let renderer = ImageRenderer(content: RingView(fraction: min(max(percent, 0), 100) / 100))
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        guard let image = renderer.nsImage else { return nil }
        image.isTemplate = true
        lastPercent = percent
        cached = image
        return image
    }

    /// The symbol used when there is no ring.
    func symbol(for state: Downloader.State, fetching: Bool) -> String {
        if fetching { return "arrow.down.circle.dotted" }
        switch state {
        case .running, .stopping: return "arrow.down.circle.dotted"
        default: return "arrow.down.circle"
        }
    }
}

/// The MenuBarExtra label. Tiny on purpose.
struct MenuBarLabel: View {
    let downloader: Downloader
    @State private var icon = MenuBarIcon()

    var body: some View {
        let state = downloader.state
        if let ring = icon.ring(for: state) {
            Image(nsImage: ring)
        } else {
            Image(systemName: icon.symbol(for: state, fetching: Services.actions?.isFetching ?? false))
        }
    }
}
