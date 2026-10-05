import AppKit
import SwiftUI
import CoreAudio

@MainActor protocol EQWorkerControlling: AnyObject {
    func start(onReady: @escaping () -> Void, onFailure: @escaping (String) -> Void)
    func setEQ(gains: [Double])
    func stop()
    func setPlaybackActive(_ active: Bool)
    var diagnosticSummary: String { get }
}
extension EQWorkerControlling {
    func setPlaybackActive(_ active: Bool) {}
    var diagnosticSummary: String { "" }
}
extension EqHelper: EQWorkerControlling {}

@MainActor final class Player: ObservableObject {
    @Published var title = "Nothing playing"
    @Published var artist = "Open Spotify to start"
    @Published var artwork: NSImage?
    @Published var playing = false
    @Published var position = 0.0
    @Published var duration = 0.0
    @Published private(set) var gains: [Double]
    @Published private(set) var selectedPreset: String
    @Published private(set) var desiredEQEnabled: Bool
    @Published private(set) var eqEnabled = false
    @Published private(set) var eqStarting = false
    @Published private(set) var runtimeState = EQRuntimeState.off
    @Published private(set) var issue: PlayerIssue?
    @Published private(set) var status = "EQ is off"
    lazy var loginItem = LoginItemService()
    private let settings: SettingsStore
    private let automation: any SpotifyControlling
    private let running: () -> Bool
    private let readRoute: () -> OutputRoute?
    private let makeWorker: @MainActor ([Double]) throws -> any EQWorkerControlling
    private let now: () -> Date
    private var helper: (any EQWorkerControlling)?
    private var generation = 0
    private var metadataGeneration = 0
    private var outputRoute: OutputRoute?
    private var routeReadyAt = Date.distantPast
    private var sleeping = false
    private var stopped = false
    private var failureLatched = false
    private var automationDenied = false
    private var timer: Timer?
    private var refreshTask: Task<Void, Never>?
    private var commandTask: Task<Void, Never>?
    private var artworkTask: Task<Void, Never>?
    private var artworkURL = ""

    init(settings: SettingsStore = SettingsStore(),
         automation: any SpotifyControlling = SpotifyAutomation(),
         running: @escaping () -> Bool = spotifyIsRunning,
         readRoute: (() -> OutputRoute?)? = nil,
         makeWorker: @escaping @MainActor ([Double]) throws -> any EQWorkerControlling = { try EqHelper(gains: $0) },
         now: @escaping () -> Date = Date.init,
         startMonitoring: Bool = true) {
        self.settings = settings
        self.automation = automation
        self.running = running
        self.readRoute = readRoute ?? Self.defaultOutputRoute
        self.makeWorker = makeWorker
        self.now = now
        let saved = settings.load()
        gains = saved.gains
        selectedPreset = saved.preset
        desiredEQEnabled = saved.desiredEQEnabled
        outputRoute = self.readRoute()
        guard startMonitoring else { return }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
    }
    private func persist() {
        settings.save(AppSettings(gains: gains, preset: selectedPreset, desiredEQEnabled: desiredEQEnabled))
    }
    private static func defaultOutputRoute() -> OutputRoute? {
        var address = AudioObjectPropertyAddress(mSelector: kAudioHardwarePropertyDefaultOutputDevice,
            mScope: kAudioObjectPropertyScopeGlobal, mElement: kAudioObjectPropertyElementMain)
        var device: AudioObjectID = 0
        var size = UInt32(MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(AudioObjectID(kAudioObjectSystemObject), &address, 0, nil, &size, &device) == noErr,
              device != 0 else { return nil }
        address.mSelector = kAudioDevicePropertyNominalSampleRate
        var rate = 0.0
        size = UInt32(MemoryLayout<Double>.size)
        guard AudioObjectGetPropertyData(device, &address, 0, nil, &size, &rate) == noErr,
              rate.isFinite, rate > 0 else { return nil }
        return OutputRoute(id: device, sampleRate: rate)
    }
    private func checkOutputRoute() {
        let current = readRoute()
        let action = OutputRouteTransition.action(previous: outputRoute, current: current, eqRequested: desiredEQEnabled)
        outputRoute = current
        guard action != .none else { return }
        stopWorker()
        runtimeState = current == nil ? .waitingForOutput : .starting
        status = current == nil ? "Waiting for an audio output…" : "Output changed; reconnecting EQ…"
        failureLatched = false
        if case .audioFailed = issue { issue = nil }
        routeReadyAt = now().addingTimeInterval(1)
    }
    func refresh() {
        guard !stopped, !sleeping else { return }
        checkOutputRoute()
        guard running() else {
            clearMetadata()
            reconcile()
            return
        }
        guard !automationDenied, refreshTask == nil, commandTask == nil else { reconcile(); return }
        let token = metadataGeneration
        refreshTask = Task { [weak self] in
            guard let self else { return }
            defer { self.refreshTask = nil }
            do {
                let snapshot = try await self.automation.snapshot()
                guard !Task.isCancelled, self.metadataGeneration == token, !self.stopped else { return }
                self.playing = snapshot.playing
                self.title = snapshot.title
                self.artist = snapshot.artist
                self.position = snapshot.position
                self.duration = snapshot.duration
                self.loadArtwork(snapshot.artworkURL)
                if case .audioFailed = self.issue {} else { self.issue = nil }
            } catch {
                guard !Task.isCancelled, self.metadataGeneration == token, !self.stopped else { return }
                self.playing = false
                self.issue = (error as? PlayerIssue) ?? .automationFailed(error.localizedDescription)
                self.automationDenied = self.issue == .automationDenied
            }
            self.reconcile()
        }
    }
    private func reconcile() {
        helper?.setPlaybackActive(playing)
        let target = SpotifyLifecycle.target(desired: desiredEQEnabled, sleeping: sleeping,
            spotifyRunning: running(), playing: playing, outputAvailable: outputRoute != nil,
            failed: failureLatched || issue != nil)
        guard target == .active else {
            // Pausing keeps an established tap; unavailable dependencies always release it.
            if target != .waitingForPlayback { stopWorker() }
            runtimeState = target
            switch target {
            case .off: status = "EQ is off"
            case .sleeping: status = "EQ suspended during sleep"
            case .waitingForSpotify: status = "Waiting for Spotify to play…"
            case .waitingForOutput: status = "Waiting for an audio output…"
            case .waitingForPlayback: status = "Waiting for Spotify to play…"
            case .failed: status = issue?.message ?? "EQ needs a retry"
            default: break
            }
            return
        }
        guard now() >= routeReadyAt else {
            runtimeState = .starting
            status = "Output changed; reconnecting EQ…"
            return
        }
        guard helper == nil else {
            runtimeState = eqStarting ? .starting : .active
            status = eqStarting ? "Starting EQ…" : "Spotify EQ active"
            return
        }
        generation += 1
        let token = generation
        eqStarting = true
        runtimeState = .starting
        status = "Starting EQ… Approve macOS audio capture if prompted."
        do {
            let session = try makeWorker(gains)
            helper = session
            session.start(onReady: { [weak self] in
                guard let self, self.generation == token else { return }
                self.helper?.setEQ(gains: self.gains)
                self.eqEnabled = true
                self.eqStarting = false
                self.reconcile()
            }, onFailure: { [weak self] message in
                guard let self, self.generation == token else { return }
                self.stopWorker()
                self.failureLatched = true
                self.issue = .audioFailed(message)
                self.runtimeState = .failed
                self.status = message
            })
        } catch {
            stopWorker()
            failureLatched = true
            issue = .audioFailed(error.localizedDescription)
            runtimeState = .failed
            status = issue!.message
        }
    }
    private func stopWorker() {
        generation += 1
        helper?.stop()
        helper = nil
        eqEnabled = false
        eqStarting = false
    }
    func enableEQ(_ on: Bool) {
        desiredEQEnabled = on
        persist()
        if on { retry() }
        else { stopWorker(); reconcile() }
    }
    func retry() {
        failureLatched = false
        automationDenied = false
        issue = nil
        refresh()
    }
    /// A support report intentionally excludes track names, artwork URLs, and listening history.
    func diagnosticReport() -> String {
        ["state=\(runtimeState)", "requested=\(desiredEQEnabled)",
         "output=\(outputRoute?.id.description ?? "unavailable")",
         "sampleRate=\(outputRoute?.sampleRate.description ?? "unavailable")",
         "gains=\(gains)", "status=\(status)", helper?.diagnosticSummary ?? "worker=stopped"].joined(separator: "\n")
    }
    func performRecovery(_ action: RecoveryAction) {
        switch action {
        case .retry: retry()
        case .openLoginSettings: loginItem.openSettings()
        case .openAutomationSettings:
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_Automation") { NSWorkspace.shared.open(url) }
        case .openAudioCaptureSettings:
            if let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ScreenCapture") { NSWorkspace.shared.open(url) }
        }
    }
    func spotifyDidQuit() {
        metadataGeneration += 1
        clearMetadata()
        stopWorker()
        failureLatched = false
        if !automationDenied { issue = nil }
        reconcile()
    }
    func willSleep() {
        sleeping = true
        metadataGeneration += 1
        stopWorker()
        reconcile()
    }
    func didWake() {
        sleeping = false
        playing = false
        failureLatched = false
        if !automationDenied { issue = nil }
        outputRoute = readRoute()
        routeReadyAt = now().addingTimeInterval(1)
        refresh()
    }
    func shutdown() {
        stopped = true
        metadataGeneration += 1
        timer?.invalidate()
        timer = nil
        refreshTask?.cancel()
        commandTask?.cancel()
        artworkTask?.cancel()
        stopWorker()
    }
    private func command(_ text: String) {
        guard commandTask == nil, !stopped, !sleeping else { return }
        commandTask = Task { [weak self] in
            guard let self else { return }
            do { _ = try await self.automation.execute(text) }
            catch {
                guard !Task.isCancelled, !self.stopped else { self.commandTask = nil; return }
                self.issue = (error as? PlayerIssue) ?? .automationFailed(error.localizedDescription)
                self.automationDenied = self.issue == .automationDenied
            }
            self.commandTask = nil
            self.refresh()
        }
    }
    func back() { command("previous track") }
    func toggle() { command("playpause") }
    func next() { command("next track") }
    func seek(_ value: Double) {
        guard value.isFinite else { return }
        command("set player position to \(max(0, min(value, duration)))")
    }
    func preset(_ preset: EQPreset) {
        guard preset.gains.count == EQBand.allCases.count,
              preset.gains.allSatisfy({ $0.isFinite && (-9...9).contains($0) }) else { return }
        selectedPreset = preset.name
        gains = preset.gains
        helper?.setEQ(gains: gains)
        persist()
    }
    func setBand(_ band: EQBand, gain: Double) {
        guard gain.isFinite else { return }
        selectedPreset = "Custom"
        gains[band.rawValue] = min(9, max(-9, gain))
        helper?.setEQ(gains: gains)
        persist()
    }
    private func clearMetadata() {
        playing = false
        title = "Nothing playing"
        artist = "Open Spotify to start"
        position = 0
        duration = 0
        loadArtwork("")
    }
    nonisolated private static func fetchArtwork(_ remote: URL) async throws -> Data? {
        let request = URLRequest(url: remote, timeoutInterval: 10)
        let (bytes, response) = try await URLSession.shared.bytes(for: request)
        guard let http = response as? HTTPURLResponse, http.statusCode == 200,
              response.expectedContentLength <= 5_000_000 else { return nil }
        var data = Data()
        for try await byte in bytes {
            try Task.checkCancellation()
            guard data.count < 5_000_000 else { return nil }
            data.append(byte)
        }
        return data
    }
    private func loadArtwork(_ url: String) {
        guard url != artworkURL else { return }
        artworkTask?.cancel()
        artworkURL = url
        artwork = nil
        guard let remote = URL(string: url), remote.scheme == "https" else { return }
        artworkTask = Task { [weak self] in
            do {
                guard let data = try await Self.fetchArtwork(remote),
                      let self, !Task.isCancelled, self.artworkURL == url else { return }
                self.artwork = NSImage(data: data)
            } catch { }
        }
    }
}
