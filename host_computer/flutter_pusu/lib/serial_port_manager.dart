import 'dart:async';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter_libserialport/flutter_libserialport.dart';

enum ConnectionStatus {
  connected,
  disconnected,
  noPorts,
}

class SerialPortManager extends ChangeNotifier {
  List<String> availablePorts = [];
  String? selectedPort;
  bool isConnected = false;
  SerialPort? _serialPort;
  Timer? _refreshTimer;
  bool _isRefreshingPorts = false;
  final ValueNotifier<ConnectionStatus> connectionStatus =
      ValueNotifier<ConnectionStatus>(ConnectionStatus.noPorts);

  final StreamController<Uint8List> _rxStreamController =
      StreamController.broadcast();
  Stream<Uint8List> get stream => _rxStreamController.stream;

  Timer? _readTimer;

  void init() {
    _refreshPortsAsync();
    _refreshTimer =
        Timer.periodic(const Duration(seconds: 5), (_) => _refreshPortsAsync());
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

  Future<void> _refreshPortsAsync() async {
    if (_isRefreshingPorts) return;
    _isRefreshingPorts = true;
    try {
      final newPorts = await Isolate.run(() => SerialPort.availablePorts)
          .timeout(const Duration(seconds: 2), onTimeout: () => availablePorts);
      _applyPorts(newPorts);
    } catch (e) {
      print('Refresh serial ports error: $e');
    } finally {
      _isRefreshingPorts = false;
    }
  }

  void _applyPorts(List<String> newPorts) {
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
      final config = SerialPortConfig()
        ..baudRate = 921600
        ..bits = 8
        ..stopBits = 1
        ..parity = SerialPortParity.none;
      _serialPort!.config = config;

      if (_serialPort!.openReadWrite()) {
        clearInputBuffer();
        isConnected = true;
        _updateStatus();
        notifyListeners();
        _refreshPortsAsync();
        _startReading();
      } else {
        throw Exception('Failed to open serial port: ${SerialPort.lastError}');
      }
    } catch (e) {
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
        disconnect();
      }
    });
  }

  void sendData(Uint8List data) {
    if (isConnected && _serialPort != null) {
      try {
        _serialPort!.write(data);
      } catch (e) {
        print('Write error: $e');
        disconnect();
      }
    }
  }

  void clearInputBuffer() {
    if (_serialPort == null || !_serialPort!.isOpen) return;

    int totalCleared = 0;
    for (int attempt = 0; attempt < 8; attempt++) {
      final int bytes = _serialPort!.bytesAvailable;
      if (bytes <= 0) break;

      final data = _serialPort!.read(bytes);
      totalCleared += data.length;
      if (data.isEmpty) break;
    }

    if (totalCleared > 0) {
      print('Cleared $totalCleared residual bytes from serial input buffer');
    }
  }

  void disconnect() {
    _disconnect();
    _refreshPortsAsync();
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
    _refreshPortsAsync();
  }
}

bool setEquals<T>(Set<T> a, Set<T> b) {
  if (a.length != b.length) return false;
  return a.every(b.contains);
}
