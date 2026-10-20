import SwiftUI
import AppKit
import Carbon.HIToolbox

/// The one place that records a shortcut. Only one shortcut can record at a time.
/// Key events are read through a local monitor, only for the window that was key
/// when recording started, and only until recording ends.
@MainActor
@Observable
final class ShortcutRecording {
    static let shared = ShortcutRecording()

    private(set) var active: ShortcutActions.Kind?
    private(set) var held = ""
    private(set) var message: String?
    private(set) var messageKind: ShortcutActions.Kind?
    @ObservationIgnored private var monitor: Any?
    @ObservationIgnored private var observers: [any NSObjectProtocol] = []

    private init() {}

    /// `onKey` gets a key code and Carbon mask and returns a problem text, or nil if it was accepted.
    func start(_ kind: ShortcutActions.Kind, onKey: @escaping @MainActor (Int, Int) -> String?) {
        // No key window: end any recording normally (hot keys come back) and do not start.
        guard let window = NSApp.keyWindow else { end(reload: true); return }
        // Switching shortcuts: end the other recording first, without reloading in between.
        end(reload: false)
        message = nil
        messageKind = nil
        let windowID = ObjectIdentifier(window)
        active = kind
        held = ""
        // Stop the live hot keys so pressing the old combo does not start a download.
        Services.hotKeys.suspend()

        monitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .flagsChanged]) { [weak self] event in
            // Other windows (the panel, for example) keep their keys.
            guard let eventWindow = event.window, ObjectIdentifier(eventWindow) == windowID else { return event }
            let isKeyDown = event.type == .keyDown
            let code = Int(event.keyCode)
            let mask = ShortcutRecording.carbonMask(event.modifierFlags)
            MainActor.assumeIsolated {
                self?.handle(kind, isKeyDown: isKeyDown, code: code, mask: mask, onKey: onKey)
            }
            return nil
        }
        let center = NotificationCenter.default
        for name in [NSWindow.didResignKeyNotification, NSWindow.willCloseNotification] {
            observers.append(center.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.stop() }
            })
        }
    }

    /// Ends recording and puts the hot keys back. Safe to call when idle.
    func stop() { end(reload: true) }

    private func end(reload: Bool) {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
        for observer in observers { NotificationCenter.default.removeObserver(observer) }
        observers = []
        held = ""
        guard active != nil else { return }
        active = nil
        if reload { Services.hotKeys.reload() }
    }

    private func handle(_ kind: ShortcutActions.Kind, isKeyDown: Bool, code: Int, mask: Int,
                        onKey: (Int, Int) -> String?) {
        guard active == kind else { return }
        guard isKeyDown else { held = KeyNames.symbols(forModifiers: mask); return }
        if code == kVK_Escape { stop(); return }
        if let problem = onKey(code, mask) {
            message = problem
            messageKind = kind
        } else {
            message = nil
            stop()
        }
    }

    nonisolated static func carbonMask(_ flags: NSEvent.ModifierFlags) -> Int {
        var mask = 0
        if flags.contains(.command) { mask |= cmdKey }
        if flags.contains(.option) { mask |= optionKey }
        if flags.contains(.control) { mask |= controlKey }
        if flags.contains(.shift) { mask |= shiftKey }
        return mask
    }
}

/// Shows one shortcut in a capsule. Click it, then press the new keys.
struct ShortcutRecorder: View {
    let kind: ShortcutActions.Kind
    @AppStorage private var code: Int
    @AppStorage private var modifiers: Int
    private let recording = ShortcutRecording.shared

    init(kind: ShortcutActions.Kind) {
        self.kind = kind
        switch kind {
        case .video:
            _code = AppStorage(wrappedValue: Settings.Default.videoHotKeyCode, Settings.Key.videoHotKeyCode)
            _modifiers = AppStorage(wrappedValue: Settings.Default.hotKeyModifiers, Settings.Key.videoHotKeyModifiers)
        case .audio:
            _code = AppStorage(wrappedValue: Settings.Default.audioHotKeyCode, Settings.Key.audioHotKeyCode)
            _modifiers = AppStorage(wrappedValue: Settings.Default.hotKeyModifiers, Settings.Key.audioHotKeyModifiers)
        }
    }

    private var isRecording: Bool { recording.active == kind }

    var body: some View {
        VStack(alignment: .trailing, spacing: 2) {
            Button {
                if isRecording { recording.stop() } else { startRecording() }
            } label: {
                Text(label)
                    .monospacedDigit()
                    .padding(.horizontal, 10)
                    .padding(.vertical, 3)
                    .frame(minWidth: 90)
                    .overlay(Capsule().strokeBorder(isRecording ? Color.accentColor : .secondary.opacity(0.6)))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(kind == .video ? "Video shortcut" : "Audio shortcut")
            if let message = recording.message, recording.messageKind == kind {
                Text(message).font(.caption).foregroundStyle(.red)
            }
        }
        .onDisappear { if isRecording { recording.stop() } }
    }

    private var label: String {
        if isRecording { return recording.held.isEmpty ? "Press keys..." : recording.held }
        return KeyNames.display(code: code, modifiers: modifiers)
    }

    private func startRecording() {
        recording.start(kind) { newCode, newMask in
            if let problem = Self.problem(code: newCode, mask: newMask, kind: kind) { return problem }
            let oldCode = code, oldMask = modifiers
            code = newCode
            modifiers = newMask
            recording.stop()  // reloads the hot keys with the new combo
            guard Services.hotKeys.isRegistered(kind) else {
                // macOS refused it. Put the old combo back.
                code = oldCode
                modifiers = oldMask
                Services.hotKeys.reload()
                return "Could not use that shortcut."
            }
            return nil
        }
    }

    /// Why a combo cannot be used, or nil when it is fine.
    private static func problem(code: Int, mask: Int, kind: ShortcutActions.Kind) -> String? {
        // Command alone (or with Shift) would take shortcuts like Command-C from every app.
        if mask & (controlKey | optionKey) == 0 { return "Add Control or Option." }
        // Option-Command-D (Dock) and Option-Command-A (Finder) belong to macOS.
        if mask == cmdKey | optionKey, code == kVK_ANSI_D || code == kVK_ANSI_A { return "Used by macOS." }
        let other = kind == .video ? Settings.audioHotKey : Settings.videoHotKey
        if other.code == code, other.modifiers == mask { return "Already used." }
        return nil
    }
}
