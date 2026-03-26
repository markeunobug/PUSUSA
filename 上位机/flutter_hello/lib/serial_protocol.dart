// 文件: lib/serial_protocol.dart
// 串口通信协议实现
import 'dart:async';
import 'dart:typed_data';
import 'serial_port_manager.dart';
import 'package:fl_chart/fl_chart.dart';

class SerialProtocol {
  final SerialPortManager _manager;
  final StreamController<List<FlSpot>> _spectrumStream = StreamController.broadcast(); // 用于频谱数据流

  SerialProtocol(this._manager) {
    _manager.stream.listen(_parseIncomingData);
  }

  // 频谱数据流（供SpectrumChart订阅）
  Stream<List<FlSpot>> get spectrumStream => _spectrumStream.stream;

  // 计算CRC16 Modbus
  int _calculateCrc16Modbus(Uint8List data) {
    int crc = 0xFFFF;
    for (int byte in data) {
      crc ^= byte;
      for (int i = 0; i < 8; i++) {
        if (crc & 0x0001 != 0) {
          crc = (crc >> 1) ^ 0xA001;
        } else {
          crc = crc >> 1;
        }
      }
    }
    return crc;
  }

  // 构建帧
  Uint8List _buildFrame(int cmd, Uint8List data) {
    final length = Uint8List(2)..buffer.asByteData().setUint16(0, data.length);
    final payload = Uint8List.fromList(length + [cmd] + data.toList());
    final crcValue = _calculateCrc16Modbus(payload);
    final crc = Uint8List(2)..buffer.asByteData().setUint16(0, crcValue);
    return Uint8List.fromList([0xAA] + payload.toList() + crc.toList() + [0x55]);
  }

  // 解析传入数据（处理粘包）
  Uint8List _buffer = Uint8List(0);
  void _parseIncomingData(Uint8List newData) {
    _buffer = Uint8List.fromList(_buffer + newData);
    int failCount = 0;
    while (_buffer.length >= 6) { // 最小帧长: Start+Len+Cmd+CRC+End (no data)
      if (_buffer[0] != 0xAA) {
        _buffer = _buffer.sublist(1); // 丢弃无效
        continue;
      }
      final len = _buffer.buffer.asByteData(1).getUint16(0);
      final frameLen = 1 + 2 + 1 + len + 2 + 1; // Start+Len+Cmd+Data+CRC+End
      if (_buffer.length < frameLen) break;
      final frame = _buffer.sublist(0, frameLen);
      _buffer = _buffer.sublist(frameLen);

      final payload = frame.sublist(1, 1 + 2 + 1 + len);
      final calcCrc = _calculateCrc16Modbus(payload);
      final rxCrc = frame.buffer.asByteData(1 + 2 + 1 + len).getUint16(0);
      if (calcCrc != rxCrc || frame.last != 0x55) {
        print('串口接收数据校验失败');
        // 在校验失败时：
        failCount++;
        if (failCount > 5) {
          _buffer = Uint8List(0);
          failCount = 0;
          print('Too many failures, cleared buffer');
        }
        continue; // 校验失败
      }

      final cmd = frame[3];
      final data = frame.sublist(4, 4 + len);
      _handleResponse(cmd, data);
    }
  }

  // 处理响应
  void _handleResponse(int cmd, Uint8List data) {
    final byteData = data.buffer.asByteData();
    switch (cmd) {
      case 0x81: // ACK
        // 处理ACK: originalCmd = data[0], success = data[1], error = data[2]
        print('ACK: Cmd=${data[0]}, Success=${data[1]}, Error=${data[2]}');
        break;
      case 0x82: // SPECTRUM_DATA
        final byteData = data.buffer.asByteData();
        // 显式指定大端读取整数
        final pointCount = byteData.getUint16(0, Endian.big);
        final timestamp = byteData.getUint32(2, Endian.big);
        final spots = <FlSpot>[];
        for (int i = 0; i < pointCount; i++) {
          final offset = 6 + i * 16;
          // 关键：指定小端读取double（匹配STM32存储）
          final freq = byteData.getFloat64(offset, Endian.little);
          final amp = byteData.getFloat64(offset + 8, Endian.little);
          spots.add(FlSpot(freq, amp));
        }
        _spectrumStream.add(spots);
        print('Received ${pointCount} points at ts=$timestamp');
        break;
      case 0x83: // STATUS_DATA
        final temp = byteData.getFloat64(0);
        final battery = data[8];
        final error = data[9];
        print('Status: Temp=$temp°C, Battery=$battery%, Error=$error');
        // 可添加Notifier推送
        break;
    }
  }

  void setFreq(double startHz, double stopHz, double centerHz, double spanHz) {
    final data = Uint8List(32);
    final byteData = data.buffer.asByteData();
    // 显式指定小端序写入double（匹配STM32）
    byteData.setFloat64(0, startHz, Endian.little);
    byteData.setFloat64(8, stopHz, Endian.little);
    byteData.setFloat64(16, centerHz, Endian.little);
    byteData.setFloat64(24, spanHz, Endian.little);
    
    // 调试输出：打印原始字节（可选，用于核对）
    print('发送频率参数字节: ${data.toList()}');
    print('Set Frequency: Start=$startHz, Stop=$stopHz, Center=$centerHz, Span=$spanHz');
    _manager.sendData(_buildFrame(0x01, data));
  }

  void setAmplitude(double refLevel, int attenuator, int preamp) {
    final data = Uint8List(10);
    final byteData = data.buffer.asByteData();
    byteData.setFloat64(0, refLevel, Endian.little); // 补小端序
    data[8] = attenuator & 0xFF; // 确保只取低8位
    data[9] = preamp & 0xFF;     // 确保只取低8位

    // 调试打印：参数值 + 原始字节
    print('=== 发送幅度参数 ===');
    print('RefLevel: $refLevel dBm, Attenuator: $attenuator, Preamp: $preamp');
    print('发送的原始字节(data): ${data.toList()}');
    final frame = _buildFrame(0x02, data);
    print('完整帧字节: ${frame.toList()}');

    _manager.sendData(_buildFrame(0x02, data));
  }

  void setBw(int rbwMode, double rbwHz, int vbwMode, double vbwHz) {
    final data = Uint8List(18);
    final byteData = data.buffer.asByteData();
    data[0] = rbwMode;
    byteData.setFloat64(1, rbwHz, Endian.little); // 补小端序
    data[9] = vbwMode;
    byteData.setFloat64(10, vbwHz, Endian.little); // 补小端序
    _manager.sendData(_buildFrame(0x03, data));
  }

  void setSweep(double speed, int mode) {
    final data = Uint8List(9);
    final byteData = data.buffer.asByteData();
    byteData.setFloat64(0, speed, Endian.little); // 补小端序
    data[8] = mode;
    _manager.sendData(_buildFrame(0x05, data));
  }

  void setDetect(int mode) {
    final data = Uint8List(1)..[0] = mode;
    _manager.sendData(_buildFrame(0x04, data));
  }

  void getSpectrum() {
    _manager.sendData(_buildFrame(0x06, Uint8List(0)));
  }

  void getStatus() {
    _manager.sendData(_buildFrame(0x07, Uint8List(0)));
  }

  void reset() {
    _manager.sendData(_buildFrame(0x08, Uint8List(0)));
  }

  void dispose() {
    _spectrumStream.close();
  }
}