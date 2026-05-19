class FrequencyConfig {
  final double startHz;
  final double stopHz;
  final double centerHz;
  final double spanHz;

  const FrequencyConfig({
    required this.startHz,
    required this.stopHz,
    required this.centerHz,
    required this.spanHz,
  });
}

class AmplitudeConfig {
  final double refLevelDbm;
  final int attenuatorMode;
  final int preampMode;

  const AmplitudeConfig({
    required this.refLevelDbm,
    required this.attenuatorMode,
    required this.preampMode,
  });
}

class BandwidthConfig {
  final int rbwMode;
  final double rbwHz;
  final int vbwMode;
  final double vbwHz;

  const BandwidthConfig({
    required this.rbwMode,
    required this.rbwHz,
    required this.vbwMode,
    required this.vbwHz,
  });
}

class SweepConfig {
  final double speedHz;
  final int mode;
  final int pointCount;

  const SweepConfig({
    required this.speedHz,
    required this.mode,
    required this.pointCount,
  });
}

class DetectConfig {
  final int mode;

  const DetectConfig({required this.mode});
}

enum RfLnaMode {
  bypass,
  enable,
  auto,
}

enum RfPathMode {
  directIf,
  mixerChain,
  auto,
}

class RfFrontendConfig {
  final RfLnaMode lnaMode;
  final RfPathMode pathMode;
  final int attenCode;

  const RfFrontendConfig({
    required this.lnaMode,
    required this.pathMode,
    required this.attenCode,
  });

  double get attenDb => attenCode * 0.25;

  RfFrontendConfig copyWith({
    RfLnaMode? lnaMode,
    RfPathMode? pathMode,
    int? attenCode,
  }) {
    return RfFrontendConfig(
      lnaMode: lnaMode ?? this.lnaMode,
      pathMode: pathMode ?? this.pathMode,
      attenCode: attenCode ?? this.attenCode,
    );
  }
}

class RfFrontendStatus {
  final RfFrontendConfig config;
  final int appliedGpio;
  final int error;

  const RfFrontendStatus({
    required this.config,
    required this.appliedGpio,
    required this.error,
  });

  bool get ok => error == 0;
}

class DeviceControlConfig {
  final FrequencyConfig frequency;
  final AmplitudeConfig amplitude;
  final BandwidthConfig bandwidth;
  final SweepConfig sweep;
  final DetectConfig detect;

  const DeviceControlConfig({
    required this.frequency,
    required this.amplitude,
    required this.bandwidth,
    required this.sweep,
    required this.detect,
  });
}
