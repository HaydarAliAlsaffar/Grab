import SwiftUI

/// A two-thumb slider across 0...total. The thumbs stay at least `minGap` apart.
struct RangeSlider: View {
    @Binding var lower: Double
    @Binding var upper: Double
    let total: Double
    var minGap = TrimRange.minLength

    private enum Thumb { case lower, upper }

    private let thumb: CGFloat = 14
    private let trackHeight: CGFloat = 4
    /// The thumb chosen when the current drag began.
    @State private var active: Thumb?

    var body: some View {
        GeometryReader { geo in
            let span = max(geo.size.width - thumb, 1)
            let lowX = position(lower, span: span)
            let highX = position(upper, span: span)
            ZStack(alignment: .leading) {
                Capsule().fill(.secondary.opacity(0.35))
                    .frame(height: trackHeight)
                Capsule().fill(.tint)
                    .frame(width: max(highX - lowX, 0), height: trackHeight)
                    .offset(x: lowX + thumb / 2)
                handle().offset(x: lowX)
                    .accessibilityLabel("Start")
                handle().offset(x: highX)
                    .accessibilityLabel("End")
            }
            .frame(width: geo.size.width, height: geo.size.height, alignment: .leading)
            .contentShape(Rectangle())
            .gesture(drag(span: span))
        }
        .frame(height: 20)
    }

    private func handle() -> some View {
        Circle()
            .fill(.white)
            .frame(width: thumb, height: thumb)
            .shadow(color: .black.opacity(0.25), radius: 1.5, y: 0.5)
    }

    private func position(_ value: Double, span: CGFloat) -> CGFloat {
        guard total > 0 else { return 0 }
        return CGFloat(min(max(value / total, 0), 1)) * span
    }

    /// One drag for the whole track. The thumb is chosen once, then kept until the drag ends.
    private func drag(span: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { drag in
                let pointer = drag.location.x - thumb / 2
                if active == nil {
                    let lowX = position(lower, span: span), highX = position(upper, span: span)
                    let startPointer = drag.startLocation.x - thumb / 2
                    let lowDistance = abs(startPointer - lowX), highDistance = abs(startPointer - highX)
                    if abs(lowDistance - highDistance) < thumb {
                        // Overlapping thumbs: wait for movement, then moving left grabs Start.
                        let dx = drag.location.x - drag.startLocation.x
                        guard abs(dx) >= 1 else { return }
                        active = dx < 0 ? .lower : .upper
                    } else {
                        active = lowDistance < highDistance ? .lower : .upper
                    }
                }
                let seconds = min(max(Double(pointer / span), 0), 1) * total
                // Snap to whole seconds, but let the right end reach a fractional total.
                let value = seconds >= total - 0.5 ? total : seconds.rounded()
                switch active {
                case .lower: lower = min(max(value, 0), TrimRange.tenth(upper - minGap))
                case .upper: upper = max(min(value, total), TrimRange.tenth(lower + minGap))
                case nil: break
                }
            }
            .onEnded { _ in active = nil }
    }
}
