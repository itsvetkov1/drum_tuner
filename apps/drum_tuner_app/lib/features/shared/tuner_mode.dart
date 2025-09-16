import 'package:flutter/material.dart';

enum TunerMode { pitch, lug, resonant, spectrum }

extension TunerModeX on TunerMode {
  String get label {
    switch (this) {
      case TunerMode.pitch:
        return 'Pitch';
      case TunerMode.lug:
        return 'Lug';
      case TunerMode.resonant:
        return 'Resonant';
      case TunerMode.spectrum:
        return 'Spectrum';
    }
  }

  IconData get icon {
    switch (this) {
      case TunerMode.pitch:
        return Icons.music_note;
      case TunerMode.lug:
        return Icons.adjust;
      case TunerMode.resonant:
        return Icons.waves;
      case TunerMode.spectrum:
        return Icons.bar_chart;
    }
  }
}
