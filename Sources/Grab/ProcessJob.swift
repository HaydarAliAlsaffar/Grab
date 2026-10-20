import Foundation
import Darwin

/// Holds a running child process so it can be stopped from any thread.
// @unchecked Sendable: every access to `process` and `cancelled` happens under `lock`.
final class ProcessJob: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var cancelled = false

    /// A process with no input and two fresh pipes for output and errors.
    static func makeProcess(executable: URL, arguments: [String]) -> (process: Process, out: Pipe, err: Pipe) {
        let process = Process()
        process.executableURL = executable
        process.arguments = arguments
        process.standardInput = FileHandle.nullDevice
        let out = Pipe(), err = Pipe()
        process.standardOutput = out
        process.standardError = err
        return (process, out, err)
    }

    /// Returns false if the job was cancelled before it could start.
    func start(_ process: Process) throws -> Bool {
        lock.lock(); defer { lock.unlock() }
        if cancelled { return false }
        try process.run()
        self.process = process
        return true
    }

    var isCancelled: Bool {
        lock.lock(); defer { lock.unlock() }
        return cancelled
    }

    /// Runs the program to the end and returns its exit status and output.
    /// Nil if the job was cancelled before it started or the process could not launch.
    func run(executable: URL, arguments: [String]) async -> (status: Int32, stdout: Data, stderr: Data)? {
        let (process, out, err) = Self.makeProcess(executable: executable, arguments: arguments)
        do {
            guard try start(process) else { return nil }
        } catch {
            return nil
        }
        let outHandle = out.fileHandleForReading
        let errHandle = err.fileHandleForReading
        async let outData = Task.detached { outHandle.readDataToEndOfFile() }.value
        async let errData = Task.detached { errHandle.readDataToEndOfFile() }.value
        let (stdout, stderr) = await (outData, errData)
        process.waitUntilExit()
        return (process.terminationStatus, stdout, stderr)
    }

    /// SIGTERM now, SIGKILL after 2 seconds for anything still alive.
    /// The process's children (yt-dlp runs ffmpeg) get the same signals, because
    /// stopping only the parent can leave ffmpeg running.
    func cancel() {
        lock.lock(); defer { lock.unlock() }
        cancelled = true
        guard let p = process, p.isRunning else { return }
        let pid = p.processIdentifier
        let children = Self.childPIDs(of: pid)
        p.terminate()
        for child in children { kill(child, SIGTERM) }
        DispatchQueue.global().asyncAfter(deadline: .now() + 2) { [weak p] in
            var targets = children
            if let p, p.isRunning {
                targets += Self.childPIDs(of: pid)
                kill(pid, SIGKILL)
            }
            // Signal 0 only checks that the child is still there.
            for child in targets where kill(child, 0) == 0 { kill(child, SIGKILL) }
        }
    }

    /// Direct children of a process, from libproc. It returns the number of pids found.
    private static func childPIDs(of pid: pid_t) -> [pid_t] {
        var pids = [pid_t](repeating: 0, count: 64)
        let n = proc_listchildpids(pid, &pids, Int32(pids.count * MemoryLayout<pid_t>.size))
        guard n > 0 else { return [] }
        let me = getpid()
        return pids.prefix(min(Int(n), pids.count)).filter { $0 > 1 && $0 != me }
    }
}
