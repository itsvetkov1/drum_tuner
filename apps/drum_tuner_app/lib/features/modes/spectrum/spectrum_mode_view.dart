import 'package:drum_tuning_plugin/drum_tuning_plugin.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../analysis/analysis_snapshot_provider.dart';

class SpectrumModeView extends ConsumerWidget {
  const SpectrumModeView({super.key});

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
          Text('Spectrum Mode', style: theme.textTheme.headlineMedium),
          const SizedBox(height: 24),
          Expanded(
            child: Card(
              clipBehavior: Clip.hardEdge,
              child: Stack(
                children: <Widget>[
                  Positioned.fill(
                    child: ColoredBox(
                      color: theme.colorScheme.surfaceVariant.withOpacity(0.2),
                      child: const Center(
                        child: Text('Spectrum chart placeholder'),
                      ),
                    ),
                  ),
                  Positioned(
                    top: 16,
                    right: 16,
                    child: Container(
                      width: 160,
                      height: 100,
                      decoration: BoxDecoration(
                        color: theme.colorScheme.surface.withOpacity(0.85),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      alignment: Alignment.center,
                      child: const Text('Waveform inset'),
                    ),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Text('Peaks detected: ${latest?.peaks.length ?? 0}'),
          Text('Long-press to freeze, double-tap resets zoom (to be implemented).'),
        ],
      ),
    );
  }
}
