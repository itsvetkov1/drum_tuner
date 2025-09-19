import 'package:drum_tuner_app/features/analysis/analysis_snapshot.dart';
import 'package:drum_tuner_app/features/modes/lug/lug_state.dart';
import 'package:drum_tuner_app/features/analysis/analysis_snapshot_provider.dart';
import 'package:drum_tuning_plugin/drum_tuning_plugin.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _TestSnapshotNotifier extends AnalysisSnapshotNotifier {
  @override
  AnalysisSnapshot build() {
    return const AnalysisSnapshot();
  }

  void emit(AnalysisSnapshot snapshot) {
    state = snapshot;
  }
}

void main() {
  test('resolveTierWithHysteresis respects 0.05 Hz hysteresis bands', () {
    expect(resolveTierWithHysteresis(0.12, null), LugAdjustmentTier.slight);
    expect(
      resolveTierWithHysteresis(0.11, LugAdjustmentTier.inTune),
      LugAdjustmentTier.inTune,
    );
    expect(
      resolveTierWithHysteresis(0.16, LugAdjustmentTier.inTune),
      LugAdjustmentTier.slight,
    );
    expect(
      resolveTierWithHysteresis(0.07, LugAdjustmentTier.slight),
      LugAdjustmentTier.slight,
    );
    expect(
      resolveTierWithHysteresis(0.04, LugAdjustmentTier.slight),
      LugAdjustmentTier.inTune,
    );
  });

  test('lug state captures measurements with hysteresis and history', () {
    final ProviderContainer container = ProviderContainer(
      overrides: <Override>[
        analysisSnapshotProvider.overrideWith(_TestSnapshotNotifier.new),
      ],
    );
    addTearDown(container.dispose);

    final _TestSnapshotNotifier snapshotNotifier =
        container.read(analysisSnapshotProvider.notifier)
            as _TestSnapshotNotifier;
    final LugStateNotifier lugNotifier =
        container.read(lugStateProvider.notifier);

    lugNotifier.setActive(0);
    snapshotNotifier.emit(
      const AnalysisSnapshot(
        latest: AnalysisResult(
          f1Hz: 200,
          confidence: 0.9,
          timestampMs: 1,
        ),
      ),
    );
    lugNotifier.setReference(0);

    lugNotifier.setActive(1);
    snapshotNotifier.emit(
      const AnalysisSnapshot(
        latest: AnalysisResult(
          f1Hz: 200.14,
          confidence: 0.9,
          timestampMs: 2,
        ),
      ),
    );

    LugState state = container.read(lugStateProvider);
    expect(state.lugs[1].deltaHz, closeTo(0.14, 1e-6));
    expect(state.lugs[1].tier, LugAdjustmentTier.slight);
    expect(state.lugs[1].direction, LugAdjustmentDirection.loosen);
    expect(state.lugs[1].history.length, 1);

    snapshotNotifier.emit(
      const AnalysisSnapshot(
        latest: AnalysisResult(
          f1Hz: 200.08,
          confidence: 0.9,
          timestampMs: 3,
        ),
      ),
    );
    state = container.read(lugStateProvider);
    expect(state.lugs[1].tier, LugAdjustmentTier.slight);

    snapshotNotifier.emit(
      const AnalysisSnapshot(
        latest: AnalysisResult(
          f1Hz: 200.02,
          confidence: 0.9,
          timestampMs: 4,
        ),
      ),
    );
    state = container.read(lugStateProvider);
    expect(state.lugs[1].tier, LugAdjustmentTier.inTune);
    expect(state.lugs[1].direction, LugAdjustmentDirection.inTune);

    for (int i = 0; i < 6; i++) {
      snapshotNotifier.emit(
        AnalysisSnapshot(
          latest: AnalysisResult(
            f1Hz: 200.3 + i * 0.01,
            confidence: 0.9,
            timestampMs: 5 + i,
          ),
        ),
      );
    }
    state = container.read(lugStateProvider);
    expect(state.lugs[1].history.length, 6);
  });
}
