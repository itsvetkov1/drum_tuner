import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../modes/lug/lug_mode_view.dart';
import '../modes/pitch/pitch_mode_view.dart';
import '../modes/resonant/resonant_mode_view.dart';
import '../modes/spectrum/spectrum_mode_view.dart';
import '../shared/tuner_mode.dart';

final selectedModeProvider =
    StateProvider<TunerMode>((Ref ref) => TunerMode.pitch);

class ShellPage extends ConsumerWidget {
  const ShellPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final TunerMode mode = ref.watch(selectedModeProvider);
    return Scaffold(
      body: SafeArea(child: _ShellBody(mode: mode)),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => Navigator.of(context).pushNamed('/mic-test'),
        icon: const Icon(Icons.mic),
        label: const Text('Mic test'),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.endFloat,
      bottomNavigationBar: NavigationBar(
        selectedIndex: TunerMode.values.indexOf(mode),
        onDestinationSelected: (int index) {
          ref.read(selectedModeProvider.notifier).state =
              TunerMode.values[index];
        },
        destinations: TunerMode.values
            .map((TunerMode m) => NavigationDestination(
                  icon: Icon(m.icon),
                  label: m.label,
                ))
            .toList(growable: false),
      ),
    );
  }
}

class _ShellBody extends StatelessWidget {
  const _ShellBody({required this.mode});

  final TunerMode mode;

  @override
  Widget build(BuildContext context) {
    final Widget body = switch (mode) {
      TunerMode.pitch => const PitchModeView(),
      TunerMode.lug => const LugModeView(),
      TunerMode.resonant => const ResonantModeView(),
      TunerMode.spectrum => const SpectrumModeView(),
    };

    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 250),
      child: KeyedSubtree(
        key: ValueKey<TunerMode>(mode),
        child: body,
      ),
    );
  }
}
