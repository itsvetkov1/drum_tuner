import 'package:drum_tuning_plugin/drum_tuning_plugin.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../analysis/analysis_snapshot_provider.dart';

class PitchModeView extends ConsumerWidget {
  const PitchModeView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(analysisSnapshotProvider);
    final latest = snapshot.latest;

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
          if (latest == null)
            const _PlaceholderCard(message: 'Waiting for strike...')
          else
            _PitchReadout(latest: latest),
        ],
      ),
    );
  }
}

class _PitchReadout extends StatelessWidget {
  const _PitchReadout({required this.latest});

  final AnalysisResult latest;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Text('${latest.f0Hz?.toStringAsFixed(2) ?? '--'} Hz', style: theme.textTheme.displaySmall),
            const SizedBox(height: 8),
            Text('Note: ${latest.noteName ?? '--'}', style: theme.textTheme.titleMedium),
            Text('Cents: ${latest.cents?.toStringAsFixed(1) ?? '--'}', style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            LinearProgressIndicator(value: latest.confidence.clamp(0, 1)),
            const SizedBox(height: 4),
            Text('Confidence', style: theme.textTheme.labelMedium),
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
