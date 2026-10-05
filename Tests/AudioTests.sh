#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
mkdir -p .build
xcrun clang -std=c11 -O2 -Wall -Wextra -Werror -mmacosx-version-min=14.4 -c AudioTransport.c -o .build/AudioTransport.o
xcrun clang -std=c11 -O2 -Wall -Wextra -Werror -mmacosx-version-min=14.4 -c Tests/AudioTransportTests.c -o .build/AudioTransportTests.o
# xcrun swiftc -target arm64-apple-macosx14.4 -warnings-as-errors selects the current Swift toolchain linker, avoiding an older CLT linker.
xcrun swiftc -target arm64-apple-macosx14.4 -warnings-as-errors .build/AudioTransport.o .build/AudioTransportTests.o -o .build/audio-transport-tests
.build/audio-transport-tests
xcrun swiftc -target arm64-apple-macosx14.4 -warnings-as-errors -module-cache-path .build/module-cache -parse-as-library Tests/AudioDSPTests.swift AudioFormat.swift EQConfiguration.swift -o .build/audio-dsp-tests
xcrun swiftc -target arm64-apple-macosx14.4 -warnings-as-errors -module-cache-path .build/module-cache -parse-as-library -import-objc-header AudioTransport.h Tests/AudioRenderTests.swift AudioFormat.swift EQConfiguration.swift .build/AudioTransport.o -o .build/audio-render-tests
# Both executables use offline rendering only and never start a hardware output.
.build/audio-dsp-tests
.build/audio-render-tests
xcrun swiftc -target arm64-apple-macosx14.4 -warnings-as-errors -module-cache-path .build/module-cache -parse-as-library Tests/AudioTransitionTests.swift AudioFormat.swift EQConfiguration.swift -o .build/audio-transition-tests
.build/audio-transition-tests
