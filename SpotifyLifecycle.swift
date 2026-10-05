import Foundation

enum EQRuntimeState: Equatable {
    case off, waitingForSpotify, waitingForPlayback, waitingForOutput, sleeping, starting, active, failed
}

enum SpotifyLifecycle {
    static func shouldShowMenu(spotifyRunning: Bool) -> Bool { spotifyRunning }

    static func target(desired: Bool, sleeping: Bool, spotifyRunning: Bool,
                       playing: Bool, outputAvailable: Bool, failed: Bool) -> EQRuntimeState {
        guard desired else { return .off }
        guard !sleeping else { return .sleeping }
        guard spotifyRunning else { return .waitingForSpotify }
        guard outputAvailable else { return .waitingForOutput }
        guard !failed else { return .failed }
        guard playing else { return .waitingForPlayback }
        return .active
    }
}
