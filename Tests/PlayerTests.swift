import Foundation

actor FakeSpotify: SpotifyControlling {
    var value = SpotifySnapshot(playing: true, title: "Test", artist: "Artist")
    var failure: PlayerIssue?
    func execute(_ command: String) async throws -> String { "" }
    func snapshot() async throws -> SpotifySnapshot {
        if let failure { throw failure }
        return value
    }
    func setPlaying(_ playing: Bool) { value.playing = playing }
    func setFailure(_ failure: PlayerIssue?) { self.failure = failure }
}

@MainActor final class FakeWorker: EQWorkerControlling {
    var gains: [Double]
    var ready: (() -> Void)?
    var failure: ((String) -> Void)?
    var stopped = false
    init(gains: [Double]) { self.gains = gains }
    func start(onReady: @escaping () -> Void, onFailure: @escaping (String) -> Void) {
        ready = onReady
        failure = onFailure
    }
    func setEQ(gains: [Double]) { self.gains = gains }
    func stop() { stopped = true }
}

@main struct PlayerTests {
    @MainActor static func settle(_ player: Player) async {
        player.refresh()
        for _ in 0..<20 { await Task.yield() }
        try? await Task.sleep(nanoseconds: 10_000_000)
    }
    @MainActor static func main() async {
        let suite = "eq.controller.tests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = SettingsStore(defaults: defaults)
        let spotify = FakeSpotify()
        var isRunning = true
        var route: OutputRoute? = OutputRoute(id: 10, sampleRate: 44_100)
        var clock = Date()
        var workers: [FakeWorker] = []
        let player = Player(settings: store, automation: spotify, running: { isRunning }, readRoute: { route },
            makeWorker: { gains in
                let worker = FakeWorker(gains: gains)
                workers.append(worker)
                return worker
            }, now: { clock }, startMonitoring: false)
        player.enableEQ(true)
        await settle(player)
        precondition(workers.count == 1 && player.eqStarting)
        player.preset(EQPreset.all[1])
        workers[0].ready?()
        precondition(workers[0].gains == EQPreset.all[1].gains && player.eqEnabled)

        await spotify.setPlaying(false)
        await settle(player)
        precondition(player.runtimeState == .waitingForPlayback && !workers[0].stopped)
        await spotify.setPlaying(true)
        await settle(player)
        precondition(player.runtimeState == .active && player.status == "Spotify EQ active")

        route = nil
        await settle(player)
        precondition(workers[0].stopped && player.desiredEQEnabled && player.runtimeState == .waitingForOutput)
        route = OutputRoute(id: 10, sampleRate: 44_100)
        await settle(player)
        clock += 2
        await settle(player)
        precondition(workers.count == 2)
        workers[1].ready?()

        await spotify.setPlaying(false)
        route = OutputRoute(id: 20, sampleRate: 48_000)
        await settle(player)
        isRunning = false
        player.spotifyDidQuit()
        precondition(player.desiredEQEnabled && workers[1].stopped)
        isRunning = true
        await spotify.setPlaying(true)
        clock += 2
        await settle(player)
        precondition(workers.count == 3)
        workers[2].ready?()

        route = OutputRoute(id: 20, sampleRate: 44_100)
        player.refresh()
        precondition(player.runtimeState == .starting && !player.eqEnabled)
        await settle(player)
        precondition(player.runtimeState == .starting && workers[2].stopped)
        player.enableEQ(false)
        clock += 2
        await settle(player)
        precondition(workers.count == 3 && !player.desiredEQEnabled && player.runtimeState == .off)
        workers[2].ready?() // Stale readiness must not resurrect a stopped session.
        precondition(!player.eqEnabled)

        player.enableEQ(true)
        await settle(player)
        precondition(workers.count == 4)
        workers[3].ready?()
        player.willSleep()
        precondition(workers[3].stopped && player.desiredEQEnabled)
        player.didWake()
        clock += 2
        await settle(player)
        precondition(workers.count == 5)
        workers[4].ready?()
        workers[4].failure?("Simulated capture error")
        await settle(player)
        precondition(workers.count == 5 && player.runtimeState == .failed)
        player.retry()
        await settle(player)
        precondition(workers.count == 6)

        await spotify.setFailure(.automationDenied)
        await settle(player)
        precondition(player.issue == .automationDenied && player.runtimeState == .failed)
        await spotify.setFailure(nil)
        await settle(player)
        precondition(workers.count == 6) // Permission denial requires explicit recovery.
        player.retry()
        await settle(player)
        precondition(workers.count == 7)
        player.shutdown()
        precondition(workers[6].stopped && store.load().desiredEQEnabled)
        precondition(store.load().gains == EQPreset.all[1].gains)
        print("Controller startup gain sync, route recovery, quit intent, pause/resume, cancellation, sleep/wake, failure/retry, permissions, and persistence passed")
    }
}
