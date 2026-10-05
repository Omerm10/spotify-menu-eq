# Validation record

## Automated verification on September 27, 2026

The full `zsh test.sh` suite passed and the optimized app built with warnings treated as errors.
The resulting local app passed code-signature verification with its ad hoc signature.

| Area | Evidence |
| --- | --- |
| Startup settings | The original helper reproduced a stale Flat configuration after selecting Bass Boost during startup; the corrected real subprocess test applies and acknowledges the newest preset. |
| Worker failures | Fragmented UTF-8, oversized responses, early exit, startup timeout, blocked input, cancellation, and delayed teardown are covered by real subprocess tests. |
| Liveness | Progress stalls are detected while playback is expected; a paused stream does not cause a false audio-progress failure. |
| Lifecycle | Actual controller tests cover output loss, same-device recovery, format change, Spotify quit during recovery, sleep/wake, Off cancellation, stale callbacks, failure/retry, and denied Automation. |
| Settings | Isolated preferences cover persistence, malformed data, invalid/nonfinite gains, version fallback, and preset consistency. |
| Automation | Real subprocess tests cover success, stderr errors, denial, timeout, bounded output, snapshot parsing, and refusal to launch absent Spotify. |
| Audio transport | One million frames transferred in order between concurrent producer/consumer threads; no overflow in that test. |
| Memory safety | The transport test passed AddressSanitizer. |
| Flat rendering | The actual ring/source/EQ offline graph rendered 102,400 frames at each of 44.1 and 48 kHz with zero underruns/overflows and maximum absolute sample error below 1.1e-14. |
| Headroom | Full-scale sweeps across the six presets and all-positive/all-negative extreme gains remained finite; maximum measured peak was 0.99. |
| Preset transitions | 400 changes per rate with synthetic noise and multitone input produced peaks of 0.89245 at 44.1 kHz and 0.86886 at 48 kHz, with no measured clipping. |

These finite signal tests do not prove clipping is impossible for every input and gain combination.
They also do not establish subjective click-free transitions; filter changes are not crossfaded.

## Live validation

The final isolated test used the MacBook Pro speakers at 44.1 kHz, with the earlier prototype worker stopped.
Three consecutive starts became ready in 1.18, 1.19, and 1.20 seconds and each exited cleanly.
A separate two-minute run started in 1.20 seconds, acknowledged 13 configurations, captured 5,338,112 frames, and rendered 5,337,088 frames.
Its final queue held 1,024 frames, and the high-water mark was 1,536 frames.
Every final live run reported zero underrun frames, overflow frames, invalid buffers, nonfinite samples, and clipped output samples.
These counters establish short live continuity for this route, not long-term fidelity across other hardware.
Earlier exploratory runs overlapped the old prototype worker and are excluded from this final evidence.
The probe collects counters and setup errors; it does not save the music stream.

```sh
python3 Tests/LiveWorkerProbe.py --cycles 3 --seconds 5 --report /tmp/eq-live.json
python3 Tests/LiveWorkerProbe.py --cycles 1 --seconds 120 --report /tmp/eq-sustained.json
```

A separate two-minute session exercised the real controller, Spotify automation, and worker during physical Bluetooth disconnection and reconnection.
The route moved from AirPods at 48 kHz to built-in speakers at 44.1 kHz and back to AirPods at 48 kHz.
Processing recovered on each route, with no failed controller states or reported underrun, overflow, invalid-buffer, nonfinite-sample, or clipping counters.
The user reported that it worked well.
This exposed a transient status defect during reconnection; a regression test now requires the controller to leave the active state immediately when the old worker stops.

For a live controller support session while Spotify is playing:

```sh
'./Spotify Menu EQ.app/Contents/MacOS/SpotifyMenuEQ' --diagnose-session 120
```

This uses isolated temporary preferences and prints route, state, and worker counters without track metadata or recorded audio.

## Remaining release gates

- Independently measure Spotify-only processing with a second app playing at the same time.
- Measure physical output latency and clock drift on representative wired, Bluetooth, and USB routes.
- Perform actual sleep/wake and fresh-login sessions; extend disconnect/reconnect coverage to additional supported hardware.
- Validate first-run permission denial, approval, revocation, and recovery on a clean account or Mac using the distribution-signed app.
- Verify launch-at-login registration and removal through a real login cycle.
- Listen across representative tracks and rapid preset changes.
- Finish the UI integration and verify it manually; menu-bar accessibility automation could not inspect this app reliably in the current tool session.

Do not promote simulated lifecycle coverage or offline render measurements into claims that these physical gates passed.
