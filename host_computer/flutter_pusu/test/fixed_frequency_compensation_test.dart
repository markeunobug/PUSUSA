import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_pusu/fixed_frequency_compensation.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('uses the fifth preceding point when it exists', () {
    final data = _spots(60e6, 10e6, 120);
    final replacements = buildFixedFrequencyCompensationValues(data);

    expect(replacements[80e6], 0.0);
    expect(replacements[1.13e9], 102.0);
    expect(replacements[1.17e9], 106.0);
  });

  test('uses the furthest available preceding point when fewer than five exist',
      () {
    final data = _spots(50e6, 10e6, 8);
    final replacements = buildFixedFrequencyCompensationValues(
      data,
      targetsHz: const <double>[80e6],
    );

    expect(replacements[80e6], 0.0);
  });

  test('uses a following point only after a complete sweep is available', () {
    final partial = _spots(80e6, 10e6, 1);
    final hidden = applyFixedFrequencyCompensation(
      partial,
      const <double, double>{},
      targetsHz: const <double>[80e6],
    );
    expect(hidden, isEmpty);

    final complete = _spots(80e6, 10e6, 8);
    final replacements = buildFixedFrequencyCompensationValues(
      complete,
      targetsHz: const <double>[80e6],
    );
    final displayed = applyFixedFrequencyCompensation(
      complete,
      replacements,
      targetsHz: const <double>[80e6],
    );
    expect(displayed.first.x, 80e6);
    expect(displayed.first.y, 5.0);
  });

  test('does not use a following point before sweep completion', () {
    final data = _spots(80e6, 10e6, 8);
    final replacements = buildFixedFrequencyCompensationValues(
      data,
      targetsHz: const <double>[80e6],
      allowFollowingFallback: false,
    );
    final displayed = applyFixedFrequencyCompensation(
      data,
      replacements,
      targetsHz: const <double>[80e6],
    );

    expect(replacements, isEmpty);
    expect(displayed.any((spot) => spot.x == 80e6), isFalse);
  });

  test('keeps target frequency while replacing only its amplitude', () {
    final data = _spots(50e6, 10e6, 120);
    final replacements = buildFixedFrequencyCompensationValues(data);
    final displayed = applyFixedFrequencyCompensation(data, replacements);

    expect(displayed.firstWhere((spot) => spot.x == 80e6).y, 0.0);
    expect(displayed.firstWhere((spot) => spot.x == 1.13e9).y, 103.0);
    expect(displayed.firstWhere((spot) => spot.x == 1.17e9).y, 107.0);
  });

  test('does not alter a sweep that does not cover a target', () {
    final data = _spots(200e6, 10e6, 10);
    final replacements = buildFixedFrequencyCompensationValues(data);
    final displayed = applyFixedFrequencyCompensation(data, replacements);

    expect(displayed, data);
  });

  test('replaces the point nearest to a target when the grid is not exact', () {
    final data = _spots(55e6, 10e6, 10);
    final replacements = buildFixedFrequencyCompensationValues(
      data,
      targetsHz: const <double>[80e6],
    );
    final displayed = applyFixedFrequencyCompensation(
      data,
      replacements,
      targetsHz: const <double>[80e6],
    );

    expect(replacements.keys.single, 75e6);
    expect(displayed.firstWhere((spot) => spot.x == 75e6).y, 0.0);
  });

  test('compensates 79.5, 80, and 80.5 MHz independently', () {
    final data = _spots(75e6, 0.5e6, 20);
    final replacements = buildFixedFrequencyCompensationValues(data);
    final actualSpectrum = applyFixedFrequencyCompensation(data, replacements);

    expect(actualSpectrum.firstWhere((spot) => spot.x == 79.5e6).y, 4.0);
    expect(actualSpectrum.firstWhere((spot) => spot.x == 80e6).y, 5.0);
    expect(actualSpectrum.firstWhere((spot) => spot.x == 80.5e6).y, 6.0);
  });

  test('replacement follows a live noise-floor shift before sweep completion',
      () {
    final before = _spots(75e6, 0.5e6, 20);
    final after = <FlSpot>[
      for (final spot in before) FlSpot(spot.x, spot.y + 12.0),
    ];

    final beforeValues = buildFixedFrequencyCompensationValues(
      before,
      allowFollowingFallback: false,
    );
    final afterValues = buildFixedFrequencyCompensationValues(
      after,
      allowFollowingFallback: false,
    );

    expect(afterValues[79.5e6]! - beforeValues[79.5e6]!, 12.0);
    expect(afterValues[80e6]! - beforeValues[80e6]!, 12.0);
    expect(afterValues[80.5e6]! - beforeValues[80.5e6]!, 12.0);
  });
}

List<FlSpot> _spots(double startHz, double stepHz, int count) => <FlSpot>[
      for (var i = 0; i < count; i++)
        FlSpot(startHz + i * stepHz, i.toDouble()),
    ];
