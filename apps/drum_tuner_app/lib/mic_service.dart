import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/services.dart';
import 'package:record/record.dart';

class MicServiceException implements Exception {
  MicServiceException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => 'MicServiceException: ' + message;
}

class MicService {
  MicService(
      {AudioRecorder? recorder,
      Duration amplitudeInterval = const Duration(milliseconds: 100)})
      : _recorder = recorder ?? AudioRecorder(),
        _amplitudeInterval = amplitudeInterval;

  final AudioRecorder _recorder;
  final Duration _amplitudeInterval;
  Stream<Amplitude>? _amplitudeStream;
  StreamSubscription<Uint8List>? _recordingSubscription;

  Stream<Amplitude> get amplitude =>
      _amplitudeStream ??= _recorder.onAmplitudeChanged(_amplitudeInterval);

  Future<bool> ensurePermission() async {
    try {
      return await _recorder.hasPermission();
    } on PlatformException catch (error) {
      throw _mapException(error, context: 'permission');
    } catch (error) {
      throw _mapException(error, context: 'permission');
    }
  }

  Future<void> start() async {
    try {
      final bool granted = await ensurePermission();
      if (!granted) {
        throw MicServiceException('Microphone permission denied.');
      }

      if (await _recorder.isRecording()) {
        return;
      }

      final Stream<Uint8List> dataStream = await _recorder.startStream(
        const RecordConfig(
          encoder: AudioEncoder.pcm16bits,
          sampleRate: 44100,
          numChannels: 1,
        ),
      );

      await _recordingSubscription?.cancel();
      _recordingSubscription = dataStream.listen((Uint8List _) {});
    } on MicServiceException {
      rethrow;
    } on PlatformException catch (error) {
      throw _mapException(error, action: 'start');
    } catch (error) {
      throw _mapException(error, action: 'start');
    }
  }

  Future<void> stop() async {
    try {
      await _recordingSubscription?.cancel();
      _recordingSubscription = null;
      if (await _recorder.isRecording()) {
        await _recorder.stop();
      }
    } on PlatformException catch (error) {
      throw _mapException(error, action: 'stop');
    } catch (error) {
      throw _mapException(error, action: 'stop');
    }
  }

  MicServiceException _mapException(Object error,
      {String? action, String? context}) {
    final String description;
    if (error is PlatformException) {
      description = error.message ?? error.code;
    } else {
      description = error.toString();
    }
    final String lower = description.toLowerCase();

    if (lower.contains('secure context') || lower.contains('https')) {
      return MicServiceException(
        'Microphone access requires a secure context (HTTPS or localhost).',
        cause: error,
      );
    }

    if (lower.contains('not supported') || lower.contains('unsupported')) {
      return MicServiceException(
        'Microphone is not supported in this browser.',
        cause: error,
      );
    }

    if (lower.contains('denied') || lower.contains('permission')) {
      return MicServiceException('Microphone permission denied.', cause: error);
    }

    if (lower.contains('busy') || lower.contains('in use')) {
      return MicServiceException(
          'Microphone is currently in use by another application.',
          cause: error);
    }

    final String prefix;
    if (context != null) {
      prefix = 'Microphone ' + context + ' error.';
    } else if (action != null) {
      prefix = 'Failed to ' + action + ' microphone capture.';
    } else {
      prefix = 'Microphone error.';
    }
    return MicServiceException(prefix + ' (' + description + ')', cause: error);
  }
}
