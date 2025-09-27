import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../mic_service.dart';
import '../../analysis/providers.dart';

enum PitchMicStatus { idle, requesting, enabled, denied, unsupported, error }

class PitchMicState {
  const PitchMicState({
    required this.status,
    this.message,
  });

  final PitchMicStatus status;
  final String? message;

  PitchMicState copyWith({PitchMicStatus? status, String? message}) {
    return PitchMicState(
      status: status ?? this.status,
      message: message ?? this.message,
    );
  }
}

final pitchMicControllerProvider =
    StateNotifierProvider<PitchMicController, PitchMicState>((Ref ref) {
  return PitchMicController(ref);
});

class PitchMicController extends StateNotifier<PitchMicState> {
  PitchMicController(this._ref)
      : _micService = MicService(),
        super(
          const PitchMicState(
            status: kIsWeb ? PitchMicStatus.idle : PitchMicStatus.enabled,
          ),
        ) {
    if (!kIsWeb) {
      _ref.read(micCaptureEnabledProvider.notifier).state = true;
    }
  }

  final Ref _ref;
  final MicService _micService;

  Future<void> enableMicrophone() async {
    if (!kIsWeb) {
      _ref.read(micCaptureEnabledProvider.notifier).state = true;
      state = state.copyWith(status: PitchMicStatus.enabled);
      return;
    }

    state = state.copyWith(
      status: PitchMicStatus.requesting,
      message: 'Requesting microphone access...',
    );

    try {
      final bool granted = await _micService.ensurePermission();
      if (!granted) {
        state = state.copyWith(
          status: PitchMicStatus.denied,
          message: 'Microphone permission was denied by the browser.',
        );
        return;
      }

      state = state.copyWith(
        status: PitchMicStatus.enabled,
        message: 'Microphone enabled. Tap the drum to capture pitch.',
      );
      final notifier = _ref.read(micCaptureEnabledProvider.notifier);
      notifier.state = true;
      try {
        await _ref.read(analysisServiceProvider).start();
      } catch (error) {
        notifier.state = false;
        state = state.copyWith(
          status: PitchMicStatus.error,
          message: 'Failed to start analysis: ',
        );
      }
    } on MicServiceException catch (error) {
      state = state.copyWith(
        status: _mapException(error),
        message: error.message,
      );
    } catch (error) {
      state = state.copyWith(
        status: PitchMicStatus.error,
        message: 'Unexpected microphone error: $error',
      );
    }
  }

  void disableMicrophone() {
    if (kIsWeb) {
      _ref.read(micCaptureEnabledProvider.notifier).state = false;
      state = const PitchMicState(status: PitchMicStatus.idle);
      _ref.read(analysisServiceProvider).stop();
    }
  }

  PitchMicStatus _mapException(MicServiceException error) {
    final String message = error.message.toLowerCase();
    if (message.contains('secure context') || message.contains('https')) {
      return PitchMicStatus.unsupported;
    }
    if (message.contains('denied')) {
      return PitchMicStatus.denied;
    }
    return PitchMicStatus.error;
  }

  @override
  void dispose() {
    _micService.stop();
    super.dispose();
  }
}
