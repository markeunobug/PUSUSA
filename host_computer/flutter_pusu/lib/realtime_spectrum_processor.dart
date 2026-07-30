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
  int averageCount = 0;
  List<List<double>> get waterfall => List.unmodifiable(_waterfall);
  void reset() {
    latest = average = maxHold = null;
    _waterfall.clear();
    averageCount = 0;
  }

  void resetAverage() {
    average = null;
    averageCount = 0;
  }

  void resetMaxHold() => maxHold = null;
  void add(RealtimeSpectrumFrame frame,
      {bool averageEnabled = true, bool maxHoldEnabled = true}) {
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
    _waterfall.insert(0, List.unmodifiable(frame.rawDbfs));
    if (_waterfall.length > waterfallRows) {
      _waterfall.removeLast();
    }
  }
}
