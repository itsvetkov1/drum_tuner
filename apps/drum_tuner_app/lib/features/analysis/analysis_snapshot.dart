import 'package:drum_tuning_plugin/drum_tuning_plugin.dart';

class AnalysisSnapshot {
  const AnalysisSnapshot({
    this.latest,
    this.history = const <AnalysisResult>[],
  });

  final AnalysisResult? latest;
  final List<AnalysisResult> history;

  AnalysisSnapshot copyWith({
    AnalysisResult? latest,
    List<AnalysisResult>? history,
  }) {
    return AnalysisSnapshot(
      latest: latest ?? this.latest,
      history: history ?? this.history,
    );
  }
}
