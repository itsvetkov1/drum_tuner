class FFT {
  constructor(size) {
    if (!Number.isInteger(size) || size <= 0 || (size & (size - 1)) !== 0) {
      throw new Error('FFT size must be a power of two.');
    }
    this.size = size;
    this.levels = Math.log2(size) | 0;
    this.cosTable = new Float64Array(size / 2);
    this.sinTable = new Float64Array(size / 2);
    for (let i = 0; i < size / 2; i++) {
      this.cosTable[i] = Math.cos((2 * Math.PI * i) / size);
      this.sinTable[i] = -Math.sin((2 * Math.PI * i) / size);
    }
  }

  transform(real, imag) {
    const n = this.size;
    const levels = this.levels;
    const cosTable = this.cosTable;
    const sinTable = this.sinTable;

    for (let i = 0; i < n; i++) {
      const j = reverseBits(i, levels);
      if (j > i) {
        const tempReal = real[i];
        const tempImag = imag[i];
        real[i] = real[j];
        imag[i] = imag[j];
        real[j] = tempReal;
        imag[j] = tempImag;
      }
    }

    for (let size = 2; size <= n; size <<= 1) {
      const halfSize = size >> 1;
      const tableStep = n / size;
      for (let i = 0; i < n; i += size) {
        let k = 0;
        for (let j = i; j < i + halfSize; j++) {
          const l = j + halfSize;
          const tpre = real[l] * cosTable[k] - imag[l] * sinTable[k];
          const tpim = real[l] * sinTable[k] + imag[l] * cosTable[k];
          real[l] = real[j] - tpre;
          imag[l] = imag[j] - tpim;
          real[j] += tpre;
          imag[j] += tpim;
          k += tableStep;
        }
      }
    }
  }
}

function reverseBits(index, bits) {
  let reversed = 0;
  for (let i = 0; i < bits; i++, index >>= 1) {
    reversed = (reversed << 1) | (index & 1);
  }
  return reversed;
}

function hannWindow(size) {
  const window = new Float64Array(size);
  const factor = 2 * Math.PI / (size - 1);
  for (let i = 0; i < size; i++) {
    window[i] = 0.5 * (1 - Math.cos(factor * i));
  }
  return window;
}

function parabolicInterpolate(magnitudes, index) {
  if (index <= 0 || index >= magnitudes.length - 1) {
    return index;
  }
  const left = magnitudes[index - 1];
  const center = magnitudes[index];
  const right = magnitudes[index + 1];
  const denominator = left - 2 * center + right;
  if (Math.abs(denominator) < 1e-9) {
    return index;
  }
  const delta = 0.5 * (left - right) / denominator;
  return index + delta;
}

function clamp(value, min, max) {
  return Math.min(Math.max(value, min), max);
}

function extractPeaks(magnitudes, minBin, maxBin, binResolution, limit = 5) {
  const peaks = [];
  for (let i = minBin + 1; i < maxBin - 1; i++) {
    const magnitude = magnitudes[i];
    if (magnitude <= magnitudes[i - 1] || magnitude <= magnitudes[i + 1]) {
      continue;
    }
    peaks.push({
      index: i,
      Hz: binResolution * i,
      mag: magnitude,
    });
  }
  peaks.sort((a, b) => b.mag - a.mag);
  return peaks.slice(0, limit).map((peak) => ({ Hz: peak.Hz, mag: peak.mag }));
}

function findF1(peaks, f0) {
  if (!f0 || !isFinite(f0) || f0 <= 0) {
    return null;
  }
  const min = f0 * 1.4;
  const max = f0 * 3.2;
  for (const peak of peaks) {
    if (peak.Hz >= min && peak.Hz <= max) {
      return peak.Hz;
    }
  }
  return null;
}

class StrikeSession {
  constructor(refineSize) {
    this.buffer = new Float32Array(refineSize);
    this.writeIndex = 0;
    this.coarseSent = false;
    this.startSample = 0;
    this.lastRms = 0;
  }

  append(samples) {
    if (this.writeIndex >= this.buffer.length) {
      return;
    }
    const remaining = this.buffer.length - this.writeIndex;
    const chunk = samples.subarray(0, Math.min(remaining, samples.length));
    this.buffer.set(chunk, this.writeIndex);
    this.writeIndex += chunk.length;
  }
}

class DrumAnalyzerProcessor extends AudioWorkletProcessor {
  constructor(options = {}) {
    super();
    const params = options.processorOptions || {};
    this.sampleRate = params.sampleRate || sampleRate;
    this.coarseSize = params.coarseSize || 4096;
    this.refineSize = params.refineSize || 16384;
    this.zeroPadFactor = Math.max(1, params.zeroPadFactor || 1);
    this.strikeOnRms = params.strikeOnRms || 0.012;
    this.strikeOffRms = params.strikeOffRms || 0.006;
    this.cooldownSamples = Math.floor((params.cooldownMs || 250) * this.sampleRate / 1000);
    this.amplitudeIntervalSamples = Math.max(1, Math.floor((params.amplitudeIntervalMs || 50) * this.sampleRate / 1000));
    this.minFrequencyHz = params.minFrequencyHz || 20;
    this.maxFrequencyHz = params.maxFrequencyHz || 1200;
    this.debug = params.debug !== false;

    this.coarseWindow = hannWindow(this.coarseSize);
    this.refineWindow = hannWindow(this.refineSize);

    this.coarseFFT = new FFT(this.coarseSize);
    this.refineFFT = new FFT(this.refineSize * this.zeroPadFactor);

    this.coarseReal = new Float64Array(this.coarseFFT.size);
    this.coarseImag = new Float64Array(this.coarseFFT.size);
    this.coarseMagnitudes = new Float64Array(this.coarseFFT.size / 2);

    this.refineReal = new Float64Array(this.refineFFT.size);
    this.refineImag = new Float64Array(this.refineFFT.size);
    this.refineMagnitudes = new Float64Array(this.refineFFT.size / 2);

    this.session = null;
    this.cooldownUntilSample = 0;
    this.runningSampleIndex = 0;
    this.envelope = 0;
    this.envelopeDecay = 0.85;
    this.samplesSinceAmplitude = 0;
    this.log('initialized', {
      sampleRate: this.sampleRate,
      coarseSize: this.coarseSize,
      refineSize: this.refineSize,
      zeroPad: this.zeroPadFactor,
    });
  }

  process(inputs, outputs) {
    const input = inputs[0];
    if (!input || input.length === 0) {
      this._clearOutputs(outputs);
      return true;
    }
    const channel = input[0];
    if (!channel) {
      this._clearOutputs(outputs);
      return true;
    }

    let sumSquares = 0;
    let peak = 0;
    for (let i = 0; i < channel.length; i++) {
      const sample = channel[i];
      sumSquares += sample * sample;
      const abs = Math.abs(sample);
      if (abs > peak) {
        peak = abs;
      }
    }

    const rms = Math.sqrt(sumSquares / channel.length);
    this.envelope = this.envelopeDecay * this.envelope + (1 - this.envelopeDecay) * rms;
    this.samplesSinceAmplitude += channel.length;

    if (this.samplesSinceAmplitude >= this.amplitudeIntervalSamples) {
      this.samplesSinceAmplitude = 0;
      this.port.postMessage({
        type: 'amplitude',
        payload: {
          rms,
          peak,
          db: 20 * Math.log10(Math.max(rms, 1e-6)),
        },
      });
    }

    const nowSample = this.runningSampleIndex;

    if (!this.session) {
      const canTrigger = nowSample >= this.cooldownUntilSample;
      if (canTrigger && this.envelope >= this.strikeOnRms) {
        this.session = new StrikeSession(this.refineSize);
        this.session.startSample = nowSample;
        this.log('strike:start', { startSample: nowSample, envelope: this.envelope });
      }
    }

    if (this.session) {
      this.session.append(channel);
      this.session.lastRms = rms;
      if (!this.session.coarseSent && this.session.writeIndex >= this.coarseSize) {
        const coarseView = this.session.buffer.subarray(0, this.coarseSize);
        const coarseResult = this.analyzeWindow(coarseView, true, this.session.lastRms);
        if (coarseResult) {
          this.emitResult(coarseResult, 'coarse', this.session.startSample);
        } else {
          this.log('coarse:analysis-null', { startSample: this.session.startSample });
        }
        this.session.coarseSent = true;
      }
      if (this.session.writeIndex >= this.refineSize) {
        const refineView = this.session.buffer.subarray(0, this.refineSize);
        const refineResult = this.analyzeWindow(refineView, false, this.session.lastRms);
        if (refineResult) {
          this.emitResult(refineResult, 'refine', this.session.startSample);
        } else {
          this.log('refine:analysis-null', { startSample: this.session.startSample });
        }
        this.cooldownUntilSample = nowSample + this.cooldownSamples;
        this.session = null;
      } else if (this.envelope <= this.strikeOffRms && this.session.writeIndex >= this.coarseSize) {
        // If the strike decays early, still emit what we have once.
        const refineView = this.session.buffer.subarray(0, Math.max(this.session.writeIndex, this.coarseSize));
        const padded = new Float32Array(this.refineSize);
        padded.set(refineView.subarray(0, Math.min(refineView.length, this.refineSize)));
        const result = this.analyzeWindow(padded, false, this.session.lastRms);
        if (result) {
          this.emitResult(result, 'refine', this.session.startSample);
        } else {
          this.log('refine:early-null', { startSample: this.session.startSample });
        }
        this.cooldownUntilSample = nowSample + this.cooldownSamples;
        this.session = null;
      }
    }

    this.runningSampleIndex += channel.length;
    this._clearOutputs(outputs);
    return true;
  }

  analyzeWindow(samples, isCoarse, windowRms) {
    const windowSize = isCoarse ? this.coarseSize : this.refineSize;
    const fft = isCoarse ? this.coarseFFT : this.refineFFT;
    const window = isCoarse ? this.coarseWindow : this.refineWindow;
    const real = isCoarse ? this.coarseReal : this.refineReal;
    const imag = isCoarse ? this.coarseImag : this.refineImag;
    const magnitudes = isCoarse ? this.coarseMagnitudes : this.refineMagnitudes;
    const fftSize = fft.size;

    for (let i = 0; i < windowSize; i++) {
      const sample = i < samples.length ? samples[i] : 0;
      real[i] = sample * window[i];
      imag[i] = 0;
    }
    for (let i = windowSize; i < fftSize; i++) {
      real[i] = 0;
      imag[i] = 0;
    }

    fft.transform(real, imag);

    const bins = fftSize / 2;
    const binResolution = this.sampleRate / fftSize;
    const minBin = Math.max(1, Math.floor(this.minFrequencyHz / binResolution));
    const maxBin = Math.min(bins - 2, Math.ceil(this.maxFrequencyHz / binResolution));
    let bestMag = 0;
    let bestBin = -1;
    let totalMag = 0;

    for (let i = 0; i < bins; i++) {
      const mag = Math.hypot(real[i], imag[i]);
      magnitudes[i] = mag;
      totalMag += mag;
      if (i >= minBin && i <= maxBin && mag > bestMag) {
        bestMag = mag;
        bestBin = i;
      }
    }

    if (bestBin <= 0 || bestMag <= 1e-9) {
      return null;
    }

    const refinedBin = parabolicInterpolate(magnitudes, bestBin);
    const f0 = refinedBin * binResolution;
    if (!isFinite(f0) || f0 <= 0) {
      return null;
    }

    const peaks = extractPeaks(magnitudes, minBin, maxBin, binResolution, 6);
    const f1 = findF1(peaks, f0);
    const rtf = f1 ? f1 / f0 : null;

    const noiseFloor = Math.max(1e-9, (totalMag - bestMag) / Math.max(1, bins));
    const confidence = clamp(bestMag / (bestMag + noiseFloor), isCoarse ? 0.3 : 0.0, 1.0);

    return {
      f0Hz: f0,
      f1Hz: f1,
      rtf,
      peaks,
      confidence: isCoarse ? Math.min(confidence, 0.6) : confidence,
      rms: windowRms || 0,
      stage: isCoarse ? 'coarse' : 'refine',
    };
  }

  emitResult(result, stage, startSample) {
    const timestampSamples = startSample + (stage === 'coarse' ? this.coarseSize : this.refineSize);
    const timestampMs = Math.round((timestampSamples / this.sampleRate) * 1000);
    this.log('emit', { stage, f0: result.f0Hz, f1: result.f1Hz, confidence: result.confidence });
    this.port.postMessage({
      type: 'analysis',
      payload: {
        stage: result.stage,
        timestampMs,
        f0Hz: result.f0Hz,
        f1Hz: result.f1Hz,
        rtf: result.rtf,
        confidence: result.confidence,
        peaks: result.peaks,
        rms: result.rms,
      },
    });
  }

  log(message, data) {
    if (!this.debug) {
      return;
    }
    this.port.postMessage({ type: 'log', message: { message, data } });
  }

  _clearOutputs(outputs) {
    if (!outputs || outputs.length === 0) {
      return;
    }
    for (let i = 0; i < outputs.length; i++) {
      const channels = outputs[i];
      if (!channels) {
        continue;
      }
      for (let c = 0; c < channels.length; c++) {
        const buffer = channels[c];
        if (!buffer) {
          continue;
        }
        buffer.fill(0);
      }
    }
  }
}

registerProcessor('drum-analyzer', DrumAnalyzerProcessor);
