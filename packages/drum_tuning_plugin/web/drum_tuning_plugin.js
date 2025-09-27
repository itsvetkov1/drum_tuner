(function () {
  const globalScope = typeof window !== 'undefined' ? window : self;
  if (globalScope.drumTuningPlugin) {
    return;
  }

  const DEBUG = true;
  function debugLog(...args) {
    if (!DEBUG) {
      return;
    }
    console.log('[drum_tuning_plugin]', ...args);
  }

  function debugError(...args) {
    console.error('[drum_tuning_plugin]', ...args);
  }

  const scriptUrl =
    typeof document !== 'undefined' && document.currentScript
      ? document.currentScript.src
      : '';

  function resolveAssetUrls(file) {
    const urls = [];
    const seen = new Set();

    function pushUrl(url) {
      if (!url) {
        return;
      }
      if (!seen.has(url)) {
        seen.add(url);
        urls.push(url);
      }
    }

    try {
      if (scriptUrl) {
        pushUrl(new URL(file, scriptUrl).toString());
      }
    } catch (error) {
      debugError('resolveAssetUrls scriptUrl failed', error);
    }

    const assetsBase =
      (globalScope.flutterConfiguration &&
        globalScope.flutterConfiguration.assetsBase)
        ? globalScope.flutterConfiguration.assetsBase
        : null;
    try {
      if (assetsBase) {
        pushUrl(new URL(`packages/drum_tuning_plugin/${file}`, assetsBase).toString());
      }
    } catch (error) {
      debugError('resolveAssetUrls assetsBase failed', error);
    }

    const baseLocation = globalScope.location || self.location;
    try {
      pushUrl(new URL(`assets/packages/drum_tuning_plugin/${file}`, baseLocation).toString());
    } catch (error) {
      debugError('resolveAssetUrls assets fallback failed', error);
    }

    try {
      pushUrl(new URL(`packages/drum_tuning_plugin/${file}`, baseLocation).toString());
    } catch (error) {
      debugError('resolveAssetUrls packages fallback failed', error);
    }

    pushUrl(`assets/packages/drum_tuning_plugin/${file}`);
    pushUrl(`packages/drum_tuning_plugin/${file}`);

    return urls;
  }

  const DEFAULT_OPTIONS = {
    coarseSize: 4096,
    refineSize: 16384,
    zeroPadFactor: 2,
    strikeOnRms: 0.012,
    strikeOffRms: 0.006,
    cooldownMs: 260,
    amplitudeIntervalMs: 50,
    minFrequencyHz: 20,
    maxFrequencyHz: 1200,
  };

  const state = {
    listeners: new Set(),
    amplitudeListeners: new Set(),
    audioContext: null,
    mediaStream: null,
    mediaSource: null,
    workletNode: null,
    zeroGain: null,
    startPromise: null,
    isStarted: false,
    lastAmplitudeNotify: 0,
    startCount: 0,
  };

  function mergeOptions(options) {
    return Object.assign({}, DEFAULT_OPTIONS, options || {});
  }

  function ensureMediaDevices() {
    if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) {
      debugError('mediaDevices unavailable');
      throw new Error('Microphone is not supported in this browser.');
    }
  }

  async function ensurePermission(options) {
    ensureMediaDevices();
    const constraints = buildConstraints(options);
    debugLog('ensurePermission:start', constraints);
    const stream = await navigator.mediaDevices.getUserMedia(constraints);
    // Immediately stop tracks; we only needed to prompt for permission.
    for (const track of stream.getTracks()) {
      track.stop();
    }
    debugLog('ensurePermission:granted');
    return true;
  }

  function buildConstraints(options) {
    const audioConstraints = {
      echoCancellation: false,
      noiseSuppression: false,
      autoGainControl: false,
      channelCount: 1,
    };
    if (options && options.sampleRate) {
      audioConstraints.sampleRate = options.sampleRate;
    }
    return { audio: audioConstraints, video: false };
  }

  async function loadWorkletModule(audioContext) {
    if (!audioContext) {
      debugError('AudioContext missing when loading worklet');
      throw new Error('AudioContext is not initialised.');
    }
    const moduleUrls = resolveAssetUrls('drum_analyzer.worklet.js');
    let lastError = null;
    for (const url of moduleUrls) {
      try {
        debugLog('loadWorkletModule', url);
        await audioContext.audioWorklet.addModule(url);
        return;
      } catch (error) {
        lastError = error;
        debugError('loadWorkletModule failed', url, error);
      }
    }
    throw lastError || new Error('Unable to load drum analyzer worklet.');
  }

  function notifyListeners(set, payload) {
    for (const listener of Array.from(set)) {
      try {
        listener(payload);
      } catch (error) {
        debugError('listener error', error);
      }
    }
  }

  function cleanup() {
    debugLog('cleanup:start');
    if (state.mediaSource) {
      try {
        state.mediaSource.disconnect();
      } catch (_) {}
      state.mediaSource = null;
    }
    if (state.workletNode) {
      try {
        state.workletNode.port.onmessage = null;
        state.workletNode.disconnect();
      } catch (_) {}
      state.workletNode = null;
    }
    if (state.zeroGain) {
      try {
        state.zeroGain.disconnect();
      } catch (_) {}
      state.zeroGain = null;
    }
    if (state.mediaStream) {
      for (const track of state.mediaStream.getTracks()) {
        track.stop();
      }
      state.mediaStream = null;
    }
    if (state.audioContext) {
      state.audioContext.close().catch(() => {});
      state.audioContext = null;
    }
    state.isStarted = false;
    state.startPromise = null;
    state.startCount = 0;
    debugLog('cleanup:done');
  }

  async function start(options) {
    state.startCount = Math.max(0, state.startCount) + 1;
    debugLog('start:requested', { startCount: state.startCount, isStarted: state.isStarted });
    if (state.isStarted) {
      debugLog('start:already-started');
      return;
    }
    if (state.startPromise) {
      debugLog('start:await-existing');
      await state.startPromise;
      return;
    }
    const merged = mergeOptions(options);
    const promise = startInternal(merged)
      .catch((error) => {
        debugError('startInternal failed', error);
        cleanup();
        throw error;
      })
      .finally(() => {
        state.startPromise = null;
      });
    state.startPromise = promise;
    await promise;
  }

  async function startInternal(options) {
    ensureMediaDevices();
    debugLog('startInternal:options', options);
    const constraints = buildConstraints(options);
    const mediaStream = await navigator.mediaDevices.getUserMedia(constraints);
    debugLog('startInternal:mediaStream', { tracks: mediaStream.getTracks().length });

    const AudioContextCtor = window.AudioContext || window.webkitAudioContext;
    if (!AudioContextCtor) {
      debugError('Web Audio API unavailable');
      throw new Error('Web Audio API is not supported in this browser.');
    }

    const audioContext = new AudioContextCtor({ sampleRate: options.sampleRate });
    debugLog('startInternal:audioContext-created', {
      sampleRate: audioContext.sampleRate,
      state: audioContext.state,
    });
    await loadWorkletModule(audioContext);

    const source = audioContext.createMediaStreamSource(mediaStream);
    const node = new AudioWorkletNode(audioContext, 'drum-analyzer', {
      numberOfOutputs: 1,
      processorOptions: {
        sampleRate: audioContext.sampleRate,
        coarseSize: options.coarseSize,
        refineSize: options.refineSize,
        zeroPadFactor: options.zeroPadFactor,
        strikeOnRms: options.strikeOnRms,
        strikeOffRms: options.strikeOffRms,
        cooldownMs: options.cooldownMs,
        amplitudeIntervalMs: options.amplitudeIntervalMs,
        minFrequencyHz: options.minFrequencyHz,
        maxFrequencyHz: options.maxFrequencyHz,
        debug: true,
      },
    });

    node.port.onmessage = (event) => {
      const data = event.data || {};
      switch (data.type) {
        case 'analysis':
          notifyListeners(state.listeners, data.payload);
          break;
        case 'amplitude':
          const now = performance.now();
          if (now - state.lastAmplitudeNotify >= options.amplitudeIntervalMs) {
            state.lastAmplitudeNotify = now;
            notifyListeners(state.amplitudeListeners, data.payload);
          }
          break;
        case 'log':
          debugLog('worklet', data.message);
          break;
        case 'error':
          debugError('worklet', data.message);
          break;
        default:
          break;
      }
    };

    // Keep the node alive; connect to a zero-gain destination.
    const zeroGain = audioContext.createGain();
    zeroGain.gain.value = 0;
    source.connect(node);
    node.connect(zeroGain);
    zeroGain.connect(audioContext.destination);
    debugLog('startInternal:audio-graph-connected');

    if (audioContext.state === 'suspended') {
      try {
        await audioContext.resume();
        debugLog('startInternal:audioContext-resumed');
      } catch (error) {
        debugError('failed to resume AudioContext', error);
      }
    }

    state.audioContext = audioContext;
    state.mediaStream = mediaStream;
    state.mediaSource = source;
    state.workletNode = node;
    state.zeroGain = zeroGain;
    state.isStarted = true;
    state.lastAmplitudeNotify = 0;
    debugLog('startInternal:ready');
  }

  async function stop() {
    debugLog('stop:requested', { startCount: state.startCount });
    if (state.startCount > 0) {
      state.startCount -= 1;
    }
    if (state.startCount > 0) {
      debugLog('stop:deferred', { startCount: state.startCount });
      return;
    }
    debugLog('stop:cleanup');
    cleanup();
  }

  function subscribe(callback) {
    if (typeof callback !== 'function') {
      throw new TypeError('Expected a function.');
    }
    state.listeners.add(callback);
    return () => {
      state.listeners.delete(callback);
    };
  }

  function subscribeAmplitude(callback) {
    if (typeof callback !== 'function') {
      throw new TypeError('Expected a function.');
    }
    state.amplitudeListeners.add(callback);
    return () => {
      state.amplitudeListeners.delete(callback);
    };
  }

  globalScope.drumTuningPlugin = {
    ensurePermission,
    start,
    stop,
    subscribe,
    subscribeAmplitude,
    isRunning() {
      return state.isStarted;
    },
    sampleRate() {
      return state.audioContext ? state.audioContext.sampleRate : null;
    },
  };
})();
