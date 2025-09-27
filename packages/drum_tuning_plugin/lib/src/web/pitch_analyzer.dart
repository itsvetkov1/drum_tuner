import 'dart:math';
import 'dart:typed_data';

import '../models/analysis_result.dart';

class WebPitchAnalyzer {
  static const int sampleRate = 44100;
  static const double rmsThreshold = 0.015;
  static const double targetRms = 0.12;
  static const int strikeCooldownMs = 180;
  static const double _int16Scale = 32768.0;
  static final double _ln2 = log(2);

  static const List<String> _noteNames = <String>[
    'C',
    'C#',
    'D',
    'D#',
    'E',
    'F',
    'F#',
    'G',
    'G#',
    'A',
    'A#',
    'B',
  ];

  int _lastEmissionMs = -strikeCooldownMs;

  AnalysisResult? process(Int16List samples, int timestampMs) {
    final int length = samples.length;
    if (length < 2) {
      return null;
    }

    if (timestampMs - _lastEmissionMs < strikeCooldownMs) {
      return null;
    }

    final Float64List normalized = Float64List(length);
    double sumSquares = 0;
    for (int i = 0; i < length; i++) {
      final double value = samples[i] / _int16Scale;
      normalized[i] = value;
      sumSquares += value * value;
    }

    final double rmsValue = sqrt(sumSquares / length);
    if (rmsValue < rmsThreshold) {
      return null;
    }

    final double? frequency = _estimateFrequency(normalized);
    final double confidence = (rmsValue / targetRms).clamp(0.0, 1.0);

    _lastEmissionMs = timestampMs;

    return AnalysisResult(
      f0Hz: frequency,
      f1Hz: null,
      rtf: null,
      noteName: _noteNameForFrequency(frequency),
      cents: _centsOffset(frequency),
      confidence: confidence,
      peaks: const <Peak>[],
      timestampMs: timestampMs,
    );
  }

  double? _estimateFrequency(Float64List normalized) {
    final int length = normalized.length;
    double sum = 0;
    for (final double value in normalized) {
      sum += value;
    }
    final double mean = sum / length;
    for (int i = 0; i < length; i++) {
      normalized[i] -= mean;
    }

    final int minLag = max(1, (sampleRate / 1200).floor());
    final int theoreticalMaxLag = (sampleRate / 30).floor();
    final int maxLag = min(length - 1, theoreticalMaxLag);
    if (maxLag <= minLag) {
      return null;
    }

    final List<double> correlations = List<double>.filled(maxLag + 1, 0);
    double bestScore = double.negativeInfinity;
    int bestLag = -1;

    for (int lag = minLag; lag <= maxLag; lag++) {
      double correlation = 0;
      for (int i = 0; i < length - lag; i++) {
        correlation += normalized[i] * normalized[i + lag];
      }
      correlations[lag] = correlation;
      if (correlation > bestScore) {
        bestScore = correlation;
        bestLag = lag;
      }
    }

    if (bestLag <= 0 || bestScore <= 0) {
      return null;
    }

    double refinedLag = bestLag.toDouble();
    if (bestLag > minLag && bestLag < maxLag) {
      final double prev = correlations[bestLag - 1];
      final double next = correlations[bestLag + 1];
      final double denom = prev - 2 * bestScore + next;
      if (denom.abs() > 1e-9) {
        final double delta = 0.5 * (prev - next) / denom;
        refinedLag += delta;
      }
    }

    if (refinedLag <= 0) {
      return null;
    }

    return sampleRate / refinedLag;
  }

  String? _noteNameForFrequency(double? frequency) {
    if (frequency == null || frequency <= 0) {
      return null;
    }
    final double midi = 69 + 12 * _log2(frequency / 440.0);
    final int nearestMidi = midi.round();
    final int octave = (nearestMidi ~/ 12) - 1;
    final int noteIndex = ((nearestMidi % 12) + 12) % 12;
    return '${_noteNames[noteIndex]}$octave';
  }

  double? _centsOffset(double? frequency) {
    if (frequency == null || frequency <= 0) {
      return null;
    }
    final double midi = 69 + 12 * _log2(frequency / 440.0);
    final int nearestMidi = midi.round();
    return (midi - nearestMidi) * 100.0;
  }

  double _log2(double value) {
    return log(value) / _ln2;
  }
}
