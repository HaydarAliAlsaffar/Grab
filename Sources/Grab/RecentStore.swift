import Foundation
import Observation

struct RecentItem: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let fileURL: URL
    let title: String
    let addedAt: Date
}

/// The last few downloaded files, saved as JSON in UserDefaults.
@MainActor
@Observable
final class RecentStore {
    static let limit = 6
    private static let key = Settings.Key.recentDownloads

    @ObservationIgnored private let defaults: UserDefaults
    private var stored: [RecentItem]

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        if let data = defaults.data(forKey: Self.key),
           let decoded = try? JSONDecoder().decode([RecentItem].self, from: data) {
            stored = Array(decoded.prefix(Self.limit))
        } else {
            stored = []
        }
    }

    /// Entries whose file still exists inside the user's home or the save folder.
    var items: [RecentItem] {
        stored.filter { FileAccess.isUserFile($0.fileURL) }
    }

    func add(fileURL: URL, title: String) {
        guard FileAccess.isUserFile(fileURL) else { return }
        let path = fileURL.standardizedFileURL.path
        stored.removeAll { $0.fileURL.standardizedFileURL.path == path }
        stored.insert(RecentItem(id: UUID(), fileURL: fileURL, title: title, addedAt: Date()), at: 0)
        if stored.count > Self.limit { stored = Array(stored.prefix(Self.limit)) }
        save()
    }

    /// Drops entries whose file is gone from storage.
    func prune() {
        let kept = items
        guard kept.count != stored.count else { return }
        stored = kept
        save()
    }

    private func save() {
        guard let data = try? JSONEncoder().encode(stored) else { return }
        defaults.set(data, forKey: Self.key)
    }
}
