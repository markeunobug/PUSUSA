import 'package:flutter_pusu/frequency_format.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('marker GHz display preserves kHz-level changes', () {
    expect(formatMarkerFreqAutoUnit(1000005000.0), '1.000005 GHz');
    expect(formatMarkerFreqAutoUnit(1000500000.0), '1.000500 GHz');
  });

  test('frequency input keeps useful precision without trailing zeros', () {
    expect(formatFreqInput(1000005000.0, 1e9), '1.000005');
    expect(formatFreqInput(1000000000.0, 1e9), '1');
  });
}
