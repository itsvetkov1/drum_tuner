# Web Mic Debug Logging (temporary)

This is a throwaway note describing the extra diagnostics we just enabled to
understand the web microphone error. Remove it once we finish debugging.

## Where to watch

- **Browser console** (Chrome DevTools etc.) — the bridge in
  `packages/drum_tuning_plugin/web/drum_tuning_plugin.js` now calls
  `console.log('[drum_tuning_plugin]', …)` for permission requests, AudioContext
  lifecycle, and messages forwarded from the worklet.
- **Worklet logs** — `packages/drum_tuning_plugin/web/drum_analyzer.worklet.js`
  posts `type: 'log'` events whenever a strike triggers, coarse/refine analysis
  runs, or a result emits. These surface through the bridge with the same
  console prefix.
- **Flutter runner output** — `apps/drum_tuner_app/lib/mic_service_web_impl.dart`
  now prints `[MicServiceWeb] …` lines (guarded by `kDebugMode`) covering
  permission calls, start/stop, amplitude samples, and bridge script loading.

Grab those logs on the next repro attempt so we can pinpoint the failure path.
