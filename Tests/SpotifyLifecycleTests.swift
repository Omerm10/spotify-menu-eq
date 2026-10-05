import Foundation

@main struct SpotifyLifecycleTests {
    static func main() {
        precondition(SpotifyLifecycle.shouldShowMenu(spotifyRunning: true))
        precondition(!SpotifyLifecycle.shouldShowMenu(spotifyRunning: false))
        // Requested intent survives pause, Spotify quit, missing output, and sleep.
        let expected: [(Bool, Bool, Bool, Bool, Bool, EQRuntimeState)] = [
            (false, true, true, true, false, .active),
            (false, true, false, true, false, .waitingForPlayback),
            (false, false, false, true, false, .waitingForSpotify),
            (false, true, true, false, false, .waitingForOutput),
            (true, true, true, true, false, .sleeping),
            (false, true, true, true, true, .failed)
        ]
        for (sleeping, running, playing, output, failed, state) in expected {
            precondition(SpotifyLifecycle.target(desired: true, sleeping: sleeping, spotifyRunning: running,
                playing: playing, outputAvailable: output, failed: failed) == state)
            precondition(SpotifyLifecycle.target(desired: false, sleeping: sleeping, spotifyRunning: running,
                playing: playing, outputAvailable: output, failed: failed) == .off)
        }
        print("Desired EQ intent, dependency loss, sleep, failure, and manual cancellation passed")
    }
}
