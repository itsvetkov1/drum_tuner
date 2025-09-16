# AGENTS.md — drum-tuning app (flutter + c++ dsp)

> this file tells the **codex** cli how to work in this repo: priorities, rules, build/test, and what to read first. use **gpt-5-codex**. no internet unless asked.

## project goals (what & why)
- build a pro-grade drum-tuning app for **ios + android** with **flutter ui**, **native real-time capture**, and a **shared c++ dsp core**. on-device only.
- accuracy target: ±0.5 Hz in ~50–500 Hz; first useful result fast, then refine to stable lock.
- serve 4 modes: **pitch (f0)**, **lug/edge (f1)**, **resonant head (rtf=f1/f0)**, **spectrum**.

## non-negotiables (guardrails)
- analysis: **fft-only** pipeline with coarse→refine; sub-bin interpolation; optional zero-pad.
- capture: **avaudioengine (ios)**, **oboe/aaudio (android)**; mono float; 44.1/48 kHz.
- data leaves device only on explicit export; respect licenses; no proprietary code.

## repo layout (monorepo)
```
/apps/drum_tuner_app           # flutter app (dart ui + state)
/packages/drum_tuning_plugin   # federated flutter plugin (ios/android bridges)
/packages/dsp-core             # c++ dsp (cmake, gtest, cli tools)
/qa-fixtures                   # wav fixtures + golden json
/docs                          # readme, in-app help, decisions
```

### models & events
- `AnalysisResult { f0Hz, f1Hz, rtf, peaks[], noteName, cents, confidence }`
- event flow: native capture → c++ analyze → native → `EventChannel` → `Stream<AnalysisResult>` in dart.

## build & run (local)
- prerequisites: flutter sdk, android ndk, xcode (ios), cmake.
- install deps:  
  - app: `flutter pub get`  
  - dsp: `cd packages/dsp-core && cmake -S . -B build && cmake --build build`
- run app: `cd apps/drum_tuner_app && flutter run`
- tests:  
  - c++: `cd packages/dsp-core && ctest --test-dir build`  
  - flutter unit/widget: `flutter test`  
  - plugin bridge (integration): `flutter test integration_test`  
- lint: `flutter analyze`

## approvals & safety (for codex)
- default to **read/edit/run inside repo only**. ask before:  
  - adding deps, touching files outside repo, enabling network, or changing public apis.  
- prefer small commits; open a pr when a task completes.

## docs to read first (in this order)
1) `/docs/architecture.md` – high-level data flow & plugin wiring  
2) `/docs/dsp-notes.md` – fft sizes, windows, sub-bin interpolation, target filter defaults  
3) `/docs/modes.md` – pitch, lug, resonant, spectrum ui rules & copy  
4) `/docs/decisions.md` – locked choices & timestamps

## implementation rules (summary)
### capture & pre-processing
- ios: `AVAudioSession` (playAndRecord/measurement), `AVAudioEngine` tap; android: `OBOE/AAudio` fallback `AudioRecord`.  
- strike detection: envelope + threshold + hysteresis + lockout; collect window for analysis.  
- pre-fx: dc removal, hann/hamming, optional pre-emphasis.

### frequency analysis (fft-only)
- coarse: ~150 ms, `fft 4096`, quick estimate → immediate ui.  
- refine: ~500 ms (700–800 ms if <70 Hz), `fft 16384`, 2–4× zero-pad, parabolic/quadratic sub-bin → stable lock.  
- label peaks: pick **f0**, find **f1** with edge-biased heuristics or band search.  
- target filter: pitch mode off by default; lug mode on around last good **f1**; widen on low confidence.

### modes (ui + logic)
- **pitch**: show Hz + note + cents; “coarse→refined” state; median over last N stable reads.  
- **lug**: circular lug map (4/6/8/10); reference-lug flow; display ΔHz (+ small ±cents); graded tighten/loosen hints; mini history.  
- **resonant**: show `rtf=f1/f0`; text hints: <1.4 raise reso / >1.65 lower reso.  
- **spectrum**: 20–500+ Hz magnitude; peak markers; waveform inset; zoom/hold; export png.

### presets & kit designer
```
PresetKit {
  name, createdAt, version,
  drums: [{ id, name, size, targetF0Hz, targetF1Hz, intervalNote }]
}
```
- features: import/export; interval calculator; preload targets into modes.

### state management & ui
- default: **riverpod**; acceptable: bloc/cubit, provider.  
- widgets: `CustomPainter` spectrum, `LugMap` widget, chip controls, big type, haptics on lock; color-blind-safe palette; dark mode default.  
- nav: tabs/bottom bar; persistent info bar (active preset, last f0/f1).

## performance budgets
- dsp refine step <50 ms cpu; idle cpu <5%; mem <100 MB.  
- latency: first coarse <200 ms; refined lock <700 ms (longer for low bass).  
- stability: ≥80% of repeated strikes within ±0.5 Hz under normal room noise.

## device & environment handling
- mic limits: warn on poor LF; suggest external mic for <50–60 Hz; “bass boost” profile (longer window + lf emphasis).  
- noise advice; show confidence meter.

## definitions (ready & done)
- **DoR**: feature has user story, mode, targets, ui mock, test plan, and uses defaults above; proceed if missing details are minor.  
- **DoD**: micro-plan → code/tests/fixtures → validation → pr with summary/risks → decisions/backlog updated.

## quality assurance (tests)
- **c++ (gtest)**: synthetic multi-tone inputs; assert peak indices & interpolation.  
- **goldens**: recorded kicks/snares/toms wavs + annotated f0/f1 json; compare in ci.  
- **flutter**: widget tests for `LugMap`; integration tests streaming mock `AnalysisResult` events.  
- acceptance samples:  
  - pitch: detects 110.0 Hz within ±0.2 Hz; note within ±5 cents.  
  - lug: after 3 passes, all lugs within ±0.5 Hz of reference on sample tom.  
  - resonant: rtf within ±0.02 on synthetic pairs; correct guidance strings.  
  - spectrum: 20–500 Hz view, labels peaks > –20 dBFS, zoom/hold ok.

## ci/cd & release
- github actions: flutter build/test, c++ tests, size checks.  
- android: signing configs; ios: fastlane lanes.  
- crash/symbolication with privacy.  
- beta: testflight (ios) / play internal testing (android).

## task patterns for the codex cli
run from repo root:
```bash
# read docs and propose plan
codex "read /docs/architecture.md and /docs/modes.md; draft a micro-plan to add Lug mode polish"

# implement feature with tests & pr text
codex "follow AGENTS.md; implement spectrum export PNG; add tests; update docs; open a PR with summary + risks"

# dsp tweak
codex "in /packages/dsp-core, add 2x zero-pad in refine path; update gtests and golden thresholds"
```

## open questions
- target filter auto-lock thresholds per drum size?  
- minimal android api & ios version?  
- external mic profiles library?
