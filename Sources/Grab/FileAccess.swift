import Foundation

/// Checks applied before a stored or printed path is revealed or dragged.
enum FileAccess {
    /// True for an existing file URL inside the user's home directory or the save folder.
    /// Symlinks are resolved first, so a link cannot point outside home.
    nonisolated static func isUserFile(_ url: URL) -> Bool {
        guard url.isFileURL else { return false }
        let home = FileManager.default.homeDirectoryForCurrentUser.resolvingSymlinksInPath().standardizedFileURL.path
        let saveFolder = Settings.saveFolderURL.resolvingSymlinksInPath().standardizedFileURL.path
        let path = url.resolvingSymlinksInPath().standardizedFileURL.path
        let roots = [home, saveFolder].filter { $0 != "/" && !$0.isEmpty }
        guard roots.contains(where: { path.hasPrefix($0 + "/") }) else { return false }
        return FileManager.default.fileExists(atPath: path)
    }
}
