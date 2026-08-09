import 'package:fl_chart/fl_chart.dart';

const List<double> fixedFrequencyCompensationTargetsHz = <double>[
  79.5e6,
  80e6,
  80.5e6,
  1.13e9,
  1.17e9,
];

const List<double> fixedFrequencyCompensation300kAdditionalTargetsHz = <double>[
  79.85e6,
  80.15e6,
];

List<double> fixedFrequencyCompensationTargetsForRbw(double rbwHz) {
  if ((rbwHz - 300e3).abs() <= 1.0) {
    return <double>[
      ...fixedFrequencyCompensationTargetsHz,
      ...fixedFrequencyCompensation300kAdditionalTargetsHz,
    ];
  }
  return fixedFrequencyCompensationTargetsHz;
}

const int fixedFrequencyCompensationLookbackPoints = 5;

/// Builds the replacement values after a complete sweep is available.
///
/// A target normally uses the point five positions before it. When fewer than
/// five preceding points exist, the furthest available preceding point is
/// used. If there is no preceding point, the furthest available point up to
/// five positions after it is used. The latter case is intentionally only
/// called after a complete sweep so a leading target is not shown prematurely.
Map<double, double> buildFixedFrequencyCompensationValues(
  List<FlSpot> data, {
  List<double> targetsHz = fixedFrequencyCompensationTargetsHz,
  int lookbackPoints = fixedFrequencyCompensationLookbackPoints,
  bool allowFollowingFallback = true,
}) {
  if (data.isEmpty || lookbackPoints <= 0) return <double, double>{};

  final sorted = List<FlSpot>.from(data)..sort((a, b) => a.x.compareTo(b.x));
  final replacements = <double, double>{};
  final usedIndices = <int>{};

  for (final targetHz in targetsHz) {
    if (targetHz < sorted.first.x || targetHz > sorted.last.x) continue;

    final targetIndex = _closestIndex(sorted, targetHz);
    if (!usedIndices.add(targetIndex)) continue;

    final sourceIndex = targetIndex >= lookbackPoints
        ? targetIndex - lookbackPoints
        : targetIndex > 0
            ? 0
            : allowFollowingFallback && sorted.length > 1
                ? (lookbackPoints < sorted.length
                    ? lookbackPoints
                    : sorted.length - 1)
                : -1;
    if (sourceIndex >= 0) {
      replacements[sorted[targetIndex].x] = sorted[sourceIndex].y;
    }
  }
  return replacements;
}

/// Applies replacement values to the current spectrum data.
///
/// A target without a cached replacement is omitted. This keeps a leading
/// target hidden while its first complete sweep is still being assembled.
List<FlSpot> applyFixedFrequencyCompensation(
  List<FlSpot> data,
  Map<double, double> replacements, {
  List<double> targetsHz = fixedFrequencyCompensationTargetsHz,
}) {
  if (data.isEmpty) return data;

  final sorted = List<FlSpot>.from(data)..sort((a, b) => a.x.compareTo(b.x));
  final targetIndices = <int, double>{};
  for (final targetHz in targetsHz) {
    if (targetHz < sorted.first.x || targetHz > sorted.last.x) continue;
    targetIndices[_closestIndex(sorted, targetHz)] = targetHz;
  }

  return [
    for (var i = 0; i < sorted.length; i++)
      if (!targetIndices.containsKey(i))
        sorted[i]
      else if (replacements.containsKey(sorted[i].x))
        FlSpot(sorted[i].x, replacements[sorted[i].x]!)
  ];
}

int _closestIndex(List<FlSpot> data, double targetHz) {
  var closestIndex = 0;
  var closestDistance = (data.first.x - targetHz).abs();
  for (var i = 1; i < data.length; i++) {
    final distance = (data[i].x - targetHz).abs();
    if (distance < closestDistance) {
      closestIndex = i;
      closestDistance = distance;
    }
  }
  return closestIndex;
}
