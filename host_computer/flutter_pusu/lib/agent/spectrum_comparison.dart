import 'dart:math' as math;

import 'spectrum_analysis.dart';

class AgentSpectrumComparison {
  const AgentSpectrumComparison({
    required this.firstPointCount,
    required this.secondPointCount,
    required this.comparedPointCount,
    required this.overlapStartHz,
    required this.overlapStopHz,
    required this.meanDeltaDb,
    required this.rmsDeltaDb,
    required this.maximumIncreaseDb,
    required this.maximumDecreaseDb,
    required this.maximumAbsoluteDeltaDb,
    required this.firstAnalysis,
    required this.secondAnalysis,
  });

  final int firstPointCount;
  final int secondPointCount;
  final int comparedPointCount;
  final double overlapStartHz;
  final double overlapStopHz;
  final double meanDeltaDb;
  final double rmsDeltaDb;
  final double maximumIncreaseDb;
  final double maximumDecreaseDb;
  final double maximumAbsoluteDeltaDb;
  final AgentSpectrumAnalysis firstAnalysis;
  final AgentSpectrumAnalysis secondAnalysis;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'delta_definition': 'second_minus_first_db',
        'first_point_count': firstPointCount,
        'second_point_count': secondPointCount,
        'compared_point_count': comparedPointCount,
        'overlap_start_hz': overlapStartHz,
        'overlap_stop_hz': overlapStopHz,
        'mean_delta_db': meanDeltaDb,
        'rms_delta_db': rmsDeltaDb,
        'maximum_increase_db': maximumIncreaseDb,
        'maximum_decrease_db': maximumDecreaseDb,
        'maximum_absolute_delta_db': maximumAbsoluteDeltaDb,
        'noise_floor_delta_db':
            secondAnalysis.noiseFloorDbm - firstAnalysis.noiseFloorDbm,
        'main_peak_power_delta_db':
            _mainPeakPower(secondAnalysis) - _mainPeakPower(firstAnalysis),
        'main_peak_frequency_delta_hz': _mainPeakFrequency(secondAnalysis) -
            _mainPeakFrequency(firstAnalysis),
        'first_analysis': firstAnalysis.toJson(),
        'second_analysis': secondAnalysis.toJson(),
      };

  static double _mainPeakPower(AgentSpectrumAnalysis analysis) =>
      analysis.peaks.isEmpty
          ? analysis.maximumDbm
          : analysis.peaks.first.powerDbm;

  static double _mainPeakFrequency(AgentSpectrumAnalysis analysis) =>
      analysis.peaks.isEmpty ? double.nan : analysis.peaks.first.frequencyHz;
}

abstract final class AgentSpectrumComparator {
  static AgentSpectrumComparison compare(
    List<AgentSpectrumPoint> firstInput,
    List<AgentSpectrumPoint> secondInput,
  ) {
    if (firstInput.isEmpty || secondInput.isEmpty) {
      throw ArgumentError('用于对比的两条频谱都不能为空');
    }
    final first = List<AgentSpectrumPoint>.from(firstInput)
      ..sort((a, b) => a.frequencyHz.compareTo(b.frequencyHz));
    final second = List<AgentSpectrumPoint>.from(secondInput)
      ..sort((a, b) => a.frequencyHz.compareTo(b.frequencyHz));
    final overlapStart = math.max(
      first.first.frequencyHz,
      second.first.frequencyHz,
    );
    final overlapStop = math.min(
      first.last.frequencyHz,
      second.last.frequencyHz,
    );
    if (overlapStart > overlapStop) {
      throw ArgumentError('两条频谱没有重叠的频率范围');
    }

    final deltas = <double>[];
    for (final point in first) {
      if (point.frequencyHz < overlapStart || point.frequencyHz > overlapStop) {
        continue;
      }
      final secondPower = _interpolate(second, point.frequencyHz);
      if (secondPower != null) {
        deltas.add(secondPower - point.powerDbm);
      }
    }
    if (deltas.isEmpty) {
      throw ArgumentError('两条频谱没有可对齐的频点');
    }

    final mean = deltas.reduce((a, b) => a + b) / deltas.length;
    final rms = math.sqrt(
      deltas.map((delta) => delta * delta).reduce((a, b) => a + b) /
          deltas.length,
    );
    return AgentSpectrumComparison(
      firstPointCount: first.length,
      secondPointCount: second.length,
      comparedPointCount: deltas.length,
      overlapStartHz: overlapStart,
      overlapStopHz: overlapStop,
      meanDeltaDb: mean,
      rmsDeltaDb: rms,
      maximumIncreaseDb: deltas.reduce(math.max),
      maximumDecreaseDb: deltas.reduce(math.min),
      maximumAbsoluteDeltaDb:
          deltas.map((delta) => delta.abs()).reduce(math.max),
      firstAnalysis: AgentSpectrumAnalyzer.analyze(first),
      secondAnalysis: AgentSpectrumAnalyzer.analyze(second),
    );
  }

  static double? _interpolate(
    List<AgentSpectrumPoint> points,
    double frequencyHz,
  ) {
    if (frequencyHz < points.first.frequencyHz ||
        frequencyHz > points.last.frequencyHz) {
      return null;
    }
    var low = 0;
    var high = points.length - 1;
    while (low <= high) {
      final middle = (low + high) ~/ 2;
      final point = points[middle];
      if (point.frequencyHz == frequencyHz) return point.powerDbm;
      if (point.frequencyHz < frequencyHz) {
        low = middle + 1;
      } else {
        high = middle - 1;
      }
    }
    if (low <= 0 || low >= points.length) return null;
    final left = points[low - 1];
    final right = points[low];
    final width = right.frequencyHz - left.frequencyHz;
    if (width <= 0) return left.powerDbm;
    final ratio = (frequencyHz - left.frequencyHz) / width;
    return left.powerDbm + (right.powerDbm - left.powerDbm) * ratio;
  }
}

class AgentSpectrumLimitEvaluation {
  const AgentSpectrumLimitEvaluation({
    required this.passed,
    required this.checks,
    required this.analysis,
  });

  final bool passed;
  final List<Map<String, dynamic>> checks;
  final AgentSpectrumAnalysis analysis;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'passed': passed,
        'checks': checks,
        'analysis': analysis.toJson(),
      };
}

abstract final class AgentSpectrumLimitEvaluator {
  static AgentSpectrumLimitEvaluation evaluate(
    List<AgentSpectrumPoint> points, {
    double? maximumNoiseFloorDbm,
    double? minimumMainPeakDbm,
    double? minimumSpurSuppressionDb,
  }) {
    if (maximumNoiseFloorDbm == null &&
        minimumMainPeakDbm == null &&
        minimumSpurSuppressionDb == null) {
      throw ArgumentError('至少需要提供一项限值条件');
    }
    final analysis = AgentSpectrumAnalyzer.analyze(points, peakCount: 8);
    final checks = <Map<String, dynamic>>[];
    if (maximumNoiseFloorDbm != null) {
      checks.add(<String, dynamic>{
        'name': 'maximum_noise_floor_dbm',
        'limit': maximumNoiseFloorDbm,
        'actual': analysis.noiseFloorDbm,
        'passed': analysis.noiseFloorDbm <= maximumNoiseFloorDbm,
      });
    }
    final mainPeakPower = analysis.peaks.isEmpty
        ? analysis.maximumDbm
        : analysis.peaks.first.powerDbm;
    if (minimumMainPeakDbm != null) {
      checks.add(<String, dynamic>{
        'name': 'minimum_main_peak_dbm',
        'limit': minimumMainPeakDbm,
        'actual': mainPeakPower,
        'passed': mainPeakPower >= minimumMainPeakDbm,
      });
    }
    if (minimumSpurSuppressionDb != null) {
      final suppression = analysis.peaks.length < 2
          ? null
          : mainPeakPower - analysis.peaks[1].powerDbm;
      checks.add(<String, dynamic>{
        'name': 'minimum_spur_suppression_db',
        'limit': minimumSpurSuppressionDb,
        'actual': suppression,
        'passed':
            suppression != null && suppression >= minimumSpurSuppressionDb,
        if (suppression == null) 'reason': '未找到可用于计算的第二峰值',
      });
    }
    return AgentSpectrumLimitEvaluation(
      passed: checks.every((check) => check['passed'] == true),
      checks: checks,
      analysis: analysis,
    );
  }
}
