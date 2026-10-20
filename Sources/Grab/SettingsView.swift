import SwiftUI
import ServiceManagement

/// The Settings window. Values are stored with @AppStorage under the keys in Settings.swift.
struct SettingsView: View {
    let updater: Updater
    @AppStorage(Settings.Key.defaultHeight) private var height = Settings.Default.height
    @AppStorage(Settings.Key.defaultVideoFormat) private var videoFormat = Settings.Default.videoFormat
    @AppStorage(Settings.Key.defaultAudioFormat) private var audioFormat = Settings.Default.audioFormat
    @AppStorage(Settings.Key.skipSponsors) private var skipSponsors = Settings.Default.skipSponsors
    @State private var launchAtLogin = false
    @State private var launchError: String?

    var body: some View {
        Form {
            Section("Defaults") {
                Picker("Video quality", selection: $height) {
                    ForEach([2160, 1440, 1080, 720, 480], id: \.self) { Text("\($0)p").tag($0) }
                }
                Picker("Video format", selection: $videoFormat) {
                    ForEach(VideoFormat.allCases, id: \.rawValue) { Text($0.displayName).tag($0.rawValue) }
                }
                Picker("Audio format", selection: $audioFormat) {
                    ForEach(AudioFormat.allCases, id: \.rawValue) { Text($0.displayName).tag($0.rawValue) }
                }
                Toggle("Skip sponsors by default", isOn: $skipSponsors)
            }

            SaveFolderSection()

            Section("Shortcuts") {
                LabeledContent("Download video") { ShortcutRecorder(kind: .video) }
                LabeledContent("Download audio") { ShortcutRecorder(kind: .audio) }
                Text("Click a shortcut, then press the new keys.")
                    .font(.caption).foregroundStyle(.secondary)
            }

            Section("General") {
                Toggle("Launch at Login", isOn: Binding(get: { launchAtLogin }, set: setLaunchAtLogin))
                if let launchError {
                    Text(launchError).font(.caption).foregroundStyle(.red)
                }
            }

            DownloaderSection(updater: updater)
        }
        .formStyle(.grouped)
        .frame(width: 440)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear { launchAtLogin = SMAppService.mainApp.status == .enabled }
    }

    private func setLaunchAtLogin(_ on: Bool) {
        launchError = nil
        do {
            if on { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
            launchAtLogin = on
            if SMAppService.mainApp.status == .requiresApproval {
                launchError = "Approve Grab in System Settings, Login Items."
            }
        } catch {
            DebugLog.write("Launch at Login error", lines: ["\(error)"])
            launchAtLogin = SMAppService.mainApp.status == .enabled
            launchError = "Could not change Launch at Login."
        }
    }
}
