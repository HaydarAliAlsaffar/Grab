import SwiftUI

/// Trim toggle, range slider and start and end fields.
struct TrimView: View {
    @Bindable var trim: TrimState

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Toggle("Trim", isOn: $trim.isOn)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                if trim.isOn {
                    Text("\(TrimRange.format(TrimRange(start: trim.start, end: trim.end).length, tenths: true)) clip")
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
            if trim.isOn {
                RangeSlider(
                    lower: Binding(get: { trim.start }, set: { trim.setRange(start: $0) }),
                    upper: Binding(get: { trim.end }, set: { trim.setRange(end: $0) }),
                    total: trim.duration)
                HStack {
                    TimeField(label: "Start", value: trim.start) { trim.setStart($0) }
                    Spacer()
                    TimeField(label: "End", value: trim.end) { trim.setEnd($0) }
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }
}

/// A time text field. Commits on Enter or when focus leaves; bad input reverts.
private struct TimeField: View {
    let label: String
    let value: Double
    /// Returns the value now in effect (the old one if the input was rejected).
    let commit: (Double) -> Double

    @State private var text = ""
    /// True once the user has typed in the field since the last refresh or commit.
    @State private var dirty = false
    /// The value when the current edit began, restored if the final text is not accepted.
    @State private var original = 0.0
    /// True when the latest typed text parsed and was applied.
    @State private var applied = false
    @FocusState private var focused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Text(label).font(.caption).foregroundStyle(.secondary)
            TextField(label, text: $text)
                .textFieldStyle(.roundedBorder)
                .multilineTextAlignment(.center)
                .monospacedDigit()
                .frame(width: 80)
                .labelsHidden()
                .focused($focused)
                .onSubmit(finish)
        }
        .onAppear { text = TrimRange.format(value, tenths: true) }
        .onChange(of: text) { _, new in
            // Only user edits count; refreshes set `text` to the formatted value.
            guard focused, new != TrimRange.format(value, tenths: true) else { return }
            if !dirty { original = value }
            dirty = true
            // Apply in-range input that gives a valid range right away, so Export never
            // misses it. Anything else is not applied.
            applied = false
            if let parsed = TrimRange.parse(new) {
                let result = commit(parsed)
                applied = abs(result - TrimRange.tenth(parsed)) < 0.001
            }
        }
        .onChange(of: value) { _, new in
            if !dirty { text = TrimRange.format(new, tenths: true) }
        }
        .onChange(of: focused) { _, isFocused in
            if !isFocused { finish() }
        }
    }

    /// Enter or focus loss: show the value in effect, which reverts bad input.
    private func finish() {
        var current = value
        // An earlier keystroke may have been applied ("1:9"), so undo it if the final text was not.
        if dirty && !applied { current = commit(original) }
        dirty = false
        text = TrimRange.format(current, tenths: true)
    }
}
