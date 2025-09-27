import 'package:record/record.dart';

class MicServiceException implements Exception {
  MicServiceException(this.message, {this.cause});

  final String message;
  final Object? cause;

  @override
  String toString() => 'MicServiceException: $message';
}

abstract class MicServiceDelegate {
  Stream<Amplitude> get amplitude;

  Future<bool> ensurePermission();

  Future<void> start();

  Future<void> stop();
}
