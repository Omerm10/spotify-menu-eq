import Foundation
import Darwin

@main struct HelperProcessTests {
    @MainActor static func main() throws {
        let args = CommandLine.arguments
        if args.contains("--orphan-owner") {
            let child = try EqHelper(gains: [0, 0, 0, 0, 0], launchArgument: "--helper-hang")
            child.start(onReady: {}, onFailure: { _ in })
            RunLoop.current.run(until: Date().addingTimeInterval(0.2))
            print(child.workerPID); fflush(stdout)
            _exit(0)
        }
        if let mode = args.dropFirst().first, mode.hasPrefix("--helper-") {
            WorkerProtocol.watchParent(pid_t(args[2]) ?? 0)
            let report = ProcessInfo.processInfo.environment["EQ_TEST_REPORT"]!
            switch mode {
            case "--helper-delayed":
                Thread.sleep(forTimeInterval: 0.3)
                try JSONEncoder().encode(args.dropFirst(3).compactMap(Double.init)).write(to: URL(fileURLWithPath: report), options: .atomic)
                WorkerProtocol.send("READY")
                while let line = readLine() {
                    if let gains = EQCommand.decode(line) {
                        try JSONEncoder().encode(gains).write(to: URL(fileURLWithPath: report), options: .atomic)
                        WorkerProtocol.send("APPLIED " + gains.map(String.init(describing:)).joined(separator: " "))
                    }
                }
            case "--helper-fragmented":
                for byte in Data("ERROR Audio café unavailable\n".utf8) {
                    FileHandle.standardOutput.write(Data([byte]))
                    usleep(1000)
                }
            case "--helper-oversize":
                FileHandle.standardOutput.write(Data(repeating: 65, count: 9000))
                Thread.sleep(forTimeInterval: 3)
            case "--helper-stalled-audio":
                WorkerProtocol.send("READY")
                for _ in 0..<30 {
                    WorkerProtocol.send("HEALTH capturedFrames=512 renderedFrames=512")
                    Thread.sleep(forTimeInterval: 0.05)
                }
            case "--helper-slow-stop":
                signal(SIGTERM, SIG_IGN)
                WorkerProtocol.send("READY")
                Thread.sleep(forTimeInterval: 10)
            case "--helper-blocked":
                WorkerProtocol.send("READY")
                Thread.sleep(forTimeInterval: 10)
            case "--helper-hang":
                Thread.sleep(forTimeInterval: 10)
            case "--helper-crash": exit(7)
            default: exit(2)
            }
            return
        }
        let report = FileManager.default.temporaryDirectory.appendingPathComponent("eq-helper-\(UUID().uuidString).json")
        setenv("EQ_TEST_REPORT", report.path, 1)
        defer { try? FileManager.default.removeItem(at: report) }
        var failures = 0
        func expect(_ condition: Bool, _ label: String) {
            print("\(condition ? "PASS" : "FAIL") \(label)")
            if !condition { failures += 1 }
        }
        func spin(_ seconds: TimeInterval) { RunLoop.current.run(until: Date().addingTimeInterval(seconds)) }
        let zero = [Double](repeating: 0, count: 5)
        let desired: [Double] = [5, 2, -2, 0, 0]
        do {
            let helper = try EqHelper(gains: zero, launchArgument: "--helper-delayed")
            var ready = false
            var error: String?
            helper.start(onReady: { ready = true }, onFailure: { error = $0 })
            helper.setEQ(gains: desired)
            spin(0.7)
            let applied = try JSONDecoder().decode([Double].self, from: Data(contentsOf: report))
            expect(ready && error == nil && applied == desired && helper.appliedGains == desired, "latest preset applied and acknowledged after startup")
            helper.stop(); spin(0.3)
            expect(!helper.isRunning, "worker exits on EOF")
        }
        for (mode, timeout, expected) in [
            ("--helper-fragmented", 2.0, "Audio café unavailable"),
            ("--helper-oversize", 2.0, "size limit"),
            ("--helper-crash", 2.0, "exited (7)"),
            ("--helper-hang", 0.2, "timed out")
        ] {
            let helper = try EqHelper(gains: zero, launchArgument: mode, startupTimeout: timeout)
            var errors: [String] = []
            helper.start(onReady: {}, onFailure: { errors.append($0) })
            spin(0.8)
            expect(errors.count == 1 && errors[0].contains(expected) && !helper.isRunning, "\(mode): single clear failure and cleanup")
            helper.stop()
        }
        do {
            let helper = try EqHelper(gains: zero, launchArgument: "--helper-blocked")
            var ready = false
            var errors = 0
            helper.start(onReady: { ready = true }, onFailure: { _ in errors += 1 })
            spin(0.2)
            let start = Date()
            for index in 0..<20_000 { helper.setEQ(gains: [Double(index % 9), 0, 0, 0, 0]) }
            expect(ready && Date().timeIntervalSince(start) < 1, "blocked pipe cannot block the main actor")
            spin(2.5)
            expect(errors == 1 && !helper.isRunning, "blocked settings transport times out and cleans up")
            helper.stop()
        }
        do {
            let helper = try EqHelper(gains: zero, launchArgument: "--helper-hang", startupTimeout: 0.3)
            var callbacks = 0
            helper.start(onReady: { callbacks += 1 }, onFailure: { _ in callbacks += 1 })
            helper.stop(); spin(0.6)
            expect(callbacks == 0 && !helper.isRunning, "cancelled startup never emits stale callbacks")
        }
        do {
            let old = try EqHelper(gains: zero, launchArgument: "--helper-slow-stop")
            old.start(onReady: {}, onFailure: { _ in })
            spin(0.2)
            old.stop()
            let replacement = try EqHelper(gains: zero, launchArgument: "--helper-delayed")
            var ready = false
            var overlap = false
            replacement.start(onReady: { ready = true; overlap = old.isRunning }, onFailure: { _ in })
            spin(1.7)
            expect(ready && !overlap && !old.isRunning, "rapid Off/On waits for previous muting worker to exit")
            replacement.stop(); spin(0.3)
        }
        for playback in [false, true] {
            let helper = try EqHelper(gains: zero, launchArgument: "--helper-stalled-audio", healthTimeout: 0.3)
            var failure: String?
            helper.setPlaybackActive(playback)
            helper.start(onReady: {}, onFailure: { failure = $0 })
            spin(0.8)
            expect(playback ? failure?.contains("stopped progressing") == true : failure == nil,
                   playback ? "stalled audio detected while Spotify plays" : "paused Spotify does not trigger audio liveness failure")
            helper.stop(); spin(0.3)
        }
        do {
            let owner = Process()
            let pipe = Pipe()
            owner.executableURL = Bundle.main.executableURL
            owner.arguments = ["--orphan-owner"]
            owner.standardOutput = pipe
            try owner.run()
            try pipe.fileHandleForWriting.close()
            owner.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            try pipe.fileHandleForReading.close()
            let pid = pid_t(String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines))
            spin(1.2)
            expect(owner.terminationStatus == 0 && pid != nil && Darwin.kill(pid!, 0) == -1 && errno == ESRCH,
                   "worker exits after abrupt parent death")
        }
        if failures > 0 { exit(1) }
    }
}
