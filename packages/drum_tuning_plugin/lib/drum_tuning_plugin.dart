library drum_tuning_plugin;

export 'src/models/analysis_result.dart';

import 'src/drum_tuning_platform_interface.dart';
import 'src/models/analysis_result.dart';

class DrumTuningPlugin {
  const DrumTuningPlugin();

  Stream<AnalysisResult> get analysisStream {
    return DrumTuningPlatform.instance.analysisStream();
  }

  Future<void> startListening() {
    return DrumTuningPlatform.instance.startListening();
  }

  Future<void> stopListening() {
    return DrumTuningPlatform.instance.stopListening();
  }
}
