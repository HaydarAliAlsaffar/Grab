import Carbon.HIToolbox
import Foundation

/// Carbon calls this on the main thread. It cannot capture, so the HotKeys
/// instance comes back through userData.
private func hotKeyCallback(_ next: EventHandlerCallRef?, _ event: EventRef?,
                            _ userData: UnsafeMutableRawPointer?) -> OSStatus {
    guard let event, let userData else { return OSStatus(eventNotHandledErr) }
    var hotKeyID = EventHotKeyID()
    let status = GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID),
                                   nil, MemoryLayout<EventHotKeyID>.size, nil, &hotKeyID)
    guard status == noErr else { return status }
    // Ignore keys that are not ours so other handlers still see the event.
    guard hotKeyID.signature == HotKeys.signature, hotKeyID.id == 1 || hotKeyID.id == 2 else {
        return OSStatus(eventNotHandledErr)
    }
    // The pointer crosses into the main actor closure as a plain integer.
    let address = UInt(bitPattern: userData)
    let id = hotKeyID.id
    MainActor.assumeIsolated {
        guard let pointer = UnsafeMutableRawPointer(bitPattern: address) else { return }
        Unmanaged<HotKeys>.fromOpaque(pointer).takeUnretainedValue().handle(id: id)
    }
    return noErr
}

/// The two global shortcuts, registered with Carbon (no Accessibility permission needed).
@MainActor
final class HotKeys {
    var onVideo: (() -> Void)?
    var onAudio: (() -> Void)?

    nonisolated fileprivate static let signature: OSType = 0x4752_4142  // "GRAB"
    private var handlerRef: EventHandlerRef?
    private var videoRef: EventHotKeyRef?
    private var audioRef: EventHotKeyRef?

    /// Installs the event handler once, then registers both hot keys. Safe to call again.
    /// Also re-reads Settings, so the shortcut recorder calls this after a remap.
    func reload() {
        if handlerRef == nil {
            var eventType = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
            // Unretained is safe only because Services.hotKeys owns HotKeys for the whole app
            // lifetime and this handler is never removed.
            let userData = Unmanaged.passUnretained(self).toOpaque()
            let status = InstallEventHandler(GetApplicationEventTarget(), hotKeyCallback, 1, &eventType, userData, &handlerRef)
            if status != noErr {
                DebugLog.write("InstallEventHandler error", lines: ["status \(status)"])
                handlerRef = nil
                return
            }
        }
        unregisterKeys()
        let video = Settings.videoHotKey, audio = Settings.audioHotKey
        videoRef = Self.registerKey(video.code, video.modifiers, id: 1)
        audioRef = Self.registerKey(audio.code, audio.modifiers, id: 2)
    }

    /// True when the key for that shortcut is currently registered with macOS.
    func isRegistered(_ kind: ShortcutActions.Kind) -> Bool {
        (kind == .video ? videoRef : audioRef) != nil
    }

    /// Unregisters both keys while the recorder listens, so the old combo does not fire.
    func suspend() { unregisterKeys() }

    private func unregisterKeys() {
        if let videoRef { UnregisterEventHotKey(videoRef) }
        if let audioRef { UnregisterEventHotKey(audioRef) }
        videoRef = nil
        audioRef = nil
    }

    private static func registerKey(_ code: Int, _ modifiers: Int, id: UInt32) -> EventHotKeyRef? {
        guard code >= 0, modifiers >= 0, code <= Int(UInt32.max), modifiers <= Int(UInt32.max) else { return nil }
        var ref: EventHotKeyRef?
        let hotKeyID = EventHotKeyID(signature: signature, id: id)
        let status = RegisterEventHotKey(UInt32(code), UInt32(modifiers), hotKeyID, GetApplicationEventTarget(), 0, &ref)
        if status != noErr {
            DebugLog.write("RegisterEventHotKey error", lines: ["id \(id), status \(status)"])
            return nil
        }
        return ref
    }

    fileprivate func handle(id: UInt32) {
        switch id {
        case 1: onVideo?()
        case 2: onAudio?()
        default: break
        }
    }
}
