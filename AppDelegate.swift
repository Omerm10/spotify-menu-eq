import AppKit
import SwiftUI

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate {
    private var player: Player!
    private var item: NSStatusItem!
    private let popover = NSPopover()
    func applicationDidFinishLaunching(_ notification: Notification) {
        player = Player()
        item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(systemSymbolName: "waveform", accessibilityDescription: "Spotify Menu EQ")
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
        popover.behavior = .transient
        // Keep content transparent so the system popover material remains visible.
        let contentController = NSHostingController(rootView: PlayerView(player: player))
        contentController.sizingOptions = [.preferredContentSize]
        popover.contentViewController = contentController
        popover.contentSize = contentController.view.fittingSize
        item.isVisible = SpotifyLifecycle.shouldShowMenu(spotifyRunning: spotifyIsRunning())
        let center = NSWorkspace.shared.notificationCenter
        center.addObserver(self, selector: #selector(willSleep), name: NSWorkspace.willSleepNotification, object: nil)
        center.addObserver(self, selector: #selector(didWake), name: NSWorkspace.didWakeNotification, object: nil)
        center.addObserver(self, selector: #selector(spotifyLaunched(_:)),
                           name: NSWorkspace.didLaunchApplicationNotification, object: nil)
        center.addObserver(self, selector: #selector(spotifyTerminated(_:)),
                           name: NSWorkspace.didTerminateApplicationNotification, object: nil)
        if CommandLine.arguments.contains("--show-controls") {
            DispatchQueue.main.async { [weak self] in self?.showControls() }
        }
    }
    @objc private func spotifyLaunched(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.bundleIdentifier == "com.spotify.client" else { return }
        item.isVisible = true
        player.refresh()
    }
    @objc private func spotifyTerminated(_ notification: Notification) {
        guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication,
              app.bundleIdentifier == "com.spotify.client" else { return }
        player.spotifyDidQuit()
        item.isVisible = false
        popover.performClose(nil)
    }
    @objc private func togglePopover() {
        guard let button = item.button else { return }
        if popover.isShown { popover.performClose(nil) }
        else { player.refresh(); popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY) }
    }
    @objc private func willSleep() { player.willSleep() }
    @objc private func didWake() { player.didWake() }
    private func showControls() {
        item.isVisible = true
        if !popover.isShown { togglePopover() }
    }
    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        showControls()
        return true
    }
    func applicationWillTerminate(_ notification: Notification) {
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        player?.shutdown()
    }
}
