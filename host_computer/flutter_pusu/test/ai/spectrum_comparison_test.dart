import 'package:flutter_pusu/agent/spectrum_analysis.dart';
import 'package:flutter_pusu/agent/spectrum_comparison.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  List<AgentSpectrumPoint> trace(
    List<double> powers, {
    double startHz = 100,
    double stepHz = 10,
  }) {
    return List<AgentSpectrumPoint>.generate(
      powers.length,
      (index) => AgentSpectrumPoint(
        frequencyHz: startHz + index * stepHz,
        powerDbm: powers[index],
      ),
    );
  }

  test('comparison interpolates frequency grids and reports second minus first',
      () {
    final first = trace(<double>[-100, -80, -100, -60, -100]);
    final second = trace(
      <double>[-98, -78, -98, -58, -98],
      startHz: 100,
      stepHz: 10,
    );

    final comparison = AgentSpectrumComparator.compare(first, second);

    expect(comparison.comparedPointCount, 5);
    expect(comparison.meanDeltaDb, closeTo(2, 0.001));
    expect(comparison.maximumAbsoluteDeltaDb, closeTo(2, 0.001));
  });

  test('comparison rejects non-overlapping traces', () {
    expect(
      () => AgentSpectrumComparator.compare(
        trace(<double>[-100, -90]),
        trace(<double>[-100, -90], startHz: 1000),
      ),
      throwsArgumentError,
    );
  });

  test('limit evaluator returns pass for compliant spectrum', () {
    final evaluation = AgentSpectrumLimitEvaluator.evaluate(
      trace(<double>[-100, -20, -100, -70, -100, -100, -100]),
      maximumNoiseFloorDbm: -95,
      minimumMainPeakDbm: -25,
      minimumSpurSuppressionDb: 40,
    );

    expect(evaluation.passed, isTrue);
    expect(evaluation.checks, hasLength(3));
  });

  test('limit evaluator returns fail when main peak is too weak', () {
    final evaluation = AgentSpectrumLimitEvaluator.evaluate(
      trace(<double>[-100, -40, -100, -80, -100]),
      minimumMainPeakDbm: -30,
    );

    expect(evaluation.passed, isFalse);
  });
}
