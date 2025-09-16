import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'method_channel_drum_tuning.dart';
import 'models/analysis_result.dart';

abstract class DrumTuningPlatform extends PlatformInterface {
  DrumTuningPlatform() : super(token: _token);

  static final Object _token = Object();

  static DrumTuningPlatform _instance = MethodChannelDrumTuning();

  static DrumTuningPlatform get instance => _instance;

  static set instance(DrumTuningPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Stream<AnalysisResult> analysisStream();

  Future<void> startListening();

  Future<void> stopListening();
}
