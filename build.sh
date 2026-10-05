#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"

# Development build only. Distribution signing and notarization are a separate release step.
mode=${1:-debug}
case "$mode" in
  debug) optimization=(-Onone -g) ;;
  release) optimization=(-O) ;;
  *) print -u2 'Usage: ./build.sh [debug|release]'; exit 2 ;;
esac
mkdir -p .build/module-cache
bundle=${EQ_APP_BUNDLE:-"$PWD/Spotify Menu EQ.app"}
mkdir -p "$bundle/Contents/MacOS"

sources=(
  main.swift AppDelegate.swift PlayerView.swift EqualizerView.swift EqualizerCurve.swift Player.swift DiagnosticSession.swift
  SpotifyAutomation.swift SpotifyLifecycle.swift OutputRouteTransition.swift
  AppSettings.swift ReadinessServices.swift EqHelper.swift WorkerProtocol.swift WorkerRuntime.swift
  SpotifyAudio.swift AudioFormat.swift EQConfiguration.swift
)
xcrun clang -target arm64-apple-macosx14.4 -std=c11 -O2 -Wall -Wextra -Werror \
  -c AudioTransport.c -o .build/AudioTransport.o
xcrun swiftc -target arm64-apple-macosx14.4 -module-cache-path .build/module-cache \
  -warnings-as-errors "${optimization[@]}" -parse-as-library \
  -import-objc-header AudioTransport.h "${sources[@]}" .build/AudioTransport.o \
  -o .build/SpotifyMenuEQ -framework AppKit -framework SwiftUI -framework CoreAudio \
  -framework AudioToolbox -framework AVFoundation -framework ServiceManagement
cp Info.plist "$bundle/Contents/Info.plist"
cp .build/SpotifyMenuEQ "$bundle/Contents/MacOS/SpotifyMenuEQ"
codesign --force --sign - "$bundle"
codesign --verify --strict "$bundle"
print "Built ($mode): $bundle"
