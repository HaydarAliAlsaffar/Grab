import SwiftUI

struct PreviewCard: View {
    let info: VideoInfo

    var body: some View {
        HStack(spacing: 10) {
            thumbnail
            VStack(alignment: .leading, spacing: 2) {
                Text(info.displayTitle)
                    .font(.callout.weight(.semibold))
                    .lineLimit(2)
                if !subtitle.isEmpty {
                    Text(subtitle)
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(10)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    private var subtitle: String {
        [info.uploader, info.formattedDuration].compactMap { $0 }.joined(separator: " - ")
    }

    private var placeholder: some View {
        RoundedRectangle(cornerRadius: 8)
            .fill(.gray.opacity(0.25))
            .overlay(Image(systemName: "play.rectangle").foregroundStyle(.secondary))
    }

    private var thumbnail: some View {
        Group {
            if let url = info.thumbnailURL {
                AsyncImage(url: url) { phase in
                    if let image = phase.image {
                        image.resizable().aspectRatio(contentMode: .fill)
                    } else {
                        placeholder
                    }
                }
            } else {
                placeholder
            }
        }
        .frame(width: 96, height: 54)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
