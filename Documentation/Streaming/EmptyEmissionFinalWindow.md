# Retain a token-empty stream's prefix at final decoding

An overlapping stream can advance decoder navigation while emitting no tokens.
On the final window, `redecodePlan` previously returned the legacy `(nil, nil)`
entry for an empty token list. Consequently the final re-decode reused that
advanced state and could skip the start of the audio still retained in the window.
The fix requests frame zero with a fresh decoder state and no emission cutoff
when re-decoding has been requested but no tokens have previously emitted.
The first-window path and nonempty-token suppression policy are unchanged.

## Fixed public-file counterexample

The bundled 3-second, mono, 16 kHz PCM fixture is derived from UTEP DRAL
`ES_002_3.34.wav`, dedicated to the public domain under CC0 by its publisher.
Original URL, license evidence, source transcript and original/derived SHA256
are recorded beside the WAV. It is public speech, not user dictation or TTS.
The publisher's literal text is not a locally human-audited acoustic reference.

With v3 int8 and the 11 s left / 1 s chunk / 0.4 s right window, the first
two windows emit no tokens. At EOF, the previous code returned only
“Como yo pienso.”, while batch returned the ten-word published sentence.
The changed entry policy recovers the same full result as batch. No prompt,
dictionary, text replacement, deduplication or parameter tuning is involved.

## Tests and exact reproduction

Base revision: `ef2613d8bcbb0312f636dd5763163350fd0e22da`.
Its tree is identical to `16ff239818ddb6787629dab38ae43e8bdd0e7546`.
Use this PR's head for the fixed code and regression files.

Five model-free policy tests need no weights:

```sh
swift test --filter EmptyEmissionFinalWindowTests
```

The opt-in audio test uses only an explicitly supplied existing local model
directory, calls `AsrModels.loadLocal`, sets ModelHub offline, and never opens
capture/playback devices or downloads weights. Without the variable it skips.
The microphone enum in `startStreaming` is a channel label, not device capture.

```sh
FLUIDAUDIO_EMPTY_EMISSION_MODEL_DIR="/absolute/path/to/local/parakeet-tdt-0.6b-v3" \
  swift test --filter EmptyEmissionFinalWindowAudioTests
```

It checks the bundled WAV hash, the batch control, the two empty early windows,
terminal delivery, and the full final transcript. The two Swift files are also
usable unchanged in a focused SwiftPM test target importing this library with
the Diarizer trait. The observations below used that isolated target rather
than compiling/running every unrelated SDK test target. No new benchmark
framework or metrics implementation is introduced.

For an exact before/after comparison, create a fresh disposable worktree at
this PR head. Preserve its new tests and fixture, but replace only the copied
decoder source with the base version. Never do this in an active checkout:

```sh
regression_root=$(mktemp -d)
git worktree add --detach "$regression_root/before" HEAD
git show ef2613d8bcbb0312f636dd5763163350fd0e22da:Sources/FluidAudio/ASR/Parakeet/SlidingWindow/TDT/AsrManager+Transcription.swift \
  > "$regression_root/before/Sources/FluidAudio/ASR/Parakeet/SlidingWindow/TDT/AsrManager+Transcription.swift"
swift test --package-path "$regression_root/before" --filter EmptyEmissionFinalWindowTests
```

The two empty-emission reset assertions fail before; all five pass after.
The audio test's full-prefix assertion fails with the base decoder and passes
with the fix. The native audio test was executed successfully after the fix;
the earlier fixed-file streaming observation supplies the acoustic baseline.
Model component hashes and paired numeric observations are in
`Fixtures/empty-emission-reference-observation.json` beside the WAV.
Serialize native builds/inference with the host's cooperative test lock.
SwiftPM software dependency resolution is separate from ASR weight loading;
reuse its existing artifact cache when running offline.

## Observed controls and limits

Observed on Apple M3 Pro / 18 GiB, macOS 27.0.1, Swift 6.4, debug build,
existing v3 int8 weights, CPU+ANE default. The source artifact hashes are
recorded, but the weights' original download revision was not re-established.
Five pure tests passed after the change, plus the opt-in audio regression.
Eight DRAL files and four synthetic support clips were replayed once with
the unchanged configuration; only the affected 3-second case changed its
normalized final text. The other eleven results, all interior token edits,
and all twelve terminal revision contracts were preserved. Context equality
is a regression check, not a human fidelity audit. Repetition, negative and
number controls remained visible; source-reference scores are diagnostic only.

The affected case's observed EOF-to-terminal time was 0.153 s before and
0.091 s after; own-process CPU was 0.198 s and 0.256 s. One observation per
condition, cache history and external CoreML/ANE work prevent a speedup or
population latency claim. No additional buffering policy or window size was
introduced. Full default SDK CI and different devices remain separate checks.

The eight public files overlap and represent only three conversation families;
they contain no genuine Spanish/English code-switching. Synthetic controls
are not human holdout data, and their prompts are provisional acoustic references.
This change does not qualify the app's microphone, UI, paste, diarization or
translation pipeline, and does not change Portavoz's dependency pin or app.

Silence abstention remains unresolved: a 1.4-second all-zero window still
emits “Thank you.” with this checkpoint, while a 3-second whole-file control
is empty. That begins before EOF and is not fixed by this reset. No phrase
blacklist, energy threshold or silence-removal policy is added.
