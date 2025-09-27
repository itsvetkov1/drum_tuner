import 'package:drum_tuning_plugin/drum_tuning_plugin.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'analysis_service.dart';

final drumTuningPluginProvider = Provider<DrumTuningPlugin>((Ref ref) {
  return const DrumTuningPlugin();
});

final analysisServiceProvider = Provider<AnalysisService>((Ref ref) {
  final DrumTuningPlugin plugin = ref.watch(drumTuningPluginProvider);
  return AnalysisService(plugin);
});

final micCaptureEnabledProvider = StateProvider<bool>((Ref ref) {
  return !kIsWeb;
});

final analysisStreamProvider =
    StreamProvider.autoDispose<AnalysisResult>((Ref ref) {
  final AnalysisService service = ref.watch(analysisServiceProvider);
  final bool enabled = ref.watch(micCaptureEnabledProvider);
  if (!enabled) {
    Future<void>.microtask(service.stop);
    return const Stream<AnalysisResult>.empty();
  }
  Future<void>.microtask(service.start);
  ref.onDispose(service.stop);
  return service.stream;
});
