# Validate the empty-final-window test contract

The EOF reset deliberately returns a frame-zero entry when re-decoding is
requested and no tokens have emitted. The older
`testRedecodePlan_InactiveWithoutPreviousTokensOrTimestamps` described that call
as a first window and expected nil. It therefore contradicted the repaired
decoder-entry contract.

`testRedecodePlan_DistinguishesFirstWindowFromEmptyFinalRedecode` separates the
two cases. It preserves the existing nonempty-output fallback and also checks
the absence of suppression when there is no emitted prefix.

| Inputs | Initial time override | Emission cutoff |
| --- | --- | --- |
| First window: `redecode: false`, no tokens | nil | nil |
| Requested final re-decode, no tokens | 0 | nil |
| Existing tokens, timestamps absent | nil | nil |

`transcribeChunk` requests re-decoding for a final chunk or existing output.
When the plan returns frame zero it constructs a fresh `TdtDecoderState`.
The test repair changes no production code, suppression boundary, seam policy,
stable prefix, golden output, formatter configuration, or workflow. The
regression class retains 49 methods and has 180 assertion call sites, previously
176. Existing empty-output policy tests also cover an absent timestamp array.

## Local validation

The source head before this test-only follow-up was
`ec9bb13a7ac31701e4446814336a4c0a7ed81d91`. Validation used a new independent
checkout on Apple silicon with Swift 6.4, debug configuration, the native
SwiftPM build system, two build jobs, and serial test execution on October 24,
2026. The test file SHA256 after the repair was
`0e6c422bff3a2d769c73688720929cc70d6a7bce2667fe472920bef1405a310e`.

| Check | Result |
| --- | --- |
| Complete default-trait package and test-target compilation | Passed, 118.65 s |
| Repaired method, selected separately | 1 passed |
| TokenDeduplicationRegressionTests | 49 passed |
| EmptyEmissionFinalWindowTests | 5 passed |
| EmptyDecodeRecoveryTests | 5 passed |
| EndAlignedFinalWindowTests | 11 passed |
| TdtDecoderStateTests | 11 passed |
| TdtDecoderStateV3Tests | 31 passed |
| EmptyEmissionFinalWindowAudioTests, without explicit model directory | 1 skipped |
| Strict lint of the test repair and three original PR Swift files | Passed |

There were 112 unique passing test methods, plus the separately repeated
repaired method: 113 passing executions. No selected logic tests skipped.
The acoustic skip is not an acoustic pass. Neither the complete default SDK
test suite nor the twelve-case acoustic replay was executed during this
follow-up. Earlier acoustic observations remain separately documented in
[EmptyEmissionFinalWindow.md](EmptyEmissionFinalWindow.md).

## Reproduce

From a fresh checkout containing this repair, use Bash or Zsh. These argument
arrays preserve filter alternation as one argument and keep SwiftPM state
inside the disposable checkout:

```sh
mkdir -p .validation/{build,cache,config,security}
swiftpm_state=(
  --scratch-path "$PWD/.validation/build"
  --cache-path "$PWD/.validation/cache"
  --config-path "$PWD/.validation/config"
  --security-path "$PWD/.validation/security"
  --disable-netrc --disable-keychain --build-system native -j 2
)
swift build "${swiftpm_state[@]}" --build-tests
swift test "${swiftpm_state[@]}" --skip-build --no-parallel \
  --filter 'TokenDeduplicationRegressionTests/testRedecodePlan_DistinguishesFirstWindowFromEmptyFinalRedecode'
swift test "${swiftpm_state[@]}" --skip-build --no-parallel \
  --filter TokenDeduplicationRegressionTests
swift test "${swiftpm_state[@]}" --skip-build --no-parallel \
  --filter 'EmptyEmissionFinalWindowTests|EmptyDecodeRecoveryTests|EndAlignedFinalWindowTests|DecoderStateTests|TdtDecoderStateV3Tests'
swift test "${swiftpm_state[@]}" --skip-build --no-parallel \
  --filter EmptyEmissionFinalWindowAudioTests
```

SwiftPM may download its checksum-pinned public software artifact on a cold
cache. That is separate from ASR model loading. The listed logic tests load no
models and launch no application, capture, or playback. The audio test skips
unless `FLUIDAUDIO_EMPTY_EMISSION_MODEL_DIR` explicitly names an existing local
installation; use the original regression document for its requirements.

The recorded run used an allowlisted child environment, workspace-owned home,
temp and module-cache directories, a cooperative heavy-test lock, and a test
sandbox denying network and access to original checkouts and user Library.
Those execution controls are separate from the portable commands above. Do
not inherit credentials or private model/provider settings into a test run.
Coordinate expensive work on shared hosts; a cooperative lock does not prove
that unrelated host activity has stopped.

## CI scope

[Build and Test run 40125531718](https://github.com/johnny4young/FluidAudio/actions/runs/40125531718)
reported the obsolete nil assertion in its macOS job. Its separate tvOS job
used a MacOSX sysroot for the AppleTV target and failed to load the standard
library. This follow-up changes no tvOS command or SDK selection.

[Swift Format run 40125531719](https://github.com/johnny4young/FluidAudio/actions/runs/40125531719)
and [October 20 run 39441162988](https://github.com/johnny4young/FluidAudio/actions/runs/39441162988)
contain identical three-hunk diffs after removing only log timestamps. Their
sole affected file, `SlidingWindowAsrManager.swift`, has identical base/head
blob `0d3d41c9de2a88ebd69ee8730efa9c09bd445296` and is unchanged by this
follow-up. No unrelated formatting repair or rule relaxation is included.

The local Swift 6.4 result does not establish a future CI pass with another
toolchain. Inspect checks at the exact published follow-up SHA; do not infer
green CI, acoustic qualification, or merge readiness from these filtered tests.
