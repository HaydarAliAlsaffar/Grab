import Foundation
import Observation

/// Runs one yt-dlp download at a time and reports progress.
@MainActor
@Observable
final class Downloader {
    enum State: Equatable {
        case idle
        /// A nil percent means unknown (yt-dlp reports none for trimmed downloads).
        case running(percent: Double?, status: String)
        case stopping
        case finished(fileURL: URL)
        case duplicate(fileURL: URL)
        case failed(message: String)
        case cancelled
    }

    private(set) var state: State = .idle
    /// Requests waiting for the current download to end (first in, first out).
    private var queue: [DownloadRequest] = []
    private var job: ProcessJob?
    private var generation = 0
    @ObservationIgnored private let recents: RecentStore
    @ObservationIgnored private let notifier: Notifier

    init(recents: RecentStore, notifier: Notifier) {
        self.recents = recents
        self.notifier = notifier
    }

    nonisolated static let genericError = "Download failed."

    var isRunning: Bool {
        if case .running = state { return true }
        return false
    }

    var isBusy: Bool {
        switch state {
        case .running, .stopping: true
        default: false
        }
    }

    /// Back to idle, unless a download is running or stopping.
    func reset() {
        guard !isBusy else { return }
        state = .idle
    }

    var queuedCount: Int { queue.count }

    /// Starts now when nothing is running, otherwise waits its turn.
    func enqueue(_ request: DownloadRequest) {
        if isBusy { queue.append(request) } else { start(request) }
    }

    private func startNext() {
        guard !isBusy, !queue.isEmpty else { return }
        start(queue.removeFirst())
    }

    /// Early failure before any process ran.
    private func fail(_ message: String) {
        state = .failed(message: message)
        notifier.failed(message: message)
        startNext()
    }

    func start(_ request: DownloadRequest) {
        guard !isBusy else { return }
        guard let ytDlp = Tools.locate("yt-dlp"), let ffmpeg = Tools.locate("ffmpeg") else {
            fail("yt-dlp or ffmpeg was not found.")
            return
        }
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: request.saveFolder.path, isDirectory: &isDir), isDir.boolValue else {
            fail("The save folder is missing.")
            return
        }
        // Fresh per-download temp directory inside the app's own temporary directory.
        let tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("grab-" + UUID().uuidString, isDirectory: true)
        do {
            try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        } catch {
            fail(Self.genericError)
            return
        }

        generation += 1
        let gen = generation
        let job = ProcessJob()
        self.job = job
        state = .running(percent: nil, status: "Checking...")
        let ffmpegDir = ffmpeg.deletingLastPathComponent()
        let checkArguments = Self.arguments(for: request, ffmpegDirectory: ffmpegDir, tempDirectory: tempDir, checkOnly: true)
        let arguments = Self.arguments(for: request, ffmpegDirectory: ffmpegDir, tempDirectory: tempDir)

        let expectedPasses = request.quality == .audioOnly ? 1 : 2
        let lastStatus = request.needsRecode ? "Converting..." : "Merging..."
        let report: @Sendable (Double, String) -> Void = { [weak self] percent, status in
            Task { @MainActor in self?.update(gen, percent, status) }
        }

        Task.detached {
            if let existing = await Self.existingFile(for: request, ytDlp: ytDlp, arguments: checkArguments, job: job) {
                await Self.removeDirectory(tempDir)
                await MainActor.run { [weak self] in self?.finish(gen, .duplicate(fileURL: existing), request) }
                return
            }
            if job.isCancelled {
                await Self.removeDirectory(tempDir)
                await MainActor.run { [weak self] in self?.finish(gen, .cancelled, request) }
                return
            }
            await MainActor.run { [weak self] in
                self?.update(gen, nil, request.trim == nil ? "Starting..." : "Downloading...")
            }
            var outcome = await Self.run(ytDlp: ytDlp, arguments: arguments, job: job,
                                         expectedPasses: expectedPasses, finalStatus: lastStatus,
                                         reportsPercent: request.trim == nil, progress: report)
            // A trimmed download sometimes fails once with an ffmpeg error. Try once more.
            if outcome.isTransientFailure, request.trim != nil, !job.isCancelled {
                await MainActor.run { [weak self] in self?.update(gen, nil, "Retrying...") }
                try? await Task.sleep(for: .seconds(2))
                await Self.removeDirectory(tempDir)
                try? FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
                outcome = await Self.run(ytDlp: ytDlp, arguments: arguments, job: job,
                                         expectedPasses: expectedPasses, finalStatus: lastStatus,
                                         reportsPercent: false, progress: report)
            }
            let result = outcome.state
            await Self.removeDirectory(tempDir)
            await MainActor.run { [weak self] in self?.finish(gen, result, request) }
        }
    }

    /// Stores the end state and fires the matching notification and Recent entry.
    private func finish(_ gen: Int, _ result: State, _ request: DownloadRequest) {
        guard generation == gen else { return }
        job = nil
        state = result
        switch result {
        case .finished(let url):
            recents.add(fileURL: url, title: request.title)
            notifier.saved(fileURL: url)
        case .duplicate(let url):
            recents.add(fileURL: url, title: request.title)
            notifier.info("Already downloaded", body: url.lastPathComponent, revealing: url)
        case .failed(let message):
            notifier.failed(message: message)
        default:
            break
        }
        startNext()
    }

    func cancel() {
        guard isRunning else { return }
        // Stay busy until the process has exited; the download task sets .cancelled.
        state = .stopping
        job?.cancel()
    }

    /// Removes a directory, retrying because ffmpeg children may still be writing into it.
    nonisolated private static func removeDirectory(_ url: URL) async {
        for attempt in 0..<6 {
            try? FileManager.default.removeItem(at: url)
            if !FileManager.default.fileExists(atPath: url.path) { return }
            if attempt < 5 { try? await Task.sleep(for: .milliseconds(500)) }
        }
    }

    private func update(_ gen: Int, _ percent: Double?, _ status: String) {
        guard generation == gen, isRunning else { return }
        state = .running(percent: percent, status: status)
    }

    // MARK: - Arguments

    /// The full yt-dlp argument list. The URL comes last, after "--".
    nonisolated static func arguments(for request: DownloadRequest, ffmpegDirectory: URL, tempDirectory: URL, checkOnly: Bool = false) -> [String] {
        // A trimmed clip gets its range in the name so it never collides with the full video.
        let trim = request.trim.flatMap { $0.isValid ? $0 : nil }
        let template = trim.map { "%(title).150B [\($0.fileLabel)].%(ext)s" } ?? "%(title).150B.%(ext)s"
        // The duplicate check only asks for the expected name. --print implies --simulate.
        let prints = checkOnly
            ? ["--print", "filename"]
            : ["--newline", "--progress", "--progress-template", "download:GRAB %(progress._percent_str)s",
               "--print", "after_move:filepath", "--print", "before_dl:GRABFMT %(format_id)s"]
        var args = [
            "--ignore-config", "--no-playlist", "--no-warnings",
        ] + prints + [
            "--ffmpeg-location", ffmpegDirectory.path,
            "--socket-timeout", "15",
            "-o", template,
            "-P", "home:" + request.saveFolder.path,
            "-P", "temp:" + tempDirectory.path,
        ]
        switch request.quality {
        case .height(let h):
            let format = request.videoFormat.rawValue
            args += ["-f", "bv*[height<=\(h)]+ba/b[height<=\(h)]",
                     "-S", "res,vcodec:h264,acodec:aac"]
            if request.needsRecode {
                // The chosen height has no codec MOV can hold. Merge into MKV (accepts
                // anything), then re-encode to MOV. Re-encode only when needed.
                args += ["--merge-output-format", "mkv", "--recode-video", format]
            } else {
                args += ["--merge-output-format", format, "--remux-video", format]
            }
        case .audioOnly:
            args += ["-f", "ba/b"]
            // Take YouTube's AAC stream as is instead of re-encoding Opus.
            if request.audioFormat == .m4a { args += ["-S", "acodec:aac"] }
            args += ["-x", "--audio-format", request.audioFormat.rawValue]
            // Cover art (jpg suits M4A and MP3 tags) and song info. The parse rule splits
            // "Artist - Song" titles; titles without " - " are left unchanged.
            args += ["--embed-thumbnail", "--convert-thumbnails", "jpg", "--embed-metadata",
                     "--parse-metadata", "title:%(meta_artist)s - %(meta_title)s"]
        }
        if request.skipSponsors { args += ["--sponsorblock-remove", "sponsor"] }
        if let trim {
            args += ["--download-sections", trim.sectionArgument, "--force-keyframes-at-cuts"]
        }
        args += ["--", request.url.absoluteString]
        return args
    }

    // MARK: - Process

    /// The file this request would produce, if it is already in the save folder.
    /// The printed name has the source extension, so it is swapped for the target container.
    nonisolated private static func existingFile(for request: DownloadRequest, ytDlp: URL,
                                                 arguments: [String], job: ProcessJob) async -> URL? {
        guard let result = await job.run(executable: ytDlp, arguments: arguments),
              result.status == 0 else { return nil }
        let printed = String(decoding: result.stdout, as: UTF8.self)
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .last { $0.hasPrefix("/") }
        guard let printed else { return nil }
        let target: String
        switch request.quality {
        case .audioOnly: target = request.audioFormat.rawValue
        case .height: target = request.videoFormat.rawValue
        }
        let url = URL(fileURLWithPath: printed).deletingPathExtension().appendingPathExtension(target)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }

    /// End state of one yt-dlp run. `isTransientFailure` marks a non-zero exit with an ffmpeg error.
    private struct Outcome: Sendable {
        let state: State
        var isTransientFailure = false
    }

    nonisolated private static func run(
        ytDlp: URL, arguments: [String], job: ProcessJob, expectedPasses initialPasses: Int, finalStatus: String,
        reportsPercent: Bool,
        progress: @escaping @Sendable (Double, String) -> Void
    ) async -> Outcome {
        let (process, out, err) = ProcessJob.makeProcess(executable: ytDlp, arguments: arguments)

        do {
            guard try job.start(process) else { return Outcome(state: .cancelled) }
        } catch {
            return Outcome(state: .failed(message: genericError))
        }

        let outHandle = out.fileHandleForReading
        let errHandle = err.fileHandleForReading
        async let finalPath = Task.detached { () -> (path: String?, tail: [String]) in
            var last: String?
            var tail: [String] = []
            var previous = 0.0
            var pass = 0
            var expectedPasses = initialPasses
            do {
                for try await raw in outHandle.bytes.lines {
                    let line = raw.trimmingCharacters(in: .whitespaces)
                    tail.append(line)
                    if tail.count > 20 { tail.removeFirst() }
                    if line.hasPrefix("GRABFMT ") {
                        // yt-dlp says whether video and audio come as separate streams ("a+b").
                        expectedPasses = line.contains("+") ? 2 : 1
                        pass = 0
                        previous = 0
                    } else if reportsPercent, line.hasPrefix("GRAB ") {
                        // Trimmed downloads print one stray 100% at the end, so they show no percent.
                        let value = line.dropFirst(5).replacingOccurrences(of: "%", with: "")
                            .trimmingCharacters(in: .whitespaces)
                        guard let d = Double(value), d.isFinite else { continue }
                        let pct = min(max(d, 0), 100)
                        // A big drop means the next stream (audio after video) started.
                        if previous >= 95 && pct < 5 { pass += 1 }
                        previous = pct
                        let index = min(pass, expectedPasses - 1)
                        let overall = min(1, (Double(index) + pct / 100) / Double(expectedPasses))
                        let done = index == expectedPasses - 1 && pct >= 100
                        progress(overall * 100, done ? finalStatus : "Downloading...")
                    } else if line.hasPrefix("/"), FileManager.default.fileExists(atPath: line) {
                        last = line
                    }
                }
            } catch {}
            return (last, tail)
        }.value
        async let errData = Task.detached { errHandle.readDataToEndOfFile() }.value
        let (output, stderr) = await (finalPath, errData)
        let path = output.path
        process.waitUntilExit()

        // A clean exit with a saved file wins over a late Cancel.
        if process.terminationStatus == 0, let path {
            return Outcome(state: .finished(fileURL: URL(fileURLWithPath: path)))
        }
        if job.isCancelled { return Outcome(state: .cancelled) }
        let status = process.terminationStatus
        DebugLog.write("Download failed, exit \(status)",
                       lines: [arguments.joined(separator: " ")] + DebugLog.lines(of: stderr) + output.tail)
        guard status == 0 else {
            let transient = String(decoding: stderr, as: UTF8.self).contains("ffmpeg exited with code")
            return Outcome(state: .failed(message: ProcessOutput.message(fromStderr: stderr, fallback: genericError)),
                           isTransientFailure: transient)
        }
        return Outcome(state: .failed(message: genericError))
    }
}
