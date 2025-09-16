# decisions (ADRs)

> Architecture Decision Records (ADRs). Keep each short. New decisions append at top.

## ADR-0004 — event channel rate & payload
- **Date:** 2025-09-16
- **Status:** accepted
- **Decision:** EventChannel updates at 10–20 Hz while active. Payload is compact `AnalysisResult` with optional downsampled spectrum.
- **Rationale:** Keeps UI smooth without overloading Dart side.
- **Consequences:** Avoid pushing full spectrum each frame; aggregate if needed.

## ADR-0003 — analysis pipeline: FFT-only
- **Date:** 2025-09-16
- **Status:** accepted
- **Decision:** Use a two-pass FFT pipeline (coarse→refine) with sub-bin interpolation. No autocorrelation or YIN in v1.
- **Rationale:** Transparent, fast, and sufficient for drum tuning.
- **Consequences:** For very low drums, extend refine window; consider future hybrid methods if needed.

## ADR-0002 — platform capture libs
- **Date:** 2025-09-16
- **Status:** accepted
- **Decision:** iOS via AVAudioSession + AVAudioEngine; Android via Oboe/AAudio (fallback AudioRecord). Mono float at 44.1/48 kHz.
- **Rationale:** Lowest-latency, well-supported APIs.
- **Consequences:** Maintain native code in plugin; test device matrix.

## ADR-0001 — app stack & structure
- **Date:** 2025-09-16
- **Status:** accepted
- **Decision:** Flutter app UI; federated Flutter plugin for native capture & C++ DSP; Riverpod for state.
- **Rationale:** Cross-platform UI; shared DSP; predictable state.
- **Consequences:** CI must build Dart + native + C++.

### ADR template
```
## ADR-XXXX — title
- **Date:** YYYY-MM-DD
- **Status:** proposed | accepted | superseded | deprecated
- **Decision:** <short statement>
- **Rationale:** <why>
- **Consequences:** <trade-offs>
```
