import 'dart:async';
import 'dart:typed_data';

import 'package:fl_chart/fl_chart.dart';

import 'device_models.dart';
import 'serial_port_manager.dart';

class SpectrumSegment {
  final int timestamp;
  final List<FlSpot> spots;

  const SpectrumSegment({
    required this.timestamp,
    required this.spots,
  });
}

class SerialProtocol {
  final SerialPortManager _manager;
  final StreamController<SpectrumSegment> _spectrumStream =
      StreamController.broadcast();
  final StreamController<Map<String, dynamic>> _statusStream =
      StreamController.broadcast();
  Uint8List _buffer = Uint8List(0);

  SerialProtocol(this._manager) {
    _manager.stream.listen(_parseIncomingData);
  }

  Stream<SpectrumSegment> get spectrumStream => _spectrumStream.stream;
  Stream<Map<String, dynamic>> get statusStream => _statusStream.stream;

  void resetReceiveBuffer() {
    _buffer = Uint8List(0);
  }

  int _calculateCrc16Modbus(Uint8List data) {
    int crc = 0xFFFF;
    for (final byte in data) {
      crc ^= byte;
      for (int i = 0; i < 8; i++) {
        if ((crc & 0x0001) != 0) {
          crc = (crc >> 1) ^ 0xA001;
        } else {
          crc >>= 1;
        }
      }
    }
    return crc & 0xFFFF;
  }

  Uint8List _buildFrame(int cmd, Uint8List data) {
    final length = Uint8List(2)
      ..buffer.asByteData().setUint16(0, data.length, Endian.big);
    final payload = Uint8List.fromList(length + [cmd] + data);
    final crcValue = _calculateCrc16Modbus(payload);
    final crc = Uint8List(2)
      ..buffer.asByteData().setUint16(0, crcValue, Endian.big);
    return Uint8List.fromList([0xAA] + payload + crc + [0x55]);
  }

  void _parseIncomingData(Uint8List newData) {
    _buffer = Uint8List.fromList(_buffer + newData);
    while (_buffer.length >= 6) {
      if (_buffer[0] != 0xAA) {
        _buffer = _buffer.sublist(1);
        continue;
      }

      final len = _buffer.buffer.asByteData(1).getUint16(0, Endian.big);
      final frameLen = 1 + 2 + 1 + len + 2 + 1;
      if (_buffer.length < frameLen) {
        break;
      }

      final frame = _buffer.sublist(0, frameLen);
      _buffer = _buffer.sublist(frameLen);

      final payload = frame.sublist(1, 1 + 2 + 1 + len);
      final calcCrc = _calculateCrc16Modbus(Uint8List.fromList(payload));
      final rxCrc =
          frame.buffer.asByteData(1 + 2 + 1 + len).getUint16(0, Endian.big);
      if (calcCrc != rxCrc || frame.last != 0x55) {
        continue;
      }

      final cmd = frame[3];
      final data = frame.sublist(4, 4 + len);
      _handleResponse(cmd, data);
    }
  }

  void _handleResponse(int cmd, Uint8List data) {
    final byteData = data.buffer.asByteData();
    switch (cmd) {
      case 0x81:
        if (data.length >= 3) {
          print('ACK: cmd=${data[0]}, success=${data[1]}, error=${data[2]}');
        }
        break;
      case 0x82:
        final pointCount = byteData.getUint16(0, Endian.big);
        final timestamp = byteData.getUint32(2, Endian.big);
        final spots = <FlSpot>[];
        for (int i = 0; i < pointCount; i++) {
          final offset = 6 + i * 8;
          final freq = byteData.getUint32(offset, Endian.little).toDouble();
          final amp = byteData.getFloat32(offset + 4, Endian.little).toDouble();
          spots.add(FlSpot(freq, amp));
        }
        _spectrumStream.add(
          SpectrumSegment(
            timestamp: timestamp,
            spots: spots,
          ),
        );
        print('Received spectrum: points=$pointCount timestamp=$timestamp');
        break;
      case 0x83:
        final temp = byteData.getFloat64(0, Endian.little);
        final battery = data[8];
        final error = data[9];
        _statusStream.add({
          'temperatureC': temp,
          'batteryPercent': battery,
          'errorCode': error,
        });
        print('Status: Temp=$temp C, Battery=$battery%, Error=$error');
        break;
      default:
        break;
    }
  }

  void applyControlConfig(DeviceControlConfig config) {
    setFreqConfig(config.frequency);
    setAmplitudeConfig(config.amplitude);
    setBandwidthConfig(config.bandwidth);
    setDetectConfig(config.detect);
    setSweepConfig(config.sweep);
  }

  void setFreqConfig(FrequencyConfig config) {
    final data = Uint8List(32);
    final byteData = data.buffer.asByteData();
    byteData.setFloat64(0, config.startHz, Endian.little);
    byteData.setFloat64(8, config.stopHz, Endian.little);
    byteData.setFloat64(16, config.centerHz, Endian.little);
    byteData.setFloat64(24, config.spanHz, Endian.little);
    _manager.sendData(_buildFrame(0x01, data));
  }

  void setFreq(double startHz, double stopHz, double centerHz, double spanHz) {
    setFreqConfig(
      FrequencyConfig(
        startHz: startHz,
        stopHz: stopHz,
        centerHz: centerHz,
        spanHz: spanHz,
      ),
    );
  }

  void setAmplitudeConfig(AmplitudeConfig config) {
    final data = Uint8List(10);
    final byteData = data.buffer.asByteData();
    byteData.setFloat64(0, config.refLevelDbm, Endian.little);
    data[8] = config.attenuatorMode & 0xFF;
    data[9] = config.preampMode & 0xFF;
    _manager.sendData(_buildFrame(0x02, data));
  }

  void setAmplitude(double refLevel, int attenuator, int preamp) {
    setAmplitudeConfig(
      AmplitudeConfig(
        refLevelDbm: refLevel,
        attenuatorMode: attenuator,
        preampMode: preamp,
      ),
    );
  }

  void setBandwidthConfig(BandwidthConfig config) {
    final data = Uint8List(18);
    final byteData = data.buffer.asByteData();
    data[0] = config.rbwMode & 0xFF;
    byteData.setFloat64(1, config.rbwHz, Endian.little);
    data[9] = config.vbwMode & 0xFF;
    byteData.setFloat64(10, config.vbwHz, Endian.little);
    _manager.sendData(_buildFrame(0x03, data));
  }

  void setBw(int rbwMode, double rbwHz, int vbwMode, double vbwHz) {
    setBandwidthConfig(
      BandwidthConfig(
        rbwMode: rbwMode,
        rbwHz: rbwHz,
        vbwMode: vbwMode,
        vbwHz: vbwHz,
      ),
    );
  }

  void setDetectConfig(DetectConfig config) {
    final data = Uint8List(1)..[0] = config.mode & 0xFF;
    _manager.sendData(_buildFrame(0x04, data));
  }

  void setDetect(int mode) {
    setDetectConfig(DetectConfig(mode: mode));
  }

  void setSweepConfig(SweepConfig config) {
    final data = Uint8List(11);
    final byteData = data.buffer.asByteData();
    byteData.setFloat64(0, config.speedHz, Endian.little);
    data[8] = config.mode & 0xFF;
    byteData.setUint16(9, config.pointCount & 0xFFFF, Endian.little);
    _manager.sendData(_buildFrame(0x05, data));
  }

  void setSweep(double speed, int mode, [int pointCount = 128]) {
    setSweepConfig(
      SweepConfig(
        speedHz: speed,
        mode: mode,
        pointCount: pointCount,
      ),
    );
  }

  void setSweepWithPointCount(double speed, int mode, int pointCount) {
    setSweep(speed, mode, pointCount);
  }

  void getSpectrum([int? pointCount]) {
    final data = Uint8List(pointCount == null ? 0 : 2);
    if (pointCount != null) {
      data.buffer.asByteData().setUint16(0, pointCount & 0xFFFF, Endian.little);
    }
    _manager.sendData(_buildFrame(0x06, data));
  }

  void getStatus() {
    _manager.sendData(_buildFrame(0x07, Uint8List(0)));
  }

  void reset() {
    _manager.sendData(_buildFrame(0x08, Uint8List(0)));
  }

  void dispose() {
    _spectrumStream.close();
    _statusStream.close();
  }
}
