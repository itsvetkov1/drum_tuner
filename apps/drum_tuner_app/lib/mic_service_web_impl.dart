import 'dart:async';
import 'package:flutter/foundation.dart';
// ignore: avoid_web_libraries_in_flutter
import 'dart:html' as html;
// ignore: avoid_web_libraries_in_flutter
import 'dart:js_util' as js_util;
import 'dart:math' as math;

import 'package:record/record.dart';

import 'mic_service_common.dart';

MicServiceDelegate createMicServiceDelegate(Duration amplitudeInterval) {
  return _WebMicServiceDelegate(amplitudeInterval);
}

class _WebMicServiceDelegate implements MicServiceDelegate {
  _WebMicServiceDelegate(this._amplitudeInterval);

  final Duration _amplitudeInterval;
  late final StreamController<Amplitude> _amplitudeController =
      StreamController<Amplitude>.broadcast(
    onListen: _ensureAmplitudeSubscription,
    onCancel: _handleAmplitudeCancel,
  );

  bool _initialized = false;
  bool _permissionGranted = false;
  Object? _amplitudeUnsubscribe;
  double _maxDbObserved = -160;
  DateTime? _lastEmission;

  @override
  Stream<Amplitude> get amplitude => _amplitudeController.stream;

  @override
  Future<bool> ensurePermission() async {
    await _ensureInitialized();
    try {
      _log('ensurePermission:start');
      await js_util.promiseToFuture<void>(
        js_util.callMethod(_plugin, 'ensurePermission', <Object?>[]),
      );
      _permissionGranted = true;
      _log('ensurePermission:granted');
      return true;
    } on Object catch (error) {
      throw _mapException(error, context: 'permission');
    }
  }

  @override
  Future<void> start() async {
    await _ensureInitialized();
    _log('start:requested');
    if (!_permissionGranted) {
      final bool granted = await ensurePermission();
      if (!granted) {
        throw MicServiceException('Microphone permission denied.');
      }
    }

    await js_util.promiseToFuture<void>(
      js_util.callMethod(_plugin, 'start', <Object?>[]),
    );

    _ensureAmplitudeSubscription();
    _log('start:streaming');
  }

  @override
  Future<void> stop() async {
    _log('stop:requested');
    _teardownAmplitudeSubscription();
    await js_util.promiseToFuture<void>(
      js_util.callMethod(_plugin, 'stop', <Object?>[]),
    );
    _permissionGranted = false;
    _maxDbObserved = -160;
    _lastEmission = null;
    _log('stop:completed');
  }

  Future<void> _ensureInitialized() async {
    if (_initialized) {
      return;
    }

    if (!js_util.hasProperty(html.window, 'drumTuningPlugin')) {
      final html.Element? head = html.document.head;
      if (head == null) {
        throw MicServiceException('Document head is not available.');
      }

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
        throw MicServiceException(
          'Web audio bridge is unavailable.',
          cause: lastError,
        );
      }
    }

    _initialized = true;
    _log('bridge ready');
  }

  void _ensureAmplitudeSubscription() {
    if (_amplitudeUnsubscribe != null) {
      return;
    }

    _amplitudeUnsubscribe = js_util.callMethod(
      _plugin,
      'subscribeAmplitude',
      <Object?>[
        js_util.allowInterop((Object? event) {
          _handleAmplitudeEvent(event);
        }),
      ],
    );
    _log('amplitude subscription active');
  }

  void _handleAmplitudeCancel() {
    if (!_amplitudeController.hasListener) {
      _teardownAmplitudeSubscription();
    }
  }

  void _handleAmplitudeEvent(Object? event) {
    if (!_amplitudeController.hasListener) {
      return;
    }

    final Object? dartified = js_util.dartify(event);
    if (dartified is! Map) {
      return;
    }

    final double rms = (dartified['rms'] as num?)?.toDouble() ?? 0;
    final double db = (dartified['db'] as num?)?.toDouble() ?? _toDb(rms);

    final DateTime now = DateTime.now();
    if (_lastEmission != null) {
      final Duration sinceLast = now.difference(_lastEmission!);
      if (sinceLast < _amplitudeInterval) {
        return;
      }
    }
    _lastEmission = now;

    if (db.isFinite) {
      _maxDbObserved = math.max(_maxDbObserved, db);
    }

    _amplitudeController.add(
      Amplitude(current: db, max: _maxDbObserved),
    );
    _log('amplitude',
        'current=${db.toStringAsFixed(2)} max=${_maxDbObserved.toStringAsFixed(2)}');
  }

  void _teardownAmplitudeSubscription() {
    if (_amplitudeUnsubscribe != null) {
      js_util
          .callMethod<Object?>(_amplitudeUnsubscribe!, 'call', <Object?>[null]);
      _amplitudeUnsubscribe = null;
    }
  }

  Object get _plugin =>
      js_util.getProperty<Object>(html.window, 'drumTuningPlugin');

  MicServiceException _mapException(Object error,
      {String? action, String? context}) {
    final String description;
    if (error is MicServiceException) {
      return error;
    }
    if (error is html.DomException) {
      description = error.message ?? error.name;
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
        cause: error,
      );
    }

    final String prefix;
    if (context != null) {
      prefix = 'Microphone $context error.';
    } else if (action != null) {
      prefix = 'Failed to $action microphone capture.';
    } else {
      prefix = 'Microphone error.';
    }
    return MicServiceException('$prefix ($description)', cause: error);
  }

  double _toDb(double rms) {
    return 20 * math.log(math.max(rms, 1e-6)) / math.ln10;
  }

  void _log(String message, [Object? details]) {
    if (!kDebugMode) {
      return;
    }
    if (details == null) {
      debugPrint('[MicServiceWeb] $message');
    } else {
      debugPrint('[MicServiceWeb] $message :: $details');
    }
  }

  static const String _bridgeAssetPath =
      'assets/packages/drum_tuning_plugin/web/drum_tuning_plugin.js';

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

  String _resolveRelative(Uri base, String path) {
    try {
      return base.resolve(path).toString();
    } catch (_) {
      return path;
    }
  }

  Future<bool> _tryLoadBridgeScript(html.Element head, String url) async {
    final Completer<void> completer = Completer<void>();
    final html.ScriptElement script = html.ScriptElement()
      ..src = url
      ..type = 'text/javascript'
      ..async = false
      ..defer = false
      ..dataset['drumTuningPlugin'] = 'true';

    _log('loading bridge script', url);

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
      _log('bridge script loaded', url);
      return true;
    } catch (error) {
      _log('bridge script failed', {'url': url, 'error': '$error'});
      script.remove();
      return false;
    } finally {
      await loadSub.cancel();
      await errorSub.cancel();
    }
  }
}
