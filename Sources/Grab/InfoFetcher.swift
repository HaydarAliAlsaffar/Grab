import Foundation
import Observation

/// Why a fetch failed, in plain words.
struct FetchError: Error, Sendable, Equatable {
    let message: String
    init(_ message: String) { self.message = message }
}

/// Fetches video metadata with `yt-dlp -J` for the Link section.
@MainActor
@Observable
final class InfoFetcher {
    enum State: Equatable {
        case idle
        case loading
        case loaded(VideoInfo)
        case failed(String)
    }

    var text = ""
    /// Trimmed input of the most recent fetch, so identical input is not fetched twice.
    private(set) var lastFetchedText: String?
    private(set) var state: State = .idle
    private var generation = 0
    private var task: Task<Void, Never>?

    nonisolated static let notALink = "That is not a link."
    nonisolated static let playlistError = "Playlists are not supported."
    nonisolated static let genericError = "Could not load that link."
    /// Longest link text accepted from the field, the clipboard, or a shortcut.
    nonisolated static let maxLinkLength = 2048

    /// True when the text parses as an http or https URL with a host.
    static func isLink(_ text: String) -> Bool { parse(text) != nil }

    static func parse(_ text: String) -> URL? {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !trimmed.contains(where: { $0.isWhitespace || $0.isNewline }),
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              let host = url.host(), !host.isEmpty, !isLocalHost(host) else { return nil }
        return url
    }

    /// True for localhost, ".local" names, and IP literals in private, loopback or link-local ranges.
    /// Also catches odd IPv4 spellings such as "2130706433" or "0x7f.1" (inet_aton accepts them).
    nonisolated static func isLocalHost(_ rawHost: String) -> Bool {
        var host = rawHost.lowercased()
        // Percent-encoded names and IPv6 zone ids are never needed for a public video link.
        if host.contains("%") { return true }
        if host.hasPrefix("["), host.hasSuffix("]") { host = String(host.dropFirst().dropLast()) }
        while host.hasSuffix(".") { host.removeLast() }
        if host.isEmpty || host == "localhost" || host.hasSuffix(".localhost") || host.hasSuffix(".local") { return true }

        var v4 = in_addr()
        if inet_aton(host, &v4) != 0 {
            return isPrivateV4(UInt32(bigEndian: v4.s_addr))
        }
        var v6 = in6_addr()
        if inet_pton(AF_INET6, host, &v6) == 1 {
            let b = withUnsafeBytes(of: &v6) { Array($0) }
            if b.dropLast().allSatisfy({ $0 == 0 }) && (b[15] == 0 || b[15] == 1) { return true }  // :: and ::1
            if b[0] & 0xFE == 0xFC { return true }                                                 // fc00::/7
            if b[0] == 0xFE && b[1] & 0xC0 == 0x80 { return true }                                 // fe80::/10
            let low = b[12...15].reduce(0) { $0 << 8 | UInt32($1) }
            if b[0..<10].allSatisfy({ $0 == 0 }) && b[10] == 0xFF && b[11] == 0xFF {              // ::ffff:a.b.c.d
                return isPrivateV4(low)
            }
            if b[0..<12].allSatisfy({ $0 == 0 }) { return isPrivateV4(low) }                       // ::a.b.c.d
            if b[0] == 0 && b[1] == 0x64 && b[2] == 0xFF && b[3] == 0x9B
                && b[4..<12].allSatisfy({ $0 == 0 }) { return isPrivateV4(low) }                   // 64:ff9b::/96
            if b[0] == 0x20 && b[1] == 0x02 {                                                      // 2002::/16 (6to4)
                return isPrivateV4(b[2...5].reduce(0) { $0 << 8 | UInt32($1) })
            }
        }
        return false
    }

    nonisolated private static func isPrivateV4(_ a: UInt32) -> Bool {
        let o1 = a >> 24, o2 = (a >> 16) & 0xFF
        return o1 == 0 || o1 == 127 || o1 == 10
            || (o1 == 172 && (16...31).contains(o2))
            || (o1 == 192 && o2 == 168)
            || (o1 == 169 && o2 == 254)
            || (o1 == 100 && (64...127).contains(o2))   // 100.64.0.0/10
            || o1 >= 224                                // multicast and reserved, incl. 255.255.255.255
    }

    func reset() {
        generation += 1
        task?.cancel()
        task = nil
        lastFetchedText = nil
        state = .idle
    }

    func fetch(_ input: String) {
        generation += 1
        task?.cancel()
        task = nil
        let trimmed = input.trimmingCharacters(in: .whitespacesAndNewlines)
        lastFetchedText = trimmed
        if trimmed.isEmpty { state = .idle; return }
        guard let url = Self.parse(trimmed) else { state = .failed(Self.notALink); return }

        let gen = generation
        state = .loading
        task = Task { [weak self] in
            let result = await Self.fetchInfo(url: url)
            guard let self, !Task.isCancelled, self.generation == gen else { return }
            self.task = nil
            switch result {
            case .success(let info): self.state = .loaded(info)
            case .failure(let error): self.state = .failed(error.message)
            }
        }
    }

    // MARK: - Process

    /// Runs `yt-dlp -J` for an already validated link. Shared by the panel and the shortcuts.
    /// Cancelling the calling task stops the process.
    nonisolated static func fetchInfo(url: URL) async -> Result<VideoInfo, FetchError> {
        guard let ytDlp = Tools.locate("yt-dlp") else { return .failure(FetchError("yt-dlp was not found.")) }
        let job = ProcessJob()
        return await withTaskCancellationHandler {
            await run(ytDlp: ytDlp, url: url.absoluteString, job: job)
        } onCancel: {
            job.cancel()
        }
    }

    nonisolated private static func run(ytDlp: URL, url: String, job: ProcessJob) async -> Result<VideoInfo, FetchError> {
        // "--" ensures the URL can never be read as an option.
        let arguments = ["-J", "--ignore-config", "--no-playlist", "--flat-playlist", "--no-warnings",
                         "--socket-timeout", "15", "--", url]
        guard let result = await job.run(executable: ytDlp, arguments: arguments) else {
            return .failure(FetchError(genericError))
        }

        guard result.status == 0 else {
            if !job.isCancelled {
                DebugLog.write("Fetch failed, exit \(result.status)",
                               lines: [arguments.joined(separator: " ")] + DebugLog.lines(of: result.stderr))
            }
            return .failure(FetchError(message(fromStderr: result.stderr)))
        }
        guard let info = try? JSONDecoder().decode(VideoInfo.self, from: result.stdout) else {
            return .failure(FetchError(genericError))
        }
        if info.isPlaylist { return .failure(FetchError(playlistError)) }
        return .success(info)
    }

    nonisolated private static func message(fromStderr data: Data) -> String {
        ProcessOutput.message(fromStderr: data, fallback: genericError)
    }
}
