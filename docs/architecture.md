# architecture

## purpose
High-level picture of how the app captures audio, analyzes it on-device, and shows results for tuning drums. This is the first doc Codex should read.

## goals
- Platforms: iOS and Android.
- UI: Flutter.
- Real-time capture native side, analysis in shared C++ DSP.
- On-device only; no network by default.

## components
- **Flutter app (apps/drum_tuner_app):** screens, state, preset management, UX.
- **Flutter plugin (packages/drum_tuning_plugin):** bridges native audio capture ↔ C++ DSP ↔ Dart stream.
  - Android: Oboe/AAudio (fallback AudioRecord). 44.1/48 kHz, mono float.
  - iOS: AVAudioSession + AVAudioEngine tap, measurement mode.
- **DSP core (packages/dsp-core):** C++ library with FFT-only pipeline, strike detection, f0/f1/RTF, spectrum.
- **QA fixtures (qa-fixtures):** WAV inputs + golden JSON outputs for CI validation.

## data types
```ts
// sent to Dart via EventChannel at ~10–20 Hz when active
type AnalysisResult = {
  f0Hz: number | null,
  f1Hz: number | null,
  rtf: number | null,
  noteName: string | null,
  cents: number | null,
  confidence: number,
  peaks: Array<{ Hz: number, mag: number }>,
  timestampMs: number
}
```

## flow
1) Native capture delivers audio frames.
2) Strike detector gates analysis windows.
3) C++ DSP does FFT-based analysis (coarse → refine), produces f0, f1, rtf, peaks.
4) Plugin converts to `AnalysisResult` and pushes events via EventChannel to Dart.
5) Flutter renders readings and mode-specific UI.

## threading & rates
- Native audio I/O at callback thread → lock-free ring buffer → DSP worker thread.
- EventChannel update target: 10–20 Hz while active; paused when idle.

## performance budgets
- First coarse result < 200 ms from strike.
- Refined lock ≤ 700 ms (may extend for <70 Hz).
- DSP refine step budget < 50 ms CPU on mid-tier device.
- Memory target < 100 MB total.

## error handling
- If microphone permission denied: show inline guidance and link to settings.
- If low sample rate or strong input clipping: warn and cap confidence.

## privacy & storage
- No network calls by default.
- Optional export: presets JSON and spectrum PNG saved locally.

## packaging
- **Android**: minSdk **24**, targetSdk **34**.
- **iOS**: minimum **14.0** deployment target.
- **CI**: build app, run Dart tests, run C++ tests (ctest), compare golden outputs.
