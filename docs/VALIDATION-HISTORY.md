# Spotify Menu EQ v1

Local macOS menu-bar feasibility build. Open `Spotify Menu EQ.app` or run `zsh build.sh` to rebuild with the installed Xcode toolchain. No third-party dependencies. The menu-bar waveform opens a popover with Spotify song/artwork, transport and seek controls; Flat, Warm, Bass Boost, Voice Forward, Clarity, and Soft presets; five adjustable bands (80 Hz, 250 Hz, 1 kHz, 4 kHz, 10 kHz); a Spotify-only EQ switch; and Quit. Presets and sliders are available while EQ is off, but only affect sound when EQ starts successfully.

## Verified on this Mac

- The app compiles and launches through Finder/Launch Services (`open` exits 0); the earlier `-10825` launch error was caused by Swift's default macOS 28 deployment target on a macOS 27 host. The build script targets macOS 14.4 explicitly.
- AppleScript reports the playing/paused song, artwork and timing; transport, presets and EQ toggle update the popover. The rendered popover was checked against the supplied screenshot.
- EQ runs in a child process. A 20-second startup watchdog kills a stuck worker; simulated delayed-ready and stalled-worker checks pass. A simulated abrupt parent exit also caused its worker to exit via the parent-death watchdog.
- Earlier live starts reached `Spotify EQ active`; turning EQ off removed each child process. A separate process tap captured nonzero callbacks from the worker. This verifies audio output from the isolated worker, not audible sound quality or exact EQ gain.
- A short listening test found severe distortion at Flat in an earlier build; after the sample-rate/headroom changes, the user reported Flat sounded clean and presets had an audible effect. The tap advertises 48,000 Hz while 343 callbacks × 512 frames over 3.97 seconds and the aggregate nominal rate show 44,100 Hz. The graph uses the aggregate clock, with regression tests for matched/mismatched rates.
- A +12 dB band boost can clip the mix; the current five-band UI limits boosts to +9 dB and reserves negative preamp headroom for the two largest positive bands. Headroom mapping has regression tests. This is frequency EQ, not vocal/instrument separation.
- The new five-band configuration, six presets, command encoding, sample-rate mapping, and preamp headroom tests pass. The rebuilt app launched and its accessibility tree showed five EQ sliders plus seek; selecting Bass Boost set the five displayed gains to +5, +2, -2, 0, 0 dB. This verifies the controls, not the processed sound.
- A live start of the rebuilt app timed out after 20 seconds and the worker exited. A subsequent attempt reached `Spotify EQ active`; a separate tap of its output captured 344 nonzero callbacks in about four seconds. Selecting Flat while the worker remained active set all five displayed gains to 0 dB. The tap still advertises 48 kHz while the aggregate is 44.1 kHz. Permission was not separately proven to be the earlier startup cause.
- On the successful attempt, the user reported that Flat sounded clean and presets audibly changed the sound. This is a positive short listening test, not proof of reliable repeated startup or long-term fidelity. An attempted privileged coreaudiod restart failed because sudo required a password; it was not restarted.

## Post-restart live retest (September 26, 2026)

- The companion process started 33 seconds after system boot without a manual launch in this session (PID 963); Login Item status was `1` and System Events listed `Spotify Menu EQ`. This supports startup via the enabled Login Item, though process timing alone cannot prove the launch mechanism.
- With Spotify running, its menu-bar accessibility item was present. Quitting Spotify hid the menu bar from the companion's accessibility tree while the companion process stayed alive; reopening Spotify restored the item and track details.
- The first EQ click reported `Play Spotify before enabling EQ` because playback had paused. After resuming playback and clicking again, the worker reached `Spotify EQ active`. Quitting Spotify removed the worker; reopening and playing spawned a new worker and again reported active. This was one successful live restart sequence, not a reliability test. No Core Audio timeout occurred in this sequence; intermittent startup stalls remain unresolved.
- Spotify stayed `playing`, the EQ worker remained alive, and the displayed track advanced from 1:04 to 3:17 over a 120-second wait. This verifies continuity of app state, not sound quality or glitch-free audio. Spotify-only isolation from other apps was not audibly or instrumentally retested; the process-specific tap selection in source is not end-to-end proof.

## Repeated-start and isolation probe (September 26, 2026)

- With Spotify playing, five consecutive UI-driven EQ off/on cycles all reached `Spotify EQ active`; observed ready times were 2, 1, 1, 1, and 1 seconds. No watchdog timeout occurred. This small sample does not establish that the intermittent Core Audio stall is fixed.
- While EQ remained active, `afplay` played macOS's `Hero.aiff` through another process and exited successfully; Spotify remained `playing` and the EQ worker remained alive. Source inspection shows the tap selects Spotify's audio process ID and requests `stereoMixdownOfProcesses: [process]`, but this probe did not capture or measure the other app's output. Spotify-only audible isolation remains unverified.

## Additional startup stress check (September 26, 2026)

- Twenty more consecutive UI-driven EQ off/on cycles while Spotify played all reached `Spotify EQ active` in 1–2 seconds. Combined with the prior five, this is 25 successful starts in this session with no timeout. These rapid repeats exercise the current warm Core Audio state; they do not reproduce a fresh-login, changed-output, or cold HAL startup and cannot rule out the earlier intermittent stall. EQ was left active.

## Production validation gate

- Repeat EQ startup across real logins/restarts, sleep/wake cycles, and output-device changes. If the intermittent Core Audio stall recurs, capture the worker stack and Core Audio logs while it is stuck before changing code. A single successful cold start does not establish reliability.
- Instrumentally record Spotify and a second app playing together: verify only Spotify is equalized, and measure clipping, dropouts, and latency. Include subjective listening across presets and representative tracks.
- Exercise sustained playback plus pause/resume, Spotify quit/reopen, device disconnect/reconnect, and permission denial/reapproval; record outcomes and failure recovery.
- Build, sign, and notarize a release candidate, then test installation and first-run permissions on a clean supported Mac. The current app is locally ad-hoc signed and is not production-approved.

## Limitations / next validation

- This is a five-band EQ with low/high shelves and three parametric bands, not stem separation. Sliders/presets can be set with EQ off but do not affect sound until enabled.
- Output switching: the menu polls macOS's default output once per second. If EQ is on and the device changes, it stops the old worker, waits briefly for routing to settle, and starts a new worker with the same five gains. If Spotify is paused, reconnection waits for playback. Route-transition unit tests and manual off/on passed; the user confirmed speaker-to-AirPods reconnection and sound. A separate paused-switch test temporarily selected Serato Virtual Audio, restored the original MacBook speakers output, then resumed Spotify: the worker restarted and reported active. Rapid/disconnected-device changes remain unverified.
- Live Core Audio startup can still stall. A sampled worker was blocked inside `AudioDeviceCreateIOProcIDWithBlock` waiting on a Core Audio server response; an independent tap probe eventually timed out too. Moving playback graph startup before/after tap startup did not eliminate the stall, so that speculative change was reverted. The watchdog contains the hang but does not repair it. Do not claim reliable startup.
- Spotify quit/reopen while EQ was active has not been live-verified because the worker could not start on the latest attempt. The companion now remembers whether EQ was requested, stops the worker at Spotify quit, and attempts to resume when Spotify next plays; the intent rule has unit tests. Audio quality and behavior after that transition still need verification.
- Other route transitions (rapid changes and actual device disconnects), permissions on a fresh Mac, Spotify-only isolation from other apps, and long-running playback still need end-to-end verification. Do not treat this as a shippable build yet.
- Spotify lifecycle: while the companion is running, its menu icon hides when Spotify quits and reappears when Spotify launches. Spotify AppleScript commands are skipped while Spotify is closed, so clicking the EQ no longer launches Spotify by accident. A real quit/reopen test passed: Spotify remained closed, the icon disappeared, reopening Spotify restored the icon and track details. The companion stays running invisibly. macOS Login Item registration was enabled with `SMAppService.mainApp.register()` and read back as `enabled`; a full logout/login cycle has not been tested. To remove it, run `"Spotify Menu EQ.app/Contents/MacOS/SpotifyMenuEQ" --unregister-login` from this directory or disable it in System Settings → General → Login Items & Extensions.
- Spotify automation prompts may require approval on first use. This app is locally ad-hoc signed, not notarized or distributed.
