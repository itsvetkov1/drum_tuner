import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'lug_state.dart';

class LugModeView extends ConsumerWidget {
  const LugModeView({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final LugState state = ref.watch(lugStateProvider);
    final LugStateNotifier controller = ref.read(lugStateProvider.notifier);
    final ThemeData theme = Theme.of(context);

    return Padding(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Text('Lug Mode', style: theme.textTheme.headlineMedium),
          const SizedBox(height: 24),
          Card(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  Text(
                    state.referenceIndex != null
                        ? 'Reference lug: ${state.referenceIndex! + 1}'
                        : 'Reference lug not set',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Select the lug before you strike. Hits with confidence above threshold record into the mini history.',
                    style: theme.textTheme.bodyMedium,
                  ),
                  const SizedBox(height: 16),
                  Wrap(
                    spacing: 12,
                    runSpacing: 12,
                    children: state.lugs.map((LugInfo lug) {
                      final bool selected = state.activeIndex == lug.index;
                      return ChoiceChip(
                        label: Text('Lug ${lug.index + 1}'),
                        selected: selected,
                        onSelected: (bool value) {
                          if (value) {
                            controller.setActive(lug.index);
                          } else {
                            controller.clearActive();
                          }
                        },
                      );
                    }).toList(growable: false),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Expanded(
            child: ListView.separated(
              itemCount: state.lugs.length,
              separatorBuilder: (_, __) => const SizedBox(height: 12),
              itemBuilder: (BuildContext context, int index) {
                final LugInfo info = state.lugs[index];
                final bool isReference = state.referenceIndex == index;
                final bool isActive = state.activeIndex == index;
                return _LugCard(
                  info: info,
                  isReference: isReference,
                  isActive: isActive,
                  onSetReference: () => controller.setReference(index),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _LugCard extends StatelessWidget {
  const _LugCard({
    required this.info,
    required this.isReference,
    required this.isActive,
    required this.onSetReference,
  });

  final LugInfo info;
  final bool isReference;
  final bool isActive;
  final VoidCallback onSetReference;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    final String hzText = info.lastHz != null
        ? '${info.lastHz!.toStringAsFixed(2)} Hz'
        : '-- Hz';
    final String deltaText = info.deltaHz != null
        ? _formatSigned(info.deltaHz!, 2)
        : '--';
    final String centsText = info.centsOffset != null
        ? '${_formatSigned(info.centsOffset!, 1)} cents'
        : '--';
    final String guidance = _guidanceMessage(info);

    return Card(
      child: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: <Widget>[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: <Widget>[
                Row(
                  children: <Widget>[
                    Text('Lug ${info.index + 1}',
                        style: theme.textTheme.titleLarge),
                    const SizedBox(width: 12),
                    if (isReference)
                      Chip(
                        label: const Text('Reference'),
                        backgroundColor:
                            theme.colorScheme.secondaryContainer,
                      ),
                    if (isActive && !isReference)
                      Padding(
                        padding: const EdgeInsets.only(left: 8),
                        child: Chip(
                          label: const Text('Selected'),
                          backgroundColor:
                              theme.colorScheme.primaryContainer,
                        ),
                      ),
                  ],
                ),
                TextButton.icon(
                  onPressed: info.lastHz != null && !isReference
                      ? onSetReference
                      : null,
                  icon: const Icon(Icons.flag),
                  label: Text(isReference ? 'Reference' : 'Set reference'),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text('Last reading: $hzText', style: theme.textTheme.bodyLarge),
            const SizedBox(height: 4),
            Text('Δ $deltaText · $centsText',
                style: theme.textTheme.bodyMedium),
            const SizedBox(height: 8),
            Text(guidance, style: theme.textTheme.titleMedium),
            const SizedBox(height: 12),
            _MiniHistory(history: info.history),
          ],
        ),
      ),
    );
  }
}

class _MiniHistory extends StatelessWidget {
  const _MiniHistory({required this.history});

  final List<LugHistoryEntry> history;

  @override
  Widget build(BuildContext context) {
    final ThemeData theme = Theme.of(context);
    const int window = 6;
    final List<LugHistoryEntry> windowed = history.length > window
        ? history.sublist(history.length - window)
        : history;

    return Row(
      children: List<Widget>.generate(window, (int index) {
        final int sourceIndex = index - (window - windowed.length);
        final LugHistoryEntry? entry =
            sourceIndex >= 0 && sourceIndex < windowed.length
                ? windowed[sourceIndex]
                : null;
        final double opacity = entry == null
            ? 0.15
            : 0.35 + (sourceIndex + 1) / windowed.length * 0.55;
        final Color color = entry == null
            ? theme.colorScheme.onSurface.withOpacity(opacity)
            : _colorForDirection(entry.direction, opacity);

        return Padding(
          padding: const EdgeInsets.only(right: 6),
          child: Container(
            width: 10,
            height: 28,
            decoration: BoxDecoration(
              color: color,
              borderRadius: BorderRadius.circular(4),
            ),
          ),
        );
      }),
    );
  }
}

String _guidanceMessage(LugInfo info) {
  final LugAdjustmentDirection? direction = info.direction;
  final LugAdjustmentTier? tier = info.tier;

  if (direction == null || tier == null || info.deltaHz == null) {
    if (info.lastHz == null) {
      return 'Capture this lug to compare against reference.';
    }
    return 'Set a reference lug to evaluate this reading.';
  }

  if (direction == LugAdjustmentDirection.inTune ||
      tier == LugAdjustmentTier.inTune) {
    return 'Lug ${info.index + 1} in tune';
  }

  final String action =
      direction == LugAdjustmentDirection.loosen ? 'Loosen' : 'Tighten';
  final String tierLabel = switch (tier) {
    LugAdjustmentTier.slight => 'slightly',
    LugAdjustmentTier.medium => 'medium',
    LugAdjustmentTier.strong => 'strong',
    LugAdjustmentTier.inTune => 'in tune',
  };

  return '$action lug ${info.index + 1} $tierLabel';
}

Color _colorForDirection(LugAdjustmentDirection direction, double opacity) {
  switch (direction) {
    case LugAdjustmentDirection.loosen:
      return Colors.green.withOpacity(opacity);
    case LugAdjustmentDirection.tighten:
      return Colors.blue.withOpacity(opacity);
    case LugAdjustmentDirection.inTune:
      return Colors.grey.withOpacity(opacity);
  }
}

String _formatSigned(double value, int fractionDigits) {
  final String formatted = value.abs().toStringAsFixed(fractionDigits);
  if (value > 0) {
    return '+$formatted';
  }
  if (value < 0) {
    return '-$formatted';
  }
  return '±$formatted';
}
