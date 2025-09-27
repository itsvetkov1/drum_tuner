import 'package:record/record.dart';

import 'mic_service_common.dart';
import 'mic_service_stub.dart'
    if (dart.library.html) 'mic_service_web_impl.dart' as impl;

export 'mic_service_common.dart' show MicServiceException;

class MicService {
  MicService({Duration amplitudeInterval = const Duration(milliseconds: 100)})
      : _delegate = impl.createMicServiceDelegate(amplitudeInterval);

  final MicServiceDelegate _delegate;

  Stream<Amplitude> get amplitude => _delegate.amplitude;

  Future<bool> ensurePermission() => _delegate.ensurePermission();

  Future<void> start() => _delegate.start();

  Future<void> stop() => _delegate.stop();
}
