import 'dart:async';
import 'dart:typed_data';

import 'package:fl_chart/fl_chart.dart';

import 'device_models.dart';
import 'phase_noise_models.dart';
import 'serial_port_manager.dart';

class SpectrumSegment {
  final int timestamp;
  final int totalPoints;
  final int currentIndex;
  final bool done;
  final List<FlSpot> spots;

  const SpectrumSegment({
    required this.timestamp,
    required this.totalPoints,
    required this.currentIndex,
    required this.done,
    required this.spots,
  });
}

class SweepProfileSection {
  final int id;
  final int count;
  final int totalTicks;
  final int minTicks;
  final int maxTicks;

  const SweepProfileSection({
    required this.id,
    required this.count,
    required this.totalTicks,
    required this.minTicks,
    required this.maxTicks,
  });

  double get averageTicks => count == 0 ? 0.0 : totalTicks / count;
}

class SweepProfileReport {
  final int version;
  final bool enabled;
  final int rbwMode;
  final int countsPerSecond;
  final int sweepCount;
  final int pointCount;
  final int dmaRearmCount;
  final List<SweepProfileSection> sections;

  const SweepProfileReport({
    required this.version,
    required this.enabled,
    required this.rbwMode,
    required this.countsPerSecond,
    required this.sweepCount,
    required this.pointCount,
    required this.dmaRearmCount,
    required this.sections,
  });

  double ticksToMs(num ticks) {
    if (countsPerSecond <= 0) return 0.0;
    return ticks * 1000.0 / countsPerSecond;
  }
}

class SerialProtocol {
  static const int _minFrameLength = 7;
  static const int _maxPayloadLength = 16384;
  static const int _phaseNoiseVersion = 1;
  static const int _phaseNoiseFlagAllowEstimatedEnbw = 1 << 1;

  final SerialPortManager _manager;
  final StreamController<SpectrumSegment> _spectrumStream =
      StreamController.broadcast();
  final StreamController<Map<String, dynamic>> _statusStream =
      StreamController.broadcast();
  final StreamController<RfFrontendStatus> _rfFrontendStatusStream =
      StreamController.broadcast();
  final StreamController<SweepProfileReport> _sweepProfileStream =
      StreamController.broadcast();
  final StreamController<PhaseNoiseDataFrame> _phaseNoiseStream =
      StreamController.broadcast();
  final StreamController<PhaseNoiseStatusFrame> _phaseNoiseStatusStream =
      StreamController.broadcast();
  Uint8List _buffer = Uint8List(0);
  Completer<bool>? _handshakeCompleter;
  final Map<int, List<Completer<bool>>> _ackWaiters = {};
  int badFrameCount = 0;
  int crcErrorCount = 0;
  int resyncCount = 0;
  int unknownFrameCount = 0;

  SerialProtocol(this._manager) {
    _manager.stream.listen(_parseIncomingData);
  }

  Stream<SpectrumSegment> get spectrumStream => _spectrumStream.stream;
  Stream<Map<String, dynamic>> get statusStream => _statusStream.stream;
  Stream<RfFrontendStatus> get rfFrontendStatusStream =>
      _rfFrontendStatusStream.stream;
  Stream<SweepProfileReport> get sweepProfileStream =>
      _sweepProfileStream.stream;
  Stream<PhaseNoiseDataFrame> get phaseNoiseStream => _phaseNoiseStream.stream;
  Stream<PhaseNoiseStatusFrame> get phaseNoiseStatusStream =>
      _phaseNoiseStatusStream.stream;

  void resetReceiveBuffer() {
    _buffer = Uint8List(0);
  }

  Future<bool> statusHandshake({
    int attempts = 8,
    Duration timeout = const Duration(milliseconds: 350),
  }) async {
    for (int attempt = 0; attempt < attempts; attempt++) {
      resetReceiveBuffer();
      await _manager.drainInputBuffer();
      resetReceiveBuffer();
      _handshakeCompleter = Completer<bool>();
      getStatus();

      final ok = await _handshakeCompleter!.future
          .timeout(timeout, onTimeout: () => false);
      _handshakeCompleter = null;
      if (ok) {
        return true;
      }

      await Future.delayed(const Duration(milliseconds: 150));
    }

    return false;
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
    while (_buffer.length >= _minFrameLength) {
      if (_buffer[0] != 0xAA) {
        print(
          'Serial frame resync: first=0x${_buffer[0].toRadixString(16)}, '
          'buffer=${_buffer.length}',
        );
        _dropUntilNextStart();
        continue;
      }

      final len = _buffer.buffer.asByteData(1).getUint16(0, Endian.big);
      if (len > _maxPayloadLength) {
        badFrameCount++;
        print(
          'Serial bad frame: payload length $len exceeds $_maxPayloadLength '
          '(bad=$badFrameCount, crc=$crcErrorCount, resync=$resyncCount)',
        );
        _dropUntilNextStart(skipFirst: true);
        continue;
      }

      final frameLen = 1 + 2 + 1 + len + 2 + 1;
      if (_buffer.length < frameLen) {
        break;
      }

      final frame = _buffer.sublist(0, frameLen);
      _buffer = _buffer.sublist(frameLen);

      if (frame.last != 0x55) {
        badFrameCount++;
        print(
          'Serial bad frame: missing end byte, cmd=0x${frame[3].toRadixString(16)}, '
          'len=$len end=0x${frame.last.toRadixString(16)} '
          '(bad=$badFrameCount, crc=$crcErrorCount, resync=$resyncCount)',
        );
        _buffer = Uint8List.fromList(frame.sublist(1) + _buffer);
        _dropUntilNextStart();
        continue;
      }

      final payload = frame.sublist(1, 1 + 2 + 1 + len);
      final calcCrc = _calculateCrc16Modbus(Uint8List.fromList(payload));
      final rxCrc =
          frame.buffer.asByteData(1 + 2 + 1 + len).getUint16(0, Endian.big);
      if (calcCrc != rxCrc) {
        crcErrorCount++;
        print(
          'Serial CRC error: cmd=0x${frame[3].toRadixString(16)}, len=$len, '
          'rx=0x${rxCrc.toRadixString(16)}, calc=0x${calcCrc.toRadixString(16)} '
          '(bad=$badFrameCount, crc=$crcErrorCount, resync=$resyncCount)',
        );
        _dropUntilNextStart();
        continue;
      }

      final cmd = frame[3];
      final data = frame.sublist(4, 4 + len);
      _handleResponse(cmd, data);
    }
  }

  void _dropUntilNextStart({bool skipFirst = false}) {
    final start = skipFirst ? 1 : 0;
    int next = -1;
    for (int i = start; i < _buffer.length; i++) {
      if (_buffer[i] == 0xAA) {
        next = i;
        break;
      }
    }

    if (next < 0) {
      _buffer = Uint8List(0);
    } else if (next > 0) {
      _buffer = _buffer.sublist(next);
    }
    resyncCount++;
  }

  void _handleResponse(int cmd, Uint8List data) {
    final byteData = data.buffer.asByteData();
    switch (cmd) {
      case 0x81:
        if (data.length >= 3) {
          print('ACK: cmd=${data[0]}, success=${data[1]}, error=${data[2]}');
          _completeAckWaiter(data[0], data[1] == 1 && data[2] == 0);
          if (_handshakeCompleter != null && data[0] == 0x07) {
            if (data[1] != 1 && !_handshakeCompleter!.isCompleted) {
              _handshakeCompleter!.complete(false);
            }
          }
        }
        break;
      case 0x82:
        if (data.length < 6) {
          badFrameCount++;
          print(
            'Spectrum frame too short: len=${data.length} '
            '(bad=$badFrameCount, crc=$crcErrorCount, resync=$resyncCount)',
          );
          break;
        }
        final pointCount = byteData.getUint16(0, Endian.big);
        final timestamp = byteData.getUint32(2, Endian.big);
        final newFormatLength = 11 + pointCount * 8;
        final oldFormatLength = 6 + pointCount * 16;
        late final int totalPoints;
        late final int currentIndex;
        late final bool done;
        late final List<FlSpot> spots;
        late final String frameFormat;

        if (data.length == newFormatLength) {
          totalPoints = byteData.getUint16(6, Endian.big);
          currentIndex = byteData.getUint16(8, Endian.big);
          done = data[10] != 0;
          spots = <FlSpot>[];
          for (int i = 0; i < pointCount; i++) {
            final offset = 11 + i * 8;
            final freq = byteData.getUint32(offset, Endian.little).toDouble();
            final amp =
                byteData.getFloat32(offset + 4, Endian.little).toDouble();
            spots.add(FlSpot(freq, amp));
          }
          frameFormat = 'segmented-v2';
        } else if (data.length == oldFormatLength) {
          totalPoints = pointCount;
          currentIndex = 0;
          done = true;
          spots = <FlSpot>[];
          for (int i = 0; i < pointCount; i++) {
            final offset = 6 + i * 16;
            final freq = byteData.getFloat64(offset, Endian.little);
            final amp = byteData.getFloat64(offset + 8, Endian.little);
            spots.add(FlSpot(freq, amp));
          }
          frameFormat = 'legacy-double';
        } else {
          badFrameCount++;
          print(
            'Spectrum frame length mismatch: len=${data.length}, '
            'points=$pointCount, expectedNew=$newFormatLength, '
            'expectedLegacy=$oldFormatLength '
            '(bad=$badFrameCount, crc=$crcErrorCount, resync=$resyncCount)',
          );
          break;
        }

        _spectrumStream.add(
          SpectrumSegment(
            timestamp: timestamp,
            totalPoints: totalPoints,
            currentIndex: currentIndex,
            done: done,
            spots: spots,
          ),
        );
        print(
          'Received spectrum: format=$frameFormat points=$pointCount timestamp=$timestamp '
          'progress=${currentIndex + pointCount}/$totalPoints done=$done',
        );
        break;
      case 0x83:
        if (data.length < 10) {
          badFrameCount++;
          break;
        }
        final temp = byteData.getFloat64(0, Endian.little);
        final battery = data[8];
        final error = data[9];
        final status = <String, dynamic>{
          'temperatureC': temp,
          'batteryPercent': battery,
          'errorCode': error,
        };
        if (data.length >= 27) {
          status.addAll({
            'dmaStartCount': byteData.getUint32(10, Endian.big),
            'dmaErrorCount': byteData.getUint32(14, Endian.big),
            'frameReadyCount': byteData.getUint32(18, Endian.big),
            'processFrameCount': byteData.getUint32(22, Endian.big),
            'spectrumValid': data[26],
          });
        }
        if (data.length >= 43) {
          status.addAll({
            's2mmDmacr': byteData.getUint32(27, Endian.big),
            's2mmDmasr': byteData.getUint32(31, Endian.big),
            'dmaIrqCount': byteData.getUint32(35, Endian.big),
            'dmaLastIrqStatus': byteData.getUint32(39, Endian.big),
          });
        }
        if (data.length >= 59) {
          status.addAll({
            'uartRxBadFrameCount': byteData.getUint32(43, Endian.big),
            'uartRxCrcErrorCount': byteData.getUint32(47, Endian.big),
            'uartRxOverrunCount': byteData.getUint32(51, Endian.big),
            'uartRxResyncCount': byteData.getUint32(55, Endian.big),
          });
        }
        _statusStream.add(status);
        if (_handshakeCompleter != null && !_handshakeCompleter!.isCompleted) {
          _handshakeCompleter!.complete(true);
        }
        print(
          'Status: Temp=$temp C, Battery=$battery%, Error=$error, '
          'spectrumValid=${status['spectrumValid'] ?? '-'}, '
          'dmaStart=${status['dmaStartCount'] ?? '-'}, '
          'dmaError=${status['dmaErrorCount'] ?? '-'}, '
          'frameReady=${status['frameReadyCount'] ?? '-'}, '
          'processFrame=${status['processFrameCount'] ?? '-'}, '
          's2mmDmasr=${status['s2mmDmasr'] != null ? '0x${(status['s2mmDmasr'] as int).toRadixString(16)}' : '-'}',
        );
        break;
      case 0x84:
        final status = parseRfFrontendStatus(data);
        if (status == null) {
          badFrameCount++;
          print(
            'RF frontend status frame too short: len=${data.length} '
            '(bad=$badFrameCount, crc=$crcErrorCount, resync=$resyncCount)',
          );
          break;
        }
        _rfFrontendStatusStream.add(status);
        print(
          'RF frontend status: lna=${status.config.lnaMode.name}, '
          'path=${status.config.pathMode.name}, '
          'atten=${status.config.attenDb.toStringAsFixed(2)} dB, '
          'gpio=0x${status.appliedGpio.toRadixString(16).padLeft(2, '0')}, '
          'error=${status.error}',
        );
        break;
      case 0x85:
        final report = parseSweepProfile(data);
        if (report == null) {
          badFrameCount++;
          print(
            'Sweep profile frame invalid: len=${data.length} '
            '(bad=$badFrameCount, crc=$crcErrorCount, resync=$resyncCount)',
          );
          break;
        }
        _sweepProfileStream.add(report);
        _printSweepProfile(report);
        break;
      case 0x86:
        final point = parsePhaseNoiseData(data);
        if (point == null) {
          badFrameCount++;
          print(
            'Phase-noise data frame invalid: len=${data.length} '
            '(bad=$badFrameCount, crc=$crcErrorCount, resync=$resyncCount)',
          );
          break;
        }
        _phaseNoiseStream.add(point);
        print(
          'Phase-noise data: trace=${point.traceId} '
          'progress=${point.receivedPoints}/${point.plannedTotalPoints} '
          'avg=${point.averageIndex} offset=${point.offsetHz}Hz '
          'pn=${point.phaseNoiseDbcHz.toStringAsFixed(2)}dBc/Hz '
          'done=${point.done}',
        );
        break;
      case 0x87:
        final status = parsePhaseNoiseStatus(data);
        if (status == null) {
          badFrameCount++;
          print(
            'Phase-noise status frame invalid: len=${data.length} '
            '(bad=$badFrameCount, crc=$crcErrorCount, resync=$resyncCount)',
          );
          break;
        }
        _phaseNoiseStatusStream.add(status);
        print(
          'Phase-noise status: state=${status.state} trace=${status.traceId} '
          'progress=${status.receivedPoints}/${status.plannedTotalPoints} '
          'avg=${status.averageIndex} offset=${status.currentOffsetHz}Hz '
          'rbw=${status.currentRbwHz}Hz error=${status.errorCode} '
          'warning=${status.warningCode}',
        );
        break;
      default:
        unknownFrameCount++;
        print(
          'Unknown response frame: cmd=0x${cmd.toRadixString(16)}, '
          'len=${data.length}, unknown=$unknownFrameCount '
          '(bad=$badFrameCount, crc=$crcErrorCount, resync=$resyncCount)',
        );
        break;
    }
  }

  Future<bool> _sendAndWaitAck(
    int cmd,
    Uint8List data, {
    Duration timeout = const Duration(milliseconds: 800),
  }) {
    final completer = Completer<bool>();
    (_ackWaiters[cmd] ??= <Completer<bool>>[]).add(completer);
    _manager.sendData(_buildFrame(cmd, data));

    return completer.future.timeout(timeout, onTimeout: () {
      final waiters = _ackWaiters[cmd];
      waiters?.remove(completer);
      if (waiters != null && waiters.isEmpty) {
        _ackWaiters.remove(cmd);
      }
      return false;
    });
  }

  void _completeAckWaiter(int cmd, bool ok) {
    final waiters = _ackWaiters[cmd];
    if (waiters == null || waiters.isEmpty) {
      return;
    }

    final completer = waiters.removeAt(0);
    if (waiters.isEmpty) {
      _ackWaiters.remove(cmd);
    }
    if (!completer.isCompleted) {
      completer.complete(ok);
    }
  }

  void applyControlConfig(DeviceControlConfig config) {
    setFreqConfig(config.frequency);
    setAmplitudeConfig(config.amplitude);
    setBandwidthConfig(config.bandwidth);
    setDetectConfig(config.detect);
    setSweepConfig(config.sweep);
  }

  Future<bool> applyControlConfigConfirmed(DeviceControlConfig config) async {
    if (!await setFreqConfigConfirmed(config.frequency)) return false;
    if (!await setAmplitudeConfigConfirmed(config.amplitude)) return false;
    if (!await setBandwidthConfigConfirmed(config.bandwidth)) return false;
    if (!await setDetectConfigConfirmed(config.detect)) return false;
    if (!await setSweepConfigConfirmed(config.sweep)) return false;
    return true;
  }

  Uint8List _buildFreqData(FrequencyConfig config) {
    final data = Uint8List(32);
    final byteData = data.buffer.asByteData();
    byteData.setFloat64(0, config.startHz, Endian.little);
    byteData.setFloat64(8, config.stopHz, Endian.little);
    byteData.setFloat64(16, config.centerHz, Endian.little);
    byteData.setFloat64(24, config.spanHz, Endian.little);
    return data;
  }

  void setFreqConfig(FrequencyConfig config) {
    _manager.sendData(_buildFrame(0x01, _buildFreqData(config)));
  }

  Future<bool> setFreqConfigConfirmed(FrequencyConfig config) {
    return _sendAndWaitAck(0x01, _buildFreqData(config));
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

  Uint8List _buildAmplitudeData(AmplitudeConfig config) {
    final data = Uint8List(10);
    final byteData = data.buffer.asByteData();
    byteData.setFloat64(0, config.refLevelDbm, Endian.little);
    data[8] = config.attenuatorMode & 0xFF;
    data[9] = config.preampMode & 0xFF;
    return data;
  }

  void setAmplitudeConfig(AmplitudeConfig config) {
    _manager.sendData(_buildFrame(0x02, _buildAmplitudeData(config)));
  }

  Future<bool> setAmplitudeConfigConfirmed(AmplitudeConfig config) {
    return _sendAndWaitAck(0x02, _buildAmplitudeData(config));
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

  Uint8List _buildBandwidthData(BandwidthConfig config) {
    final data = Uint8List(18);
    final byteData = data.buffer.asByteData();
    data[0] = config.rbwMode & 0xFF;
    byteData.setFloat64(1, config.rbwHz, Endian.little);
    data[9] = config.vbwMode & 0xFF;
    byteData.setFloat64(10, config.vbwHz, Endian.little);
    return data;
  }

  void setBandwidthConfig(BandwidthConfig config) {
    _manager.sendData(_buildFrame(0x03, _buildBandwidthData(config)));
  }

  Future<bool> setBandwidthConfigConfirmed(BandwidthConfig config) {
    return _sendAndWaitAck(0x03, _buildBandwidthData(config));
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

  Uint8List _buildDetectData(DetectConfig config) {
    return Uint8List(1)..[0] = config.mode & 0xFF;
  }

  void setDetectConfig(DetectConfig config) {
    _manager.sendData(_buildFrame(0x04, _buildDetectData(config)));
  }

  Future<bool> setDetectConfigConfirmed(DetectConfig config) {
    return _sendAndWaitAck(0x04, _buildDetectData(config));
  }

  void setDetect(int mode) {
    setDetectConfig(DetectConfig(mode: mode));
  }

  Uint8List _buildSweepData(SweepConfig config) {
    final data = Uint8List(11);
    final byteData = data.buffer.asByteData();
    byteData.setFloat64(0, config.speedHz, Endian.little);
    data[8] = config.mode & 0xFF;
    byteData.setUint16(9, config.pointCount & 0xFFFF, Endian.little);
    return data;
  }

  void setSweepConfig(SweepConfig config) {
    _manager.sendData(_buildFrame(0x05, _buildSweepData(config)));
  }

  Future<bool> setSweepConfigConfirmed(SweepConfig config) {
    return _sendAndWaitAck(0x05, _buildSweepData(config));
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

  void startSweep() {
    _manager.sendData(_buildFrame(0x09, Uint8List(0)));
  }

  void stopSweep() {
    _manager.sendData(_buildFrame(0x0A, Uint8List(0)));
  }

  void setVgaGainCode(int code) {
    _manager.sendData(_buildFrame(0x0B, Uint8List.fromList([code & 0xFF])));
  }

  int _encodeRfLnaMode(RfLnaMode mode) {
    switch (mode) {
      case RfLnaMode.bypass:
        return 0;
      case RfLnaMode.enable:
        return 1;
      case RfLnaMode.auto:
        return 2;
    }
  }

  int _encodeRfPathMode(RfPathMode mode) {
    switch (mode) {
      case RfPathMode.directIf:
        return 0;
      case RfPathMode.mixerChain:
        return 1;
      case RfPathMode.auto:
        return 2;
    }
  }

  RfLnaMode _decodeRfLnaMode(int value) {
    switch (value) {
      case 1:
        return RfLnaMode.enable;
      case 2:
        return RfLnaMode.auto;
      case 0:
      default:
        return RfLnaMode.bypass;
    }
  }

  RfPathMode _decodeRfPathMode(int value) {
    switch (value) {
      case 1:
        return RfPathMode.mixerChain;
      case 2:
        return RfPathMode.auto;
      case 0:
      default:
        return RfPathMode.directIf;
    }
  }

  Uint8List _buildRfFrontendData(
    RfFrontendConfig config, {
    bool applyImmediately = true,
  }) {
    final code = config.attenCode.clamp(0, 127).toInt();
    return Uint8List.fromList([
      _encodeRfLnaMode(config.lnaMode),
      _encodeRfPathMode(config.pathMode),
      code,
      applyImmediately ? 0x01 : 0x00,
    ]);
  }

  void setRfFrontend(RfFrontendConfig config) {
    _manager.sendData(_buildFrame(0x0C, _buildRfFrontendData(config)));
  }

  Future<bool> setRfFrontendConfirmed(RfFrontendConfig config) {
    return _sendAndWaitAck(0x0C, _buildRfFrontendData(config));
  }

  void getRfFrontendStatus() {
    _manager.sendData(_buildFrame(0x0D, Uint8List(0)));
  }

  void getSweepProfile() {
    _manager.sendData(_buildFrame(0x0E, Uint8List(0)));
  }

  int _encodePhaseNoiseCarrierMode(PhaseNoiseCarrierMode mode) {
    switch (mode) {
      case PhaseNoiseCarrierMode.manual:
        return 0;
      case PhaseNoiseCarrierMode.auto:
        return 1;
    }
  }

  int _encodePhaseNoiseSidebandMode(PhaseNoiseSidebandMode mode) {
    switch (mode) {
      case PhaseNoiseSidebandMode.upper:
        return 0;
      case PhaseNoiseSidebandMode.lower:
        return 1;
      case PhaseNoiseSidebandMode.both:
        return 2;
    }
  }

  Uint8List _buildPhaseNoiseConfigData(
    PhaseNoiseConfig config, {
    bool continuous = false,
    bool emitIntermediateAverages = true,
  }) {
    final data = Uint8List(36);
    final byteData = data.buffer.asByteData();
    var flags = _phaseNoiseFlagAllowEstimatedEnbw;
    if (continuous) {
      flags |= 1 << 0;
    }
    if (emitIntermediateAverages) {
      flags |= 1 << 2;
    }

    data[0] = _phaseNoiseVersion;
    data[1] = flags & 0xFF;
    data[2] = _encodePhaseNoiseCarrierMode(config.carrierMode);
    // v1 firmware currently accepts upper sideband only.
    data[3] = _encodePhaseNoiseSidebandMode(PhaseNoiseSidebandMode.upper);
    byteData.setFloat64(
      4,
      config.protocolNominalCarrierHz,
      Endian.little,
    );
    byteData.setFloat64(12, config.startOffsetHz, Endian.little);
    byteData.setFloat64(20, config.stopOffsetHz, Endian.little);
    byteData.setUint16(
      28,
      config.pointsPerDecade.clamp(1, 0xFFFF).toInt(),
      Endian.little,
    );
    byteData.setUint16(
      30,
      config.averageTarget.clamp(1, 0xFFFF).toInt(),
      Endian.little,
    );
    byteData.setUint16(
      32,
      (config.carrierSearchSpanHz / 1000.0).round().clamp(0, 0xFFFF).toInt(),
      Endian.little,
    );
    byteData.setInt8(
      34,
      config.minimumCarrierLevelDbm.round().clamp(-128, 127).toInt(),
    );
    data[35] = 0;
    return data;
  }

  void setPhaseNoiseConfig(
    PhaseNoiseConfig config, {
    bool continuous = false,
    bool emitIntermediateAverages = true,
  }) {
    _manager.sendData(
      _buildFrame(
        0x0F,
        _buildPhaseNoiseConfigData(
          config,
          continuous: continuous,
          emitIntermediateAverages: emitIntermediateAverages,
        ),
      ),
    );
  }

  Future<bool> setPhaseNoiseConfigConfirmed(
    PhaseNoiseConfig config, {
    bool continuous = false,
    bool emitIntermediateAverages = true,
  }) {
    return _sendAndWaitAck(
      0x0F,
      _buildPhaseNoiseConfigData(
        config,
        continuous: continuous,
        emitIntermediateAverages: emitIntermediateAverages,
      ),
    );
  }

  void startPhaseNoise() {
    _manager.sendData(_buildFrame(0x10, Uint8List(0)));
  }

  Future<bool> startPhaseNoiseConfirmed() {
    return _sendAndWaitAck(0x10, Uint8List(0));
  }

  void stopPhaseNoise() {
    _manager.sendData(_buildFrame(0x11, Uint8List(0)));
  }

  Future<bool> stopPhaseNoiseConfirmed() {
    return _sendAndWaitAck(0x11, Uint8List(0));
  }

  void getPhaseNoiseStatus() {
    _manager.sendData(_buildFrame(0x12, Uint8List(0)));
  }

  Future<bool> getPhaseNoiseStatusConfirmed() {
    return _sendAndWaitAck(0x12, Uint8List(0));
  }

  RfFrontendStatus? parseRfFrontendStatus(Uint8List data) {
    if (data.length < 5) {
      return null;
    }

    return RfFrontendStatus(
      config: RfFrontendConfig(
        lnaMode: _decodeRfLnaMode(data[0]),
        pathMode: _decodeRfPathMode(data[1]),
        attenCode: data[2].clamp(0, 127).toInt(),
      ),
      appliedGpio: data[3],
      error: data[4],
    );
  }

  SweepProfileReport? parseSweepProfile(Uint8List data) {
    const headerLength = 24;
    const sectionLength = 30;

    if (data.length < headerLength) {
      return null;
    }

    final byteData = data.buffer.asByteData(data.offsetInBytes, data.length);
    final sectionCount = byteData.getUint16(20, Endian.big);
    final expectedLength = headerLength + sectionCount * sectionLength;
    if (data.length < expectedLength) {
      return null;
    }

    final sections = <SweepProfileSection>[];
    for (int i = 0; i < sectionCount; i++) {
      final offset = headerLength + i * sectionLength;
      sections.add(
        SweepProfileSection(
          id: data[offset],
          count: byteData.getUint32(offset + 2, Endian.big),
          totalTicks: byteData.getUint64(offset + 6, Endian.big),
          minTicks: byteData.getUint64(offset + 14, Endian.big),
          maxTicks: byteData.getUint64(offset + 22, Endian.big),
        ),
      );
    }

    return SweepProfileReport(
      version: data[0],
      enabled: data[1] != 0,
      rbwMode: data[2],
      countsPerSecond: byteData.getUint32(4, Endian.big),
      sweepCount: byteData.getUint32(8, Endian.big),
      pointCount: byteData.getUint32(12, Endian.big),
      dmaRearmCount: byteData.getUint32(16, Endian.big),
      sections: sections,
    );
  }

  PhaseNoiseDataFrame? parsePhaseNoiseData(Uint8List data) {
    const payloadLength = 42;
    if (data.length != payloadLength || data[0] != _phaseNoiseVersion) {
      return null;
    }

    final byteData = data.buffer.asByteData(data.offsetInBytes, data.length);
    final plannedTotalPoints = byteData.getUint16(4, Endian.big);
    final currentIndex = byteData.getUint16(6, Endian.big);
    final averageIndex = byteData.getUint16(8, Endian.big);
    final receivedPoints = plannedTotalPoints == 0
        ? 0
        : (currentIndex + 1).clamp(0, plannedTotalPoints).toInt();

    return PhaseNoiseDataFrame(
      version: data[0],
      flags: data[1],
      traceId: byteData.getUint16(2, Endian.big),
      plannedTotalPoints: plannedTotalPoints,
      receivedPoints: receivedPoints,
      currentIndex: currentIndex,
      averageIndex: averageIndex,
      carrierHz: byteData.getFloat64(10, Endian.little),
      carrierLevelDbm: byteData.getFloat32(18, Endian.little),
      offsetHz: byteData.getUint32(22, Endian.little),
      noisePowerDbm: byteData.getFloat32(26, Endian.little),
      phaseNoiseDbcHz: byteData.getFloat32(30, Endian.little),
      rbwHz: byteData.getUint32(34, Endian.little),
      errorCode: data[38],
    );
  }

  PhaseNoiseStatusFrame? parsePhaseNoiseStatus(Uint8List data) {
    const payloadLength = 64;
    if (data.length != payloadLength || data[0] != _phaseNoiseVersion) {
      return null;
    }

    final byteData = data.buffer.asByteData(data.offsetInBytes, data.length);
    final plannedTotalPoints = byteData.getUint16(6, Endian.big);
    final currentIndex = byteData.getUint16(8, Endian.big);
    final averageIndex = byteData.getUint16(10, Endian.big);
    final receivedPoints = plannedTotalPoints == 0
        ? 0
        : (currentIndex + 1).clamp(0, plannedTotalPoints).toInt();

    return PhaseNoiseStatusFrame(
      version: data[0],
      state: data[1],
      flags: data[2],
      errorCode: data[3],
      traceId: byteData.getUint16(4, Endian.big),
      plannedTotalPoints: plannedTotalPoints,
      receivedPoints: receivedPoints,
      currentIndex: currentIndex,
      averageIndex: averageIndex,
      nominalCarrierHz: byteData.getFloat64(12, Endian.little),
      measuredCarrierHz: byteData.getFloat64(20, Endian.little),
      carrierLevelDbm: byteData.getFloat32(28, Endian.little),
      startOffsetHz: byteData.getFloat64(32, Endian.little),
      stopOffsetHz: byteData.getFloat64(40, Endian.little),
      currentOffsetHz: byteData.getUint32(48, Endian.little),
      currentRbwHz: byteData.getUint32(52, Endian.little),
      elapsedMs: byteData.getUint32(56, Endian.little),
      warningCode: byteData.getUint16(60, Endian.little),
    );
  }

  String _sweepProfileSectionName(int id) {
    switch (id) {
      case 0:
        return 'point_total';
      case 1:
        return 'set_lo1';
      case 2:
        return 'wait_lock';
      case 3:
        return 'dma_reset';
      case 4:
        return 'dma_start';
      case 5:
        return 'dma_wait';
      case 6:
        return 'accumulate_dma';
      case 7:
        return 'measure';
      case 8:
        return 'emit_uart';
      case 9:
        return 'acc_ddc';
      case 10:
        return 'acc_cic';
      default:
        return 'section_$id';
    }
  }

  void _printSweepProfile(SweepProfileReport report) {
    print(
      'Sweep profile: enabled=${report.enabled}, version=${report.version}, '
      'rbwMode=${report.rbwMode}, points=${report.pointCount}, '
      'dmaRearms=${report.dmaRearmCount}, ticksPerSec=${report.countsPerSecond}',
    );

    for (final section in report.sections) {
      final perPointMs = report.pointCount > 0
          ? report.ticksToMs(section.totalTicks / report.pointCount)
          : 0.0;

      print(
        '  ${_sweepProfileSectionName(section.id)}: '
        'count=${section.count}, '
        'avg/call=${report.ticksToMs(section.averageTicks).toStringAsFixed(3)}ms, '
        'per_point=${perPointMs.toStringAsFixed(3)}ms, '
        'min=${report.ticksToMs(section.minTicks).toStringAsFixed(3)}ms, '
        'max=${report.ticksToMs(section.maxTicks).toStringAsFixed(3)}ms',
      );
    }
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
    _rfFrontendStatusStream.close();
    _sweepProfileStream.close();
    _phaseNoiseStream.close();
    _phaseNoiseStatusStream.close();
  }
}
