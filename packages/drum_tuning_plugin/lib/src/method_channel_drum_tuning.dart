import 'dart:async';

import 'package:flutter/services.dart';

import 'drum_tuning_platform_interface.dart';
import 'models/analysis_result.dart';

class MethodChannelDrumTuning extends DrumTuningPlatform {
  MethodChannelDrumTuning() {
    _analysisController = StreamController<AnalysisResult>.broadcast(
      onListen: _ensureEventSubscription,
      onCancel: _maybeTearDownSubscription,
    );
  }

  static const MethodChannel _methodChannel = MethodChannel('drum_tuning_plugin/methods');
  static const EventChannel _eventChannel = EventChannel('drum_tuning_plugin/analysis');

  late StreamController<AnalysisResult> _analysisController;
  StreamSubscription<dynamic>? _eventSubscription;

  @override
  Stream<AnalysisResult> analysisStream() => _analysisController.stream;

  @override
  Future<void> startListening() => _methodChannel.invokeMethod<void>('start');

  @override
  Future<void> stopListening() => _methodChannel.invokeMethod<void>('stop');

  void _ensureEventSubscription() {
    _eventSubscription ??= _eventChannel
        .receiveBroadcastStream()
        .listen(_handleEvent, onError: _analysisController.addError);
  }

  void _maybeTearDownSubscription() {
    if (!_analysisController.hasListener) {
      _eventSubscription?.cancel();
      _eventSubscription = null;
    }
  }

  void _handleEvent(dynamic event) {
    if (event is Map<dynamic, dynamic>) {
      _analysisController.add(AnalysisResult.fromMap(event));
    }
  }
}
