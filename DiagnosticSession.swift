import Foundation

/// Explicit, opt-in support session using the real controller and isolated preferences.
/// Reports counters and lifecycle changes without storing music or track metadata.
enum DiagnosticSession {
    @MainActor static func run(seconds: TimeInterval) -> Int32 {
        let suite = "com.omerm.spotify-menu-eq-v1.diagnostic.\(UUID().uuidString)"
        guard let defaults = UserDefaults(suiteName: suite) else { return 1 }
        defer { defaults.removePersistentDomain(forName: suite) }
        let player = Player(settings: SettingsStore(defaults: defaults))
        player.enableEQ(true)
        var activeSeen = false
        var failuresSeen = false
        let deadline = Date().addingTimeInterval(seconds)
        while Date() < deadline {
            RunLoop.current.run(until: min(deadline, Date().addingTimeInterval(2)))
            activeSeen = activeSeen || player.eqEnabled
            failuresSeen = failuresSeen || player.runtimeState == .failed
            print(player.diagnosticReport().replacingOccurrences(of: "\n", with: " | "))
            fflush(stdout)
        }
        player.enableEQ(false)
        player.shutdown()
        RunLoop.current.run(until: Date().addingTimeInterval(1.2))
        return activeSeen && !failuresSeen ? 0 : 1
    }
}
