import 'package:drum_tuning_plugin/drum_tuning_plugin.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../analysis/analysis_snapshot.dart';
import '../../analysis/analysis_snapshot_provider.dart';

enum PitchStage { listening, coarse, refined }

class PitchUiState {
  const PitchUiState({
    required this.stage,
    this.frequencyHz,
    this.noteName,
    this.cents,
    required this.confidence,
  });

  final PitchStage stage;
  final double? frequencyHz;
  final String? noteName;
  final double? cents;
  final double confidence;

  factory PitchUiState.fromSnapshot(AnalysisSnapshot snapshot) {
    final AnalysisResult? latest = snapshot.latest;
    final List<AnalysisResult> history = snapshot.history;
    final bool hasRefinedWindow =
        history.length >= AnalysisSnapshotNotifier.historyWindow;

    if (latest == null && !hasRefinedWindow) {
      return const PitchUiState(
        stage: PitchStage.listening,
        confidence: 0,
      );
    }

    if (latest == null) {
      final _PitchMedian median = _calculateMedian(history);
      final AnalysisResult? fallback = history.isNotEmpty ? history.last : null;
      return PitchUiState(
        stage: hasRefinedWindow ? PitchStage.refined : PitchStage.listening,
        frequencyHz: median.hz ?? fallback?.f0Hz,
        noteName: median.note ?? fallback?.noteName,
        cents: median.cents ?? fallback?.cents,
        confidence: fallback?.confidence ?? 0,
      );
    }

    if (!hasRefinedWindow) {
      return PitchUiState(
        stage: PitchStage.coarse,
        frequencyHz: latest.f0Hz,
        noteName: latest.noteName,
        cents: latest.cents,
        confidence: latest.confidence,
      );
    }

    final _PitchMedian median = _calculateMedian(history);
    return PitchUiState(
      stage: PitchStage.refined,
      frequencyHz: median.hz ?? latest.f0Hz,
      noteName: median.note ?? latest.noteName,
      cents: median.cents ?? latest.cents,
      confidence: latest.confidence,
    );
  }

  String get stageLabel {
    switch (stage) {
      case PitchStage.listening:
        return 'Listening';
      case PitchStage.coarse:
        return 'Coarse estimate';
      case PitchStage.refined:
        return 'Refined lock';
    }
  }
}

class _PitchMedian {
  const _PitchMedian({
    this.hz,
    this.note,
    this.cents,
  });

  final double? hz;
  final String? note;
  final double? cents;
}

_PitchMedian _calculateMedian(List<AnalysisResult> results) {
  if (results.isEmpty) {
    return const _PitchMedian();
  }

  final List<double> hzValues = results
      .map((AnalysisResult result) => result.f0Hz)
      .whereType<double>()
      .toList(growable: false);
  if (hzValues.isEmpty) {
    return const _PitchMedian();
  }

  final double medianHz = _medianOf(hzValues);
  final AnalysisResult? closest = _closestByFrequency(results, medianHz);

  return _PitchMedian(
    hz: medianHz,
    note: closest?.noteName,
    cents: closest?.cents,
  );
}

double _medianOf(List<double> values) {
  final List<double> sorted = List<double>.of(values)..sort();
  final int mid = sorted.length ~/ 2;

  if (sorted.length.isOdd) {
    return sorted[mid];
  }

  return (sorted[mid - 1] + sorted[mid]) / 2;
}

AnalysisResult? _closestByFrequency(
  List<AnalysisResult> results,
  double target,
) {
  AnalysisResult? closest;
  double bestDistance = double.infinity;

  for (final AnalysisResult result in results) {
    final double? f0 = result.f0Hz;
    if (f0 == null) {
      continue;
    }

    final double distance = (f0 - target).abs();
    if (distance < bestDistance) {
      bestDistance = distance;
      closest = result;
    }
  }

  return closest;
}

final pitchUiStateProvider = Provider.autoDispose<PitchUiState>((Ref ref) {
  final AnalysisSnapshot snapshot = ref.watch(analysisSnapshotProvider);
  return PitchUiState.fromSnapshot(snapshot);
});
