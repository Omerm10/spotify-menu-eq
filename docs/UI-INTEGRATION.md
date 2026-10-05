# UI integration contract

The visual design and app icon remain separate work.
The existing popover retains its layout and styling.
Its EQ switch now binds to requested state and remains cancellable during startup.

## Player state

| Property | Meaning |
| --- | --- |
| `desiredEQEnabled` | Persisted user intent; bind the EQ switch to this property through `enableEQ(_:)`. |
| `eqEnabled` | A worker has reported capture and render progress. |
| `eqStarting` | A worker is being started; the user can still turn EQ off. |
| `runtimeState` | `off`, `waitingForSpotify`, `waitingForPlayback`, `waitingForOutput`, `sleeping`, `starting`, `active`, or `failed`. |
| `gains`, `selectedPreset` | Validated, persisted EQ configuration. |
| `issue` | Typed failure and its supported recovery actions. |
| `status` | Short human-readable state description. |

Use `preset(_:)` and `setBand(_:gain:)` to change sound.
The worker receives the newest complete configuration even when edits arrive during startup.
Use `enableEQ(false)` to stop processing and cancel future automatic starts.
Use `retry()` to retry a latched failure after the user has addressed its cause.

## Permissions and recovery

`PlayerIssue.automationDenied` is distinct from unavailable Spotify, an automation timeout, a generic scripting failure, and an audio failure.
Use `issue.recoveryActions` and `performRecovery(_:)` for explicit retry and relevant System Settings links.
Audio failures retain their actual error instead of interpreting every timeout as permission denial.
System Settings navigation does not grant or reset permissions.

## Login and discoverability

Observe `player.loginItem` directly when presenting launch-at-login controls.
Its published `status` reflects `SMAppService.mainApp.status`, including a state that requires approval.
Call `setEnabled(_:)` only in response to the user's choice, and show `errorMessage` if registration fails.
Call `refresh()` when settings become visible or regain focus.

The existing menu-hiding behavior is retained.
Reopening the app reveals the existing controls even when Spotify is closed.
The finished UI should offer discoverable settings, Quit, permission recovery, and launch-at-login controls in that state.

## Support diagnostics

`player.diagnosticReport()` returns state, route, sample rate, gains, worker counters, and bounded diagnostic text.
Let the user inspect and save that text through the UI.
The report intentionally omits track names, artwork URLs, and listening history.
No telemetry, audio recording upload, or automatic reporting service is included.
