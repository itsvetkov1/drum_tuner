import 'dart:async';
import 'dart:html' as html;
import 'dart:js_util' as js_util;
import 'dart:math';

import 'package:flutter/services.dart';
import 'package:flutter_web_plugins/flutter_web_plugins.dart';

import '../drum_tuning_platform_interface.dart';
import '../models/analysis_result.dart';

class DrumTuningWeb extends DrumTuningPlatform {
  DrumTuningWeb() : _controller = StreamController<AnalysisResult>.broadcast();

  static void registerWith(Registrar registrar) {
    DrumTuningPlatform.instance = DrumTuningWeb();
  }

  final StreamController<AnalysisResult> _controller;
  bool _isListening = false;
  bool _initialized = false;
  bool _permissionChecked = false;

  Object? _analysisUnsubscribe;

  @override
  Stream<AnalysisResult> analysisStream() => _controller.stream;

  @override
  Future<void> startListening() async {
    if (_isListening) {
      return;
    }

    try {
      await _ensureInitialized();
      final Object plugin = _pluginObject;

      if (!_permissionChecked) {
        await js_util.promiseToFuture<void>(
          js_util.callMethod(plugin, 'ensurePermission', <Object?>[]),
        );
        _permissionChecked = true;
      }

      await js_util.promiseToFuture<void>(
        js_util.callMethod(plugin, 'start', <Object?>[]),
      );

      _analysisUnsubscribe = js_util.callMethod(plugin, 'subscribe', <Object?>[
        js_util.allowInterop((Object? event) {
          _handleAnalysisEvent(event);
        }),
      ]);

      _isListening = true;
    } on Object catch (error, stackTrace) {
      _controller.addError(error, stackTrace);
      rethrow;
    }
  }

  @override
  Future<void> stopListening() async {
    if (!_isListening) {
      return;
    }

    final Object plugin = _pluginObject;

    if (_analysisUnsubscribe != null) {
      js_util.callMethod<Object?>(
        _analysisUnsubscribe!,
        'call',
        <Object?>[null],
      );
      _analysisUnsubscribe = null;
    }

    await js_util
        .promiseToFuture<void>(js_util.callMethod(plugin, 'stop', <Object?>[]));

    _isListening = false;
  }

  Future<void> _ensureInitialized() async {
    if (_initialized) {
      return;
    }

    final html.Element? head = html.document.head;
    if (head == null) {
      throw PlatformException(
        code: 'NO_DOCUMENT_HEAD',
        message: 'Document head is not available for script injection.',
      );
    }

    if (!js_util.hasProperty(html.window, 'drumTuningPlugin')) {
      Object? lastError;
      for (final String candidate in _bridgeScriptCandidates()) {
        final bool loaded = await _tryLoadBridgeScript(head, candidate);
        if (loaded && js_util.hasProperty(html.window, 'drumTuningPlugin')) {
          lastError = null;
          break;
        }
        lastError ??= 'Failed to load $candidate';
      }

      if (!js_util.hasProperty(html.window, 'drumTuningPlugin')) {
        throw PlatformException(
          code: 'PLUGIN_UNAVAILABLE',
          message: 'Web audio bridge failed to initialise.',
          details: lastError,
        );
      }
    }

    _initialized = true;
  }

  Object get _pluginObject =>
      js_util.getProperty<Object>(html.window, 'drumTuningPlugin');

  static const String _bridgeAssetPath =
      'assets/packages/drum_tuning_plugin/web/drum_tuning_plugin.js';

  void _handleAnalysisEvent(Object? event) {
    final Object? payload = event;
    final Object? dartified = js_util.dartify(payload);
    if (dartified is! Map) {
      return;
    }

    final Map<dynamic, dynamic> data = dartified.cast<dynamic, dynamic>();
    final double? f0 = (data['f0Hz'] as num?)?.toDouble();
    final double? f1 = (data['f1Hz'] as num?)?.toDouble();
    final double? rtf = (data['rtf'] as num?)?.toDouble();
    final double confidence = (data['confidence'] as num?)?.toDouble() ?? 0;
    final int timestampMs = (data['timestampMs'] as num?)?.toInt() ??
        DateTime.now().millisecondsSinceEpoch;

    final List<dynamic> peaksRaw =
        (data['peaks'] as List<dynamic>?) ?? const <dynamic>[];
    final List<Peak> peaks = peaksRaw
        .whereType<Map<dynamic, dynamic>>()
        .map((Map<dynamic, dynamic> peakData) {
      final double hz = (peakData['Hz'] as num?)?.toDouble() ?? 0;
      final double mag = (peakData['mag'] as num?)?.toDouble() ?? 0;
      return Peak(hz: hz, magnitude: mag);
    }).toList(growable: false);

    final AnalysisResult result = AnalysisResult(
      f0Hz: f0,
      f1Hz: f1,
      rtf: rtf,
      noteName: _noteNameForFrequency(f0),
      cents: _centsOffset(f0),
      confidence: confidence,
      peaks: peaks,
      timestampMs: timestampMs,
    );

    _controller.add(result);
  }

  String? _noteNameForFrequency(double? frequency) {
    if (frequency == null || frequency <= 0 || !frequency.isFinite) {
      return null;
    }
    final double midi = 69 + 12 * _log2(frequency / 440.0);
    final int nearestMidi = midi.round();
    final int octave = (nearestMidi ~/ 12) - 1;
    final int noteIndex = ((nearestMidi % 12) + 12) % 12;
    return _noteNames[noteIndex] + octave.toString();
  }

  double? _centsOffset(double? frequency) {
    if (frequency == null || frequency <= 0 || !frequency.isFinite) {
      return null;
    }
    final double midi = 69 + 12 * _log2(frequency / 440.0);
    final int nearestMidi = midi.round();
    return (midi - nearestMidi) * 100.0;
  }

  double _log2(double value) => log(value) / _ln2;

  static const List<String> _noteNames = <String>[
    'C',
    'C#',
    'D',
    'D#',
    'E',
    'F',
    'F#',
    'G',
    'G#',
    'A',
    'A#',
    'B',
  ];

  static final double _ln2 = log(2);

  List<String> _bridgeScriptCandidates() {
    final Uri base = Uri.base;
    final List<String> raw = <String>[
      _resolveRelative(base, _bridgeAssetPath),
      _resolveRelative(
        base,
        'assets/packages/drum_tuning_plugin/drum_tuning_plugin.js',
      ),
      _resolveRelative(
        base,
        'packages/drum_tuning_plugin/drum_tuning_plugin.js',
      ),
    ];
    final Set<String> seen = <String>{};
    final List<String> result = <String>[];
    for (final String url in raw) {
      if (url.isEmpty) {
        continue;
      }
      if (seen.add(url)) {
        result.add(url);
      }
    }
    return result;
  }

  Future<bool> _tryLoadBridgeScript(html.Element head, String url) async {
    final Completer<void> completer = Completer<void>();
    final html.ScriptElement script = html.ScriptElement()
      ..src = url
      ..type = 'text/javascript'
      ..defer = false
      ..async = false
      ..dataset['drumTuningPlugin'] = 'true';

    final StreamSubscription<html.Event> loadSub = script.onLoad.listen((_) {
      if (!completer.isCompleted) {
        completer.complete();
      }
    });

    final StreamSubscription<html.Event> errorSub =
        script.onError.listen((html.Event error) {
      if (!completer.isCompleted) {
        completer.completeError(error);
      }
    });

    head.append(script);

    try {
      await completer.future;
      return true;
    } catch (_) {
      script.remove();
      return false;
    } finally {
      await loadSub.cancel();
      await errorSub.cancel();
    }
  }

  String _resolveRelative(Uri base, String path) {
    try {
      return base.resolve(path).toString();
    } catch (_) {
      return path;
    }
  }
}
