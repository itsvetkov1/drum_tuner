import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';
import 'package:record/record.dart';

import '../drum_tuning_platform_interface.dart';
import '../models/analysis_result.dart';
import 'pitch_analyzer.dart';

class DrumTuningWeb extends DrumTuningPlatform {
  DrumTuningWeb({AudioRecorder? recorder, WebPitchAnalyzer? analyzer})
      : _recorder = recorder ?? AudioRecorder(),
        _analyzer = analyzer ?? WebPitchAnalyzer();

  static void registerWith(Registrar registrar) {
    DrumTuningPlatform.instance = DrumTuningWeb();
  }

  final StreamController<AnalysisResult> _controller =
      StreamController<AnalysisResult>.broadcast();
  final AudioRecorder _recorder;
  final WebPitchAnalyzer _analyzer;

  StreamSubscription<Uint8List>? _audioSubscription;
  bool _isListening = false;

  @override
  Stream<AnalysisResult> analysisStream() {
    return _controller.stream;
  }

  @override
  Future<void> startListening() async {
    if (_isListening) {
      return;
    }

    try {
      final bool granted = await _recorder.hasPermission();
      if (!granted) {
        throw PlatformException(
          code: 'MIC_PERMISSION_DENIED',
          message: 'Browser denied microphone access.',
        );
      }

      final Stream<Uint8List> stream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: WebPitchAnalyzer.sampleRate,
          numChannels: 1,
        ),
      );

      _isListening = true;
      _audioSubscription = stream.listen(
        _handleAudioChunk,
        onError: (Object error, StackTrace stackTrace) {
          _controller.addError(error, stackTrace);
        },
        onDone: () {
          _isListening = false;
        },
      );
    } on PlatformException {
      rethrow;
    } catch (error, stackTrace) {
      _controller.addError(error, stackTrace);
      rethrow;
    }
  }

  @override
  Future<void> stopListening() async {
    if (!_isListening) {
      return;
    }
    _isListening = false;
    await _audioSubscription?.cancel();
    _audioSubscription = null;
    try {
      if (await _recorder.isRecording()) {
        await _recorder.stop();
      }
    } on PlatformException {
      // Swallow stop errors to mirror native behaviour.
    }
  }

  void _handleAudioChunk(Uint8List bytes) {
    if (!_isListening || bytes.isEmpty) {
      return;
    }

    final Int16List samples = Int16List.view(
      bytes.buffer,
      bytes.offsetInBytes,
      bytes.lengthInBytes ~/ Int16List.bytesPerElement,
    );

    final int timestampMs = DateTime.now().millisecondsSinceEpoch;
    final AnalysisResult? result = _analyzer.process(samples, timestampMs);
    if (result != null) {
      _controller.add(result);
    }
  }
}
