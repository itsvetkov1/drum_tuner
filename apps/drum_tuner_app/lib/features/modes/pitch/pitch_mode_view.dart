import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../analysis/analysis_snapshot_provider.dart';
import 'pitch_state.dart';

class PitchModeView extends ConsumerWidget {
  const PitchModeView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final PitchUiState state = ref.watch(pitchUiStateProvider);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text(
            'Pitch Mode',
            style: Theme.of(context).textTheme.headlineMedium,
          ),
          const SizedBox(height: 24),
          switch (state.stage) {
            PitchStage.listening => const _PlaceholderCard(
                message: 'Listening for strike...'),
            PitchStage.coarse || PitchStage.refined => _PitchReadout(state: state),
          },
        ],
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
            Text('Note: ${state.noteName ?? '--'}', style: theme.textTheme.titleMedium),
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
  final String sign = value > 0 ? '+' : value < 0 ? '-' : '±';
  if (sign == '±') {
    return '±$formatted';
  }
  return '$sign$formatted';
}
