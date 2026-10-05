# Spotify Menu EQ

A native macOS menu-bar app that gives Spotify desktop audio a five-band equalizer, with playback controls and album artwork a click away.
Built with Swift, SwiftUI, and Apple's Core Audio process taps, with no third-party runtime dependencies.

**Early development release:** the source is available to build locally while the UI is being refined.
There is currently no Developer ID-signed, notarized app download.
The build supports Apple silicon and targets macOS 14.4 or later; hardware and OS coverage is still limited.

## Features

- Five adjustable bands: 80 Hz, 250 Hz, 1 kHz, 4 kHz, and 10 kHz, each with a -9 to +9 dB range.
- Six presets: Flat, Warm, Bass Boost, Voice Forward, Clarity, and Soft.
- Play/pause, previous/next track, seeking, track information, and album artwork.
- Saved EQ settings and an on/off switch; a fresh installation starts with EQ off.
- Spotify process audio capture, with recovery logic for playback, output-route, and lifecycle changes.
- Local diagnostics for troubleshooting audio and worker state.

This is an independent project and is not affiliated with or endorsed by Spotify.

## Requirements

- An Apple silicon Mac running macOS 14.4 or later.
- The Spotify desktop app.
- An installed Xcode toolchain with the macOS SDK and command-line tools selected.
- macOS permission to control Spotify and capture system audio.

Intel builds and the Spotify web player are not currently supported.

## Build and run

```sh
git clone https://github.com/Omerm10/spotify-menu-eq.git
cd spotify-menu-eq
zsh build.sh release
open "Spotify Menu EQ.app"
```

The build creates `Spotify Menu EQ.app` in the repository directory and applies an ad hoc signature for local development.
It does not produce a notarized distribution build.
For a debug build with symbols, run `zsh build.sh`.
Intermediate files and test executables are stored in `.build/`.

1. Open Spotify and start playing a track.
2. Click the waveform icon in the menu bar.
3. Enable EQ, then select a preset or adjust individual bands.
4. Approve the relevant macOS permission prompts when they appear.

The menu-bar icon normally hides when Spotify closes.
Reopen Spotify Menu EQ through Finder to reveal its controls even if Spotify is closed, or run:

```sh
"Spotify Menu EQ.app/Contents/MacOS/SpotifyMenuEQ" --show-controls
```

## Permissions and troubleshooting

Spotify playback controls use macOS Automation permission.
If control is denied, review **System Settings > Privacy & Security > Automation** and allow this app to control Spotify.
Audio processing also needs system audio capture permission; review the corresponding audio recording permission in Privacy & Security.
The label for this permission can differ between macOS versions.

If EQ is waiting, make sure Spotify is playing and an audio output is available.
Turning EQ off cancels pending startup and reconnection.
Spotify quitting, output loss, and sleep suspend processing without clearing your saved preference.
After resolving a failure, turn EQ off and on to retry.
A startup timeout alone does not mean permission was denied.

For a short diagnostic session while Spotify is playing:

```sh
"Spotify Menu EQ.app/Contents/MacOS/SpotifyMenuEQ" --diagnose-session 120
```

This session uses temporary settings and prints route, state, and worker counters.
It omits track metadata and does not record the audio stream.
Review diagnostic output before attaching it to an issue, since it can contain device names and system error details.

### Launch at login

Launch at login is opt-in and currently available through terminal commands while the settings UI is unfinished.
Keep the app in a stable location before registering it.

```sh
"Spotify Menu EQ.app/Contents/MacOS/SpotifyMenuEQ" --login-status
"Spotify Menu EQ.app/Contents/MacOS/SpotifyMenuEQ" --register-login
"Spotify Menu EQ.app/Contents/MacOS/SpotifyMenuEQ" --unregister-login
```

## Development

```sh
zsh test.sh
zsh build.sh release
```

Swift and C builds treat warnings as errors.
The test suite covers configuration, settings, Spotify automation, worker communication, controller lifecycle, the C audio transport, and offline audio rendering.
Tests use isolated preferences and synthetic processes; the offline audio tests do not start hardware playback.
Access to macOS audio components is required, so restrictive execution sandboxes can prevent those tests from running.

See [CONTRIBUTING.md](CONTRIBUTING.md) for contribution and bug-report guidance.

### How it works

The app captures Spotify's process audio through a Core Audio tap and routes it through an AVAudioEngine equalizer to the macOS default output device.
A separate worker process owns audio processing, while the menu-bar app coordinates state and playback controls.
A preallocated C stereo ring connects capture and rendering without blocking locks in the capture callback.
Album artwork is fetched from HTTPS URLs supplied by Spotify.
The app has no built-in telemetry or automatic diagnostic upload service.

| Area | Main files |
| --- | --- |
| Menu-bar app and interface | `AppDelegate.swift`, `PlayerView.swift`, `EqualizerView.swift` |
| State and lifecycle | `Player.swift`, `SpotifyLifecycle.swift`, `OutputRouteTransition.swift` |
| Playback controls | `SpotifyAutomation.swift` |
| Audio processing | `SpotifyAudio.swift`, `AudioTransport.c`, `AudioFormat.swift`, `EQConfiguration.swift` |
| Worker communication and recovery | `EqHelper.swift`, `WorkerProtocol.swift`, `WorkerRuntime.swift` |
| Settings and diagnostics | `AppSettings.swift`, `ReadinessServices.swift`, `DiagnosticSession.swift` |

## Current status and roadmap

The project has automated coverage and short live validation on built-in speakers and a Bluetooth route.
Those results do not establish reliability or latency across every Mac, macOS version, and audio device.
See the [validation record](docs/VALIDATION.md) for measurements and remaining physical test gates.

- Refine the UI, app icon, accessibility, settings, and permission recovery controls.
- Expand clean-install, permission, sleep/wake, login, and audio-device testing.
- Independently verify Spotify-only processing while another app is playing audio.
- Measure physical latency and clock drift across wired, Bluetooth, and USB outputs.
- Complete Developer ID signing, hardened runtime, notarization, and app packaging.

Rapid preset changes are not crossfaded; offline signal tests do not guarantee inaudible transitions for every input.
The [UI integration notes](docs/UI-INTEGRATION.md) describe the existing service contracts for interface work.
Earlier prototype results remain in [validation history](docs/VALIDATION-HISTORY.md).

## License

[MIT](LICENSE). Copyright (c) 2026 Omerm10.
