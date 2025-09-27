import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../analysis/analysis_snapshot_provider.dart';
import '../../analysis/providers.dart';
import 'pitch_mic_controller.dart';
import 'pitch_state.dart';

class PitchModeView extends ConsumerWidget {
  const PitchModeView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final PitchUiState state = ref.watch(pitchUiStateProvider);
    final PitchMicState micState = ref.watch(pitchMicControllerProvider);
    final bool micEnabled = ref.watch(micCaptureEnabledProvider);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'Pitch Mode',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          if (kIsWeb) ...<Widget>[
            const SizedBox(height: 16),
            _MicPermissionSection(state: micState),
            const SizedBox(height: 16),
          ],
          if (!micEnabled && kIsWeb)
            const _PlaceholderCard(
                message: 'Enable the microphone to start analysis.')
          else
            switch (state.stage) {
              PitchStage.listening =>
                const _PlaceholderCard(message: 'Listening for strike...'),
              PitchStage.coarse ||
              PitchStage.refined =>
                _PitchReadout(state: state),
            },
        ],
      ),
    );
  }
}

class _MicPermissionSection extends ConsumerWidget {
  const _MicPermissionSection({required this.state});

  final PitchMicState state;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final theme = Theme.of(context);
    final PitchMicController controller =
        ref.read(pitchMicControllerProvider.notifier);
    final bool enabled = ref.watch(micCaptureEnabledProvider);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(
              'Microphone access',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 8),
            Text(
              state.message ??
                  (enabled
                      ? 'Microphone ready. Strike a drum to capture pitch.'
                      : 'Grant microphone access to analyze your drum.'),
              style: theme.textTheme.bodyMedium,
            ),
            const SizedBox(height: 12),
            if (!enabled)
              ElevatedButton.icon(
                onPressed: state.status == PitchMicStatus.requesting
                    ? null
                    : () => controller.enableMicrophone(),
                icon: const Icon(Icons.mic),
                label: Text(state.status == PitchMicStatus.requesting
                    ? 'Requesting...'
                    : 'Enable microphone'),
              )
            else if (state.status == PitchMicStatus.enabled)
              Text(
                'Listening…',
                style: theme.textTheme.bodySmall,
              ),
          ],
        ),
      ),
    );
  }
}

class _PitchReadout extends StatelessWidget {
  const _PitchReadout({required this.state});

  final PitchUiState state;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text(state.stageLabel, style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            Text(
              state.frequencyHz != null
                  ? '${state.frequencyHz!.toStringAsFixed(2)} Hz'
                  : '-- Hz',
              style: theme.textTheme.displaySmall,
            ),
            const SizedBox(height: 8),
            Text('Note: ${state.noteName ?? '--'}',
                style: theme.textTheme.titleMedium),
            Text(
              'Cents: ${state.cents != null ? _formatSigned(state.cents!, 1) : '--'}',
              style: theme.textTheme.titleMedium,
            ),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: state.confidence.clamp(0, 1)),
            const SizedBox(height: 4),
            Text('Confidence', style: theme.textTheme.labelMedium),
            if (state.stage == PitchStage.refined)
              Padding(
                padding: const EdgeInsets.only(top: 8),
                child: Text(
                  'Median of last ${AnalysisSnapshotNotifier.historyWindow} locks',
                  style: theme.textTheme.bodySmall,
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PlaceholderCard extends StatelessWidget {
  const _PlaceholderCard({required this.message});

  final String message;

  @override
  Widget build(BuildContext context) {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Text(
          message,
          style: Theme.of(context).textTheme.titleLarge,
        ),
      ),
    );
  }
}

String _formatSigned(double value, int fractionDigits) {
  final String formatted = value.abs().toStringAsFixed(fractionDigits);
  final String sign = value > 0
      ? '+'
      : value < 0
          ? '-'
          : '±';
  if (sign == '±') {
    return '±$formatted';
  }
  return '$sign$formatted';
}
