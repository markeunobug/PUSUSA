import 'package:flutter_pusu/phase_noise_models.dart';
import 'package:flutter_pusu/phase_noise_processor.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
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

    expect(dbcHz, closeTo(-120.0, 1e-9));
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
    expect(rawPoints.first.dbcHz, closeTo(-120.0, 1e-9));
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
    expect(rawPoints.single.dbcHz, closeTo(-112.5963731, 1e-6));
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
    expect(second.rawPoints.first.dbcHz, closeTo(-100.0, 1e-9));
    expect(second.averagePoints.first.dbcHz, first.averagePoints.first.dbcHz);
  });
}
