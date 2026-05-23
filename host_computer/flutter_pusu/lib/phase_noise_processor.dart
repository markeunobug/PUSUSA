import 'dart:math' as math;

import 'phase_noise_models.dart';

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
          message: 'Invalid phase-noise configuration',
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
          message: 'No carrier found in sweep data',
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
          message: 'Fewer than 3 valid phase-noise points',
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
          message: 'Offset < RBW, result is approximate',
        ),
      );
    }

    if (carrier.levelDbm < config.minimumCarrierLevelDbm) {
      warnings.add(
        const PhaseNoiseWarning(
          code: PhaseNoiseWarningCode.weakCarrier,
          message: 'Carrier level is below recommended threshold',
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
          message: 'Both-sideband average has missing paired points',
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
