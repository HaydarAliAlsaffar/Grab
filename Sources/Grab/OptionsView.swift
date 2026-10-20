import SwiftUI

/// Quality and format pickers for a loaded preview.
struct OptionsView: View {
    let info: VideoInfo
    @Binding var quality: Quality
    @Binding var videoFormat: VideoFormat
    @Binding var audioFormat: AudioFormat
    @Binding var skipSponsors: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Quality").font(.subheadline.weight(.semibold))
                Spacer()
                Picker("Quality", selection: $quality) {
                    ForEach(Self.choices(for: info), id: \.self) { q in
                        Text(q.label).tag(q)
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)
                .fixedSize()
            }
            Group {
                if quality == .audioOnly {
                    Picker("Format", selection: $audioFormat) {
                        ForEach(AudioFormat.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                } else {
                    Picker("Format", selection: $videoFormat) {
                        ForEach(VideoFormat.allCases, id: \.self) { Text($0.displayName).tag($0) }
                    }
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            if info.isYouTube {
                Toggle("Skip sponsors", isOn: $skipSponsors)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
        .onChange(of: info, initial: true) { _, newInfo in
            quality = Self.defaultQuality(for: newInfo)
            videoFormat = Settings.defaultVideoFormat
            audioFormat = Settings.defaultAudioFormat
            skipSponsors = Settings.skipSponsors
        }
    }

    static func choices(for info: VideoInfo) -> [Quality] {
        info.availableHeights.map { Quality.height($0) } + [.audioOnly]
    }

    /// The height closest to but not above the default, else the highest available.
    static func defaultQuality(for info: VideoInfo, preferred: Int = Settings.defaultHeight) -> Quality {
        let heights = info.availableHeights
        if let h = heights.first(where: { $0 <= preferred }) { return .height(h) }
        if let h = heights.first { return .height(h) }
        return .audioOnly
    }
}
