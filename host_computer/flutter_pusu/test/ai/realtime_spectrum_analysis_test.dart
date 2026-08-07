import 'package:flutter_pusu/agent/realtime_spectrum_analysis.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  List<RealtimeSpectrumSample> samples(List<double> levels) {
    return List<RealtimeSpectrumSample>.generate(
      levels.length,
      (index) => RealtimeSpectrumSample(
        frequencyHz: 770e6 + index * 100e3,
        levelDbfs: levels[index],
      ),
    );
  }

  test('realtime analysis preserves dBFS semantics and trace name', () {
    final analysis = RealtimeSpectrumAnalyzer.analyze(
      samples(<double>[-100, -30, -100, -60, -100]),
      trace: 'average',
      peakCount: 2,
      thresholdAboveNoiseDb: 6,
    );

    expect(analysis.trace, 'average');
    expect(analysis.maximumDbfs, -30);
    expect(analysis.peaks.first.levelDbfs, -30);
    expect(analysis.toJson()['amplitude_unit'], 'dBFS');
  });

  test('realtime downsample preserves a narrow strongest bin', () {
    final input = samples(List<double>.filled(315, -100));
    input[157] = const RealtimeSpectrumSample(
      frequencyHz: 785.7e6,
      levelDbfs: -10,
    );

    final result = RealtimeSpectrumAnalyzer.downsample(input, 64);

    expect(result, hasLength(64));
    expect(result.any((sample) => sample.levelDbfs == -10), isTrue);
  });
}
