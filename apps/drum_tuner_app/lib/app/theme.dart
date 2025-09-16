import 'package:flutter/material.dart';

ThemeData buildAppTheme(Brightness brightness) {
  final ColorScheme scheme = ColorScheme.fromSeed(
    seedColor: const Color(0xFF4E93FF),
    brightness: brightness,
  );
  return ThemeData(
    colorScheme: scheme,
    useMaterial3: true,
    scaffoldBackgroundColor: brightness == Brightness.dark
        ? const Color(0xFF101318)
        : scheme.background,
    textTheme: Typography.material2021(platform: TargetPlatform.android).white.apply(
          fontFamily: 'Roboto',
        ),
  );
}
