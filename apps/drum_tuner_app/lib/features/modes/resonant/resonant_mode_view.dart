import 'package:drum_tuning_plugin/drum_tuning_plugin.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../analysis/analysis_snapshot_provider.dart';

class ResonantModeView extends ConsumerWidget {
  const ResonantModeView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final snapshot = ref.watch(analysisSnapshotProvider);
    final AnalysisResult? latest = snapshot.latest;
    final theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text('Resonant Mode', style: theme.textTheme.headlineMedium),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    'rtf = ${latest?.rtf?.toStringAsFixed(3) ?? '--'}',
                    style: theme.textTheme.displaySmall,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    _resonantHint(latest?.rtf),
                    style: theme.textTheme.titleMedium,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _resonantHint(double? ratio) {
    if (ratio == null) {
      return 'Awaiting first measurement.';
    }
    if (ratio < 1.40) {
      return 'Raise resonant head';
    }
    if (ratio > 1.65) {
      return 'Lower resonant head';
    }
    if (ratio >= 1.54 && ratio <= 1.58) {
      return 'Sweet spot';
    }
    if (ratio >= 1.50 && ratio <= 1.62) {
      return 'Resonant ratio in range';
    }
    return 'Close — fine adjust';
  }
}
