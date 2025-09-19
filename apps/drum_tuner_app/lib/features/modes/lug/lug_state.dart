import 'dart:math' as math;

import 'package:drum_tuning_plugin/drum_tuning_plugin.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../analysis/analysis_snapshot.dart';
import '../../analysis/analysis_snapshot_provider.dart';

const double kLugSlightThresholdHz = 0.10;
const double kLugMediumThresholdHz = 0.30;
const double kLugStrongThresholdHz = 0.80;
const double kLugHysteresisHz = 0.05;

class LugState {
  const LugState({
    required this.lugs,
    this.referenceIndex,
    this.activeIndex,
  });

  final List<LugInfo> lugs;
  final int? referenceIndex;
  final int? activeIndex;

  LugState copyWith({
    List<LugInfo>? lugs,
    int? referenceIndex,
    bool clearReference = false,
    int? activeIndex,
    bool clearActive = false,
  }) {
    return LugState(
      lugs: lugs ?? this.lugs,
      referenceIndex:
          clearReference ? null : (referenceIndex ?? this.referenceIndex),
      activeIndex: clearActive ? null : (activeIndex ?? this.activeIndex),
    );
  }

  static LugState initial({int lugCount = 6}) {
    return LugState(
      lugs: List<LugInfo>.generate(lugCount, (int index) => LugInfo(index: index)),
    );
  }
}

class LugInfo {
  const LugInfo({
    required this.index,
    this.lastHz,
    this.lastTimestampMs,
    this.deltaHz,
    this.centsOffset,
    this.tier,
    this.direction,
    this.history = const <LugHistoryEntry>[],
  });

  final int index;
  final double? lastHz;
  final int? lastTimestampMs;
  final double? deltaHz;
  final double? centsOffset;
  final LugAdjustmentTier? tier;
  final LugAdjustmentDirection? direction;
  final List<LugHistoryEntry> history;

  LugInfo copyWith({
    double? lastHz,
    bool clearLastHz = false,
    int? lastTimestampMs,
    double? deltaHz,
    bool clearDelta = false,
    double? centsOffset,
    bool clearCents = false,
    LugAdjustmentTier? tier,
    bool clearTier = false,
    LugAdjustmentDirection? direction,
    bool clearDirection = false,
    List<LugHistoryEntry>? history,
  }) {
    return LugInfo(
      index: index,
      lastHz: clearLastHz ? null : (lastHz ?? this.lastHz),
      lastTimestampMs: lastTimestampMs ?? this.lastTimestampMs,
      deltaHz: clearDelta ? null : (deltaHz ?? this.deltaHz),
      centsOffset: clearCents ? null : (centsOffset ?? this.centsOffset),
      tier: clearTier ? null : (tier ?? this.tier),
      direction: clearDirection ? null : (direction ?? this.direction),
      history: history ?? this.history,
    );
  }
}

class LugHistoryEntry {
  const LugHistoryEntry({required this.direction});

  final LugAdjustmentDirection direction;
}

enum LugAdjustmentDirection { tighten, loosen, inTune }

enum LugAdjustmentTier { inTune, slight, medium, strong }

class LugStateNotifier extends AutoDisposeNotifier<LugState> {
  static const double _confidenceThreshold = 0.65;
  static const int _miniHistoryLength = 6;

  int? _lastTimestampMs;

  @override
  LugState build() {
    final ProviderSubscription<AnalysisSnapshot> sub = ref.listen(
      analysisSnapshotProvider,
      (AnalysisSnapshot? previous, AnalysisSnapshot next) {
        _onSnapshot(next);
      },
    );

    ref.onDispose(sub.close);

    return LugState.initial();
  }

  void setActive(int index) {
    state = state.copyWith(activeIndex: index);
  }

  void clearActive() {
    state = state.copyWith(clearActive: true);
  }

  void setReference(int index) {
    state = state.copyWith(referenceIndex: index);
    _recalculateDeltas();
  }

  void _onSnapshot(AnalysisSnapshot snapshot) {
    final AnalysisResult? latest = snapshot.latest;
    if (latest == null) {
      return;
    }
    if (latest.timestampMs == _lastTimestampMs) {
      return;
    }
    if (latest.confidence < _confidenceThreshold) {
      return;
    }

    final int? targetIndex = state.activeIndex;
    if (targetIndex == null) {
      return;
    }

    final double? lugFrequency = latest.f1Hz;
    if (lugFrequency == null) {
      return;
    }

    _lastTimestampMs = latest.timestampMs;
    _recordMeasurement(targetIndex, lugFrequency, latest.timestampMs);
  }

  void _recordMeasurement(int index, double frequency, int timestampMs) {
    final List<LugInfo> nextLugs = List<LugInfo>.of(state.lugs);
    final LugInfo existing = nextLugs[index];

    final int? referenceIndex = state.referenceIndex;
    final double? referenceHz = referenceIndex == null
        ? null
        : (referenceIndex == index ? frequency : nextLugs[referenceIndex].lastHz);

    final double? delta = referenceHz != null ? frequency - referenceHz : null;
    final double? cents =
        referenceHz != null ? _centsOffset(frequency, referenceHz) : null;

    final LugAdjustmentTier? tier = delta != null
        ? resolveTierWithHysteresis(delta.abs(), existing.tier)
        : null;
    LugAdjustmentDirection? direction = delta != null
        ? _directionFor(delta)
        : (referenceHz == null ? null : LugAdjustmentDirection.inTune);
    if (tier == LugAdjustmentTier.inTune) {
      direction = LugAdjustmentDirection.inTune;
    }

    final List<LugHistoryEntry> history = List<LugHistoryEntry>.of(existing.history);
    if (direction != null && delta != null) {
      history.add(LugHistoryEntry(direction: direction));
      if (history.length > _miniHistoryLength) {
        history.removeAt(0);
      }
    }

    nextLugs[index] = existing.copyWith(
      lastHz: frequency,
      lastTimestampMs: timestampMs,
      deltaHz: delta ?? (referenceHz == null ? null : 0),
      centsOffset: cents ?? (referenceHz == null ? null : 0),
      tier: tier,
      direction: direction,
      history: history,
    );

    state = state.copyWith(lugs: nextLugs);
    _recalculateDeltas();
  }

  void _recalculateDeltas() {
    final int? referenceIndex = state.referenceIndex;
    if (referenceIndex == null) {
      return;
    }

    final List<LugInfo> lugs = List<LugInfo>.of(state.lugs);
    final double? referenceHz = lugs[referenceIndex].lastHz;
    if (referenceHz == null || referenceHz <= 0) {
      return;
    }

    for (int i = 0; i < lugs.length; i++) {
      final LugInfo info = lugs[i];
      final double? hz = info.lastHz;
      if (hz == null || i == referenceIndex) {
        lugs[i] = info.copyWith(
          deltaHz: i == referenceIndex ? 0 : null,
          centsOffset: i == referenceIndex ? 0 : null,
          tier: i == referenceIndex ? LugAdjustmentTier.inTune : info.tier,
          direction:
              i == referenceIndex ? LugAdjustmentDirection.inTune : info.direction,
        );
        continue;
      }

      final double delta = hz - referenceHz;
      final LugAdjustmentTier tier =
          resolveTierWithHysteresis(delta.abs(), info.tier);
      final LugAdjustmentDirection direction = tier == LugAdjustmentTier.inTune
          ? LugAdjustmentDirection.inTune
          : _directionFor(delta);

      lugs[i] = info.copyWith(
        deltaHz: delta,
        centsOffset: _centsOffset(hz, referenceHz),
        tier: tier,
        direction: direction,
      );
    }

    state = state.copyWith(lugs: lugs);
  }

  LugAdjustmentDirection _directionFor(double delta) {
    if (delta > 0) {
      return LugAdjustmentDirection.loosen;
    }
    if (delta < 0) {
      return LugAdjustmentDirection.tighten;
    }
    return LugAdjustmentDirection.inTune;
  }

  double _centsOffset(double hz, double referenceHz) {
    return 1200 * (math.log(hz / referenceHz) / math.ln2);
  }
}

LugAdjustmentTier resolveTierWithHysteresis(
  double absDelta,
  LugAdjustmentTier? previous,
) {
  if (previous == null) {
    return _baseTier(absDelta);
  }

  switch (previous) {
    case LugAdjustmentTier.inTune:
      if (absDelta >= kLugSlightThresholdHz + kLugHysteresisHz) {
        return _baseTier(absDelta);
      }
      return LugAdjustmentTier.inTune;
    case LugAdjustmentTier.slight:
      if (absDelta <= math.max(0, kLugSlightThresholdHz - kLugHysteresisHz)) {
        return LugAdjustmentTier.inTune;
      }
      if (absDelta >= kLugMediumThresholdHz + kLugHysteresisHz) {
        return _baseTier(absDelta);
      }
      return LugAdjustmentTier.slight;
    case LugAdjustmentTier.medium:
      if (absDelta <= math.max(0, kLugMediumThresholdHz - kLugHysteresisHz)) {
        return LugAdjustmentTier.slight;
      }
      if (absDelta >= kLugStrongThresholdHz + kLugHysteresisHz) {
        return LugAdjustmentTier.strong;
      }
      return LugAdjustmentTier.medium;
    case LugAdjustmentTier.strong:
      if (absDelta <= math.max(0, kLugStrongThresholdHz - kLugHysteresisHz)) {
        return LugAdjustmentTier.medium;
      }
      return LugAdjustmentTier.strong;
  }
}

LugAdjustmentTier _baseTier(double absDelta) {
  if (absDelta <= kLugSlightThresholdHz) {
    return LugAdjustmentTier.inTune;
  }
  if (absDelta <= kLugMediumThresholdHz) {
    return LugAdjustmentTier.slight;
  }
  if (absDelta <= kLugStrongThresholdHz) {
    return LugAdjustmentTier.medium;
  }
  return LugAdjustmentTier.strong;
}

final lugStateProvider =
    AutoDisposeNotifierProvider<LugStateNotifier, LugState>(
  LugStateNotifier.new,
);
