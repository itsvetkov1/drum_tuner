import 'dart:math';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:drum_tuning_plugin/src/models/analysis_result.dart';
import 'package:drum_tuning_plugin/src/web/pitch_analyzer.dart';

void main() {
  group('WebPitchAnalyzer', () {
    test('detects 110 Hz within ±0.5 Hz and labels A2', () {
      final WebPitchAnalyzer analyzer = WebPitchAnalyzer();
      final Int16List samples = _generateSineWave(
        frequencyHz: 110,
        amplitude: 0.2,
      );

      final AnalysisResult? result = analyzer.process(samples, 0);

      expect(result, isNotNull);
      expect(result!.f0Hz, isNotNull);
      expect(result.f0Hz!, closeTo(110, 0.5));
      expect(result.noteName, 'A2');
      expect(result.cents, isNotNull);
      expect(result.cents!.abs(), lessThan(5));
      expect(result.confidence, closeTo(1.0, 1e-3));
    });

    test('respects cooldown between strikes', () {
      final WebPitchAnalyzer analyzer = WebPitchAnalyzer();
      final Int16List samples = _generateSineWave(
        frequencyHz: 196,
        amplitude: 0.2,
      );

      final AnalysisResult? first = analyzer.process(samples, 0);
      final AnalysisResult? second = analyzer.process(samples, 100);
      final AnalysisResult? third = analyzer.process(samples, 400);

      expect(first, isNotNull);
      expect(second, isNull,
          reason: 'Cooldown should suppress immediate re-triggers');
      expect(third, isNotNull,
          reason: 'Cooldown elapsed should allow new result');
    });

    test('ignores low-level noise below RMS threshold', () {
      final WebPitchAnalyzer analyzer = WebPitchAnalyzer();
      final Int16List quietSamples = _generateSineWave(
        frequencyHz: 110,
        amplitude: 0.005,
      );

      final AnalysisResult? result = analyzer.process(quietSamples, 0);
      expect(result, isNull);
    });
  });
}

Int16List _generateSineWave({
  required double frequencyHz,
  required double amplitude,
  int sampleRate = WebPitchAnalyzer.sampleRate,
  int sampleCount = 4096,
}) {
  final Int16List buffer = Int16List(sampleCount);
  final double twoPiF = 2 * pi * frequencyHz;
  for (int i = 0; i < sampleCount; i++) {
    final double value = amplitude * sin(twoPiF * i / sampleRate);
    final int sample = (value * 32767).round();
    buffer[i] = sample.clamp(-32768, 32767);
  }
  return buffer;
}
