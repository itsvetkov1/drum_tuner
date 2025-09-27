import 'package:drum_tuning_plugin/drum_tuning_plugin.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'analysis_snapshot.dart';
import 'providers.dart';

class AnalysisSnapshotNotifier extends AutoDisposeNotifier<AnalysisSnapshot> {
  static const int historyWindow = 5;
  static const double _confidenceThreshold = 0.65;

  @override
  AnalysisSnapshot build() {
    final ProviderSubscription<AsyncValue<AnalysisResult>> subscription =
        ref.listen(
      analysisStreamProvider,
      (AsyncValue<AnalysisResult>? previous, AsyncValue<AnalysisResult> next) {
        next.whenData(_handleEvent);
      },
    );

    ref.onDispose(subscription.close);

    ref.listen<bool>(micCaptureEnabledProvider, (bool? _, bool next) {
      if (!next) {
        state = const AnalysisSnapshot();
      }
    });

    return const AnalysisSnapshot();
  }

  void _handleEvent(AnalysisResult result) {
    final List<AnalysisResult> updatedHistory =
        List<AnalysisResult>.from(state.history);
    if (result.confidence >= _confidenceThreshold) {
      updatedHistory.add(result);
      if (updatedHistory.length > historyWindow) {
        updatedHistory.removeAt(0);
      }
    }

    state = state.copyWith(
      latest: result,
      history: List<AnalysisResult>.unmodifiable(updatedHistory),
    );
  }
}

final analysisSnapshotProvider =
    AutoDisposeNotifierProvider<AnalysisSnapshotNotifier, AnalysisSnapshot>(
  AnalysisSnapshotNotifier.new,
);
