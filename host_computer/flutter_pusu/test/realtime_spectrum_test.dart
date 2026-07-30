import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_pusu/realtime_spectrum_models.dart';
import 'package:flutter_pusu/realtime_spectrum_processor.dart';

void main() {
  test('realtime FFT v1 data parser verifies exact payload and little endian',
      () {
    final bytes = Uint8List(RealtimeSpectrumFrame.payloadLength);
    final b = bytes.buffer.asByteData();
    bytes[0] = 1;
    bytes[1] = 1;
    bytes[2] = 1;
    bytes[3] = 0;
    b.setUint32(4, 7, Endian.little);
    b.setFloat64(8, 775e6, Endian.little);
    b.setUint32(16, 130000000, Endian.little);
    b.setUint32(20, 4096, Endian.little);
    b.setUint16(24, 1103, Endian.big);
    b.setUint16(26, 315, Endian.big);
    b.setFloat32(36, -77.5, Endian.little);
    b.setFloat32(36 + 314 * 4, -22, Endian.little);
    final f = RealtimeSpectrumCodec.parseData(bytes)!;
    expect(f.windowId, 1);
    expect(f.amplitudeUnit, 1);
    expect(f.sequence, 7);
    expect(f.rawDbfs.length, 315);
    expect(f.rawDbfs.first, closeTo(-77.5, .001));
    expect(f.frequencyHz(0), closeTo(775e6 + 1103 * 130e6 / 4096 - 40e6, .01));
    expect(
        RealtimeSpectrumCodec.parseData(
            Uint8List.sublistView(bytes, 0, bytes.length - 1)),
        isNull);
  });
  test('average uses relative linear domain and max hold uses dBFS maximum',
      () {
    final p = RealtimeSpectrumProcessor(waterfallRows: 2);
    RealtimeSpectrumFrame f(double db) => RealtimeSpectrumFrame(
        windowId: 1,
        amplitudeUnit: 1,
        errorCode: 0,
        sequence: 1,
        centerHz: 100e6,
        sampleRateHz: 130000000,
        fftSize: 4096,
        firstBin: 0,
        droppedFrames: 0,
        framesEmitted: 1,
        rawDbfs: List.filled(315, db));
    p.add(f(-30));
    p.add(f(-20));
    expect(p.average!.first, closeTo(-22.596, .01));
    expect(p.maxHold!.first, -20);
  });
  test('waterfall row zero is newest and overflow removes oldest tail', () {
    final p = RealtimeSpectrumProcessor(waterfallRows: 2);
    RealtimeSpectrumFrame f(double db) => RealtimeSpectrumFrame(
        windowId: 1,
        amplitudeUnit: 1,
        errorCode: 0,
        sequence: 1,
        centerHz: 100e6,
        sampleRateHz: 130000000,
        fftSize: 4096,
        firstBin: 0,
        droppedFrames: 0,
        framesEmitted: 1,
        rawDbfs: List.filled(315, db));
    p.add(f(-30));
    p.add(f(-20));
    expect(p.waterfall.map((row) => row.first), [-20, -30]);
    p.add(f(-10));
    expect(p.waterfall.map((row) => row.first), [-10, -20]);
  });
  test('waterfall display normalization clamps at floor and reference', () {
    expect(
        normalizeWaterfallLevel(-180, floorDbfs: -140, referenceDbfs: -30), 0);
    expect(
        normalizeWaterfallLevel(-140, floorDbfs: -140, referenceDbfs: -30), 0);
    expect(normalizeWaterfallLevel(-85, floorDbfs: -140, referenceDbfs: -30),
        closeTo(.5, 1e-12));
    expect(
        normalizeWaterfallLevel(-30, floorDbfs: -140, referenceDbfs: -30), 1);
    expect(normalizeWaterfallLevel(10, floorDbfs: -140, referenceDbfs: -30), 1);
    expect(
        () => normalizeWaterfallLevel(-80, floorDbfs: -30, referenceDbfs: -30),
        throwsArgumentError);
  });
  test('terminal gate permits only IDLE NONE or STOPPED before reconfigure',
      () {
    RealtimeSpectrumStatus status(int error) {
      final bytes = Uint8List(28);
      bytes[0] = 1;
      bytes[1] = 0;
      bytes[3] = error;
      return RealtimeSpectrumCodec.parseStatus(bytes)!;
    }

    // This is the exact pure predicate called by RealtimeSpectrumPage._waitForIdle.
    expect(status(0).permitsReconfiguration, isTrue);
    expect(status(10).permitsReconfiguration, isTrue);
    expect(status(11).permitsReconfiguration, isFalse);
    expect(status(7).permitsReconfiguration, isFalse);
  });
}
