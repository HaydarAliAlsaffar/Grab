import AppKit
import UserNotifications

/// Posts local notifications and reveals files when one is clicked.
@MainActor
final class Notifier: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Notifier()
    nonisolated static let categoryID = "GRAB_FILE"
    nonisolated private static let showAction = "SHOW_IN_FINDER"

    private var center: UNUserNotificationCenter { .current() }

    /// Call once at launch.
    func install() {
        center.delegate = self
        let show = UNNotificationAction(identifier: Self.showAction, title: "Show in Finder", options: [.foreground])
        let category = UNNotificationCategory(identifier: Self.categoryID, actions: [show],
                                             intentIdentifiers: [], options: [])
        center.setNotificationCategories([category])
    }

    func saved(fileURL: URL) {
        post(title: "Saved", body: fileURL.lastPathComponent, fileURL: fileURL)
    }

    func failed(message: String) {
        let body = ProcessOutput.detail(of: message, droppingPrefix: Downloader.genericError)
        post(title: "Download failed", body: body.isEmpty ? "Try again." : body, fileURL: nil)
    }

    /// A plain message. Pass a file to make a click reveal it.
    func info(_ title: String, body: String, revealing fileURL: URL? = nil) {
        post(title: title, body: body, fileURL: fileURL)
    }

    private func post(title: String, body: String, fileURL: URL?) {
        let content = UNMutableNotificationContent()
        content.title = title
        content.body = body
        if let fileURL {
            content.userInfo = ["path": fileURL.path]
            content.categoryIdentifier = Self.categoryID
        }
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        Task {
            guard await isAuthorized() else { return }
            do { try await center.add(request) } catch {
                DebugLog.write("Notification failed", lines: ["\(error)"])
            }
        }
    }

    /// Asks on first use. Denied or failed means no notification.
    private func isAuthorized() async -> Bool {
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional, .ephemeral:
            return true
        case .notDetermined:
            do {
                return try await center.requestAuthorization(options: [.alert, .sound])
            } catch {
                DebugLog.write("Notification authorization failed", lines: ["\(error)"])
                return false
            }
        default:
            return false
        }
    }

    private static func reveal(path: String?) {
        guard let path else { return }
        let url = URL(fileURLWithPath: path)
        guard FileAccess.isUserFile(url) else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    // MARK: - UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            didReceive response: UNNotificationResponse) async {
        let path = response.notification.request.content.userInfo["path"] as? String
        await MainActor.run { Self.reveal(path: path) }
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                            willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}
