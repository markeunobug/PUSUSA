import 'package:flutter_pusu/agent/spectrum_analysis.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  List<AgentSpectrumPoint> points(List<double> powers) {
    return List<AgentSpectrumPoint>.generate(
      powers.length,
      (index) => AgentSpectrumPoint(
        frequencyHz: 100e6 + index * 1e6,
        powerDbm: powers[index],
      ),
    );
  }

  test('robust noise floor is not lifted by one strong peak', () {
    final input = points(<double>[
      -101,
      -100,
      -99,
      -100,
      -101,
      -100,
      -99,
      -100,
      -101,
      -10,
    ]);

    expect(AgentSpectrumAnalyzer.estimateNoiseFloor(input), closeTo(-100, 0.1));
  });

  test('analysis returns strongest separated local peaks in order', () {
    final analysis = AgentSpectrumAnalyzer.analyze(
      points(<double>[-100, -50, -100, -80, -100, -30, -100]),
      peakCount: 2,
      thresholdAboveNoiseDb: 10,
    );

    expect(analysis.peaks, hasLength(2));
    expect(analysis.peaks[0].powerDbm, -30);
    expect(analysis.peaks[1].powerDbm, -50);
  });

  test('peak threshold filters weak local maxima', () {
    final analysis = AgentSpectrumAnalyzer.analyze(
      points(<double>[-100, -96, -100, -80, -100]),
      peakCount: 5,
      thresholdAboveNoiseDb: 6,
    );

    expect(analysis.peaks.map((peak) => peak.powerDbm), contains(-80));
    expect(analysis.peaks.map((peak) => peak.powerDbm), isNot(contains(-96)));
  });

  test('peak-preserving downsample respects maximum point count', () {
    final input = points(List<double>.generate(1000, (index) => -100.0));
    input[456] = const AgentSpectrumPoint(
      frequencyHz: 556e6,
      powerDbm: -10,
    );

    final sampled = AgentSpectrumAnalyzer.downsample(input, 64);

    expect(sampled.length, lessThanOrEqualTo(64));
    expect(sampled.any((point) => point.powerDbm == -10), isTrue);
  });

  test('empty spectrum cannot be analyzed', () {
    expect(
      () => AgentSpectrumAnalyzer.analyze(const <AgentSpectrumPoint>[]),
      throwsArgumentError,
    );
  });
}
