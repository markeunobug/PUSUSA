import 'dart:math' as math;

extension PhaseNoisePositiveDouble on double {
  double? takeIfPositive() => this > 0 ? this : null;
}

enum PhaseNoiseCarrierMode {
  auto,
  manual,
}

enum PhaseNoiseSidebandMode {
  upper,
  lower,
  both,
}

enum PhaseNoiseDensityPreset {
  fast,
  normal,
  fine,
  custom,
}

extension PhaseNoiseDensityPresetDetails on PhaseNoiseDensityPreset {
  int get pointsPerDecade {
    switch (this) {
      case PhaseNoiseDensityPreset.fast:
        return 30;
      case PhaseNoiseDensityPreset.normal:
        return 60;
      case PhaseNoiseDensityPreset.fine:
        return 90;
      case PhaseNoiseDensityPreset.custom:
        return 60;
    }
  }

  String get label {
    switch (this) {
      case PhaseNoiseDensityPreset.fast:
        return 'Fast';
      case PhaseNoiseDensityPreset.normal:
        return 'Normal';
      case PhaseNoiseDensityPreset.fine:
        return 'Fine';
      case PhaseNoiseDensityPreset.custom:
        return 'Custom';
    }
  }
}

enum PhaseNoiseWarningCode {
  invalidConfig,
  noCarrierFound,
  offsetBelowRbw,
  weakCarrier,
  insufficientValidPoints,
  missingSidebandPoint,
  deviceWarning,
  deviceError,
}

class PhaseNoiseWarning {
  final PhaseNoiseWarningCode code;
  final String message;

  const PhaseNoiseWarning({
    required this.code,
    required this.message,
  });
}

class PhaseNoiseConfig {
  final PhaseNoiseCarrierMode carrierMode;
  final double? manualCarrierHz;
  final double? nominalCarrierHz;
  final double startOffsetHz;
  final double stopOffsetHz;
  final double rbwHz;
  final double? enbwHz;
  final int averageTarget;
  final int pointsPerDecade;
  final PhaseNoiseSidebandMode sidebandMode;
  final double carrierSearchSpanHz;
  final double minimumCarrierLevelDbm;
  final double? manualCarrierSearchWindowHz;

  const PhaseNoiseConfig({
    this.carrierMode = PhaseNoiseCarrierMode.auto,
    this.manualCarrierHz,
    this.nominalCarrierHz,
    this.startOffsetHz = 1000.0,
    this.stopOffsetHz = 1000000.0,
    this.rbwHz = 1000.0,
    this.enbwHz,
    this.averageTarget = 10,
    this.pointsPerDecade = 60,
    this.sidebandMode = PhaseNoiseSidebandMode.upper,
    this.carrierSearchSpanHz = 100000.0,
    this.minimumCarrierLevelDbm = -50.0,
    this.manualCarrierSearchWindowHz,
  });

  double get effectiveEnbwHz => enbwHz ?? rbwHz;
  double get protocolNominalCarrierHz =>
      nominalCarrierHz ?? manualCarrierHz ?? 0.0;

  int get estimatedPointCount {
    if (startOffsetHz <= 0 || stopOffsetHz < startOffsetHz) return 0;
    if (pointsPerDecade <= 0) return 0;
    final decades = math.log(stopOffsetHz / startOffsetHz) / math.ln10;
    return math.max(1, (decades * pointsPerDecade).round() + 1);
  }

  bool get isValid {
    if (startOffsetHz <= 0 || stopOffsetHz < startOffsetHz) return false;
    if (rbwHz <= 0 || effectiveEnbwHz <= 0) return false;
    if (averageTarget <= 0) return false;
    if (pointsPerDecade <= 0) return false;
    if (carrierMode == PhaseNoiseCarrierMode.manual) {
      return manualCarrierHz != null && manualCarrierHz! > 0;
    }
    return true;
  }

  PhaseNoiseConfig copyWith({
    PhaseNoiseCarrierMode? carrierMode,
    double? manualCarrierHz,
    double? nominalCarrierHz,
    double? startOffsetHz,
    double? stopOffsetHz,
    double? rbwHz,
    double? enbwHz,
    int? averageTarget,
    int? pointsPerDecade,
    PhaseNoiseSidebandMode? sidebandMode,
    double? carrierSearchSpanHz,
    double? minimumCarrierLevelDbm,
    double? manualCarrierSearchWindowHz,
  }) {
    return PhaseNoiseConfig(
      carrierMode: carrierMode ?? this.carrierMode,
      manualCarrierHz: manualCarrierHz ?? this.manualCarrierHz,
      nominalCarrierHz: nominalCarrierHz ?? this.nominalCarrierHz,
      startOffsetHz: startOffsetHz ?? this.startOffsetHz,
      stopOffsetHz: stopOffsetHz ?? this.stopOffsetHz,
      rbwHz: rbwHz ?? this.rbwHz,
      enbwHz: enbwHz ?? this.enbwHz,
      averageTarget: averageTarget ?? this.averageTarget,
      pointsPerDecade: pointsPerDecade ?? this.pointsPerDecade,
      sidebandMode: sidebandMode ?? this.sidebandMode,
      carrierSearchSpanHz: carrierSearchSpanHz ?? this.carrierSearchSpanHz,
      minimumCarrierLevelDbm:
          minimumCarrierLevelDbm ?? this.minimumCarrierLevelDbm,
      manualCarrierSearchWindowHz:
          manualCarrierSearchWindowHz ?? this.manualCarrierSearchWindowHz,
    );
  }
}

class PhaseNoiseCarrier {
  final double nominalHz;
  final double measuredHz;
  final double levelDbm;
  final double initialDeltaHz;
  final double driftHz;

  const PhaseNoiseCarrier({
    required this.nominalHz,
    required this.measuredHz,
    required this.levelDbm,
    required this.initialDeltaHz,
    required this.driftHz,
  });
}

class PhaseNoiseSweepPoint {
  final double frequencyHz;
  final double powerDbm;

  const PhaseNoiseSweepPoint({
    required this.frequencyHz,
    required this.powerDbm,
  });
}

class PhaseNoisePoint {
  final double offsetHz;
  final double noisePowerDbm;
  final double dbcHz;
  final double rbwHz;
  final bool valid;

  const PhaseNoisePoint({
    required this.offsetHz,
    required this.noisePowerDbm,
    required this.dbcHz,
    required this.rbwHz,
    required this.valid,
  });
}

class PhaseNoiseProgress {
  final int plannedTotalPoints;
  final int receivedPoints;
  final int currentIndex;
  final int averageIndex;

  const PhaseNoiseProgress({
    required this.plannedTotalPoints,
    required this.receivedPoints,
    required this.currentIndex,
    required this.averageIndex,
  });
}

class PhaseNoiseDataFrame {
  final int version;
  final int flags;
  final int traceId;
  final int plannedTotalPoints;
  final int receivedPoints;
  final int currentIndex;
  final int averageIndex;
  final double carrierHz;
  final double carrierLevelDbm;
  final int offsetHz;
  final double noisePowerDbm;
  final double phaseNoiseDbcHz;
  final int rbwHz;
  final int errorCode;

  const PhaseNoiseDataFrame({
    required this.version,
    required this.flags,
    required this.traceId,
    required this.plannedTotalPoints,
    required this.receivedPoints,
    required this.currentIndex,
    required this.averageIndex,
    required this.carrierHz,
    required this.carrierLevelDbm,
    required this.offsetHz,
    required this.noisePowerDbm,
    required this.phaseNoiseDbcHz,
    required this.rbwHz,
    required this.errorCode,
  });

  bool get done => (flags & (1 << 0)) != 0;
  bool get carrierValid => (flags & (1 << 1)) != 0;
  bool get warning => (flags & (1 << 2)) != 0;
  bool get lowerSideband => (flags & (1 << 3)) != 0;
  bool get dualAverage => (flags & (1 << 4)) != 0;
  bool get phaseNoiseValid => (flags & (1 << 5)) != 0;

  PhaseNoiseProgress get progress => PhaseNoiseProgress(
        plannedTotalPoints: plannedTotalPoints,
        receivedPoints: receivedPoints,
        currentIndex: currentIndex,
        averageIndex: averageIndex,
      );
}

class PhaseNoiseStatusFrame {
  final int version;
  final int state;
  final int flags;
  final int errorCode;
  final int traceId;
  final int plannedTotalPoints;
  final int receivedPoints;
  final int currentIndex;
  final int averageIndex;
  final double nominalCarrierHz;
  final double measuredCarrierHz;
  final double carrierLevelDbm;
  final double startOffsetHz;
  final double stopOffsetHz;
  final int currentOffsetHz;
  final int currentRbwHz;
  final int elapsedMs;
  final int warningCode;

  const PhaseNoiseStatusFrame({
    required this.version,
    required this.state,
    required this.flags,
    required this.errorCode,
    required this.traceId,
    required this.plannedTotalPoints,
    required this.receivedPoints,
    required this.currentIndex,
    required this.averageIndex,
    required this.nominalCarrierHz,
    required this.measuredCarrierHz,
    required this.carrierLevelDbm,
    required this.startOffsetHz,
    required this.stopOffsetHz,
    required this.currentOffsetHz,
    required this.currentRbwHz,
    required this.elapsedMs,
    required this.warningCode,
  });

  bool get configured => (flags & (1 << 0)) != 0;
  bool get running => (flags & (1 << 1)) != 0;
  bool get carrierValid => (flags & (1 << 2)) != 0;
  bool get dataValid => (flags & (1 << 3)) != 0;
  bool get warning => (flags & (1 << 4)) != 0;
  bool get stopRequested => (flags & (1 << 5)) != 0;
  bool get complete => (flags & (1 << 6)) != 0;

  PhaseNoiseProgress get progress => PhaseNoiseProgress(
        plannedTotalPoints: plannedTotalPoints,
        receivedPoints: receivedPoints,
        currentIndex: currentIndex,
        averageIndex: averageIndex,
      );
}

class PhaseNoiseTrace {
  final List<PhaseNoisePoint> rawPoints;
  final List<PhaseNoisePoint> averagePoints;
  final int completedAverages;
  final PhaseNoiseCarrier? carrier;
  final List<PhaseNoiseWarning> warnings;

  const PhaseNoiseTrace({
    required this.rawPoints,
    required this.averagePoints,
    required this.completedAverages,
    this.carrier,
    this.warnings = const [],
  });

  factory PhaseNoiseTrace.fromDataFrames(
    Iterable<PhaseNoiseDataFrame> frames, {
    PhaseNoiseCarrier? carrier,
    List<PhaseNoiseWarning> warnings = const [],
  }) {
    final frameList = frames.toList(growable: false);
    final points = frameList
        .map(
          (frame) => PhaseNoisePoint(
            offsetHz: frame.offsetHz.toDouble(),
            noisePowerDbm: frame.noisePowerDbm,
            dbcHz: frame.phaseNoiseDbcHz,
            rbwHz: frame.rbwHz.toDouble(),
            valid: frame.phaseNoiseValid && frame.errorCode == 0,
          ),
        )
        .toList(growable: false);

    final completedAverages = frameList.fold<int>(
      0,
      (maxAverage, frame) => math.max(maxAverage, frame.averageIndex),
    );

    return PhaseNoiseTrace(
      rawPoints: List<PhaseNoisePoint>.unmodifiable(points),
      averagePoints: const [],
      completedAverages: completedAverages,
      carrier: carrier,
      warnings: warnings,
    );
  }

  const PhaseNoiseTrace.empty()
      : rawPoints = const [],
        averagePoints = const [],
        completedAverages = 0,
        carrier = null,
        warnings = const [];
}
