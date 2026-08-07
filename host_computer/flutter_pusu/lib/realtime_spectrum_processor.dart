import 'dart:math' as math;
import 'realtime_spectrum_models.dart';

/// Maps a raw dBFS value onto the waterfall color range.
///
/// This is display-only: it does not alter received samples or averaging.
double normalizeWaterfallLevel(
  double dbfs, {
  required double floorDbfs,
  required double referenceDbfs,
}) {
  if (!dbfs.isFinite ||
      !floorDbfs.isFinite ||
      !referenceDbfs.isFinite ||
      floorDbfs >= referenceDbfs) {
    throw ArgumentError('Waterfall floor must be below reference');
  }
  return ((dbfs - floorDbfs) / (referenceDbfs - floorDbfs))
      .clamp(0.0, 1.0)
      .toDouble();
}

/// Averages dBFS values through a relative linear-power domain, then returns dBFS.
class RealtimeSpectrumProcessor {
  RealtimeSpectrumProcessor({this.waterfallRows = 240});
  final int waterfallRows;
  List<double>? latest, average, maxHold;
  final List<List<double>> _waterfall = [];
  final List<RealtimeSpectrumWaterfallRow> _waterfallHistory = [];
  int averageCount = 0;
  List<List<double>> get waterfall => List.unmodifiable(_waterfall);
  List<RealtimeSpectrumWaterfallRow> get waterfallHistory =>
      List.unmodifiable(_waterfallHistory);
  void reset() {
    latest = average = maxHold = null;
    _waterfall.clear();
    _waterfallHistory.clear();
    averageCount = 0;
  }

  void resetAverage() {
    average = null;
    averageCount = 0;
  }

  void resetMaxHold() => maxHold = null;
  void add(RealtimeSpectrumFrame frame,
      {bool averageEnabled = true,
      bool maxHoldEnabled = true,
      DateTime? capturedAtUtc}) {
    latest = List.unmodifiable(frame.rawDbfs);
    if (averageEnabled) {
      final old = average;
      final n = averageCount;
      average =
          List.unmodifiable(List<double>.generate(frame.rawDbfs.length, (i) {
        final linear = math.pow(10.0, frame.rawDbfs[i] / 10.0).toDouble();
        final previousLinear =
            old == null ? 0.0 : math.pow(10.0, old[i] / 10.0).toDouble();
        return 10.0 *
            math.log((previousLinear * n + linear) / (n + 1)) /
            math.ln10;
      }));
      averageCount++;
    }
    if (maxHoldEnabled) {
      maxHold = List.unmodifiable(List<double>.generate(
          frame.rawDbfs.length,
          (i) => maxHold == null
              ? frame.rawDbfs[i]
              : math.max(maxHold![i], frame.rawDbfs[i])));
    }
    // Row zero is always the newest frame; history advances downward.
    final levels = List<double>.unmodifiable(frame.rawDbfs);
    _waterfall.insert(0, levels);
    _waterfallHistory.insert(
      0,
      RealtimeSpectrumWaterfallRow(
        capturedAtUtc: (capturedAtUtc ?? DateTime.now().toUtc()).toUtc(),
        sequence: frame.sequence,
        framesEmitted: frame.framesEmitted,
        centerHz: frame.centerHz,
        sampleRateHz: frame.sampleRateHz,
        fftSize: frame.fftSize,
        firstBin: frame.firstBin,
        levelsDbfs: levels,
      ),
    );
    if (_waterfall.length > waterfallRows) {
      _waterfall.removeLast();
      _waterfallHistory.removeLast();
    }
  }
}

/// One retained waterfall row, newest first in [RealtimeSpectrumProcessor].
class RealtimeSpectrumWaterfallRow {
  const RealtimeSpectrumWaterfallRow({
    required this.capturedAtUtc,
    required this.sequence,
    required this.framesEmitted,
    required this.centerHz,
    required this.sampleRateHz,
    required this.fftSize,
    required this.firstBin,
    required this.levelsDbfs,
  });

  final DateTime capturedAtUtc;
  final int sequence;
  final int framesEmitted;
  final double centerHz;
  final int sampleRateHz;
  final int fftSize;
  final int firstBin;
  final List<double> levelsDbfs;

  double frequencyHz(int index) =>
      centerHz + (firstBin + index) * sampleRateHz / fftSize - 40e6;
}
