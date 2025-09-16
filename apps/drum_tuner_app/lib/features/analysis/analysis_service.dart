import 'package:drum_tuning_plugin/drum_tuning_plugin.dart';

class AnalysisService {
  AnalysisService(this._plugin);

  final DrumTuningPlugin _plugin;

  Stream<AnalysisResult> get stream => _plugin.analysisStream;

  Future<void> start() => _plugin.startListening();

  Future<void> stop() => _plugin.stopListening();
}
