import 'dart:math' as math;

import 'package:flutter_pusu/phase_noise_models.dart';
import 'package:flutter_pusu/phase_noise_processor.dart';
import 'package:flutter_test/flutter_test.dart';

const double _enbw10kHz = 18695.7919;

double _expectedDbcPerHz(double noisePowerDbm, double carrierLevelDbm) {
  return noisePowerDbm -
      carrierLevelDbm -
      10.0 * math.log(_enbw10kHz) / math.ln10;
}

void main() {
  test('phase-noise configuration rejects offsets below 1 kHz', () {
    const config = PhaseNoiseConfig(
      startOffsetHz: 999.0,
      stopOffsetHz: 1000000.0,
    );

    expect(config.isValid, isFalse);
    expect(config.estimatedPointCount, 0);
  });

  test('default density estimates 181 points from 1 kHz to 1 MHz', () {
    const config = PhaseNoiseConfig(
      startOffsetHz: 1000.0,
      stopOffsetHz: 1000000.0,
    );

    expect(config.pointsPerDecade, 60);
    expect(config.estimatedPointCount, 181);
  });

  test('converts dBm to dBc/Hz using ENBW', () {
    const processor = PhaseNoiseProcessor(
      PhaseNoiseConfig(
        rbwHz: 10000.0,
        startOffsetHz: 10000.0,
        stopOffsetHz: 100000.0,
      ),
    );

    final dbcHz = processor.dbmToDbcPerHz(
      noisePowerDbm: -80.0,
      carrierLevelDbm: 0.0,
    );

    expect(dbcHz, closeTo(_expectedDbcPerHz(-80.0, 0.0), 1e-9));
  });

  test('finds automatic carrier from strongest sweep point', () {
    const processor = PhaseNoiseProcessor(PhaseNoiseConfig());

    final carrier = processor.findCarrier([
      const PhaseNoiseSweepPoint(frequencyHz: 99000000.0, powerDbm: -40.0),
      const PhaseNoiseSweepPoint(frequencyHz: 100000000.0, powerDbm: -3.0),
      const PhaseNoiseSweepPoint(frequencyHz: 101000000.0, powerDbm: -45.0),
    ]);

    expect(carrier, isNotNull);
    expect(carrier!.nominalHz, 100000000.0);
    expect(carrier.measuredHz, 100000000.0);
    expect(carrier.levelDbm, -3.0);
  });

  test('manual carrier keeps nominal frequency and measures nearby peak', () {
    const processor = PhaseNoiseProcessor(
      PhaseNoiseConfig(
        carrierMode: PhaseNoiseCarrierMode.manual,
        manualCarrierHz: 100000000.0,
        manualCarrierSearchWindowHz: 2000.0,
      ),
    );

    final carrier = processor.findCarrier([
      const PhaseNoiseSweepPoint(frequencyHz: 99999000.0, powerDbm: -2.0),
      const PhaseNoiseSweepPoint(frequencyHz: 99950000.0, powerDbm: 1.0),
    ]);

    expect(carrier, isNotNull);
    expect(carrier!.nominalHz, 100000000.0);
    expect(carrier.measuredHz, 99999000.0);
    expect(carrier.initialDeltaHz, -1000.0);
  });

  test('manual carrier without search window uses nearest frequency point', () {
    const processor = PhaseNoiseProcessor(
      PhaseNoiseConfig(
        carrierMode: PhaseNoiseCarrierMode.manual,
        manualCarrierHz: 100000000.0,
      ),
    );

    final carrier = processor.findCarrier([
      const PhaseNoiseSweepPoint(frequencyHz: 99999000.0, powerDbm: -5.0),
      const PhaseNoiseSweepPoint(frequencyHz: 100020000.0, powerDbm: 5.0),
    ]);

    expect(carrier, isNotNull);
    expect(carrier!.measuredHz, 99999000.0);
    expect(carrier.levelDbm, -5.0);
  });

  test('converts upper sideband frequencies into offset points', () {
    const processor = PhaseNoiseProcessor(
      PhaseNoiseConfig(
        startOffsetHz: 10000.0,
        stopOffsetHz: 40000.0,
        rbwHz: 10000.0,
      ),
    );
    const carrier = PhaseNoiseCarrier(
      nominalHz: 100000000.0,
      measuredHz: 100000000.0,
      levelDbm: 0.0,
      initialDeltaHz: 0.0,
      driftHz: 0.0,
    );

    final rawPoints = processor.convertSweepPoints([
      const PhaseNoiseSweepPoint(frequencyHz: 99990000.0, powerDbm: -60.0),
      const PhaseNoiseSweepPoint(frequencyHz: 100000000.0, powerDbm: 0.0),
      const PhaseNoiseSweepPoint(frequencyHz: 100010000.0, powerDbm: -80.0),
      const PhaseNoiseSweepPoint(frequencyHz: 100040000.0, powerDbm: -90.0),
      const PhaseNoiseSweepPoint(frequencyHz: 100050000.0, powerDbm: -95.0),
    ], carrier);

    expect(rawPoints.map((p) => p.offsetHz), [10000.0, 40000.0]);
    expect(
      rawPoints.first.dbcHz,
      closeTo(_expectedDbcPerHz(-80.0, 0.0), 1e-9),
    );
    expect(rawPoints.every((p) => p.valid), isTrue);
  });

  test('both-sideband mode averages paired powers in linear domain', () {
    const processor = PhaseNoiseProcessor(
      PhaseNoiseConfig(
        startOffsetHz: 10000.0,
        stopOffsetHz: 10000.0,
        rbwHz: 10000.0,
        sidebandMode: PhaseNoiseSidebandMode.both,
      ),
    );
    const carrier = PhaseNoiseCarrier(
      nominalHz: 100000000.0,
      measuredHz: 100000000.0,
      levelDbm: 0.0,
      initialDeltaHz: 0.0,
      driftHz: 0.0,
    );

    final rawPoints = processor.convertSweepPoints([
      const PhaseNoiseSweepPoint(frequencyHz: 99990000.0, powerDbm: -80.0),
      const PhaseNoiseSweepPoint(frequencyHz: 100010000.0, powerDbm: -70.0),
    ], carrier);

    expect(rawPoints, hasLength(1));
    expect(rawPoints.single.noisePowerDbm, closeTo(-72.5963731, 1e-6));
    expect(
      rawPoints.single.dbcHz,
      closeTo(_expectedDbcPerHz(-72.5963731, 0.0), 1e-6),
    );
  });

  test('averages traces in linear domain using previous average count', () {
    const processor = PhaseNoiseProcessor(PhaseNoiseConfig());

    final averaged = processor.averageTrace(
      [
        const PhaseNoisePoint(
          offsetHz: 10000.0,
          noisePowerDbm: -60.0,
          dbcHz: -100.0,
          rbwHz: 10000.0,
          valid: true,
        ),
      ],
      [
        const PhaseNoisePoint(
          offsetHz: 10000.0,
          noisePowerDbm: -50.0,
          dbcHz: -90.0,
          rbwHz: 10000.0,
          valid: true,
        ),
      ],
      previousAverageCount: 3,
    );

    final expected = PhaseNoiseProcessor.linearToDb(
      (3 * PhaseNoiseProcessor.dbcHzToLinear(-100.0) +
              PhaseNoiseProcessor.dbcHzToLinear(-90.0)) /
          4,
    );
    expect(averaged.single.dbcHz, closeTo(expected, 1e-9));
    expect(averaged.single.dbcHz, isNot(closeTo(-97.5, 1e-9)));
  });

  test('rolling average keeps the latest N raw samples in linear domain', () {
    final averager = PhaseNoiseRollingAverager(windowSize: 2);

    PhaseNoisePoint point(double dbcHz, double noisePowerDbm) {
      return PhaseNoisePoint(
        offsetHz: 10000.0,
        noisePowerDbm: noisePowerDbm,
        dbcHz: dbcHz,
        rbwHz: 1000.0,
        valid: true,
      );
    }

    final first = averager.add(point(-100.0, -60.0));
    final second = averager.add(point(-90.0, -50.0));
    final third = averager.add(point(-80.0, -40.0));

    expect(first.dbcHz, closeTo(-100.0, 1e-9));
    expect(second.dbcHz, closeTo(-92.5963731, 1e-6));
    expect(second.noisePowerDbm, closeTo(-52.5963731, 1e-6));
    expect(third.dbcHz, closeTo(-82.5963731, 1e-6));
    expect(third.noisePowerDbm, closeTo(-42.5963731, 1e-6));
    expect(averager.sampleCountForOffset(10000.0), 2);
  });

  test('rolling average keeps offsets independent and reset clears history',
      () {
    final averager = PhaseNoiseRollingAverager(windowSize: 3);
    const firstOffset = PhaseNoisePoint(
      offsetHz: 1000.0,
      noisePowerDbm: -60.0,
      dbcHz: -100.0,
      rbwHz: 1000.0,
      valid: true,
    );
    const secondOffset = PhaseNoisePoint(
      offsetHz: 2000.0,
      noisePowerDbm: -50.0,
      dbcHz: -90.0,
      rbwHz: 1000.0,
      valid: true,
    );

    averager.add(firstOffset);
    averager.add(secondOffset);
    expect(averager.sampleCountForOffset(1000.0), 1);
    expect(averager.sampleCountForOffset(2000.0), 1);

    averager.reset(windowSize: 2);
    expect(averager.windowSize, 2);
    expect(averager.sampleCountForOffset(1000.0), 0);
    expect(averager.add(secondOffset).dbcHz, closeTo(-90.0, 1e-9));
  });

  test('processSweep emits boundary warnings', () {
    const processor = PhaseNoiseProcessor(
      PhaseNoiseConfig(
        startOffsetHz: 1000.0,
        stopOffsetHz: 3000.0,
        rbwHz: 10000.0,
        minimumCarrierLevelDbm: -10.0,
      ),
    );

    final trace = processor.processSweep([
      const PhaseNoiseSweepPoint(frequencyHz: 100000000.0, powerDbm: -20.0),
      const PhaseNoiseSweepPoint(frequencyHz: 100001000.0, powerDbm: -80.0),
      const PhaseNoiseSweepPoint(frequencyHz: 100002000.0, powerDbm: -81.0),
    ]);

    expect(
      trace.warnings.map((warning) => warning.code),
      containsAll([
        PhaseNoiseWarningCode.offsetBelowRbw,
        PhaseNoiseWarningCode.weakCarrier,
        PhaseNoiseWarningCode.insufficientValidPoints,
      ]),
    );
    expect(trace.rawPoints.every((point) => point.valid), isFalse);
  });

  test('processSweep stops updating average after target count', () {
    const processor = PhaseNoiseProcessor(
      PhaseNoiseConfig(
        startOffsetHz: 10000.0,
        stopOffsetHz: 30000.0,
        rbwHz: 10000.0,
        averageTarget: 1,
      ),
    );

    final first = processor.processSweep([
      const PhaseNoiseSweepPoint(frequencyHz: 100000000.0, powerDbm: 0.0),
      const PhaseNoiseSweepPoint(frequencyHz: 100010000.0, powerDbm: -80.0),
      const PhaseNoiseSweepPoint(frequencyHz: 100020000.0, powerDbm: -81.0),
      const PhaseNoiseSweepPoint(frequencyHz: 100030000.0, powerDbm: -82.0),
    ]);
    final second = processor.processSweep(
      [
        const PhaseNoiseSweepPoint(frequencyHz: 100000000.0, powerDbm: 0.0),
        const PhaseNoiseSweepPoint(frequencyHz: 100010000.0, powerDbm: -60.0),
        const PhaseNoiseSweepPoint(frequencyHz: 100020000.0, powerDbm: -61.0),
        const PhaseNoiseSweepPoint(frequencyHz: 100030000.0, powerDbm: -62.0),
      ],
      previousTrace: first,
    );

    expect(first.completedAverages, 1);
    expect(second.completedAverages, 1);
    expect(
      second.rawPoints.first.dbcHz,
      closeTo(_expectedDbcPerHz(-60.0, 0.0), 1e-9),
    );
    expect(second.averagePoints.first.dbcHz, first.averagePoints.first.dbcHz);
  });
}
