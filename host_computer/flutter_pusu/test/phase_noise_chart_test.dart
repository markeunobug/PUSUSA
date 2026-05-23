import 'dart:math' as math;

import 'package:flutter/material.dart' as material;
import 'package:flutter_pusu/phase_noise_chart.dart';
import 'package:flutter_pusu/phase_noise_models.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('Y axis auto range includes high real phase-noise points', () {
    final range = PhaseNoiseYAxisRange.fromPoints(
      const [
        PhaseNoisePoint(
          offsetHz: 1000.0,
          noisePowerDbm: -58.0,
          dbcHz: -37.0,
          rbwHz: 1000.0,
          valid: true,
        ),
        PhaseNoisePoint(
          offsetHz: 2000.0,
          noisePowerDbm: -61.0,
          dbcHz: -40.0,
          rbwHz: 1000.0,
          valid: true,
        ),
      ],
    );

    expect(range.contains(-37.0), isTrue);
    expect(range.minDbcHz, lessThanOrEqualTo(-40.0));
    expect(range.maxDbcHz, greaterThanOrEqualTo(-37.0));
    expect(range.minDbcHz % 10.0, 0.0);
    expect(range.maxDbcHz % 10.0, 0.0);
  });

  test('Y axis auto range falls back when no visible points are present', () {
    final range = PhaseNoiseYAxisRange.fromPoints(const []);

    expect(range.minDbcHz, -140.0);
    expect(range.maxDbcHz, -80.0);
  });

  test('CSV export includes metadata, density, and raw/average points', () {
    const trace = PhaseNoiseTrace(
      rawPoints: [
        PhaseNoisePoint(
          offsetHz: 1000.0,
          noisePowerDbm: -60.0,
          dbcHz: -96.0,
          rbwHz: 1000.0,
          valid: true,
        ),
      ],
      averagePoints: [
        PhaseNoisePoint(
          offsetHz: 1000.0,
          noisePowerDbm: -61.0,
          dbcHz: -97.0,
          rbwHz: 1000.0,
          valid: true,
        ),
      ],
      completedAverages: 3,
      carrier: PhaseNoiseCarrier(
        nominalHz: 775000000.0,
        measuredHz: 775000000.0,
        levelDbm: -6.0,
        initialDeltaHz: 0.0,
        driftHz: 0.0,
      ),
    );

    final csv = PhaseNoiseCsvExporter.buildCsv(
      trace: trace,
      config: const PhaseNoiseConfig(rbwHz: 1000.0),
    );

    expect(csv, contains('metadata_key,metadata_value'));
    expect(csv, contains('carrier_hz,775000000.000'));
    expect(csv, contains('carrier_dbm,-6.00000000000'));
    expect(csv, contains('points_per_decade,60'));
    expect(csv, contains('planned_points,181'));
    expect(csv, contains('received_points,1'));
    expect(
        csv,
        contains(
            'offset_hz,raw_dbc_hz,avg_dbc_hz,noise_power_dbm,rbw_hz,valid,warning'));
    expect(
        csv,
        contains(
            '1000.00000000,-96.0000000000,-97.0000000000,-60.0000000000,1000.00000000,1,'));
  });

  test('CSV export preserves high point count traces', () {
    final rawPoints = List<PhaseNoisePoint>.generate(
      271,
      (index) => PhaseNoisePoint(
        offsetHz: 1000.0 + index * 100.0,
        noisePowerDbm: -60.0 - index / 10.0,
        dbcHz: -96.0 - index / 10.0,
        rbwHz: 1000.0,
        valid: true,
      ),
    );

    final csv = PhaseNoiseCsvExporter.buildCsv(
      trace: PhaseNoiseTrace(
        rawPoints: rawPoints,
        averagePoints: const [],
        completedAverages: 1,
      ),
      config: const PhaseNoiseConfig(pointsPerDecade: 90),
    );

    final dataRows = csv
        .split('\n')
        .where((line) => line.trim().isNotEmpty)
        .skipWhile((line) => !line.startsWith('offset_hz,'))
        .skip(1)
        .toList();

    expect(csv, contains('points_per_decade,90'));
    expect(csv, contains('received_points,271'));
    expect(dataRows, hasLength(271));
    expect(dataRows.last, contains('28000.0000000'));
  });

  testWidgets('marker snaps to a real trace point', (tester) async {
    PhaseNoiseMarker? marker;
    const trace = PhaseNoiseTrace(
      rawPoints: [
        PhaseNoisePoint(
          offsetHz: 1000.0,
          noisePowerDbm: -60.0,
          dbcHz: -96.0,
          rbwHz: 1000.0,
          valid: true,
        ),
        PhaseNoisePoint(
          offsetHz: 2000.0,
          noisePowerDbm: -62.0,
          dbcHz: -98.0,
          rbwHz: 1000.0,
          valid: true,
        ),
        PhaseNoisePoint(
          offsetHz: 10000.0,
          noisePowerDbm: -70.0,
          dbcHz: -106.0,
          rbwHz: 1000.0,
          valid: true,
        ),
      ],
      averagePoints: [],
      completedAverages: 1,
    );

    await tester.pumpWidget(
      material.MaterialApp(
        home: material.SizedBox(
          width: 600,
          height: 360,
          child: PhaseNoiseChart(
            trace: trace,
            config: const PhaseNoiseConfig(),
            traceDisplay: PhaseNoiseTraceDisplay.raw,
            minOffsetHz: 1000.0,
            maxOffsetHz: 10000.0,
            onMarkerChanged: (value) {
              marker = value;
            },
          ),
        ),
      ),
    );

    const targetOffsetHz = 2000.0;
    final chartTopLeft = tester.getTopLeft(find.byType(PhaseNoiseChart));
    final chartSize = tester.getSize(find.byType(PhaseNoiseChart));
    final ratio =
        math.log(targetOffsetHz / 1000.0) / math.log(10000.0 / 1000.0);
    final innerChartWidth = chartSize.width - 32.0;
    final tapX = 16.0 + 72.0 + ratio * (innerChartWidth - 72.0);
    await tester.tapAt(
      chartTopLeft + material.Offset(tapX, chartSize.height * 0.58),
    );
    await tester.pump();

    expect(marker, isNotNull);
    expect(marker!.offsetHz, 2000.0);
    expect(marker!.dbcHz, -98.0);
  });
}
