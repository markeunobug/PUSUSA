import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_pusu/calibration_sweep_policy.dart';

void main() {
  group('CalibrationSweepPolicy', () {
    test('uses the selected aggressive span for each narrower RBW', () {
      expect(CalibrationSweepPolicy.spanHzForMode('300 kHz'), 2e6);
      expect(CalibrationSweepPolicy.spanHzForMode('100 kHz'), 600e3);
      expect(CalibrationSweepPolicy.spanHzForMode('30 kHz'), 200e3);
      expect(CalibrationSweepPolicy.spanHzForMode('10 kHz'), 40e3);
      expect(CalibrationSweepPolicy.spanHzForMode('1 kHz'), 5e3);
      expect(CalibrationSweepPolicy.spanHzForMode('1 MHz'), isNull);
    });

    test('retries only when peak power drops by more than 6 dB', () {
      expect(
        CalibrationSweepPolicy.shouldRetryForPowerDrop(
          previousPeakDbm: -20,
          currentPeakDbm: -26,
        ),
        isFalse,
      );
      expect(
        CalibrationSweepPolicy.shouldRetryForPowerDrop(
          previousPeakDbm: -20,
          currentPeakDbm: -26.01,
        ),
        isTrue,
      );
    });

    test('doubles the span for the single retry', () {
      expect(CalibrationSweepPolicy.retrySpanHz(600e3), 1.2e6);
    });
  });
}
