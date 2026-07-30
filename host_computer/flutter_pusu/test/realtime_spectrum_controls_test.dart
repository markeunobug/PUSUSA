import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_pusu/realtime_spectrum_controls.dart';

void main() {
  test('reference level is a raw dBFS display range with linked waterfall range', () {
    final range = realtimeDisplayRange(-30);
    expect(range.referenceDbfs, -30);
    expect(range.minDbfs, -160);
    expect(range.waterfallReferenceDbfs, -30);
    expect(range.waterfallFloorDbfs, -140);
  });

  test('reference level clamps to the display-only raw dBFS bounds', () {
    final high = realtimeDisplayRange(5);
    expect(high.referenceDbfs, 0);
    expect(high.waterfallFloorDbfs, -110);
    final low = realtimeDisplayRange(-200);
    expect(low.referenceDbfs, -140);
    expect(low.minDbfs, -160);
    expect(low.waterfallFloorDbfs, -160);
  });
}
