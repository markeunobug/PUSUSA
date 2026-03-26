import 'package:flutter/foundation.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';
import 'dart:async';
import 'dart:typed_data';

enum ConnectionStatus {
  connected,    // 绿色
  disconnected, // 红色
  noPorts       // 灰色
}

class SerialPortManager extends ChangeNotifier {
  List<String> availablePorts = [];
  String? selectedPort;
  bool isConnected = false;
  SerialPort? _serialPort;
  Timer? _refreshTimer;
  final ValueNotifier<ConnectionStatus> connectionStatus = ValueNotifier<ConnectionStatus>(ConnectionStatus.noPorts);

  final StreamController<Uint8List> _rxStreamController = StreamController.broadcast();
  Stream<Uint8List> get stream => _rxStreamController.stream;

  Timer? _readTimer;

  void init() {
    _refreshPorts();
    _refreshTimer = Timer.periodic(const Duration(seconds: 5), (_) => _refreshPorts());
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    _readTimer?.cancel();
    _rxStreamController.close();
    _disconnect();
    connectionStatus.dispose();
    super.dispose();
  }

  void _refreshPorts() {
    final newPorts = SerialPort.availablePorts;
    if (!setEquals(newPorts.toSet(), availablePorts.toSet())) {
      availablePorts = newPorts;
      if (selectedPort != null && !availablePorts.contains(selectedPort)) {
        _disconnect();
        selectedPort = null;
      }
      _updateStatus();
      notifyListeners();
    }
  }

  void _updateStatus() {
    if (availablePorts.isEmpty) {
      connectionStatus.value = ConnectionStatus.noPorts;
    } else if (isConnected) {
      connectionStatus.value = ConnectionStatus.connected;
    } else {
      connectionStatus.value = ConnectionStatus.disconnected;
    }
  }

  void connect() {
    if (selectedPort == null || isConnected) return;
    try {
      _serialPort = SerialPort(selectedPort!);
      _serialPort!.config.baudRate = 115200; // 固定波特率
      _serialPort!.config.bits = 8;
      _serialPort!.config.stopBits = 1;
      _serialPort!.config.parity = SerialPortParity.none;
      if (_serialPort!.openReadWrite()) {
        // 清空缓冲区：读取所有可用字节并丢弃
        int bytes = _serialPort!.bytesAvailable;
        if (bytes > 0) {
          _serialPort!.read(bytes);  // 丢弃
          print('Cleared $bytes residual bytes on connect');
        }
        isConnected = true;
        _updateStatus();
        notifyListeners();
        _refreshPorts(); // 连接后刷新
        _startReading();
      } else {
        throw Exception('无法打开端口: ${SerialPort.lastError}');
      }
    } catch (e) {
      // 错误处理在UI层
      rethrow;
    }
  }

  void _startReading() {
    _readTimer = Timer.periodic(const Duration(milliseconds: 10), (_) {
      if (_serialPort == null) return;

      try {
        final int bytes = _serialPort!.bytesAvailable;
        if (bytes > 0) {
          final data = _serialPort!.read(bytes);
          _rxStreamController.add(data);
        }
      } catch (e) {
        print('Serial error: $e');
        disconnect(); // 检测到错误时自动断开
      }
    });
  }

  void sendData(Uint8List data) {
    if (isConnected && _serialPort != null) {
      try {
        _serialPort!.write(data);
      } catch (e) {
        print('Write error: $e');
        disconnect(); // 写入失败时也断开
      }
    }
  }

  void disconnect() {
    _disconnect();
    _refreshPorts(); // 断开后刷新
  }

  void _disconnect() {
    _readTimer?.cancel();
    if (_serialPort != null && _serialPort!.isOpen) {
      try {
        _serialPort!.close();
      } catch (e) {
        print('Close error: $e');
      }
      _serialPort = null;
      isConnected = false;
      _updateStatus();
      notifyListeners();
    }
  }

  void setSelectedPort(String? port) {
    selectedPort = port;
    notifyListeners();
  }

  void refreshPorts() {
    _refreshPorts();
  }
}

// 辅助函数
bool setEquals<T>(Set<T> a, Set<T> b) {
  if (a.length != b.length) return false;
  return a.every(b.contains);
}