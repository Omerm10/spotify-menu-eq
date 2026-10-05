import Foundation
import Darwin

/// Owns one worker session. Nonblocking pipe writes keep a stalled worker off the UI's critical path.
@MainActor final class EqHelper {
    private static var stoppingProcesses: [Process] = []
    private let process = Process()
    private let input = Pipe()
    private let output = Pipe()
    private let errors = Pipe()
    private let ioQueue = DispatchQueue(label: "eq.worker.read", qos: .utility)
    private var readers: [DispatchSourceRead] = []
    private var bytes = Data()
    private var ready = false
    private var started = false
    private var stopping = false
    private var desiredGains: [Double]
    private var pendingCommand: Data?
    private var writeBlockedSince: Date?
    private var flushScheduled = false
    private var onReady: (() -> Void)?
    private var onFailure: ((String) -> Void)?
    private let startupTimeout: TimeInterval
    private let healthTimeout: TimeInterval
    private var playbackExpected = false
    private var lastHeartbeat = 0.0
    private var lastAudioProgress = 0.0
    private var lastCaptured: UInt64 = 0
    private var lastRendered: UInt64 = 0
    private(set) var appliedGains: [Double]?
    private(set) var diagnostics = ""
    private(set) var lastHealth = ""

    init(gains: [Double], launchArgument: String = "--eq-helper", startupTimeout: TimeInterval = 20, healthTimeout: TimeInterval = 8) throws {
        guard Self.valid(gains), let executable = Bundle.main.executableURL else {
            throw NSError(domain: "EQWorker", code: 1, userInfo: [NSLocalizedDescriptionKey: "Invalid EQ configuration or missing executable."])
        }
        desiredGains = gains
        self.startupTimeout = startupTimeout
        self.healthTimeout = healthTimeout
        process.executableURL = executable
        process.arguments = [launchArgument, String(getpid())] + gains.map(String.init(describing:))
        process.standardInput = input
        process.standardOutput = output
        process.standardError = errors
    }

    var workerPID: Int32 { process.processIdentifier }
    var isRunning: Bool { started && process.isRunning }

    func start(onReady: @escaping () -> Void, onFailure: @escaping (String) -> Void) {
        guard !started, !stopping else { return }
        started = true
        self.onReady = onReady
        self.onFailure = onFailure
        launchWhenPreviousWorkerStops()
    }

    private func launchWhenPreviousWorkerStops() {
        guard !stopping else { return }
        Self.stoppingProcesses.removeAll { !$0.isRunning }
        guard Self.stoppingProcesses.isEmpty else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                self?.launchWhenPreviousWorkerStops()
            }
            return
        }
        process.terminationHandler = { [weak self] child in
            let code = child.terminationStatus
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                guard let self, !self.stopping else { return }
                self.fail("EQ worker exited (\(code)).")
            }
        }
        do {
            try process.run()
            try input.fileHandleForReading.close()
            try output.fileHandleForWriting.close()
            try errors.fileHandleForWriting.close()
            let fd = input.fileHandleForWriting.fileDescriptor
            guard fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK) != -1,
                  fcntl(fd, F_SETNOSIGPIPE, 1) != -1 else {
                throw NSError(domain: NSPOSIXErrorDomain, code: Int(errno))
            }
            read(output.fileHandleForReading, diagnostic: false)
            read(errors.fileHandleForReading, diagnostic: true)
        } catch {
            fail("Could not launch EQ worker: \(error.localizedDescription)")
            return
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + startupTimeout) { [weak self] in
            guard let self, !self.stopping, !self.ready else { return }
            self.fail("EQ startup timed out. Check audio capture permission, then retry.")
        }
    }

    private func read(_ handle: FileHandle, diagnostic: Bool) {
        let fd = handle.fileDescriptor
        _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK)
        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: ioQueue)
        source.setEventHandler { [weak self, weak source] in
            var chunk = [UInt8](repeating: 0, count: 4096)
            let count = Darwin.read(fd, &chunk, chunk.count)
            if count > 0 {
                let data = Data(chunk.prefix(count))
                // One chunk per reader can wait for the main actor. A noisy worker cannot
                // enqueue an unbounded number of closures or retained data buffers.
                DispatchQueue.main.sync { [weak self] in self?.receive(data, diagnostic: diagnostic) }
            } else if count == 0 || (errno != EAGAIN && errno != EINTR) {
                source?.cancel()
            }
        }
        source.setCancelHandler { try? handle.close() }
        readers.append(source)
        source.resume()
    }

    private func receive(_ data: Data, diagnostic: Bool) {
        guard !stopping else { return }
        if diagnostic {
            diagnostics += String(decoding: data, as: UTF8.self)
            diagnostics = String(diagnostics.suffix(4096))
            return
        }
        bytes.append(data)
        while let end = bytes.firstIndex(of: 10) {
            guard end - bytes.startIndex <= 8192,
                  let line = String(data: bytes[..<end], encoding: .utf8) else {
                fail("Invalid response from EQ worker.")
                return
            }
            bytes.removeSubrange(...end)
            if line == "READY" {
                guard !ready else { continue }
                ready = true
                lastHeartbeat = ProcessInfo.processInfo.systemUptime
                lastAudioProgress = lastHeartbeat
                monitorHealth()
                // Replay the newest desired configuration, including edits during startup.
                setEQ(gains: desiredGains)
                guard !stopping else { return }
                onReady?()
            } else if line.hasPrefix("APPLIED "), let gains = EQCommand.decode("SET " + line.dropFirst(8)) {
                appliedGains = gains
            } else if line.hasPrefix("HEALTH ") {
                lastHealth = String(line.dropFirst(7))
                lastHeartbeat = ProcessInfo.processInfo.systemUptime
                let fields = lastHealth.split(separator: " ").reduce(into: [String: UInt64]()) { values, field in
                    let pair = field.split(separator: "=", maxSplits: 1)
                    if pair.count == 2, let value = UInt64(pair[1]) { values[String(pair[0])] = value }
                }
                if let captured = fields["capturedFrames"], let rendered = fields["renderedFrames"] {
                    if captured > lastCaptured && rendered > lastRendered { lastAudioProgress = lastHeartbeat }
                    lastCaptured = captured
                    lastRendered = rendered
                }
            } else if line.hasPrefix("ERROR ") {
                fail(String(line.dropFirst(6)))
                return
            } else if line.hasPrefix("STAGE ") {
                lastHealth = String(line.dropFirst(6))
            } else {
                fail("Unexpected response from EQ worker.")
                return
            }
        }
        if bytes.count > 8192 { fail("EQ worker response exceeded its size limit.") }
    }

    func setEQ(gains: [Double]) {
        guard !stopping, Self.valid(gains) else { return }
        desiredGains = gains
        guard ready else { return }
        // A configuration is shorter than PIPE_BUF, so a nonblocking write is atomic.
        // Coalescing keeps both memory use and pending user intent bounded.
        pendingCommand = Data(EQCommand.encode(gains).utf8)
        flush()
    }

    private func flush() {
        guard !stopping, let command = pendingCommand else { return }
        let written = command.withUnsafeBytes { Darwin.write(input.fileHandleForWriting.fileDescriptor, $0.baseAddress, $0.count) }
        if written == command.count {
            pendingCommand = nil
            writeBlockedSince = nil
        } else if written == -1 && (errno == EAGAIN || errno == EINTR) {
            let now = Date()
            if writeBlockedSince == nil { writeBlockedSince = now }
            guard now.timeIntervalSince(writeBlockedSince!) < 2 else {
                fail("EQ worker stopped accepting settings. Retry EQ.")
                return
            }
            guard !flushScheduled else { return }
            flushScheduled = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { [weak self] in
                guard let self else { return }
                self.flushScheduled = false
                self.flush()
            }
        } else {
            fail("Lost communication with EQ worker. Retry EQ.")
        }
    }

    func setPlaybackActive(_ active: Bool) {
        if playbackExpected != active { lastAudioProgress = ProcessInfo.processInfo.systemUptime }
        playbackExpected = active
    }

    var diagnosticSummary: String { lastHealth + (diagnostics.isEmpty ? "" : "\n" + diagnostics) }

    private func monitorHealth() {
        DispatchQueue.main.asyncAfter(deadline: .now() + min(1, healthTimeout / 2)) { [weak self] in
            guard let self, self.ready, !self.stopping else { return }
            let now = ProcessInfo.processInfo.systemUptime
            if now - self.lastHeartbeat > self.healthTimeout {
                self.fail("EQ worker stopped responding. Retry EQ.")
            } else if self.playbackExpected && now - self.lastAudioProgress > self.healthTimeout {
                self.fail("Spotify is playing but EQ audio stopped progressing. Retry EQ.")
            } else { self.monitorHealth() }
        }
    }

    private static func valid(_ gains: [Double]) -> Bool {
        gains.count == EQBand.allCases.count && gains.allSatisfy { $0.isFinite && (-9...9).contains($0) }
    }

    private func fail(_ message: String) {
        guard !stopping else { return }
        let callback = onFailure
        stop()
        callback?(message)
    }

    func stop() {
        guard !stopping else { return }
        stopping = true
        pendingCommand = nil
        onReady = nil
        onFailure = nil
        readers.forEach { $0.cancel() }
        readers.removeAll()
        // EOF requests orderly teardown. Escalation also contains a blocked HAL call.
        try? input.fileHandleForWriting.close()
        guard process.isRunning else { return }
        let child = process
        Self.stoppingProcesses.append(child)
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 0.2) {
            if child.isRunning { child.terminate() }
        }
        DispatchQueue.global(qos: .utility).asyncAfter(deadline: .now() + 1) {
            if child.isRunning { _ = Darwin.kill(child.processIdentifier, SIGKILL) }
        }
    }
}
