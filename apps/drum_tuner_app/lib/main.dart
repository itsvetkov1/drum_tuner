import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:record/record.dart';

import 'app/app.dart';
import 'bootstrap.dart';
import 'mic_service.dart';

Future<void> main() async {
  await bootstrap();
  runApp(ProviderScope(child: DrumTunerApp(onGenerateRoute: _onGenerateRoute)));
}

enum _MicUiStatus {
  idle,
  requesting,
  granted,
  recording,
  denied,
  unsupported,
  busy,
  error,
}

Route<dynamic>? _onGenerateRoute(RouteSettings settings) {
  if (settings.name == '/mic-test') {
    return MaterialPageRoute<void>(
      builder: (BuildContext context) => const MicTesterPage(),
      settings: settings,
    );
  }
  return null;
}

class MicTesterPage extends StatelessWidget {
  const MicTesterPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Microphone test')),
      body: const SafeArea(
        minimum: EdgeInsets.all(24),
        child: MicTester(),
      ),
    );
  }
}

class MicTester extends StatefulWidget {
  const MicTester({super.key});

  @override
  State<MicTester> createState() => _MicTesterState();
}

class _MicTesterState extends State<MicTester> {
  final MicService _micService = MicService();
  StreamSubscription<Amplitude>? _amplitudeSubscription;
  _MicUiStatus _status = _MicUiStatus.idle;
  String? _statusDetail;
  double _normalizedLevel = 0;
  double _currentDb = -160;

  bool get _isRecording => _status == _MicUiStatus.recording;
  bool get _isBusy => _status == _MicUiStatus.busy;
  bool get _isRequesting => _status == _MicUiStatus.requesting;

  @override
  void dispose() {
    _amplitudeSubscription?.cancel();
    _micService.stop();
    super.dispose();
  }

  Future<void> _handleEnable() async {
    if (_isRequesting) {
      return;
    }

    setState(() {
      _status = _MicUiStatus.requesting;
      _statusDetail = 'Requesting microphone permission...';
    });

    try {
      final bool granted = await _micService.ensurePermission();
      if (!granted) {
        setState(() {
          _status = _MicUiStatus.denied;
          _statusDetail =
              'Microphone permission was denied. Allow access in your browser settings and try again.';
        });
        return;
      }

      setState(() {
        _status = _MicUiStatus.granted;
        _statusDetail = 'Microphone permission granted. Starting capture...';
      });

      await _micService.start();
      _listenToAmplitude();
      setState(() {
        _status = _MicUiStatus.recording;
        _statusDetail = 'Listening for microphone input.';
      });
    } on MicServiceException catch (error) {
      _applyServiceError(error);
    } catch (error) {
      setState(() {
        _status = _MicUiStatus.error;
        _statusDetail = 'Unexpected microphone error: ' + error.toString();
      });
    }
  }

  Future<void> _handleStop() async {
    await _micService.stop();
    await _amplitudeSubscription?.cancel();
    _amplitudeSubscription = null;
    setState(() {
      if (_status != _MicUiStatus.denied &&
          _status != _MicUiStatus.unsupported) {
        _status = _MicUiStatus.granted;
        _statusDetail = 'Microphone stopped.';
      }
      _normalizedLevel = 0;
      _currentDb = -160;
    });
  }

  void _listenToAmplitude() {
    _amplitudeSubscription?.cancel();
    _amplitudeSubscription = _micService.amplitude.listen(
      (Amplitude amplitude) {
        setState(() {
          _currentDb = amplitude.current;
          _normalizedLevel = _normalizeDb(amplitude.current);
        });
      },
      onError: (Object error) {
        setState(() {
          _status = _MicUiStatus.error;
          _statusDetail =
              'Failed to read microphone level: ' + error.toString();
        });
      },
    );
  }

  void _applyServiceError(MicServiceException error) {
    final String lowered = error.message.toLowerCase();
    _MicUiStatus status;
    if (lowered.contains('secure context') ||
        lowered.contains('not supported')) {
      status = _MicUiStatus.unsupported;
    } else if (lowered.contains('denied')) {
      status = _MicUiStatus.denied;
    } else if (lowered.contains('busy') || lowered.contains('in use')) {
      status = _MicUiStatus.busy;
    } else {
      status = _MicUiStatus.error;
    }

    setState(() {
      _status = status;
      _statusDetail = error.message;
    });
  }

  double _normalizeDb(double db) {
    const double minDb = -60;
    const double maxDb = 0;
    final double clamped = db.clamp(minDb, maxDb);
    final double normalized = (clamped - minDb) / (maxDb - minDb);
    if (normalized.isNaN || normalized.isInfinite) {
      return 0;
    }
    return normalized.clamp(0.0, 1.0);
  }

  String _statusLabel() {
    switch (_status) {
      case _MicUiStatus.idle:
        return 'Idle';
      case _MicUiStatus.requesting:
        return 'Requesting permission';
      case _MicUiStatus.granted:
        return 'Permission granted';
      case _MicUiStatus.recording:
        return 'Listening';
      case _MicUiStatus.denied:
        return 'Permission denied';
      case _MicUiStatus.unsupported:
        return 'Not supported';
      case _MicUiStatus.busy:
        return 'Microphone busy';
      case _MicUiStatus.error:
        return 'Error';
    }
  }

  @override
  Widget build(BuildContext context) {
    final bool isRecording = _isRecording;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: <Widget>[
        Text(
          'Status: ' + _statusLabel(),
          style: Theme.of(context).textTheme.titleMedium,
        ),
        if (_statusDetail != null) ...<Widget>[
          const SizedBox(height: 8),
          Text(
            _statusDetail!,
            style: Theme.of(context).textTheme.bodyMedium,
          ),
        ],
        const SizedBox(height: 24),
        Row(
          children: <Widget>[
            ElevatedButton.icon(
              onPressed: (isRecording || _isBusy) ? null : _handleEnable,
              icon: const Icon(Icons.mic),
              label: const Text('Enable microphone'),
            ),
            if (isRecording) ...<Widget>[
              const SizedBox(width: 12),
              OutlinedButton(
                onPressed: _handleStop,
                child: const Text('Stop'),
              ),
            ],
          ],
        ),
        const SizedBox(height: 32),
        Text(
          'Level: ' +
              (_currentDb.isFinite ? _currentDb.toStringAsFixed(1) : 'вЂ”') +
              ' dBFS',
          style: Theme.of(context).textTheme.titleMedium,
        ),
        const SizedBox(height: 12),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: _normalizedLevel,
            minHeight: 12,
          ),
        ),
        const SizedBox(height: 8),
        Text('Approx. amplitude: ' +
            (100 * _normalizedLevel).round().toString() +
            ' / 100'),
        const SizedBox(height: 24),
        Text(
          'Tip: Browsers require HTTPS (or localhost) for microphone access.',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    );
  }
}
