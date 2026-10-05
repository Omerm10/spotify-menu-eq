import AppKit
import Darwin

func spotifyIsRunning() -> Bool {
    !NSRunningApplication.runningApplications(withBundleIdentifier: "com.spotify.client").isEmpty
}

struct SpotifySnapshot {
    var playing = false
    var title = "Nothing playing"
    var artist = "Open Spotify to start"
    var position = 0.0
    var duration = 0.0
    var artworkURL = ""
}

protocol SpotifyControlling: Sendable {
    func execute(_ command: String) async throws -> String
    func snapshot() async throws -> SpotifySnapshot
}

// One serial worker bounds process concurrency; the main actor never waits on AppleEvents.
final class SpotifyAutomation: SpotifyControlling, @unchecked Sendable {
    private let queue = DispatchQueue(label: "spotify.automation", qos: .utility)
    private let executable: URL
    private let arguments: @Sendable (String) -> [String]
    private let isRunning: @Sendable () -> Bool
    private let timeout: TimeInterval
    private let outputLimit = 65_536

    init(executable: URL = URL(fileURLWithPath: "/usr/bin/osascript"),
         timeout: TimeInterval = 4,
         isRunning: @escaping @Sendable () -> Bool = { spotifyIsRunning() },
         arguments: @escaping @Sendable (String) -> [String] = { command in
             ["-e", "with timeout of 3 seconds\n tell application \"Spotify\"\n\(command)\n end tell\nend timeout"]
         }) {
        self.executable = executable
        self.timeout = timeout
        self.isRunning = isRunning
        self.arguments = arguments
    }

    func execute(_ command: String) async throws -> String {
        try await withCheckedThrowingContinuation { continuation in
            queue.async {
                do { continuation.resume(returning: try self.run(command)) }
                catch { continuation.resume(throwing: error) }
            }
        }
    }

    private func run(_ command: String) throws -> String {
        guard isRunning() else { throw PlayerIssue.spotifyUnavailable }
        let process = Process()
        let output = Pipe()
        let errors = Pipe()
        process.executableURL = executable
        process.arguments = arguments(command)
        process.standardOutput = output
        process.standardError = errors
        defer {
            try? output.fileHandleForReading.close()
            try? output.fileHandleForWriting.close()
            try? errors.fileHandleForReading.close()
            try? errors.fileHandleForWriting.close()
        }
        do { try process.run() }
        catch { throw PlayerIssue.automationFailed(error.localizedDescription) }
        try? output.fileHandleForWriting.close()
        try? errors.fileHandleForWriting.close()
        defer {
            if process.isRunning { _ = Darwin.kill(process.processIdentifier, SIGKILL) }
            process.waitUntilExit()
        }
        let handles = [output.fileHandleForReading, errors.fileHandleForReading]
        let descriptors = handles.map(\.fileDescriptor)
        for fd in descriptors {
            guard fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK) != -1 else {
                throw PlayerIssue.automationFailed("Cannot read Spotify response.")
            }
        }
        var collected = [Data(), Data()]
        var open = [true, true]
        let deadline = ProcessInfo.processInfo.systemUptime + timeout
        var buffer = [UInt8](repeating: 0, count: 4096)
        while open.contains(true) || process.isRunning {
            guard ProcessInfo.processInfo.systemUptime < deadline else { throw PlayerIssue.automationTimedOut }
            var events = descriptors.enumerated().map { index, fd in
                pollfd(fd: open[index] ? fd : -1, events: Int16(POLLIN | POLLHUP), revents: 0)
            }
            _ = poll(&events, nfds_t(events.count), 10)
            for index in 0..<events.count where open[index] && events[index].revents != 0 {
                let count = Darwin.read(descriptors[index], &buffer, buffer.count)
                if count > 0 {
                    guard collected[0].count + collected[1].count + count <= outputLimit else {
                        throw PlayerIssue.automationFailed("Spotify response exceeded its size limit.")
                    }
                    collected[index].append(contentsOf: buffer.prefix(count))
                } else if count == 0 { open[index] = false }
                else if errno != EAGAIN && errno != EINTR {
                    throw PlayerIssue.automationFailed("Cannot read Spotify response.")
                }
            }
        }
        process.waitUntilExit()
        let text = String(decoding: collected[0], as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        let error = String(decoding: collected[1], as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
        guard process.terminationStatus != 0 else { return text }
        if error.contains("-600") { throw PlayerIssue.spotifyUnavailable }
        if error.contains("-1743") { throw PlayerIssue.automationDenied }
        if error.contains("-1712") { throw PlayerIssue.automationTimedOut }
        throw PlayerIssue.automationFailed(error.isEmpty ? "Spotify control exited (\(process.terminationStatus))." : String(error.prefix(500)))
    }
    func snapshot() async throws -> SpotifySnapshot {
        let raw = try await execute("""
        set separator to ASCII character 30
        set playbackState to player state as text
        if playbackState is not "playing" and playbackState is not "paused" then return playbackState
        return playbackState & separator & (name of current track) & separator & (artist of current track) & separator & (player position as text) & separator & (duration of current track as text) & separator & (artwork url of current track)
        """)
        let fields = raw.components(separatedBy: "\u{1e}")
        guard fields.count == 6 else { return SpotifySnapshot() }
        let position = Double(fields[3]) ?? 0
        let duration = (Double(fields[4]) ?? 0) / 1000
        return SpotifySnapshot(playing: fields[0] == "playing", title: fields[1], artist: fields[2],
                               position: position.isFinite ? max(0, position) : 0,
                               duration: duration.isFinite ? max(0, duration) : 0, artworkURL: fields[5])
    }
}
