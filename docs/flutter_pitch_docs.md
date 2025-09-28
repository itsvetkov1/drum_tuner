# flutter web pitch & partial detection – approaches and recommendations

## executive summary

flutter’s web platform can achieve real-time drum pitch detection by leveraging the browser’s audio apis with efficient algorithms. we identify three implementation paths—pure dart dsp, javascript (js) interop, and webassembly (wasm)—and evaluate each against accuracy (±1–3 cents) and latency (\~60 ms target) requirements.

**recommended:** use a web audio **audioworklet** with a **wasm-based** pitch detector (e.g., rust or c++ mcleod/yin). this offers the best accuracy and cpu performance within latency budgets. this approach can share code with mobile (via rust/c++ libraries on android/ios) for a unified architecture.

**fallback:** a js audioworklet running a lighter-weight pitch algorithm (or an existing js library) is viable if toolchain complexity must be minimized.

**not ideal:** pure dart was explored but is risky for real-time audio on web due to dart’s gc and limited thread priority control.

below: paths with prototypes, web constraints (mic capture, safari quirks), a decision matrix, integration plan for flutter, and risk mitigation (e.g., ios audio policies, cross-origin isolation). all citations and code refs are included for verification.

---

## clarifications & assumptions

* **latency & accuracy targets.** goal ≤60 ms end-to-end latency (≤120 ms acceptable) and pitch accuracy within ±1–3 cents on stable tones (≥80 ms duration). overtones should be identifiable with reasonable precision. \[4]\[5]
* **allowed dependencies.** client-side only. js libraries via `package:js` / `dart:js_interop` and native code compiled to wasm are allowed. prefer permissive licenses (mit/bsd).
* **target platforms.** modern desktop browsers (chrome, edge, firefox) and mobile safari on ios (14.5+). account for differences (e.g., safari’s later audioworklet support). android chrome/webview covered by chrome.

---

## viable implementation paths (survey & shortlist)

### 1) pure dart dsp (no external js)

implement the pitch detection algorithm in dart (e.g., using `dart:html` for audio input + dart math for dsp).

**pros**

* single-language surface.
* simpler code sharing with flutter mobile logic (non-dsp parts).

**cons**

* real-time dsp in dart is hard: gc pauses, main-thread contention.
* no mature pure-dart pitch library for web; most plugins use native code on mobile. \[7]\[8]
* likely need to implement fft/autocorrelation yourself; performance and maintenance risk.
* may require isolates with copy overhead; still main-thread pressure.

**notes**

* can work for higher pitches or short windows; low drums need large windows → heavy compute.

---

### 2) javascript interop (web audio + js libs)

use a tested js library + interop, or custom js in an audioworklet.

**options**

* **pitchfinder (yin, amdf, dwt)** in js. browser-friendly, returns frequency/note from `float32array`. yin is a solid speed/accuracy balance. consider moving compute to a worklet/worker to avoid ui jank. \[9]\[10]
* **aubio.js (wasm-wrapped aubio c library).** provides yin etc., mit license; faster than pure js with modest wasm size overhead; js/wasm hybrid. \[11]\[12]
* **custom web audio + autocorrelation.** use `analysernode` + time-domain data and your algorithm; feasible but needs adaptation for drums/partials. \[13–18]
* **ml (tf.js/crepe).** accurate but heavy; likely too slow/large for low-latency, client-only drum tuning. keep for offline/high-precision use.

**summary**

* interop is quick to ship; acceptable latency with audioworklet and reasonable buffer sizes.
* raw js slower than optimized wasm but may meet ≤60–120 ms with worklet.
* aubio.js improves perf vs pure js.

---

### 3) wasm + audioworklet (c/c++/rust)

compile native pitch algorithm to wasm for near-native speed; run inside audioworklet for real-time streaming.

**pros**

* avoids js gc/jit warm-up; predictable perf. \[19]\[20]
* reuse optimized libs (fft, mpm/yin). e.g., rust `pitch-detection` crate implements mcleod and yin efficiently. \[21]\[22]
* strong evidence from tutorials and projects (toptal 2022; pitchlite 2023). \[24–26]
* large speedups vs js (e.g., \~8×–23×), enabling larger windows and partials without glitches. \[1]\[2]

**cons**

* toolchain complexity (build rust/c++ to wasm; glue; loading in worklet).
* need proper asset serving/mime; optional cross-origin isolation if `sharedarraybuffer` used (we can avoid).

**verdict**

* best accuracy/cpu and code reuse (same core dsp for web + mobile). recommended.

**hybrids**

* js worklet + wasm fft for heavy parts; or onset detection on main thread then segment analysis. wasm-in-worklet already covers most needs.

---

## web audio constraints & considerations (browser audit)

* **user gesture & autoplay policy.** start mic on user action; `audiocontext.resume()` after gesture. trigger js from a button in flutter. \[3]
* **`getusermedia` constraints.** request `{ echoCancellation:false, noiseSuppression:false, autoGainControl:false }`. sample rate varies (44.1/48 k); use `audioContext.sampleRate`. \[28]\[29]
* **audioworklet setup.** `audioContext.audioWorklet.addModule('processor.js')`. same-origin, correct mime (`text/javascript`). fallback: `scriptprocessornode` (deprecated, larger latency). safari quirks historically; keep fallback. \[6]\[30]
* **sharedarraybuffer & coi.** avoid sab by using `port.postmessage()`; pass only floats/results; no special headers needed. \[27]
* **ios safari quirks.**

  * likely 48 k sample rate; read `audioContext.sampleRate`. \[31]
  * permission prompts every time; ensure user gesture. \[4]
  * serve over https; test on device.
* **main thread vs worklet.** heavy dsp must be off main thread; in flutter web you can’t run dart inside the audioworklet, so do dsp in js/wasm in the worklet, post results back.
* **signal conditioning.** avoid clipping; consider dc removal; optional simple gain control.
* **partials.** do an fft (≥4096/8192) with windowing; find peaks; parabolic interpolation for sub-bin accuracy. `analysernode` fft is limited; prefer custom fft in worklet/wasm.
* **cpu budgeting.** update \~10 hz with \~100 ms windows for tuning; accumulate small chunks (128) until window is full; then analyze (pitchlite pattern). \[25]

---

## prototype implementation plans

### approach 1: pure dart dsp (`dart:html` + isolates)

mic capture via js interop; process frames in dart. example (simplified):

```dart
import 'dart:js' as js;
import 'dart:html';
import 'dart:typed_data';
import 'dart:math';

Future<void> startAudioStream() async {
  final constraints = {
    'audio': {'echoCancellation': false, 'noiseSuppression': false, 'autoGainControl': false}
  };
  final navigator = js.context['navigator']['mediaDevices'];
  var promise = navigator.callMethod('getUserMedia', [js.JsObject.jsify(constraints)]);
  await promiseToFuture(promise).then((stream) {
    final ac = AudioContext();
    final source = ac.createMediaStreamSource(stream);
    final processor = ac.createScriptProcessor(1024, 1, 1);
    source.connectNode(processor);
    processor.connectNode(ac.destination);
    processor.onAudioProcess.listen((e) {
      final samples = e.inputBuffer.getChannelData(0);
      final f0 = detectPitch(samples, ac.sampleRate.toDouble());
      // TODO: send f0 to UI
    });
  });
}

double detectPitch(Float32List samples, double fs) {
  final n = samples.length;
  final mean = samples.reduce((a, b) => a + b) / n;
  double bestCorr = 0, freq = 0;
  int bestLag = 0;
  for (int lag = 1; lag < n ~/ 2; lag++) {
    double corr = 0;
    for (int i = 0; i < n - lag; i++) { corr += (samples[i]-mean) * (samples[i+lag]-mean); }
    if (corr > bestCorr) { bestCorr = corr; bestLag = lag; }
  }
  if (bestLag > 0) freq = fs / bestLag;
  return freq;
}
```

> practical issues: window too short for low drums; `scriptprocessor` latency; heavy `o(n²)`; isolates add copies; likely not viable for realtime low-latency.

---

### approach 2: javascript library via interop

**include pitchfinder and wire it:**

```html
<script src="https://unpkg.com/pitchfinder@1.2.0/dist/pitchfinder.umd.js"></script>
<script>
  window.startPitchListening = async function () {
    const audioCtx = new (window.AudioContext || window.webkitAudioContext)();
    const stream = await navigator.mediaDevices.getUserMedia({
      audio: { echoCancellation:false, noiseSuppression:false, autoGainControl:false }
    });
    const source = audioCtx.createMediaStreamSource(stream);
    const analyser = audioCtx.createAnalyser();
    analyser.fftSize = 2048;
    source.connect(analyser);
    const detector = Pitchfinder.YIN({ sampleRate: audioCtx.sampleRate });
    const buffer = new Float32Array(analyser.fftSize);

    if (audioCtx.audioWorklet) {
      await audioCtx.audioWorklet.addModule('worklet-processor.js');
      const node = new AudioWorkletNode(audioCtx, 'capture-processor');
      source.connect(node);
      node.port.onmessage = (e) => {
        const freq = detector(e.data) || 0;
        window.flutter_get_frequency && window.flutter_get_frequency(freq);
      };
    } else {
      function tick() {
        analyser.getFloatTimeDomainData(buffer);
        const freq = detector(buffer) || 0;
        window.flutter_get_frequency && window.flutter_get_frequency(freq);
        requestAnimationFrame(tick);
      }
      requestAnimationFrame(tick);
    }
  };
</script>
```

**simple audioworklet to batch frames (worklet-processor.js):**

```js
class CaptureProcessor extends AudioWorkletProcessor {
  constructor() { super(); this.buf = new Float32Array(2048); this.i = 0; }
  process(inputs) {
    const ch0 = inputs[0][0];
    if (ch0) {
      for (let k = 0; k < ch0.length; k++) {
        this.buf[this.i++] = ch0[k];
        if (this.i >= this.buf.length) {
          this.port.postMessage(this.buf);
          this.buf = new Float32Array(2048);
          this.i = 0;
        }
      }
    }
    return true;
  }
}
registerProcessor('capture-processor', CaptureProcessor);
```

**flutter dart glue (receive freq):**

```dart
import 'dart:js' as js;
import 'package:js/js_util.dart';

void start() {
  js.context['flutter_get_frequency'] = allowInterop((num f) {
    final freq = (f ?? 0).toDouble();
    // update state
  });
  js.context.callMethod('startPitchListening');
}
```

> for partials: add fft in js/worklet or use aubio.js (wasm) for better perf.

---

### approach 3: wasm + audioworklet (rust example)

**rust (lib)**

```rust
use pitch_detection::{McLeodDetector, PitchDetector};
use wasm_bindgen::prelude::*;

const N: usize = 4096;
const PAD: usize = 4096;

#[wasm_bindgen]
pub struct WasmPitchDetector {
    det: McLeodDetector<f32>,
    fs: f32,
}

#[wasm_bindgen]
impl WasmPitchDetector {
    #[wasm_bindgen(constructor)]
    pub fn new(sample_rate: f32) -> WasmPitchDetector {
        console_error_panic_hook::set_once();
        WasmPitchDetector { det: McLeodDetector::new(N, PAD), fs: sample_rate }
    }

    pub fn process(&mut self, samples: &[f32]) -> f32 {
        if let Some(p) = self.det.process(samples, self.fs) { p.frequency } else { 0.0 }
    }
}
```

**main thread (load wasm + worklet)**

```js
let wasmBytes;
async function setup(audioCtx) {
  const resp = await fetch('wasm_audio_bg.wasm');
  wasmBytes = await resp.arrayBuffer();
  await audioCtx.audioWorklet.addModule('pitch-processor.js');
  const node = new AudioWorkletNode(audioCtx, 'pitch-processor', {
    processorOptions: { wasmBytes, sampleRate: audioCtx.sampleRate }
  });
  return node;
}
```

**worklet (pitch-processor.js)**

```js
class PitchProcessor extends AudioWorkletProcessor {
  constructor(opts) {
    super();
    this.samplesPerAnalysis = 4096;
    this.rb = new Float32Array(this.samplesPerAnalysis);
    this.idx = 0;
    this.det = null;
    WebAssembly.instantiate(opts.processorOptions.wasmBytes, {})
      .then(mod => {
        this.wasm = mod.instance;
        const { WasmPitchDetector_new } = this.wasm.exports;
        this.det = WasmPitchDetector_new(opts.processorOptions.sampleRate);
      });
  }
  process(inputs) {
    if (!this.det) return true;
    const ch0 = inputs[0][0];
    if (ch0) {
      for (let i=0;i<ch0.length;i++) {
        this.rb[this.idx++] = ch0[i];
        if (this.idx >= this.samplesPerAnalysis) {
          const f = this.wasm.exports.WasmPitchDetector_process(this.det, this.rb);
          this.port.postMessage({ frequency: f, partials: [] });
          this.idx = 0;
        }
      }
    }
    return true;
  }
}
registerProcessor('pitch-processor', PitchProcessor);
```

> in practice you’ll use `wasm-bindgen` glue inside the worklet or bundle it; also add fft-based partials in rust and post `{partials: [..]}`.

---

## benchmarks & testing protocol

**test signals**

1. steady sines: 110 hz, 220 hz (ground truth, expect \~0 cents).
2. recorded drum hits: e.g., floor tom (\~80 hz fundamental, strong \~130 hz overtone), snare/tom (\~200 hz).
3. noisy background cases.

**metrics**

* **latency:** input→output time (goal ≤60 ms ideal; ≤120 ms acceptable).
* **cpu usage:** per-analysis runtime; overall load on desktop/mobile.
* **stability:** stddev over time on steady tones (≤1 hz variance ideal).
* **accuracy:** cents error vs ground truth.

**expected**

* pure dart: likely >100 ms latency for large windows; high cpu; may miss low drums. \[49]
* js yin: \~50–95 ms end-to-end depending on window; ok on desktop, borderline cpu on low-end phones; needs fft for partials. \[1]\[10]
* js+aubio (wasm): better cpu, similar latency; excellent accuracy.
* wasm+worklet (rust): \~85–95 ms with 4096; minimal cpu; accurate on drums; partials feasible.

---

## comparison matrix (qualitative; weights in parentheses)

| approach       | accuracy (35%) | latency (25%) | cpu (15%) | portability (15%) | dev complexity (−10% penalty) |                score |
| -------------- | -------------: | ------------: | --------: | ----------------: | ----------------------------: | -------------------: |
| pure dart dsp  |             20 |            10 |         5 |                12 |                           −10 |  **37 (not viable)** |
| js interop     |             30 |            20 |        10 |                 8 |                            −5 |      **63 (viable)** |
| wasm + worklet |             34 |            20 |        15 |                15 |                            −8 | **76 (recommended)** |

notes: complexity is modeled as a penalty; totals out of 100. sources underpin scores where cited.

---

## recommended solution & integration plan

**primary:** implement **wasm + audioworklet** using rust (mcleod/yin) + fft for partials. reuse same rust core on android/ios via ffi.

**plan**

* build rust lib (`pitch-detection`, fft) → wasm via `wasm-pack` (`--target web`).
* audioworklet loads wasm (pass bytes via `processoroptions`); accumulate 128-sample chunks to 4096; run pitch + partials; post `{frequency, partials, confidence}`.
* flutter web interop: start/stop, permission, lifecycle; update ui.
* test chrome/firefox/safari (incl. ios).
* tune window by drum range; dynamic windowing for low vs high drums.
* edge cases: silence → 0; noisy → confidence gating.

**fallback:** ship **js interop** (prefer `aubio.js` for perf). feature-detect and switch if wasm fails.

**mobile:** compile rust for ios/android; integrate via `flutter_rust_bridge`/ffi. feed same frame api from native capture (`avaudioengine`/oboe/aaudio).

**ui:** stream `{frequency, partials, timestamp, confidence}`; render note + cents; show partial list/graph; basic smoothing & clipping warnings.

**packaging:** serve `.wasm` with `application/wasm`; preload; release builds with optimizations.

**privacy:** on-device only. clear mic on dispose.

---

## constraints & risk checklist

* user gesture + `audiocontext.resume()` handled. ✔︎
* browser support audited; safari ios 14.5+ worklet supported; fallback present. ✔︎ \[6]
* no `sharedarraybuffer` → no coi headers needed. ✔︎
* realtime thread: audioworklet only; no heavy main-thread dsp. ✔︎
* numeric stability: float32 ok; double if needed. ✔︎ \[58]
* disable `ec/ns/agc`; sample rate respected. ✔︎
* transient handling: analyze post-attack (\~20–100 ms) window; optional threshold. ✔︎
* wasm load/mime correct; https; same-origin. ✔︎
* power: auto-stop on inactivity/navigation. ✔︎
* de-risk path: ship js fallback first, then wasm. ✔︎

---

## next steps (rollout)

1. prototype js (pitchfinder or aubio.js) in flutter web; verify detection with test sine.
2. implement rust wasm + audioworklet; verify desktop browsers.
3. integrate rust on mobile via ffi; reuse core detector.
4. benchmark & tune (window size, update rate); gate by device perf if needed.
5. ui polish (note+cent gauge, partials display).
6. edge-case handling (smoothing, confidence, clipping warnings).
7. docs & settings; advise best browsers/mics.
8. release; monitor; fix mime/compat quirks quickly.

---

## source list & justifications

* `flutter_detect_pitch` plugin (2025) – shows current mobile/native approach; web gap. \[22]
* hacker news (2022) – dev using rust for flutter tuner; viability; `pitch-detection`/`web-sys`. \[43]\[44]
* hn (2022) – dart gc issues for realtime dsp. \[3]
* toptal rust/wasm tutorial (2022) – move dsp off main thread; audioworklet pattern. \[47]\[48]
* bojan djurdjevic (2018) – wasm vs js speedup (8×–23×) for pitch loops. \[1]\[2]\[49]
* pitchfinder readme – yin etc.; browser usage. \[9]\[34]\[35]\[36]\[37]\[52]
* alexander ell tuner – web audio autocorrelation example. \[13–18]
* pitchlite (2023) – c++ wasm + worklet; accumulate to 4096; real-time pitch. \[25]\[26]
* stackoverflow – wasm advantages for audioworklet (no gc). \[11]
* crepe – cnn model; high accuracy but heavy; not ideal for low-latency client. \[9]
* aubio.js – wasm-based aubio in browser; mit license. \[12]\[33]
* mdn audioworklet / caniuse – ios 14.5+ support. \[6]
* zoom forum (2021) – safari worklet history; verify on devices. \[50]
* misc: sab bug webkit; ios permissions behavior; emscripten wasm audio worklets api; optimization notes. \[27–31]\[40]\[58–59]

(full urls listed in the original text.)

---

## appendix: troubleshooting & notes

* **mic on but no tone:** too low input (gain/distance); dc offset; window too short; multiple sources; browser `ec/ns/agc` on; safari loading issues; cross-origin/mime; clipping.
* **validation:** test with `oscillatornode` instead of mic to verify pipeline.
* **enhancements:** lug-by-lug workflow, decay time measurement, inharmonicity tracking.

---

## raw url list (as provided)

* wasm vs js pitch detection — bojan djurdjevic: [https://bojandjurdjevic.com/2018/WASM-vs-JS-Realtime-pitch-detection/](https://bojandjurdjevic.com/2018/WASM-vs-JS-Realtime-pitch-detection/)
* toptal wasm/rust tutorial: [https://www.toptal.com/webassembly/webassembly-rust-tutorial-web-audio](https://www.toptal.com/webassembly/webassembly-rust-tutorial-web-audio)
* flutter + rust tuner (hn): [https://news.ycombinator.com/item?id=33150946](https://news.ycombinator.com/item?id=33150946)
* flutter\_detect\_pitch: [https://pub.dev/packages/flutter\_detect\_pitch](https://pub.dev/packages/flutter_detect_pitch)
* audioworkletnode mdn: [https://developer.mozilla.org/en-US/docs/Web/API/AudioWorkletNode](https://developer.mozilla.org/en-US/docs/Web/API/AudioWorkletNode)
* pitchfinder: [https://github.com/peterkhayes/pitchfinder](https://github.com/peterkhayes/pitchfinder)
* aubio.js: [https://github.com/qiuxiang/aubiojs](https://github.com/qiuxiang/aubiojs)
* detecting pitch (autocorrelation): [https://alexanderell.is/posts/tuner/](https://alexanderell.is/posts/tuner/)
* crepe: [https://github.com/marl/crepe](https://github.com/marl/crepe)
* webassembly for audioworklet (so): [https://stackoverflow.com/questions/53108371/advantages-of-webassembly-for-audioworklet](https://stackoverflow.com/questions/53108371/advantages-of-webassembly-for-audioworklet)
* pitchlite: [https://github.com/sevagh/pitchlite](https://github.com/sevagh/pitchlite)
* sab → audioworklet bug: [https://bugs.webkit.org/show\_bug.cgi?id=237144](https://bugs.webkit.org/show_bug.cgi?id=237144)
* ios mic perms behavior: [https://github.com/aws/amazon-chime-sdk-js/issues/2381](https://github.com/aws/amazon-chime-sdk-js/issues/2381)
* emscripten wasm audio worklets api: [https://emscripten.org/docs/api\_reference/wasm\_audio\_worklets.html](https://emscripten.org/docs/api_reference/wasm_audio_worklets.html)
* zoom web sdk safari thread: [https://devforum.zoom.us/t/web-sdk-1-7-4-no-audio-for-ios-safari-unless-using-headphones/15837](https://devforum.zoom.us/t/web-sdk-1-7-4-no-audio-for-ios-safari-unless-using-headphones/15837)

> indices like \[1], \[22], etc., refer to the same numbered items in the original text.
