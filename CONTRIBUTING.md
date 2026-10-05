# Contributing

Thanks for helping improve Spotify Menu EQ.
The project is an early developer release, and the UI is actively being refined.
For substantial interface or architecture changes, open an issue first so we can coordinate the work.

## Local setup

Use an Apple silicon Mac with macOS 14.4 or later and an installed Xcode toolchain.
There are no third-party runtime packages to install.

```sh
zsh build.sh
zsh test.sh
zsh build.sh release
```

Keep pull requests focused and explain the user-visible behavior they change.
Include the checks you ran and any hardware or permission scenarios you exercised.
For bug fixes, reproduce the issue through the app as closely as possible before changing the implementation.
Add regression coverage for behavior that can be tested meaningfully.
For interface changes, include screenshots and check both appearance and accessibility.

Build and test output belongs in `.build/` and must not be committed.
Do not commit app bundles, signing credentials, audio recordings, or private diagnostic output.

## Reporting bugs

Include your macOS version, Mac model or chip, Spotify version, audio output type, reproduction steps, and expected versus actual behavior.
Mention whether the problem happens with EQ off, with Flat selected, or only with particular gains.
For output-switching problems, describe the starting and ending devices.

You can collect a short live diagnostic session while Spotify is playing:

```sh
"Spotify Menu EQ.app/Contents/MacOS/SpotifyMenuEQ" --diagnose-session 120
```

Inspect the output before posting it, and remove any personal device names or other information you do not want to make public.
The session reports state and audio counters without track metadata or a recording of the audio stream.

## Validation

Automated tests do not replace listening, permission, and hardware testing.
Use [docs/VALIDATION.md](docs/VALIDATION.md) to understand the measured results and remaining checks.
Record new results with their actual environment and distinguish automated coverage from physical validation.

Contributions are provided under the repository's [MIT license](LICENSE).
