import 'package:drum_tuner_app/features/analysis/analysis_snapshot.dart';
import 'package:drum_tuner_app/features/modes/pitch/pitch_state.dart';
import 'package:drum_tuning_plugin/drum_tuning_plugin.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('returns listening state when no data is available', () {
    const AnalysisSnapshot snapshot = AnalysisSnapshot();

    final PitchUiState state = PitchUiState.fromSnapshot(snapshot);

    expect(state.stage, PitchStage.listening);
    expect(state.frequencyHz, isNull);
    expect(state.noteName, isNull);
  });

  test('coarse stage reflects the latest reading', () {
    const AnalysisResult latest = AnalysisResult(
      f0Hz: 198.4,
      noteName: 'G3',
      cents: -12.5,
      confidence: 0.58,
      timestampMs: 10,
    );
    const AnalysisSnapshot snapshot = AnalysisSnapshot(latest: latest);

    final PitchUiState state = PitchUiState.fromSnapshot(snapshot);

    expect(state.stage, PitchStage.coarse);
    expect(state.frequencyHz, latest.f0Hz);
    expect(state.noteName, latest.noteName);
    expect(state.cents, latest.cents);
    expect(state.confidence, latest.confidence);
  });

  test('refined stage uses the median of last five stable results', () {
    const List<AnalysisResult> history = <AnalysisResult>[
      AnalysisResult(
        f0Hz: 198,
        noteName: 'N1',
        cents: -2,
        confidence: 0.9,
        timestampMs: 1,
      ),
      AnalysisResult(
        f0Hz: 199,
        noteName: 'N2',
        cents: -1,
        confidence: 0.9,
        timestampMs: 2,
      ),
      AnalysisResult(
        f0Hz: 200,
        noteName: 'N3',
        cents: 0,
        confidence: 0.9,
        timestampMs: 3,
      ),
      AnalysisResult(
        f0Hz: 201,
        noteName: 'N4',
        cents: 1,
        confidence: 0.9,
        timestampMs: 4,
      ),
      AnalysisResult(
        f0Hz: 202,
        noteName: 'N5',
        cents: 2,
        confidence: 0.9,
        timestampMs: 5,
      ),
    ];
    const AnalysisResult latest = AnalysisResult(
      f0Hz: 204,
      noteName: 'Latest',
      cents: 3,
      confidence: 0.72,
      timestampMs: 6,
    );
    final AnalysisSnapshot snapshot = AnalysisSnapshot(
      latest: latest,
      history: List<AnalysisResult>.unmodifiable(history),
    );

    final PitchUiState state = PitchUiState.fromSnapshot(snapshot);

    expect(state.stage, PitchStage.refined);
    expect(state.frequencyHz, 200);
    expect(state.noteName, 'N3');
    expect(state.cents, 0);
    expect(state.confidence, latest.confidence);
  });
}
