import 'package:drum_tuning_plugin/drum_tuning_plugin.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'analysis_service.dart';

final drumTuningPluginProvider = Provider<DrumTuningPlugin>((Ref ref) {
  return const DrumTuningPlugin();
});

final analysisServiceProvider = Provider<AnalysisService>((Ref ref) {
  final DrumTuningPlugin plugin = ref.watch(drumTuningPluginProvider);
  return AnalysisService(plugin);
});

final analysisStreamProvider = StreamProvider.autoDispose<AnalysisResult>((Ref ref) {
  final AnalysisService service = ref.watch(analysisServiceProvider);
  Future<void>.microtask(service.start);
  ref.onDispose(service.stop);
  return service.stream;
});
