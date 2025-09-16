class AnalysisResult {
  const AnalysisResult({
    this.f0Hz,
    this.f1Hz,
    this.rtf,
    this.noteName,
    this.cents,
    required this.confidence,
    this.peaks = const <Peak>[],
    required this.timestampMs,
  });

  final double? f0Hz;
  final double? f1Hz;
  final double? rtf;
  final String? noteName;
  final double? cents;
  final double confidence;
  final List<Peak> peaks;
  final int timestampMs;

  factory AnalysisResult.fromMap(Map<dynamic, dynamic> data) {
    return AnalysisResult(
      f0Hz: (data['f0Hz'] as num?)?.toDouble(),
      f1Hz: (data['f1Hz'] as num?)?.toDouble(),
      rtf: (data['rtf'] as num?)?.toDouble(),
      noteName: data['noteName'] as String?,
      cents: (data['cents'] as num?)?.toDouble(),
      confidence: (data['confidence'] as num?)?.toDouble() ?? 0,
      peaks: (data['peaks'] as List<dynamic>? ?? const <dynamic>[])
          .map((dynamic raw) => Peak.fromMap(raw as Map<dynamic, dynamic>))
          .toList(growable: false),
      timestampMs: (data['timestampMs'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'f0Hz': f0Hz,
      'f1Hz': f1Hz,
      'rtf': rtf,
      'noteName': noteName,
      'cents': cents,
      'confidence': confidence,
      'peaks': peaks.map((Peak peak) => peak.toMap()).toList(growable: false),
      'timestampMs': timestampMs,
    };
  }
}

class Peak {
  const Peak({
    required this.hz,
    required this.magnitude,
  });

  final double hz;
  final double magnitude;

  factory Peak.fromMap(Map<dynamic, dynamic> data) {
    return Peak(
      hz: (data['Hz'] as num?)?.toDouble() ?? 0,
      magnitude: (data['mag'] as num?)?.toDouble() ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return <String, dynamic>{
      'Hz': hz,
      'mag': magnitude,
    };
  }
}
