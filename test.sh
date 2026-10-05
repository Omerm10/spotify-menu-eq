#!/bin/zsh
set -euo pipefail
cd "${0:A:h}"
mkdir -p .build/module-cache
swift=(xcrun swiftc -target arm64-apple-macosx14.4 -module-cache-path .build/module-cache -warnings-as-errors -parse-as-library)
run_test() {
  local name=$1
  shift
  "${swift[@]}" "$@" "Tests/$name.swift" -o ".build/$name"
  ".build/$name"
}
run_test EqualizerCurveTests EqualizerCurve.swift
run_test AudioFormatTests AudioFormat.swift EQConfiguration.swift
run_test EQConfigurationTests EQConfiguration.swift AudioFormat.swift
run_test OutputRouteTests OutputRouteTransition.swift
run_test SpotifyLifecycleTests SpotifyLifecycle.swift
run_test AppSettingsTests AppSettings.swift EQConfiguration.swift
run_test HelperProcessTests EqHelper.swift EQConfiguration.swift WorkerProtocol.swift
run_test PlayerTests Player.swift EqHelper.swift EQConfiguration.swift AppSettings.swift SpotifyAutomation.swift ReadinessServices.swift SpotifyLifecycle.swift OutputRouteTransition.swift
run_test SpotifyAutomationTests SpotifyAutomation.swift ReadinessServices.swift
zsh Tests/AudioTests.sh
print 'All tests passed.'
