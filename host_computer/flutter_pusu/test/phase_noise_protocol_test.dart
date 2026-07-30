import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_pusu/phase_noise_models.dart';
import 'package:flutter_pusu/serial_port_manager.dart';
import 'package:flutter_pusu/serial_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

class FakeSerialPortManager extends SerialPortManager {
  final StreamController<Uint8List> controller =
      StreamController<Uint8List>.broadcast();
  final List<Uint8List> writes = <Uint8List>[];

  @override
  Stream<Uint8List> get stream => controller.stream;

  @override
  void sendData(Uint8List data) {
    writes.add(Uint8List.fromList(data));
  }
}

int crc16Modbus(Iterable<int> data) {
  var crc = 0xFFFF;
  for (final byte in data) {
    crc ^= byte;
    for (var i = 0; i < 8; i++) {
      if ((crc & 1) != 0) {
        crc = (crc >> 1) ^ 0xA001;
      } else {
        crc >>= 1;
      }
    }
  }
  return crc & 0xFFFF;
}

Uint8List buildFrame(int cmd, Uint8List payload) {
  final body = Uint8List(3 + payload.length);
  final bodyBytes = body.buffer.asByteData();
  bodyBytes.setUint16(0, payload.length, Endian.big);
  body[2] = cmd;
  body.setAll(3, payload);
  final crc = crc16Modbus(body);

  final frame = Uint8List(1 + body.length + 2 + 1);
  frame[0] = 0xAA;
  frame.setAll(1, body);
  final frameBytes = frame.buffer.asByteData();
  frameBytes.setUint16(1 + body.length, crc, Endian.big);
  frame[frame.length - 1] = 0x55;
  return frame;
}

Uint8List buildPhaseNoiseDataPayload({
  int version = 2,
  int flags = (1 << 1) | (1 << 5),
  int traceId = 0x1234,
  int plannedTotalPoints = 181,
  int currentIndex = 17,
  int averageIndex = 3,
  double carrierHz = 100000000.0,
  double carrierLevelDbm = -3.5,
  int offsetHz = 10000,
  double noisePowerDbm = -80.0,
  double phaseNoiseDbcHz = -120.0,
  int rbwHz = 1000,
  int errorCode = 0,
}) {
  final payload = Uint8List(42);
  final bytes = payload.buffer.asByteData();
  payload[0] = version;
  payload[1] = flags;
  bytes.setUint16(2, traceId, Endian.big);
  bytes.setUint16(4, plannedTotalPoints, Endian.big);
  bytes.setUint16(6, currentIndex, Endian.big);
  bytes.setUint16(8, averageIndex, Endian.big);
  bytes.setFloat64(10, carrierHz, Endian.little);
  bytes.setFloat32(18, carrierLevelDbm, Endian.little);
  bytes.setUint32(22, offsetHz, Endian.little);
  bytes.setFloat32(26, noisePowerDbm, Endian.little);
  bytes.setFloat32(30, phaseNoiseDbcHz, Endian.little);
  bytes.setUint32(34, rbwHz, Endian.little);
  payload[38] = errorCode;
  return payload;
}

Uint8List buildPhaseNoiseStatusPayload({
  int state = 3,
  int flags = (1 << 0) | (1 << 1) | (1 << 3),
  int errorCode = 0,
  int traceId = 0x1234,
  int plannedTotalPoints = 181,
  int currentIndex = 17,
  int averageIndex = 3,
  double nominalCarrierHz = 100000000.0,
  double measuredCarrierHz = 100000001.0,
  double carrierLevelDbm = -3.5,
  double startOffsetHz = 1000.0,
  double stopOffsetHz = 1000000.0,
  int currentOffsetHz = 10000,
  int currentRbwHz = 1000,
  int elapsedMs = 250,
  int warningCode = 0,
}) {
  final payload = Uint8List(64);
  final bytes = payload.buffer.asByteData();
  payload[0] = 1;
  payload[1] = state;
  payload[2] = flags;
  payload[3] = errorCode;
  bytes.setUint16(4, traceId, Endian.big);
  bytes.setUint16(6, plannedTotalPoints, Endian.big);
  bytes.setUint16(8, currentIndex, Endian.big);
  bytes.setUint16(10, averageIndex, Endian.big);
  bytes.setFloat64(12, nominalCarrierHz, Endian.little);
  bytes.setFloat64(20, measuredCarrierHz, Endian.little);
  bytes.setFloat32(28, carrierLevelDbm, Endian.little);
  bytes.setFloat64(32, startOffsetHz, Endian.little);
  bytes.setFloat64(40, stopOffsetHz, Endian.little);
  bytes.setUint32(48, currentOffsetHz, Endian.little);
  bytes.setUint32(52, currentRbwHz, Endian.little);
  bytes.setUint32(56, elapsedMs, Endian.little);
  bytes.setUint16(60, warningCode, Endian.little);
  return payload;
}

void main() {
  test('confirmed sweep stop waits for device ACK', () async {
    final manager = FakeSerialPortManager()..isConnected = true;
    final protocol = SerialProtocol(manager);

    final stopped = protocol.stopSweepConfirmed();
    expect(manager.writes, hasLength(1));
    expect(manager.writes.single[3], 0x0A);

    manager.controller.add(
      buildFrame(0x81, Uint8List.fromList([0x0A, 0x01, 0x00])),
    );
    expect(await stopped, isTrue);

    protocol.dispose();
    manager.controller.close();
  });

  test('phase-noise config payload uses config points per decade', () {
    final manager = FakeSerialPortManager()..isConnected = true;
    final protocol = SerialProtocol(manager);

    protocol.setPhaseNoiseConfig(
      const PhaseNoiseConfig(
        carrierMode: PhaseNoiseCarrierMode.manual,
        manualCarrierHz: 123000000.0,
        startOffsetHz: 1000.0,
        stopOffsetHz: 1000000.0,
        pointsPerDecade: 90,
        averageTarget: 7,
        sidebandMode: PhaseNoiseSidebandMode.lower,
        carrierSearchSpanHz: 250000.0,
        minimumCarrierLevelDbm: -42.0,
      ),
    );

    expect(manager.writes, hasLength(1));
    final frame = manager.writes.single;
    final payloadLength = frame.buffer.asByteData().getUint16(1, Endian.big);
    final payload = frame.sublist(4, 4 + payloadLength);
    final payloadBytes = payload.buffer.asByteData(
      payload.offsetInBytes,
      payload.length,
    );

    expect(frame[3], 0x0F);
    expect(payload, hasLength(36));
    expect(payload[0], 1);
    expect(payload[1] & (1 << 1), isNonZero);
    expect(payload[2], 0);
    expect(payload[3], 0);
    expect(payloadBytes.getFloat64(4, Endian.little), 123000000.0);
    expect(payloadBytes.getFloat64(12, Endian.little), 1000.0);
    expect(payloadBytes.getFloat64(20, Endian.little), 1000000.0);
    expect(payloadBytes.getUint16(28, Endian.little), 90);
    expect(payloadBytes.getUint16(30, Endian.little), 7);
    expect(payloadBytes.getUint16(32, Endian.little), 250);
    expect(payloadBytes.getInt8(34), -42);
    expect(payload[35], 0);

    protocol.dispose();
    manager.controller.close();
  });

  test('phase-noise config payload encodes default carrier acquisition fields',
      () {
    final manager = FakeSerialPortManager()..isConnected = true;
    final protocol = SerialProtocol(manager);

    protocol.setPhaseNoiseConfig(const PhaseNoiseConfig());

    expect(manager.writes, hasLength(1));
    final frame = manager.writes.single;
    final payloadLength = frame.buffer.asByteData().getUint16(1, Endian.big);
    final payload = frame.sublist(4, 4 + payloadLength);
    final payloadBytes = payload.buffer.asByteData(
      payload.offsetInBytes,
      payload.length,
    );

    expect(payload, hasLength(36));
    expect(payloadBytes.getUint16(28, Endian.little), 60);
    expect(payloadBytes.getUint16(30, Endian.little), 10);
    expect(payloadBytes.getUint16(32, Endian.little), 100);
    expect(payloadBytes.getInt8(34), -50);
    expect(payload[35], 0);

    protocol.dispose();
    manager.controller.close();
  });

  test('parses phase-noise data and status progress fields', () async {
    final manager = FakeSerialPortManager()..isConnected = true;
    final protocol = SerialProtocol(manager);

    final pointFuture = protocol.phaseNoiseStream.first;
    final statusFuture = protocol.phaseNoiseStatusStream.first;

    final dataPayload = buildPhaseNoiseDataPayload();
    final statusPayload = buildPhaseNoiseStatusPayload(warningCode: 2);

    manager.controller.add(buildFrame(0x86, dataPayload));
    manager.controller.add(buildFrame(0x87, statusPayload));

    final point = await pointFuture;
    final status = await statusFuture;

    expect(point.plannedTotalPoints, 181);
    expect(point.receivedPoints, 18);
    expect(point.currentIndex, 17);
    expect(point.averageIndex, 3);
    expect(point.containsRawMeasurement, isTrue);
    expect(point.carrierValid, isTrue);
    expect(point.phaseNoiseValid, isTrue);
    expect(point.phaseNoiseDbcHz, closeTo(-120.0, 1e-6));

    expect(status.plannedTotalPoints, 181);
    expect(status.receivedPoints, 18);
    expect(status.currentIndex, 17);
    expect(status.averageIndex, 3);
    expect(status.currentRbwHz, 1000);
    expect(status.warningCode, 2);

    protocol.dispose();
    manager.controller.close();
  });

  test('streams multiple phase-noise data frames with done and warning flags',
      () async {
    final manager = FakeSerialPortManager()..isConnected = true;
    final protocol = SerialProtocol(manager);

    final pointsFuture = protocol.phaseNoiseStream.take(3).toList();
    final frames = [
      buildFrame(
        0x86,
        buildPhaseNoiseDataPayload(
          plannedTotalPoints: 3,
          currentIndex: 0,
          averageIndex: 1,
          offsetHz: 1000,
          noisePowerDbm: -70.0,
          phaseNoiseDbcHz: -110.0,
        ),
      ),
      buildFrame(
        0x86,
        buildPhaseNoiseDataPayload(
          flags: (1 << 1) | (1 << 2) | (1 << 5),
          plannedTotalPoints: 3,
          currentIndex: 1,
          averageIndex: 1,
          offsetHz: 2000,
          noisePowerDbm: -72.0,
          phaseNoiseDbcHz: -112.0,
        ),
      ),
      buildFrame(
        0x86,
        buildPhaseNoiseDataPayload(
          flags: (1 << 0) | (1 << 1) | (1 << 5),
          plannedTotalPoints: 3,
          currentIndex: 2,
          averageIndex: 1,
          offsetHz: 5000,
          noisePowerDbm: -75.0,
          phaseNoiseDbcHz: -115.0,
        ),
      ),
    ];

    manager.controller
        .add(Uint8List.fromList(frames.expand((f) => f).toList()));

    final points = await pointsFuture;

    expect(points.map((p) => p.offsetHz), [1000, 2000, 5000]);
    expect(points.map((p) => p.receivedPoints), [1, 2, 3]);
    expect(points.map((p) => p.plannedTotalPoints), [3, 3, 3]);
    expect(points.map((p) => p.currentIndex), [0, 1, 2]);
    expect(points.map((p) => p.averageIndex), [1, 1, 1]);
    expect(points[0].done, isFalse);
    expect(points[1].warning, isTrue);
    expect(points[2].done, isTrue);
    expect(points[2].phaseNoiseDbcHz, closeTo(-115.0, 1e-6));

    protocol.dispose();
    manager.controller.close();
  });

  test('clamps phase-noise received point counts to planned totals', () async {
    final manager = FakeSerialPortManager()..isConnected = true;
    final protocol = SerialProtocol(manager);

    final pointFuture = protocol.phaseNoiseStream.first;
    final statusFuture = protocol.phaseNoiseStatusStream.first;

    manager.controller.add(
      buildFrame(
        0x86,
        buildPhaseNoiseDataPayload(
          plannedTotalPoints: 3,
          currentIndex: 12,
          averageIndex: 4,
        ),
      ),
    );
    manager.controller.add(
      buildFrame(
        0x87,
        buildPhaseNoiseStatusPayload(
          flags: (1 << 0) | (1 << 3) | (1 << 4) | (1 << 6),
          state: 5,
          plannedTotalPoints: 3,
          currentIndex: 12,
          averageIndex: 4,
          warningCode: 6,
        ),
      ),
    );

    final point = await pointFuture;
    final status = await statusFuture;

    expect(point.receivedPoints, 3);
    expect(point.currentIndex, 12);
    expect(point.averageIndex, 4);
    expect(point.progress.plannedTotalPoints, 3);
    expect(point.progress.receivedPoints, 3);

    expect(status.receivedPoints, 3);
    expect(status.currentIndex, 12);
    expect(status.averageIndex, 4);
    expect(status.complete, isTrue);
    expect(status.warning, isTrue);
    expect(status.warningCode, 6);

    protocol.dispose();
    manager.controller.close();
  });

  test('rejects invalid phase-noise parser payload lengths and versions', () {
    final manager = FakeSerialPortManager()..isConnected = true;
    final protocol = SerialProtocol(manager);

    expect(protocol.parsePhaseNoiseData(Uint8List(41)), isNull);
    expect(protocol.parsePhaseNoiseData(Uint8List(43)..[0] = 1), isNull);
    expect(protocol.parsePhaseNoiseStatus(Uint8List(63)), isNull);
    expect(protocol.parsePhaseNoiseStatus(Uint8List(65)..[0] = 1), isNull);

    final legacyData = protocol.parsePhaseNoiseData(
      buildPhaseNoiseDataPayload(version: 1),
    );
    final badDataVersion = buildPhaseNoiseDataPayload()..[0] = 3;
    final badStatusVersion = buildPhaseNoiseStatusPayload()..[0] = 2;
    expect(legacyData, isNotNull);
    expect(legacyData!.containsRawMeasurement, isFalse);
    expect(protocol.parsePhaseNoiseData(badDataVersion), isNull);
    expect(protocol.parsePhaseNoiseStatus(badStatusVersion), isNull);

    protocol.dispose();
    manager.controller.close();
  });

  test('builds a real-point trace from phase-noise data frames', () {
    final frames = [
      PhaseNoiseDataFrame(
        version: 2,
        flags: (1 << 1) | (1 << 5),
        traceId: 7,
        plannedTotalPoints: 4,
        receivedPoints: 1,
        currentIndex: 0,
        averageIndex: 1,
        carrierHz: 100000000.0,
        carrierLevelDbm: -4.0,
        offsetHz: 1000,
        noisePowerDbm: -70.0,
        phaseNoiseDbcHz: -110.0,
        rbwHz: 1000,
        errorCode: 0,
      ),
      PhaseNoiseDataFrame(
        version: 2,
        flags: (1 << 1) | (1 << 5),
        traceId: 7,
        plannedTotalPoints: 4,
        receivedPoints: 3,
        currentIndex: 2,
        averageIndex: 2,
        carrierHz: 100000000.0,
        carrierLevelDbm: -4.0,
        offsetHz: 10000,
        noisePowerDbm: -82.0,
        phaseNoiseDbcHz: -122.0,
        rbwHz: 1000,
        errorCode: 0,
      ),
      PhaseNoiseDataFrame(
        version: 2,
        flags: (1 << 1),
        traceId: 7,
        plannedTotalPoints: 4,
        receivedPoints: 4,
        currentIndex: 3,
        averageIndex: 2,
        carrierHz: 100000000.0,
        carrierLevelDbm: -4.0,
        offsetHz: 100000,
        noisePowerDbm: -90.0,
        phaseNoiseDbcHz: 0.0,
        rbwHz: 3000,
        errorCode: 7,
      ),
    ];

    final trace = PhaseNoiseTrace.fromDataFrames(frames);

    expect(trace.rawPoints, hasLength(3));
    expect(trace.averagePoints, isEmpty);
    expect(trace.completedAverages, 2);
    expect(trace.rawPoints.map((point) => point.offsetHz), [
      1000.0,
      10000.0,
      100000.0,
    ]);
    expect(trace.rawPoints.map((point) => point.dbcHz), [
      -110.0,
      -122.0,
      0.0,
    ]);
    expect(trace.rawPoints.map((point) => point.rbwHz), [
      1000.0,
      1000.0,
      3000.0,
    ]);
    expect(trace.rawPoints.map((point) => point.valid), [
      true,
      true,
      false,
    ]);
  });
}
