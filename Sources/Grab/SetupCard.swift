import SwiftUI
import AppKit

struct SetupCard: View {
    let tools: Tools
    let installer: Installer

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Setup needed").font(.subheadline.weight(.semibold))
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .glassEffect(.regular, in: .rect(cornerRadius: 16))
    }

    @ViewBuilder
    private var content: some View {
        if tools.brew == nil {
            Text("Homebrew is required to install yt-dlp and ffmpeg.")
                .font(.callout).foregroundStyle(.secondary)
            Button {
                if let url = URL(string: "https://brew.sh") { NSWorkspace.shared.open(url) }
            } label: {
                Text("Get Homebrew").frame(maxWidth: .infinity)
            }
            .buttonStyle(.glassProminent)
            .controlSize(.large)
        } else {
            Text(missingText).font(.callout).foregroundStyle(.secondary)
            switch installer.state {
            case .installing(let line):
                HStack(spacing: 8) {
                    ProgressView().controlSize(.small)
                    Text(line)
                        .font(.caption).foregroundStyle(.secondary)
                        .lineLimit(1).truncationMode(.tail)
                }
                installButton("Install").disabled(true)
            case .failed(let message):
                Text("Install failed.").font(.callout.weight(.semibold))
                Text(message).font(.caption).foregroundStyle(.secondary).lineLimit(2)
                installButton("Try Again")
            case .idle, .done:
                installButton("Install")
            }
        }
    }

    private var missingText: String {
        let names = tools.missing
        if names.count == 1 { return "\(names[0]) is missing." }
        return names.joined(separator: " and ") + " are missing."
    }

    private func installButton(_ title: String) -> some View {
        Button {
            installer.install()
        } label: {
            Text(title).frame(maxWidth: .infinity)
        }
        .buttonStyle(.glassProminent)
        .controlSize(.large)
    }
}
