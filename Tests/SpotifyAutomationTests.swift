import Foundation
import Darwin

@main struct SpotifyAutomationTests {
    static func main() async throws {
        if CommandLine.arguments.count > 1 {
            switch CommandLine.arguments[1] {
            case "success": print("playing")
            case "stderr": fputs("fixture error\n", stderr); exit(1)
            case "denied": fputs("Not authorized (-1743)\n", stderr); exit(1)
            case "timeout": sleep(10)
            case "overflow":
                let bytes = [UInt8](repeating: 65, count: 100_000)
                bytes.withUnsafeBytes { _ = fwrite($0.baseAddress, 1, $0.count, stdout) }
                fflush(stdout)
            case "snapshot": print("playing\u{1e}Title\u{1e}Artist\u{1e}1.5\u{1e}100000\u{1e}")
            default: exit(2)
            }
            return
        }
        let executable = URL(fileURLWithPath: CommandLine.arguments[0])
        func service(_ fixture: String) -> SpotifyAutomation {
            SpotifyAutomation(executable: executable, timeout: 1, isRunning: { true }, arguments: { _ in [fixture] })
        }
        let success = try await service("success").execute("unused")
        precondition(success == "playing")
        for fixture in ["stderr", "denied", "timeout", "overflow"] {
            let start = ProcessInfo.processInfo.systemUptime
            do { _ = try await service(fixture).execute("unused"); preconditionFailure("Expected \(fixture) failure") }
            catch let error as PlayerIssue {
                switch fixture {
                case "denied": precondition(error == .automationDenied)
                case "timeout": precondition(error == .automationTimedOut)
                case "overflow": precondition(error == .automationFailed("Spotify response exceeded its size limit."))
                default: precondition(error == .automationFailed("fixture error"))
                }
            }
            precondition(ProcessInfo.processInfo.systemUptime - start < 3)
        }
        let snapshot = try await service("snapshot").snapshot()
        precondition(snapshot.playing && snapshot.position == 1.5 && snapshot.duration == 100)
        let absent = SpotifyAutomation(executable: executable, isRunning: { false }, arguments: { _ in ["success"] })
        do { _ = try await absent.execute("unused"); preconditionFailure("Expected unavailable") }
        catch let error as PlayerIssue { precondition(error == .spotifyUnavailable) }
        print("Real process success, stderr, denied automation, timeout, bounded output, snapshot, and absent Spotify tests passed")
    }
}
