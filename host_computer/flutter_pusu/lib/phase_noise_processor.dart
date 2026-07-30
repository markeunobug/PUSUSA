import 'dart:collection';
import 'dart:math' as math;

import 'phase_noise_models.dart';

class PhaseNoiseRollingAverager {
  PhaseNoiseRollingAverager({required int windowSize})
      : _windowSize = _validatedWindowSize(windowSize);

  int _windowSize;
  final Map<double, _PhaseNoiseAverageBucket> _buckets = {};

  int get windowSize => _windowSize;

  void reset({int? windowSize}) {
    if (windowSize != null) {
      _windowSize = _validatedWindowSize(windowSize);
    }
    _buckets.clear();
  }

  int sampleCountForOffset(double offsetHz) {
    return _buckets[offsetHz]?.length ?? 0;
  }

  PhaseNoisePoint add(PhaseNoisePoint rawPoint) {
    if (!rawPoint.valid ||
        !rawPoint.noisePowerDbm.isFinite ||
        !rawPoint.dbcHz.isFinite) {
      return rawPoint;
    }

    final bucket = _buckets.putIfAbsent(
      rawPoint.offsetHz,
      _PhaseNoiseAverageBucket.new,
    );
    bucket.add(
      noiseMilliwatts: math.pow(10.0, rawPoint.noisePowerDbm / 10.0).toDouble(),
      phaseNoiseLinear: PhaseNoiseProcessor.dbcHzToLinear(rawPoint.dbcHz),
      windowSize: _windowSize,
    );

    return PhaseNoisePoint(
      offsetHz: rawPoint.offsetHz,
      noisePowerDbm: PhaseNoiseProcessor.linearToDb(
        bucket.noiseMilliwattsAverage,
      ),
      dbcHz: PhaseNoiseProcessor.linearToDb(
        bucket.phaseNoiseLinearAverage,
      ),
      rbwHz: rawPoint.rbwHz,
      valid: true,
    );
  }

  static int _validatedWindowSize(int value) {
    if (value <= 0) {
      throw ArgumentError.value(value, 'windowSize', 'must be positive');
    }
    return value;
  }
}

class _PhaseNoiseAverageBucket {
  final ListQueue<_PhaseNoiseLinearSample> _samples = ListQueue();
  double _noiseMilliwattsSum = 0.0;
  double _phaseNoiseLinearSum = 0.0;

  int get length => _samples.length;
  double get noiseMilliwattsAverage => _noiseMilliwattsSum / length;
  double get phaseNoiseLinearAverage => _phaseNoiseLinearSum / length;

  void add({
    required double noiseMilliwatts,
    required double phaseNoiseLinear,
    required int windowSize,
  }) {
    final sample = _PhaseNoiseLinearSample(
      noiseMilliwatts: noiseMilliwatts,
      phaseNoiseLinear: phaseNoiseLinear,
    );
    _samples.addLast(sample);
    _noiseMilliwattsSum += noiseMilliwatts;
    _phaseNoiseLinearSum += phaseNoiseLinear;

    if (_samples.length > windowSize) {
      final removed = _samples.removeFirst();
      _noiseMilliwattsSum -= removed.noiseMilliwatts;
      _phaseNoiseLinearSum -= removed.phaseNoiseLinear;
    }
  }
}

class _PhaseNoiseLinearSample {
  final double noiseMilliwatts;
  final double phaseNoiseLinear;

  const _PhaseNoiseLinearSample({
    required this.noiseMilliwatts,
    required this.phaseNoiseLinear,
  });
}

class PhaseNoiseProcessor {
  final PhaseNoiseConfig config;

  const PhaseNoiseProcessor(this.config);

  PhaseNoiseCarrier? findCarrier(
    Iterable<PhaseNoiseSweepPoint> points, {
    PhaseNoiseCarrier? previousCarrier,
  }) {
    if (!config.isValid) return null;

    final candidates = points.where(_isFinitePoint).toList();
    if (candidates.isEmpty) return null;

    if (config.carrierMode == PhaseNoiseCarrierMode.manual) {
      final nominalHz = config.manualCarrierHz!;
      final searchWindowHz = config.manualCarrierSearchWindowHz;
      final searchPoints = candidates
          .where(
            (p) =>
                searchWindowHz == null ||
                (p.frequencyHz - nominalHz).abs() <= searchWindowHz,
          )
          .toList();
      if (searchPoints.isEmpty) return null;

      final peak = searchWindowHz == null
          ? _nearestFrequencyPoint(searchPoints, nominalHz)
          : _maxPowerPoint(searchPoints);
      return PhaseNoiseCarrier(
        nominalHz: nominalHz,
        measuredHz: peak.frequencyHz,
        levelDbm: peak.powerDbm,
        initialDeltaHz: peak.frequencyHz - nominalHz,
        driftHz: previousCarrier == null
            ? 0.0
            : peak.frequencyHz - previousCarrier.measuredHz,
      );
    }

    final peak = _maxPowerPoint(candidates);
    return PhaseNoiseCarrier(
      nominalHz: peak.frequencyHz,
      measuredHz: peak.frequencyHz,
      levelDbm: peak.powerDbm,
      initialDeltaHz: 0.0,
      driftHz: previousCarrier == null
          ? 0.0
          : peak.frequencyHz - previousCarrier.measuredHz,
    );
  }

  PhaseNoiseTrace processSweep(
    Iterable<PhaseNoiseSweepPoint> points, {
    PhaseNoiseCarrier? carrier,
    PhaseNoiseTrace? previousTrace,
  }) {
    final warnings = <PhaseNoiseWarning>[];
    if (!config.isValid) {
      warnings.add(
        const PhaseNoiseWarning(
          code: PhaseNoiseWarningCode.invalidConfig,
          message: '相位噪声配置无效',
        ),
      );
      return PhaseNoiseTrace(
        rawPoints: const [],
        averagePoints: previousTrace?.averagePoints ?? const [],
        completedAverages: previousTrace?.completedAverages ?? 0,
        carrier: carrier,
        warnings: warnings,
      );
    }

    final finitePoints = points.where(_isFinitePoint).toList()
      ..sort((a, b) => a.frequencyHz.compareTo(b.frequencyHz));
    final resolvedCarrier = carrier ??
        findCarrier(finitePoints, previousCarrier: previousTrace?.carrier);
    if (resolvedCarrier == null) {
      warnings.add(
        const PhaseNoiseWarning(
          code: PhaseNoiseWarningCode.noCarrierFound,
          message: '扫频数据中未找到载波',
        ),
      );
      return PhaseNoiseTrace(
        rawPoints: const [],
        averagePoints: previousTrace?.averagePoints ?? const [],
        completedAverages: previousTrace?.completedAverages ?? 0,
        carrier: null,
        warnings: warnings,
      );
    }

    warnings.addAll(_buildBoundaryWarnings(resolvedCarrier));
    final rawPoints = convertSweepPoints(
      finitePoints,
      resolvedCarrier,
      warnings: warnings,
    );

    if (rawPoints.where((p) => p.valid).length < 3) {
      warnings.add(
        const PhaseNoiseWarning(
          code: PhaseNoiseWarningCode.insufficientValidPoints,
          message: '有效相位噪声点少于3个',
        ),
      );
    }

    final previousAverageCount = previousTrace?.completedAverages ?? 0;
    final canUpdateAverage =
        rawPoints.isNotEmpty && previousAverageCount < config.averageTarget;
    final averagePoints = canUpdateAverage
        ? averageTrace(
            previousTrace?.averagePoints,
            rawPoints,
            previousAverageCount: previousAverageCount,
          )
        : previousTrace?.averagePoints ?? const <PhaseNoisePoint>[];
    final nextAverageCount = canUpdateAverage
        ? math.min(previousAverageCount + 1, config.averageTarget)
        : previousAverageCount;

    return PhaseNoiseTrace(
      rawPoints: rawPoints,
      averagePoints: averagePoints,
      completedAverages: nextAverageCount,
      carrier: resolvedCarrier,
      warnings: warnings,
    );
  }

  List<PhaseNoisePoint> convertSweepPoints(
    Iterable<PhaseNoiseSweepPoint> points,
    PhaseNoiseCarrier carrier, {
    List<PhaseNoiseWarning>? warnings,
  }) {
    switch (config.sidebandMode) {
      case PhaseNoiseSidebandMode.upper:
        return _convertSingleSideband(points, carrier, upperSideband: true);
      case PhaseNoiseSidebandMode.lower:
        return _convertSingleSideband(points, carrier, upperSideband: false);
      case PhaseNoiseSidebandMode.both:
        return _convertBothSidebands(points, carrier, warnings: warnings);
    }
  }

  List<PhaseNoisePoint> averageTrace(
    List<PhaseNoisePoint>? previousAverage,
    List<PhaseNoisePoint> nextRaw, {
    int previousAverageCount = 1,
  }) {
    if (nextRaw.isEmpty) return previousAverage ?? const [];
    if (previousAverage == null ||
        previousAverage.isEmpty ||
        previousAverageCount <= 0) {
      return List<PhaseNoisePoint>.unmodifiable(nextRaw);
    }

    final priorByOffset = {
      for (final point in previousAverage) point.offsetHz: point,
    };

    return List<PhaseNoisePoint>.unmodifiable(nextRaw.map((point) {
      final previousPoint = priorByOffset[point.offsetHz];
      if (previousPoint == null || !previousPoint.valid || !point.valid) {
        return point;
      }

      final previousLinear = dbcHzToLinear(previousPoint.dbcHz);
      final nextLinear = dbcHzToLinear(point.dbcHz);
      final averagedLinear =
          (previousLinear * previousAverageCount + nextLinear) /
              (previousAverageCount + 1);
      final averagedDbcHz = linearToDb(averagedLinear);

      return PhaseNoisePoint(
        offsetHz: point.offsetHz,
        noisePowerDbm: point.noisePowerDbm,
        dbcHz: averagedDbcHz,
        rbwHz: point.rbwHz,
        valid: true,
      );
    }));
  }

  double dbmToDbcPerHz({
    required double noisePowerDbm,
    required double carrierLevelDbm,
  }) {
    return noisePowerDbm -
        carrierLevelDbm -
        10.0 * _log10(config.effectiveEnbwHz);
  }

  static double dbcHzToLinear(double dbcHz) {
    return math.pow(10.0, dbcHz / 10.0).toDouble();
  }

  static double linearToDb(double linear) {
    return 10.0 * _log10(linear);
  }

  List<PhaseNoiseWarning> _buildBoundaryWarnings(PhaseNoiseCarrier carrier) {
    final warnings = <PhaseNoiseWarning>[];

    if (config.startOffsetHz < config.rbwHz) {
      warnings.add(
        const PhaseNoiseWarning(
          code: PhaseNoiseWarningCode.offsetBelowRbw,
          message: '频偏小于 RBW，结果为近似值',
        ),
      );
    }

    if (carrier.levelDbm < config.minimumCarrierLevelDbm) {
      warnings.add(
        const PhaseNoiseWarning(
          code: PhaseNoiseWarningCode.weakCarrier,
          message: '载波电平低于建议阈值',
        ),
      );
    }

    return warnings;
  }

  List<PhaseNoisePoint> _convertSingleSideband(
    Iterable<PhaseNoiseSweepPoint> points,
    PhaseNoiseCarrier carrier, {
    required bool upperSideband,
  }) {
    final converted = <PhaseNoisePoint>[];
    for (final point in points) {
      final signedOffsetHz = point.frequencyHz - carrier.measuredHz;
      if (upperSideband && signedOffsetHz <= 0) continue;
      if (!upperSideband && signedOffsetHz >= 0) continue;

      final offsetHz = signedOffsetHz.abs();
      if (offsetHz < config.startOffsetHz || offsetHz > config.stopOffsetHz) {
        continue;
      }

      converted.add(_makePoint(offsetHz, point.powerDbm, carrier));
    }
    converted.sort((a, b) => a.offsetHz.compareTo(b.offsetHz));
    return List<PhaseNoisePoint>.unmodifiable(converted);
  }

  List<PhaseNoisePoint> _convertBothSidebands(
    Iterable<PhaseNoiseSweepPoint> points,
    PhaseNoiseCarrier carrier, {
    List<PhaseNoiseWarning>? warnings,
  }) {
    final lowerByOffset = <double, PhaseNoiseSweepPoint>{};
    final upperByOffset = <double, PhaseNoiseSweepPoint>{};

    for (final point in points) {
      final signedOffsetHz = point.frequencyHz - carrier.measuredHz;
      if (signedOffsetHz == 0) continue;
      final offsetHz = signedOffsetHz.abs();
      if (offsetHz < config.startOffsetHz || offsetHz > config.stopOffsetHz) {
        continue;
      }

      if (signedOffsetHz < 0) {
        lowerByOffset[offsetHz] = point;
      } else {
        upperByOffset[offsetHz] = point;
      }
    }

    final offsets =
        <double>{...lowerByOffset.keys, ...upperByOffset.keys}.toList()..sort();

    final converted = <PhaseNoisePoint>[];
    var missingPair = false;
    for (final offsetHz in offsets) {
      final lower = lowerByOffset[offsetHz];
      final upper = upperByOffset[offsetHz];
      final noisePowerDbm = _averagePowerDbm([
        if (lower != null) lower.powerDbm,
        if (upper != null) upper.powerDbm,
      ]);
      missingPair = missingPair || lower == null || upper == null;
      converted.add(_makePoint(offsetHz, noisePowerDbm, carrier));
    }

    if (missingPair) {
      warnings?.add(
        const PhaseNoiseWarning(
          code: PhaseNoiseWarningCode.missingSidebandPoint,
          message: '双边带平均缺少配对点',
        ),
      );
    }

    return List<PhaseNoisePoint>.unmodifiable(converted);
  }

  PhaseNoisePoint _makePoint(
    double offsetHz,
    double noisePowerDbm,
    PhaseNoiseCarrier carrier,
  ) {
    final valid = offsetHz >= config.rbwHz && _isFinite(noisePowerDbm);
    return PhaseNoisePoint(
      offsetHz: offsetHz,
      noisePowerDbm: noisePowerDbm,
      dbcHz: dbmToDbcPerHz(
        noisePowerDbm: noisePowerDbm,
        carrierLevelDbm: carrier.levelDbm,
      ),
      rbwHz: config.rbwHz,
      valid: valid,
    );
  }

  static PhaseNoiseSweepPoint _maxPowerPoint(
    List<PhaseNoiseSweepPoint> points,
  ) {
    return points.reduce(
      (best, point) => point.powerDbm > best.powerDbm ? point : best,
    );
  }

  static PhaseNoiseSweepPoint _nearestFrequencyPoint(
    List<PhaseNoiseSweepPoint> points,
    double frequencyHz,
  ) {
    return points.reduce(
      (best, point) => (point.frequencyHz - frequencyHz).abs() <
              (best.frequencyHz - frequencyHz).abs()
          ? point
          : best,
    );
  }

  static bool _isFinitePoint(PhaseNoiseSweepPoint point) {
    return _isFinite(point.frequencyHz) && _isFinite(point.powerDbm);
  }

  static bool _isFinite(double value) {
    return !value.isNaN && value.isFinite;
  }

  static double _averagePowerDbm(Iterable<double> dbmValues) {
    final values = dbmValues.toList(growable: false);
    if (values.isEmpty) return double.nan;
    final linearAverage = values
            .map((dbm) => math.pow(10.0, dbm / 10.0).toDouble())
            .reduce((a, b) => a + b) /
        values.length;
    return linearToDb(linearAverage);
  }

  static double _log10(double value) {
    return math.log(value) / math.ln10;
  }
}
