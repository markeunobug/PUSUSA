import 'spectrum_analysis.dart';

class RealtimeSpectrumSample {
  const RealtimeSpectrumSample({
    required this.frequencyHz,
    required this.levelDbfs,
  });

  final double frequencyHz;
  final double levelDbfs;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'frequency_hz': frequencyHz,
        'level_dbfs': levelDbfs,
      };
}

class RealtimeSpectrumPeak {
  const RealtimeSpectrumPeak({
    required this.frequencyHz,
    required this.levelDbfs,
    required this.aboveNoiseDb,
  });

  final double frequencyHz;
  final double levelDbfs;
  final double aboveNoiseDb;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'frequency_hz': frequencyHz,
        'level_dbfs': levelDbfs,
        'above_noise_db': aboveNoiseDb,
      };
}

class RealtimeSpectrumAnalysis {
  const RealtimeSpectrumAnalysis({
    required this.trace,
    required this.pointCount,
    required this.startHz,
    required this.stopHz,
    required this.minimumDbfs,
    required this.maximumDbfs,
    required this.noiseFloorDbfs,
    required this.peaks,
  });

  final String trace;
  final int pointCount;
  final double startHz;
  final double stopHz;
  final double minimumDbfs;
  final double maximumDbfs;
  final double noiseFloorDbfs;
  final List<RealtimeSpectrumPeak> peaks;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'measurement_mode': 'realtime_spectrum',
        'amplitude_unit': 'dBFS',
        'trace': trace,
        'point_count': pointCount,
        'start_hz': startHz,
        'stop_hz': stopHz,
        'minimum_dbfs': minimumDbfs,
        'maximum_dbfs': maximumDbfs,
        'noise_floor_dbfs': noiseFloorDbfs,
        'peaks': peaks.map((peak) => peak.toJson()).toList(),
      };
}

abstract final class RealtimeSpectrumAnalyzer {
  static RealtimeSpectrumAnalysis analyze(
    List<RealtimeSpectrumSample> samples, {
    required String trace,
    int peakCount = 5,
    double thresholdAboveNoiseDb = 6,
  }) {
    final generic = AgentSpectrumAnalyzer.analyze(
      samples
          .map(
            (sample) => AgentSpectrumPoint(
              frequencyHz: sample.frequencyHz,
              powerDbm: sample.levelDbfs,
            ),
          )
          .toList(),
      peakCount: peakCount,
      thresholdAboveNoiseDb: thresholdAboveNoiseDb,
    );
    return RealtimeSpectrumAnalysis(
      trace: trace,
      pointCount: generic.pointCount,
      startHz: generic.startHz,
      stopHz: generic.stopHz,
      minimumDbfs: generic.minimumDbm,
      maximumDbfs: generic.maximumDbm,
      noiseFloorDbfs: generic.noiseFloorDbm,
      peaks: generic.peaks
          .map(
            (peak) => RealtimeSpectrumPeak(
              frequencyHz: peak.frequencyHz,
              levelDbfs: peak.powerDbm,
              aboveNoiseDb: peak.aboveNoiseDb,
            ),
          )
          .toList(),
    );
  }

  static List<RealtimeSpectrumSample> downsample(
    List<RealtimeSpectrumSample> samples,
    int maximumPoints,
  ) {
    final generic = AgentSpectrumAnalyzer.downsample(
      samples
          .map(
            (sample) => AgentSpectrumPoint(
              frequencyHz: sample.frequencyHz,
              powerDbm: sample.levelDbfs,
            ),
          )
          .toList(),
      maximumPoints,
    );
    return generic
        .map(
          (point) => RealtimeSpectrumSample(
            frequencyHz: point.frequencyHz,
            levelDbfs: point.powerDbm,
          ),
        )
        .toList();
  }
}
