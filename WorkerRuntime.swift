import Foundation
import Darwin

/// A worker owns one audio graph. Its parent can always terminate it if HAL stops responding.
enum WorkerRuntime {
    static func run(arguments: [String]) -> Int32 {
        guard arguments.count == 8, let parent = pid_t(arguments[2]),
              let gains = EQCommand.decode("SET " + arguments.dropFirst(3).joined(separator: " ")) else { return 2 }
        WorkerProtocol.watchParent(parent)
        do {
            let audio = try SpotifyAudio()
            audio.setEQ(gains: gains)
            WorkerProtocol.send("STAGE Preparing audio")
            try audio.start(onStage: { WorkerProtocol.send("STAGE " + $0) })
            defer { audio.stop() }
            // READY means samples have actually traversed the capture and render paths.
            // The parent bounds this wait as well as any blocking Core Audio setup call.
            let deadline = Date().addingTimeInterval(15)
            while true {
                if let metrics = audio.metrics(), metrics.capturedFrames > 0, metrics.renderedFrames > 0 { break }
                guard Date() < deadline else {
                    WorkerProtocol.send("ERROR No audio reached the EQ output. Check Spotify playback and audio capture permission, then retry.")
                    return 1
                }
                Thread.sleep(forTimeInterval: 0.02)
            }
            WorkerProtocol.send("APPLIED " + gains.map(String.init(describing:)).joined(separator: " "))
            WorkerProtocol.send("READY")
            let health = DispatchSource.makeTimerSource(queue: DispatchQueue(label: "eq.worker.health"))
            var lastCaptured: UInt64 = 0
            var lastRendered: UInt64 = 0
            var stalledTicks = 0
            health.schedule(deadline: .now() + 1, repeating: 1)
            health.setEventHandler {
                guard let current = audio.metrics() else { return }
                // No capture is expected while Spotify is paused; do not infer denial or a hang.
                if current.capturedFrames > lastCaptured && current.renderedFrames == lastRendered {
                    stalledTicks += 1
                } else { stalledTicks = 0 }
                lastCaptured = current.capturedFrames
                lastRendered = current.renderedFrames
                WorkerProtocol.send("HEALTH " + audio.diagnostics())
                if stalledTicks >= 5 {
                    WorkerProtocol.send("ERROR Audio capture continued but EQ output stopped. Retry EQ.")
                    _exit(1)
                }
            }
            health.resume()
            defer { health.cancel() }
            // Commands are intentionally small. Reject an oversized line before parsing it.
            var line = [CChar](repeating: 0, count: 4096)
            while fgets(&line, Int32(line.count), stdin) != nil {
                let command = String(cString: line)
                guard command.hasSuffix("\n") else {
                    WorkerProtocol.send("ERROR Invalid EQ command.")
                    return 2
                }
                if command.trimmingCharacters(in: .whitespacesAndNewlines) == "STOP" { break }
                guard let next = EQCommand.decode(command) else {
                    WorkerProtocol.send("ERROR Invalid EQ settings.")
                    return 2
                }
                audio.setEQ(gains: next)
                WorkerProtocol.send("APPLIED " + next.map(String.init(describing:)).joined(separator: " "))
            }
            return 0
        } catch {
            WorkerProtocol.send("ERROR " + error.localizedDescription)
            return 1
        }
    }
}
