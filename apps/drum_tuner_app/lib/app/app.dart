import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../features/shell/shell_page.dart';
import 'theme.dart';

class DrumTunerApp extends ConsumerWidget {
  const DrumTunerApp({super.key, this.onGenerateRoute});

  final RouteFactory? onGenerateRoute;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return MaterialApp(
      title: 'Drum Tuner',
      debugShowCheckedModeBanner: false,
      theme: buildAppTheme(Brightness.light),
      darkTheme: buildAppTheme(Brightness.dark),
      themeMode: ThemeMode.dark,
      onGenerateRoute: onGenerateRoute,
      home: const ShellPage(),
    );
  }
}
