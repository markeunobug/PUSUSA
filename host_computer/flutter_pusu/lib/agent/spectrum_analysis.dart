import 'dart:math' as math;

class AgentSpectrumPoint {
  const AgentSpectrumPoint({
    required this.frequencyHz,
    required this.powerDbm,
  });

  final double frequencyHz;
  final double powerDbm;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'frequency_hz': frequencyHz,
        'power_dbm': powerDbm,
      };
}

class AgentSpectrumPeak {
  const AgentSpectrumPeak({
    required this.frequencyHz,
    required this.powerDbm,
    required this.aboveNoiseDb,
  });

  final double frequencyHz;
  final double powerDbm;
  final double aboveNoiseDb;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'frequency_hz': frequencyHz,
        'power_dbm': powerDbm,
        'above_noise_db': aboveNoiseDb,
      };
}

class AgentSpectrumAnalysis {
  const AgentSpectrumAnalysis({
    required this.pointCount,
    required this.startHz,
    required this.stopHz,
    required this.minimumDbm,
    required this.maximumDbm,
    required this.noiseFloorDbm,
    required this.peaks,
  });

  final int pointCount;
  final double startHz;
  final double stopHz;
  final double minimumDbm;
  final double maximumDbm;
  final double noiseFloorDbm;
  final List<AgentSpectrumPeak> peaks;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'point_count': pointCount,
        'start_hz': startHz,
        'stop_hz': stopHz,
        'minimum_dbm': minimumDbm,
        'maximum_dbm': maximumDbm,
        'noise_floor_dbm': noiseFloorDbm,
        'peaks': peaks.map((peak) => peak.toJson()).toList(),
      };
}

abstract final class AgentSpectrumAnalyzer {
  static AgentSpectrumAnalysis analyze(
    List<AgentSpectrumPoint> input, {
    int peakCount = 5,
    double thresholdAboveNoiseDb = 6,
  }) {
    if (input.isEmpty) {
      throw ArgumentError.value(input, 'input', '频谱数据不能为空');
    }
    final points = List<AgentSpectrumPoint>.from(input)
      ..sort((a, b) => a.frequencyHz.compareTo(b.frequencyHz));
    final noiseFloor = estimateNoiseFloor(points);
    final candidates = <AgentSpectrumPoint>[];
    if (points.length == 1) {
      candidates.add(points.single);
    } else {
      for (var i = 0; i < points.length; i++) {
        final current = points[i];
        final left = i == 0 ? double.negativeInfinity : points[i - 1].powerDbm;
        final right = i == points.length - 1
            ? double.negativeInfinity
            : points[i + 1].powerDbm;
        if (current.powerDbm >= left &&
            current.powerDbm >= right &&
            current.powerDbm - noiseFloor >= thresholdAboveNoiseDb) {
          candidates.add(current);
        }
      }
    }
    candidates.sort((a, b) => b.powerDbm.compareTo(a.powerDbm));

    final typicalBinHz = _typicalBinWidth(points);
    final minimumSpacingHz = math.max(typicalBinHz * 2, 1.0);
    final selected = <AgentSpectrumPoint>[];
    for (final candidate in candidates) {
      if (selected.every(
        (peak) =>
            (peak.frequencyHz - candidate.frequencyHz).abs() >=
            minimumSpacingHz,
      )) {
        selected.add(candidate);
      }
      if (selected.length >= peakCount.clamp(1, 20)) {
        break;
      }
    }

    final powers = points.map((point) => point.powerDbm);
    return AgentSpectrumAnalysis(
      pointCount: points.length,
      startHz: points.first.frequencyHz,
      stopHz: points.last.frequencyHz,
      minimumDbm: powers.reduce(math.min),
      maximumDbm: powers.reduce(math.max),
      noiseFloorDbm: noiseFloor,
      peaks: selected
          .map(
            (point) => AgentSpectrumPeak(
              frequencyHz: point.frequencyHz,
              powerDbm: point.powerDbm,
              aboveNoiseDb: point.powerDbm - noiseFloor,
            ),
          )
          .toList(),
    );
  }

  static double estimateNoiseFloor(List<AgentSpectrumPoint> input) {
    if (input.isEmpty) {
      throw ArgumentError.value(input, 'input', '频谱数据不能为空');
    }
    final powers = input.map((point) => point.powerDbm).toList()..sort();
    final trimmedLength = math.max(1, (powers.length * 0.8).floor());
    final trimmed = powers.sublist(0, trimmedLength);
    final middle = trimmed.length ~/ 2;
    if (trimmed.length.isOdd) {
      return trimmed[middle];
    }
    return (trimmed[middle - 1] + trimmed[middle]) / 2;
  }

  static List<AgentSpectrumPoint> downsample(
    List<AgentSpectrumPoint> input,
    int maximumPoints,
  ) {
    if (maximumPoints <= 0) {
      return const <AgentSpectrumPoint>[];
    }
    if (input.length <= maximumPoints) {
      return List<AgentSpectrumPoint>.from(input);
    }
    final result = <AgentSpectrumPoint>[];
    final bucketSize = input.length / maximumPoints;
    for (var bucket = 0; bucket < maximumPoints; bucket++) {
      final start = (bucket * bucketSize).floor();
      final stop = math.min(input.length, ((bucket + 1) * bucketSize).ceil());
      if (start >= stop) {
        continue;
      }
      var strongest = input[start];
      for (var i = start + 1; i < stop; i++) {
        if (input[i].powerDbm > strongest.powerDbm) {
          strongest = input[i];
        }
      }
      result.add(strongest);
    }
    result.sort((a, b) => a.frequencyHz.compareTo(b.frequencyHz));
    return result;
  }

  static double _typicalBinWidth(List<AgentSpectrumPoint> points) {
    if (points.length < 2) {
      return 1;
    }
    final widths = <double>[];
    for (var i = 1; i < points.length; i++) {
      final width = (points[i].frequencyHz - points[i - 1].frequencyHz).abs();
      if (width > 0) {
        widths.add(width);
      }
    }
    if (widths.isEmpty) {
      return 1;
    }
    widths.sort();
    return widths[widths.length ~/ 2];
  }
}
