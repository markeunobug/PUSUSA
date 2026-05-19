// main.dart
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/material.dart' as material;
import 'dart:async';
import 'package:fl_chart/fl_chart.dart';

// 瀵煎叆涓插彛鐩稿叧
import 'serial_port_manager.dart';
import 'serial_port_selector.dart';
import 'serial_protocol.dart';
import 'device_models.dart';

// 瀵煎叆鑷畾涔夐璋卞浘缁勪欢
import 'spectrum_chart.dart';

// ==================== 鎵弿模式鏋氫妇锛堥《灞傦級 ====================
enum SweepMode { standard, realTime }

enum FrequencyEditMode { startStop, centerSpan }

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return FluentApp(
      title: 'Spectrum Analyzer BUILD 2026-04-27 DEFAULT50M',
      theme: FluentThemeData(
        brightness: Brightness.dark,
        accentColor: Colors.blue,
      ),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  static const int _defaultSpectrumPointCount = 128;
  static const int _maxInternalSweepPointCount = 4096;

  final FocusNode startFreqFocus = FocusNode();
  final FocusNode stopFreqFocus = FocusNode();
  final FocusNode centerFreqFocus = FocusNode();
  final FocusNode spanFocus = FocusNode();
  final FocusNode refLevelFocus = FocusNode();
  final FocusNode rbwFocus = FocusNode();
  final FocusNode vbwFocus = FocusNode();
  final FocusNode scaleFocus = FocusNode();

  // 鍗曚綅閫夐」鍒楄〃
  final List<String> freqUnits = ['Hz', 'kHz', 'MHz', 'GHz'];

  // 频率 鍙傛暟鎺у埗鍣ㄥ拰鍗曚綅
  final TextEditingController startFreqController =
      TextEditingController(text: '50');
  final TextEditingController stopFreqController =
      TextEditingController(text: '1.5');
  final TextEditingController centerFreqController =
      TextEditingController(text: '775');
  final TextEditingController spanController =
      TextEditingController(text: '1450');
  final ValueNotifier<String> startFreqUnit = ValueNotifier<String>('MHz');
  final ValueNotifier<String> stopFreqUnit = ValueNotifier<String>('GHz');
  final ValueNotifier<String> centerFreqUnit = ValueNotifier<String>('MHz');
  final ValueNotifier<String> spanUnit = ValueNotifier<String>('MHz');

  // 幅度 鍙傛暟
  final TextEditingController refLevelController =
      TextEditingController(text: '0');
  final ValueNotifier<String> attenuatorValue = ValueNotifier<String>('自动');
  final ValueNotifier<String> preAmpValue = ValueNotifier<String>('自动');
  final ValueNotifier<String> vgaGainValue = ValueNotifier<String>('0 dB');
  RfFrontendConfig _rfFrontendConfig = const RfFrontendConfig(
    lnaMode: RfLnaMode.bypass,
    pathMode: RfPathMode.directIf,
    attenCode: 127,
  );
  RfFrontendStatus? _lastRfFrontendStatus;
  String _rfFrontendMessage = '未查询';
  final TextEditingController _rfAttenController =
      TextEditingController(text: '31.75');
  Timer? _rfFrontendSendDebounce;
  bool _rfFrontendCommandInFlight = false;
  bool _rfFrontendSendQueued = false;

  // BW 鍙傛暟鐘舵€?
  final ValueNotifier<String> rbwMode = ValueNotifier<String>('1 MHz');
  final ValueNotifier<String> rbwUnit = ValueNotifier<String>('MHz');
  final TextEditingController rbwController = TextEditingController(text: '1');
  final ValueNotifier<String> vbwMode = ValueNotifier<String>('VBW=RBW');
  final ValueNotifier<String> vbwUnit = ValueNotifier<String>('Hz');
  final TextEditingController vbwController = TextEditingController(text: '0');

  // 检波 鍙傛暟鐘舵€?
  final ValueNotifier<String> detectMode = ValueNotifier<String>('平均');

  // 图形 鍙傛暟
  final TextEditingController scalePerGridController =
      TextEditingController(text: '10');
  final TextEditingController pointCountController =
      TextEditingController(text: '128');

  // 鎵弿閫熷害锛堣缃€硷級
  final ValueNotifier<double> sweepSpeed = ValueNotifier<double>(30.0);

  // 鎵弿模式锛堥粯璁ゆ爣鍑嗘ā寮忥級
  SweepMode _sweepMode = SweepMode.standard;
  final FlyoutController _modeFlyoutController = FlyoutController();
  ConnectionStatus? _lastConnectionStatus;

  // 涓插彛绠＄悊
  late SerialPortManager _serialManager;
  late SerialProtocol _protocol;

  final FlyoutController _serialFlyoutController = FlyoutController();

  // 棰戣氨鏁版嵁
  List<FlSpot> _spectrumData = [];

  // 连续鎵弿瀹氭椂鍣?
  Timer? _continuousSweepTimer;
  Timer? _spectrumRequestTimeoutTimer;
  Timer? _sweepAssembleTimer;
  Timer? _startupSyncTimer;
  Timer? _serialInitTimer;
  bool _spectrumRequestInFlight = false;
  bool _isContinuousSweepRunning = false;
  bool _acceptSpectrumData = true;
  bool _deviceResponsive = false;
  bool _startupHandshakeInFlight = false;
  int _startupSyncAttempts = 0;
  int _startupSyncGeneration = 0;
  int _measurementConfigGeneration = 0;
  bool _measurementConfigInFlight = false;
  bool _suppressBandwidthListener = false;
  bool _awaitingTimeoutStatus = false;
  FrequencyEditMode _lastFrequencyEditMode = FrequencyEditMode.centerSpan;
  int? _activeSweepTimestamp;
  final Map<double, double> _displaySweepPoints = {};
  final Map<double, double> _pendingSweepPoints = {};

  // 零扫宽时域数据
  final List<FlSpot> _zeroSpanData = [];
  DateTime? _zeroSpanStartTime;
  static const double _zeroSpanWindowSec = 300.0;

  // 游标 绠＄悊
  List<Marker> _markers = [];
  Marker? _currentMarker;
  final TextEditingController _markerFreqController = TextEditingController();
  final ValueNotifier<String> _markerFreqUnit = ValueNotifier<String>('GHz');

  // 自动宄板€兼爣娉ㄥ紑鍏?
  final ValueNotifier<bool> autoPeakEnabled = ValueNotifier<bool>(true);

  // 鏈€灏忓嘲闂磋窛绯绘暟锛堜笓涓氶璋变华閫氬父1~3鍊峈BW锛?
  final double _minPeakSpacingRatio = 1.0;

  // 鎵弿璁℃暟鐩稿叧锛堟柊澧烇級
  int _scanCount = 0; // 鎵弿娆℃暟璁℃暟鍣?
  DateTime? _lastScanTime; // 涓婃缁熻鏃堕棿
  double _currentSweepSpeed = 0.0; // 褰撳墠瀹為檯鎵弿閫熷害锛堟/绉掞級
  Timer? _speedCalculationTimer; // 姣忕璁＄畻涓€娆℃壂鎻忛€熷害
  DateTime? _lastSpectrumArrivalTime; // 鏈€杩戜竴甯ч璋卞埌杈炬椂闂?
  double _confirmedStartHz = 50e6;
  double _confirmedStopHz = 1.5e9;

  @override
  void initState() {
    super.initState();
    _serialManager = SerialPortManager();
    _protocol = SerialProtocol(_serialManager);
    _lastConnectionStatus = _serialManager.connectionStatus.value;

    _protocol.spectrumStream.listen(_handleSpectrumData);
    _protocol.statusStream.listen(_handleStatusData);
    _protocol.rfFrontendStatusStream.listen(_handleRfFrontendStatus);
    _serialManager.connectionStatus.addListener(_handleConnectionStatusChanged);

    sweepSpeed.addListener(_sendSweepConfig);
    attenuatorValue.addListener(_sendAmplitudeConfig);
    preAmpValue.addListener(_sendAmplitudeConfig);
    vgaGainValue.addListener(_sendVgaGainConfig);
    rbwMode.addListener(() {
      _updateRbwField();
      _updateVbwField();
      if (_suppressBandwidthListener) return;
      _applyMeasurementConfigChange(clearDisplay: true);
    });
    vbwMode.addListener(() {
      _updateVbwField();
      if (_suppressBandwidthListener) return;
      _applyMeasurementConfigChange(clearDisplay: true);
    });
    detectMode.addListener(_sendDetectConfig);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _serialInitTimer = Timer(const Duration(milliseconds: 300), () {
        if (mounted) {
          _serialManager.init();
        }
      });
    });

    // 鍒濆鍖栧浐瀹?涓狹arker锛屽垵濮嬬鐢紝棰戠巼涓轰腑蹇冮鐜?
    _markers = List.generate(8,
        (index) => Marker(index + 1, _getCurrentCenterFreq(), enabled: false));

    // 榛樿寮€鍚父鏍?锛屽苟閫変腑
    _markers[0].enabled = true;
    _selectMarker(_markers[0]);

    // 鍒濆鍖栨壂鎻忚鏁扮浉鍏筹紙鏂板锛?
    _lastScanTime = DateTime.now();
    _speedCalculationTimer =
        Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_lastScanTime != null) {
        final duration = DateTime.now().difference(_lastScanTime!);
        if (duration.inMilliseconds > 0) {
          // 璁＄畻姣忕鎵弿娆℃暟
          _currentSweepSpeed = _scanCount / (duration.inMilliseconds / 1000);
        } else {
          _currentSweepSpeed = 0.0;
        }
      } else {
        _currentSweepSpeed = 0.0;
      }
      // 閲嶇疆璁℃暟鍜屾椂闂?
      _scanCount = 0;
      _lastScanTime = DateTime.now();
      setState(() {}); // 鏇存柊UI鏄剧ず
    });
  }

  @override
  void dispose() {
    //涔濅釜 FocusNode
    startFreqFocus.dispose();
    stopFreqFocus.dispose();
    centerFreqFocus.dispose();
    spanFocus.dispose();
    refLevelFocus.dispose();
    rbwFocus.dispose();
    vbwFocus.dispose();
    scaleFocus.dispose();

    startFreqController.dispose();
    stopFreqController.dispose();
    centerFreqController.dispose();
    spanController.dispose();
    refLevelController.dispose();
    rbwController.dispose();
    vbwController.dispose();
    scalePerGridController.dispose();
    pointCountController.dispose();
    _rfAttenController.dispose();
    _markerFreqController.dispose();
    _markerFreqUnit.dispose();
    _serialManager.connectionStatus
        .removeListener(_handleConnectionStatusChanged);
    _serialManager.dispose();
    _protocol.dispose();
    _serialFlyoutController.dispose();
    _modeFlyoutController.dispose();
    _continuousSweepTimer?.cancel();
    _spectrumRequestTimeoutTimer?.cancel();
    _sweepAssembleTimer?.cancel();
    _startupSyncTimer?.cancel();
    _serialInitTimer?.cancel();
    _rfFrontendSendDebounce?.cancel();
    _speedCalculationTimer?.cancel(); // 閿€姣佹壂鎻忛€熷害璁＄畻瀹氭椂鍣?
    sweepSpeed.removeListener(_sendSweepConfig);
    attenuatorValue.removeListener(_sendAmplitudeConfig);
    preAmpValue.removeListener(_sendAmplitudeConfig);
    vgaGainValue.removeListener(_sendVgaGainConfig);
    rbwMode.removeListener(() {
      _updateRbwField();
      _updateVbwField();
      _applyMeasurementConfigChange();
    });
    vbwMode.removeListener(() {
      _updateVbwField();
      _applyMeasurementConfigChange();
    });
    detectMode.removeListener(_sendDetectConfig);
    super.dispose();
  }

  void _handleConnectionStatusChanged() {
    final status = _serialManager.connectionStatus.value;
    final previous = _lastConnectionStatus;
    _lastConnectionStatus = status;

    if (status == ConnectionStatus.connected &&
        previous != ConnectionStatus.connected) {
      _protocol.resetReceiveBuffer();
      _deviceResponsive = false;
      _startupSyncAttempts = 0;
      _startupSyncTimer?.cancel();
      _startupSyncGeneration++;
      _serialManager.drainInputBuffer().then((_) {
        _protocol.resetReceiveBuffer();
      });
      _runStartupHandshake(_startupSyncGeneration);
    }

    if (status != ConnectionStatus.connected) {
      _protocol.resetReceiveBuffer();
      _startupSyncTimer?.cancel();
      _startupSyncGeneration++;
      _measurementConfigGeneration++;
      _deviceResponsive = false;
      _startupHandshakeInFlight = false;
      _measurementConfigInFlight = false;
      _awaitingTimeoutStatus = false;
      _rfFrontendSendDebounce?.cancel();
      _rfFrontendCommandInFlight = false;
      _rfFrontendSendQueued = false;
      _stopContinuousSweep();
      if (mounted) {
        setState(() {
          _rfFrontendMessage = '未连接';
          _lastRfFrontendStatus = null;
        });
      }
    }
  }

  Future<void> _runStartupHandshake(int generation) async {
    if (_startupHandshakeInFlight) {
      return;
    }
    _startupHandshakeInFlight = true;
    _startupSyncAttempts++;
    await _runStartupWakeSequence(generation);
    final ok = await _protocol.statusHandshake(attempts: 8);
    _startupHandshakeInFlight = false;
    if (!mounted ||
        generation != _startupSyncGeneration ||
        !_serialManager.isConnected) {
      return;
    }

    if (ok) {
      _deviceResponsive = true;
      await _syncCurrentDeviceConfig();
      await Future.delayed(const Duration(milliseconds: 40));
      await _serialManager.drainInputBuffer();
      _protocol.resetReceiveBuffer();
      _protocol.getStatus();
      _protocol.getRfFrontendStatus();
    } else if (_startupSyncAttempts < 5) {
      _startupSyncTimer?.cancel();
      _startupSyncTimer = Timer(const Duration(seconds: 1), () {
        _runStartupHandshake(generation);
      });
    }
  }

  Future<void> _runStartupWakeSequence(int generation) async {
    _protocol.resetReceiveBuffer();
    await _serialManager.drainInputBuffer();
    if (!mounted ||
        generation != _startupSyncGeneration ||
        !_serialManager.isConnected) {
      return;
    }

    _protocol.resetReceiveBuffer();
    _protocol.stopSweep();
    await Future.delayed(const Duration(milliseconds: 60));
    await _serialManager.drainInputBuffer();
    if (!mounted ||
        generation != _startupSyncGeneration ||
        !_serialManager.isConnected) {
      return;
    }

    _protocol.resetReceiveBuffer();
    _sendCurrentDeviceConfig();
    await Future.delayed(const Duration(milliseconds: 120));
    await _serialManager.drainInputBuffer(
      quietPeriod: const Duration(milliseconds: 50),
      timeout: const Duration(milliseconds: 500),
    );
    _protocol.resetReceiveBuffer();
  }

  // 璁＄畻鏈€灏忓嘲闂磋窛锛堝熀浜嶳BW锛屽崟浣嶏細Hz锛?
  double _getMinPeakSpacing() {
    double rbwHz =
        _parseFreq(rbwController.text, rbwUnit.value) ?? 1e6; // 榛樿1MHz鍏滃簳
    return rbwHz * _minPeakSpacingRatio;
  }

  // 绛涢€変笉閲嶅彔鐨勭嫭绔嬪嘲鍊硷紙闂磋窛鈮ユ渶灏忓嘲闂磋窛锛?
  List<FlSpot> _getNonOverlappingPeaks(List<FlSpot> sortedPeaks) {
    if (sortedPeaks.isEmpty) return [];

    final double minSpacing = _getMinPeakSpacing();
    List<FlSpot> nonOverlappingPeaks = [sortedPeaks.first];

    for (int i = 1; i < sortedPeaks.length; i++) {
      FlSpot currentPeak = sortedPeaks[i];
      // 妫€鏌ヤ笌宸查€夊嘲鍊肩殑鏈€灏忛棿璺?
      bool isOverlapping = nonOverlappingPeaks
          .any((peak) => (currentPeak.x - peak.x).abs() < minSpacing);
      if (!isOverlapping) {
        nonOverlappingPeaks.add(currentPeak);
      }
    }
    return nonOverlappingPeaks;
  }

  void _handleSpectrumData(SpectrumSegment segment) {
    _deviceResponsive = true;
    _startupSyncTimer?.cancel();
    if (!_acceptSpectrumData) {
      return;
    }
    if (segment.spots.isEmpty) {
      setState(() {});
      return;
    }

    _scanCount += segment.spots.length;

    if (_isZeroSpan) {
      final now = DateTime.now();
      _zeroSpanStartTime ??= now;
      for (var spot in segment.spots) {
        final elapsed =
            now.difference(_zeroSpanStartTime!).inMilliseconds / 1000.0;
        _zeroSpanData.add(FlSpot(elapsed, spot.y));
      }
      final cutoff = _zeroSpanData.last.x - _zeroSpanWindowSec;
      _zeroSpanData.removeWhere((s) => s.x < cutoff);

      if (_lastSpectrumArrivalTime != null) {
        final dtMs = now.difference(_lastSpectrumArrivalTime!).inMilliseconds;
        if (dtMs > 0) {
          final instantSpeed = 1000.0 / dtMs;
          _currentSweepSpeed = _currentSweepSpeed <= 0.0
              ? instantSpeed
              : _currentSweepSpeed * 0.7 + instantSpeed * 0.3;
        }
      }
      _lastSpectrumArrivalTime = now;

      if (!segment.done) {
        return;
      }

      _spectrumRequestTimeoutTimer?.cancel();
      _spectrumRequestInFlight = false;
      _activeSweepTimestamp = null;

      setState(() {
        _spectrumData = _zeroSpanData;
      });
      return;
    }

    if (_activeSweepTimestamp != segment.timestamp) {
      _activeSweepTimestamp = segment.timestamp;
      _pendingSweepPoints.clear();
    }

    final sortedSegment = List<FlSpot>.from(segment.spots)
      ..sort((a, b) => a.x.compareTo(b.x));

    for (var spot in sortedSegment) {
      _pendingSweepPoints[spot.x] = spot.y;
      _displaySweepPoints[spot.x] = spot.y;
    }

    setState(() {
      _spectrumData = _displaySweepPoints.entries
          .map((e) => FlSpot(e.key, e.value))
          .toList()
        ..sort((a, b) => a.x.compareTo(b.x));
    });

    if (segment.done) {
      _completeSweepAssembly();
    }
  }

  void _completeSweepAssembly() {
    final now = DateTime.now();

    _spectrumRequestInFlight = false;
    _spectrumRequestTimeoutTimer?.cancel();
    _activeSweepTimestamp = null;

    if (_lastSpectrumArrivalTime != null) {
      final dtMs = now.difference(_lastSpectrumArrivalTime!).inMilliseconds;
      if (dtMs > 0) {
        final instantSpeed = 1000.0 / dtMs;
        if (_currentSweepSpeed <= 0.0) {
          _currentSweepSpeed = instantSpeed;
        } else {
          _currentSweepSpeed = _currentSweepSpeed * 0.7 + instantSpeed * 0.3;
        }
      }
    }
    _lastSpectrumArrivalTime = now;

    setState(() {
      _displaySweepPoints.addAll(_pendingSweepPoints);
      _spectrumData = _displaySweepPoints.entries
          .map((e) => FlSpot(e.key, e.value))
          .toList()
        ..sort((a, b) => a.x.compareTo(b.x));

      if (autoPeakEnabled.value) {
        var enabledMarkers = _markers.where((m) => m.enabled).toList()
          ..sort((a, b) => a.id.compareTo(b.id));
        if (enabledMarkers.isNotEmpty && _spectrumData.isNotEmpty) {
          var sortedPeaks = List<FlSpot>.from(_spectrumData)
            ..sort((a, b) => b.y.compareTo(a.y));
          var nonOverlappingPeaks = _getNonOverlappingPeaks(sortedPeaks);
          for (int i = 0; i < enabledMarkers.length; i++) {
            if (i < nonOverlappingPeaks.length) {
              enabledMarkers[i].freqHz = nonOverlappingPeaks[i].x;
            } else {
              enabledMarkers[i].freqHz = nonOverlappingPeaks.isNotEmpty
                  ? nonOverlappingPeaks.last.x
                  : _getCurrentCenterFreq();
            }
          }
          if (_currentMarker != null && _currentMarker!.enabled) {
            _markerFreqController.text =
                _formatFreq(_currentMarker!.freqHz, _markerFreqUnit.value);
          }
        }
      }
    });
  }

  void _handleStatusData(Map<String, dynamic> status) {
    _deviceResponsive = true;
    _startupSyncTimer?.cancel();
    _awaitingTimeoutStatus = false;
    print(
      'Device status detail: error=${status['errorCode']}, '
      'spectrumValid=${status['spectrumValid'] ?? '-'}, '
      'dmaStart=${status['dmaStartCount'] ?? '-'}, '
      'dmaError=${status['dmaErrorCount'] ?? '-'}, '
      'frameReady=${status['frameReadyCount'] ?? '-'}, '
      'processFrame=${status['processFrameCount'] ?? '-'}, '
      's2mmDmasr=${status['s2mmDmasr'] != null ? '0x${(status['s2mmDmasr'] as int).toRadixString(16)}' : '-'}',
    );
  }

  void _handleRfFrontendStatus(RfFrontendStatus status) {
    _deviceResponsive = true;
    _startupSyncTimer?.cancel();
    if (!mounted) return;

    final hasPendingLocalChange = _rfFrontendCommandInFlight ||
        _rfFrontendSendQueued ||
        _rfFrontendSendDebounce?.isActive == true;

    setState(() {
      _lastRfFrontendStatus = status;
      if (!hasPendingLocalChange) {
        _rfFrontendConfig = status.config;
        _syncRfAttenText(status.config);
      }
      _rfFrontendMessage = status.ok
          ? '已应用：${_formatRfFrontendConfig(status.config)}'
          : '设备返回错误：${_rfFrontendErrorLabel(status.error)}';
    });
  }

  void _clearSpectrumDisplay() {
    _sweepAssembleTimer?.cancel();
    _activeSweepTimestamp = null;
    _pendingSweepPoints.clear();
    _displaySweepPoints.clear();
    _zeroSpanData.clear();
    _zeroSpanStartTime = null;
    setState(() {
      _spectrumData = [];
    });
  }

  double _getCurrentStartFreq() {
    return _confirmedStartHz;
  }

  double _getCurrentStopFreq() {
    return _confirmedStopHz;
  }

  bool get _isZeroSpan =>
      _confirmedStartHz > 0 && _confirmedStartHz == _confirmedStopHz;

  double _getCurrentCenterFreq() {
    return (_confirmedStartHz + _confirmedStopHz) / 2.0;
  }

  double _getUnitFactor(String unit) {
    switch (unit) {
      case 'kHz':
        return 1e3;
      case 'MHz':
        return 1e6;
      case 'GHz':
        return 1e9;
      default:
        return 1.0;
    }
  }

  double? _parseFreq(String text, String unit) {
    final double? value = double.tryParse(text);
    if (value == null || value < 0) return null;
    return value * _getUnitFactor(unit);
  }

  String _formatFreqAutoUnit(double freqHz, [int decimalPlaces = 2]) {
    if (freqHz >= 1e9) {
      return '${(freqHz / 1e9).toStringAsFixed(decimalPlaces)} GHz';
    }
    if (freqHz >= 1e6) {
      return '${(freqHz / 1e6).toStringAsFixed(decimalPlaces)} MHz';
    }
    if (freqHz >= 1e3) {
      return '${(freqHz / 1e3).toStringAsFixed(decimalPlaces)} kHz';
    }
    return '${freqHz.toStringAsFixed(decimalPlaces)} Hz';
  }

  String _formatFreq(double freqHz, String unit, [int decimalPlaces = 2]) {
    final double factor = _getUnitFactor(unit);
    return (freqHz / factor).toStringAsFixed(decimalPlaces);
  }

  String _formatFreqInput(double freqHz, String unit) {
    final double factor = _getUnitFactor(unit);
    final text = (freqHz / factor).toStringAsFixed(6);
    return text
        .replaceFirst(RegExp(r'0+$'), '')
        .replaceFirst(RegExp(r'\.$'), '');
  }

  void _syncFrequencyFieldsFromConfirmed() {
    final startHz = _confirmedStartHz;
    final stopHz = _confirmedStopHz;
    final centerHz = (startHz + stopHz) / 2.0;
    final spanHz = stopHz - startHz;

    _setFreqField(startFreqController, startFreqUnit, startHz);
    _setFreqField(stopFreqController, stopFreqUnit, stopHz);
    _setFreqField(centerFreqController, centerFreqUnit, centerHz);
    _setFreqField(spanController, spanUnit, spanHz);
  }

  void _setFreqField(TextEditingController controller,
      ValueNotifier<String> unitNotifier, double freqHz) {
    String bestUnit;
    if (freqHz >= 1e9) {
      bestUnit = 'GHz';
    } else if (freqHz >= 1e6) {
      bestUnit = 'MHz';
    } else if (freqHz >= 1e3) {
      bestUnit = 'kHz';
    } else {
      bestUnit = 'Hz';
    }
    unitNotifier.value = bestUnit;
    controller.text = _formatFreqInput(freqHz, bestUnit);
  }

  double _getSelectedRbwHz() {
    return _getRbwHzForMode(rbwMode.value);
  }

  double _getRbwHzForMode(String mode) {
    switch (mode) {
      case '10 kHz':
        return 10e3;
      case '30 kHz':
        return 30e3;
      case '100 kHz':
        return 100e3;
      case '300 kHz':
        return 300e3;
      case '1 MHz':
      default:
        return 1e6;
    }
  }

  void _updateRbwField() {
    _setFreqField(rbwController, rbwUnit, _getSelectedRbwHz());
  }

  void _updateVbwField() {
    if (!vbwMode.value.startsWith('VBW=')) return;
    final double rbwHz = _getSelectedRbwHz();
    double vbwHz = rbwHz;
    switch (vbwMode.value) {
      case 'VBW=0.1*RBW':
        vbwHz *= 0.1;
        break;
      case 'VBW=0.01*RBW':
        vbwHz *= 0.01;
        break;
      case 'VBW=10*RBW':
        vbwHz *= 10;
        break;
    }
    _setFreqField(vbwController, vbwUnit, vbwHz);
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => ContentDialog(
        title: const Text('参数错误'),
        content: Text(message),
        actions: [
          Button(
              child: const Text('确定'), onPressed: () => Navigator.pop(context))
        ],
      ),
    );
  }

  bool _commitFrequencyInputs({bool showDialog = true}) {
    switch (_lastFrequencyEditMode) {
      case FrequencyEditMode.startStop:
        return _commitStartStopInputs(showDialog: showDialog);
      case FrequencyEditMode.centerSpan:
        return _commitCenterSpanInputs(showDialog: showDialog);
    }
  }

  bool _commitStartStopInputs({bool showDialog = true}) {
    final double? startHz =
        _parseFreq(startFreqController.text.trim(), startFreqUnit.value);
    final double? stopHz =
        _parseFreq(stopFreqController.text.trim(), stopFreqUnit.value);
    if (startHz == null || stopHz == null) {
      if (showDialog) {
        _showErrorDialog('Invalid start/stop frequency input');
      }
      return false;
    }
    if (startHz > stopHz) {
      if (showDialog) {
        _showErrorDialog(
            'Start frequency cannot be greater than stop frequency');
      }
      return false;
    }

    setState(() {
      _confirmedStartHz = startHz;
      _confirmedStopHz = stopHz;
      _syncFrequencyFieldsFromConfirmed();
    });
    return true;
  }

  bool _commitCenterSpanInputs({bool showDialog = true}) {
    final double? centerHz =
        _parseFreq(centerFreqController.text.trim(), centerFreqUnit.value);
    final double? spanHz =
        _parseFreq(spanController.text.trim(), spanUnit.value);
    if (centerHz == null || spanHz == null) {
      if (showDialog) {
        _showErrorDialog('Invalid center/span frequency input');
      }
      return false;
    }
    if (spanHz < 0) {
      if (showDialog) {
        _showErrorDialog('Span cannot be negative');
      }
      return false;
    }

    final double startHz = centerHz - spanHz / 2;
    final double stopHz = centerHz + spanHz / 2;
    if (startHz < 0) {
      if (showDialog) {
        _showErrorDialog('Start frequency cannot be negative');
      }
      return false;
    }

    setState(() {
      _confirmedStartHz = startHz;
      _confirmedStopHz = stopHz;
      _syncFrequencyFieldsFromConfirmed();
    });
    return true;
  }

  void _updateFreqFromStartStop() {
    _lastFrequencyEditMode = FrequencyEditMode.startStop;
    if (!_commitStartStopInputs()) return;
    _updateRbwField();
    _updateVbwField();
    _applyFrequencyChange();
  }

  void _updateFreqFromCenterSpan() {
    _lastFrequencyEditMode = FrequencyEditMode.centerSpan;
    if (!_commitCenterSpanInputs()) return;
    _updateRbwField();
    _updateVbwField();
    _applyFrequencyChange();
  }

  void _sendAmplitudeConfig() {
    final double refLevel = double.tryParse(refLevelController.text) ?? 0;
    int attenuator = _mapAttenuatorStringToInt(attenuatorValue.value);
    int preamp = _mapPreAmpStringToInt(preAmpValue.value);
    _protocol.setAmplitude(refLevel, attenuator, preamp);
  }

  void _sendVgaGainConfig() {
    _protocol.setVgaGainCode(_mapVgaGainStringToCode(vgaGainValue.value));
  }

  void _updateRfFrontendConfig(RfFrontendConfig config) {
    final clamped =
        config.copyWith(attenCode: config.attenCode.clamp(0, 127).toInt());
    setState(() {
      _rfFrontendConfig = clamped;
      _syncRfAttenText(clamped);
      _rfFrontendMessage = '等待发送：${_formatRfFrontendConfig(clamped)}';
    });
    _scheduleRfFrontendSend();
  }

  void _scheduleRfFrontendSend() {
    _rfFrontendSendDebounce?.cancel();
    if (_rfFrontendCommandInFlight) {
      _rfFrontendSendQueued = true;
      return;
    }
    _rfFrontendSendDebounce =
        Timer(const Duration(milliseconds: 180), _sendRfFrontendConfig);
  }

  Future<void> _sendRfFrontendConfig() async {
    _rfFrontendSendDebounce?.cancel();
    if (!_serialManager.isConnected || _rfFrontendCommandInFlight) {
      return;
    }

    final config = _rfFrontendConfig;
    setState(() {
      _rfFrontendCommandInFlight = true;
      _rfFrontendMessage = '正在发送：${_formatRfFrontendConfig(config)}';
    });

    final ok = await _protocol.setRfFrontendConfirmed(config);
    if (!mounted) return;

    setState(() {
      _rfFrontendCommandInFlight = false;
      _rfFrontendMessage = ok ? 'ACK OK，等待状态回读' : 'ACK 超时或失败';
    });

    if (_rfFrontendSendQueued) {
      _rfFrontendSendQueued = false;
      _scheduleRfFrontendSend();
    }

    if (ok && _serialManager.isConnected) {
      _protocol.getRfFrontendStatus();
    }
  }

  void _queryRfFrontendStatus() {
    if (!_serialManager.isConnected) {
      setState(() {
        _rfFrontendMessage = '未连接';
      });
      return;
    }
    _protocol.getRfFrontendStatus();
    setState(() {
      _rfFrontendMessage = '正在查询';
    });
  }

  Future<void> _submitBandwidthConfig() {
    return _applyMeasurementConfigChange(clearDisplay: true);
  }

  void _sendDetectConfig() {
    _protocol.setDetect(_mapDetectStringToInt(detectMode.value));
  }

  int _estimateInternalSweepPointCount() {
    final points = _estimateRawInternalSweepPointCount();
    if (points == null) {
      return _getCurrentPointCount();
    }
    if (points < 2) {
      return 2;
    }
    if (points > 4096) {
      return 4096;
    }
    return points;
  }

  int? _estimateRawInternalSweepPointCount() {
    return _estimateRawInternalSweepPointCountForRbwHz(_getSelectedRbwHz());
  }

  int? _estimateRawInternalSweepPointCountForRbwHz(double rbwHz) {
    final startHz = _getCurrentStartFreq();
    final stopHz = _getCurrentStopFreq();
    if (stopHz <= startHz || rbwHz <= 0) {
      return null;
    }

    final stepHz = rbwHz / 2.0;
    return ((stopHz - startHz) / stepHz).floor() + 1;
  }

  bool _isSweepWorkloadSupported({bool showDialog = false}) {
    final rawPoints = _estimateRawInternalSweepPointCount();
    if (rawPoints == null || rawPoints <= _maxInternalSweepPointCount) {
      return true;
    }

    if (showDialog && mounted) {
      final rbwHz = _getSelectedRbwHz();
      final maxSpanHz = (_maxInternalSweepPointCount - 1) * (rbwHz / 2.0);
      _showErrorDialog(
        '当前扫宽/RBW组合需要约 $rawPoints 个内部扫描点，容易导致下位机长时间无响应。\n'
        '请把扫宽缩小到 ${_formatFreqAutoUnit(maxSpanHz, 2)} 以内，'
        '或先使用 300 kHz / 1 MHz RBW。',
      );
    }
    return false;
  }

  String? _findSupportedRbwModeForCurrentSpan() {
    for (final mode in const ['300 kHz', '1 MHz']) {
      final rawPoints =
          _estimateRawInternalSweepPointCountForRbwHz(_getRbwHzForMode(mode));
      if (rawPoints == null || rawPoints <= _maxInternalSweepPointCount) {
        return mode;
      }
    }
    return null;
  }

  Duration _getSpectrumRequestTimeout() {
    if (_isZeroSpan) return const Duration(milliseconds: 3000);
    final estimatedPoints = _estimateInternalSweepPointCount();
    final timeoutMs = estimatedPoints * 80 + 5000;
    return Duration(milliseconds: timeoutMs.clamp(10000, 180000));
  }

  int _getCurrentPointCount() {
    final parsed = int.tryParse(pointCountController.text.trim()) ??
        _defaultSpectrumPointCount;
    if (parsed < 8) {
      return 8;
    }
    if (parsed > 512) {
      return 512;
    }
    return parsed;
  }

  DeviceControlConfig _buildCurrentControlConfig() {
    final startHz = _getCurrentStartFreq();
    final stopHz = _getCurrentStopFreq();
    final centerHz = _getCurrentCenterFreq();
    final spanHz = (stopHz > startHz) ? (stopHz - startHz) : 0.0;

    return DeviceControlConfig(
      frequency: FrequencyConfig(
        startHz: startHz,
        stopHz: stopHz,
        centerHz: centerHz,
        spanHz: spanHz,
      ),
      amplitude: AmplitudeConfig(
        refLevelDbm: double.tryParse(refLevelController.text) ?? 0,
        attenuatorMode: _mapAttenuatorStringToInt(attenuatorValue.value),
        preampMode: _mapPreAmpStringToInt(preAmpValue.value),
      ),
      bandwidth: BandwidthConfig(
        rbwMode: _mapRbwModeStringToInt(rbwMode.value),
        rbwHz: _getSelectedRbwHz(),
        vbwMode: _mapVbwModeStringToInt(vbwMode.value),
        vbwHz: _parseFreq(vbwController.text, vbwUnit.value) ?? 0,
      ),
      sweep: SweepConfig(
        speedHz: sweepSpeed.value,
        mode: _sweepMode == SweepMode.standard ? 0 : 1,
        pointCount: _getCurrentPointCount(),
      ),
      detect: DetectConfig(
        mode: _mapDetectStringToInt(detectMode.value),
      ),
    );
  }

  void _sendCurrentDeviceConfig() {
    final config = _buildCurrentControlConfig();
    _confirmedStartHz = config.frequency.startHz;
    _confirmedStopHz = config.frequency.stopHz;
    _protocol.applyControlConfig(config);
    _sendVgaGainConfig();
  }

  Future<bool> _syncCurrentDeviceConfig() async {
    final config = _buildCurrentControlConfig();
    _confirmedStartHz = config.frequency.startHz;
    _confirmedStopHz = config.frequency.stopHz;
    final ok = await _protocol.applyControlConfigConfirmed(config);
    if (!ok) {
      print('Control config ACK timeout or failure');
      return false;
    }
    _sendVgaGainConfig();
    return true;
  }

  String _rfLnaModeLabel(RfLnaMode mode) {
    switch (mode) {
      case RfLnaMode.bypass:
        return '直通';
      case RfLnaMode.enable:
        return 'LNA';
      case RfLnaMode.auto:
        return '自动';
    }
  }

  String _rfPathModeLabel(RfPathMode mode) {
    switch (mode) {
      case RfPathMode.directIf:
        return '直通 IF';
      case RfPathMode.mixerChain:
        return '混频';
      case RfPathMode.auto:
        return '自动';
    }
  }

  void _syncRfAttenText(RfFrontendConfig config) {
    _rfAttenController.text = config.attenDb.toStringAsFixed(2);
  }

  void _submitRfAttenText() {
    final value = double.tryParse(_rfAttenController.text.trim());
    if (value == null) {
      _syncRfAttenText(_rfFrontendConfig);
      return;
    }

    final code = (value.clamp(0.0, 31.75) / 0.25).round().clamp(0, 127).toInt();
    _updateRfFrontendConfig(_rfFrontendConfig.copyWith(attenCode: code));
  }

  String _rfFrontendErrorLabel(int error) {
    switch (error) {
      case 0:
        return '0：OK';
      case 1:
        return '1：RF GPIO 未就绪/不可用';
      case 2:
        return '2：参数无效';
      case 3:
        return '3：GPIO 初始化失败';
      default:
        return '$error：未知错误';
    }
  }

  String _formatRfFrontendConfig(RfFrontendConfig config) {
    return '${_rfLnaModeLabel(config.lnaMode)} / '
        '${_rfPathModeLabel(config.pathMode)} / '
        '${config.attenDb.toStringAsFixed(2)} dB';
  }

  void _sendSweepConfig() {
    _protocol.setSweep(sweepSpeed.value,
        _sweepMode == SweepMode.standard ? 0 : 1, _getCurrentPointCount());
  }

  // ====================== 浼犵粺 switch 璇彞锛堝吋瀹规棫 Dart 鐗堟湰锛?======================
  int _mapAttenuatorStringToInt(String value) {
    switch (value) {
      case '自动':
        return 0;
      case '0dB':
        return 1;
      case '0.25dB':
        return 2;
      case '0.5dB':
        return 3;
      case '1dB':
        return 4;
      case '2dB':
        return 5;
      case '4dB':
        return 6;
      case '8dB':
        return 7;
      case '16dB':
        return 8;
      case '31.75dB':
        return 9;
      default:
        return 0;
    }
  }

  int _mapPreAmpStringToInt(String value) {
    switch (value) {
      case '自动':
        return 0;
      case '使能':
        return 1;
      case '关闭':
        return 2;
      default:
        return 0;
    }
  }

  int _mapVgaGainStringToCode(String value) {
    switch (value) {
      case '-11 dB':
        return 0x05;
      case '-10 dB':
        return 0x06;
      case '-6 dB':
        return 0x09;
      case '-3 dB':
        return 0x0D;
      case '0 dB':
        return 0x12;
      case '3 dB':
        return 0x19;
      case '6 dB':
        return 0x24;
      case '10 dB':
        return 0x39;
      case '20 dB':
        return 0x99;
      case '30 dB':
        return 0xD0;
      case '34 dB':
        return 0xFF;
      default:
        return 0x12;
    }
  }

  int _mapRbwModeStringToInt(String value) {
    switch (value) {
      case '10 kHz':
        return 0;
      case '30 kHz':
        return 1;
      case '100 kHz':
        return 2;
      case '300 kHz':
        return 3;
      case '1 MHz':
      default:
        return 4;
    }
  }

  int _mapVbwModeStringToInt(String value) {
    switch (value) {
      case 'VBW=RBW':
        return 0;
      case '手动':
        return 1;
      case 'VBW=0.1*RBW':
        return 2;
      case 'VBW=0.01*RBW':
        return 3;
      case 'VBW=10*RBW':
        return 4;
      default:
        return 0;
    }
  }

  int _mapDetectStringToInt(String value) {
    switch (value) {
      case '平均':
        return 0;
      case '取样':
        return 1;
      case '正峰值':
        return 2;
      case '负峰值':
        return 3;
      case '最大功率':
        return 4;
      case '均方根值':
        return 5;
      default:
        return 0;
    }
  }

  Future<void> _requestSpectrumIfIdle() async {
    if (_getCurrentStartFreq() > _getCurrentStopFreq()) {
      return;
    }
    if (_awaitingTimeoutStatus) {
      return;
    }
    if (!_isSweepWorkloadSupported(showDialog: true)) {
      _acceptSpectrumData = false;
      _spectrumRequestInFlight = false;
      _activeSweepTimestamp = null;
      _pendingSweepPoints.clear();
      return;
    }
    if (_spectrumRequestInFlight) {
      return;
    }
    if (_measurementConfigInFlight) {
      return;
    }
    if (!_serialManager.isConnected) {
      return;
    }
    if (!_deviceResponsive) {
      _startupSyncGeneration++;
      _runStartupHandshake(_startupSyncGeneration);
      return;
    }

    _acceptSpectrumData = true;
    _spectrumRequestInFlight = true;
    _activeSweepTimestamp = null;
    _pendingSweepPoints.clear();
    _protocol.resetReceiveBuffer();
    await _serialManager.drainInputBuffer(
      quietPeriod: const Duration(milliseconds: 25),
      timeout: const Duration(milliseconds: 180),
    );
    if (!mounted ||
        !_serialManager.isConnected ||
        _measurementConfigInFlight ||
        !_spectrumRequestInFlight) {
      _spectrumRequestInFlight = false;
      return;
    }
    _protocol.resetReceiveBuffer();
    final rawPoints = _estimateRawInternalSweepPointCount();
    print(
      'Request spectrum: rbw=${_formatFreqAutoUnit(_getSelectedRbwHz())}, '
      'span=${_formatFreqAutoUnit(_getCurrentStopFreq() - _getCurrentStartFreq())}, '
      'estimatedInternalPoints=${rawPoints ?? _getCurrentPointCount()}, '
      'displayPoints=${_getCurrentPointCount()}',
    );
    _protocol.getSpectrum(_getCurrentPointCount());

    final requestTimeout = _getSpectrumRequestTimeout();
    _spectrumRequestTimeoutTimer?.cancel();
    _spectrumRequestTimeoutTimer = Timer(requestTimeout, () async {
      print(
        'Spectrum request timed out after ${requestTimeout.inSeconds}s: '
        'rbw=${_formatFreqAutoUnit(_getSelectedRbwHz())}, '
        'span=${_formatFreqAutoUnit(_getCurrentStopFreq() - _getCurrentStartFreq())}, '
        'estimatedInternalPoints=${_estimateRawInternalSweepPointCount() ?? _getCurrentPointCount()}',
      );
      _spectrumRequestInFlight = false;
      _activeSweepTimestamp = null;
      _pendingSweepPoints.clear();
      final wasContinuous = _isContinuousSweepRunning;
      _continuousSweepTimer?.cancel();
      _continuousSweepTimer = null;
      if (wasContinuous && mounted) {
        setState(() {
          _isContinuousSweepRunning = false;
        });
      }
      _awaitingTimeoutStatus = true;
      _protocol.getStatus();
      await Future.delayed(const Duration(milliseconds: 250));
      _awaitingTimeoutStatus = false;
      if (!mounted) return;
      setState(() {
        _spectrumData = _displaySweepPoints.entries
            .map((e) => FlSpot(e.key, e.value))
            .toList()
          ..sort((a, b) => a.x.compareTo(b.x));
      });
      print(
        'Spectrum sweep paused after timeout. Press single/continuous sweep to retry.',
      );
    });
  }

  Future<void> _startContinuousSweep() async {
    _continuousSweepTimer?.cancel();
    await _applyMeasurementConfigChange(forceContinuous: true);
  }

  void _stopContinuousSweep() {
    _measurementConfigGeneration++;
    _measurementConfigInFlight = false;
    _awaitingTimeoutStatus = false;
    if (_serialManager.isConnected) {
      _protocol.stopSweep();
    }
    _acceptSpectrumData = false;
    _continuousSweepTimer?.cancel();
    _spectrumRequestTimeoutTimer?.cancel();
    _sweepAssembleTimer?.cancel();
    _spectrumRequestInFlight = false;
    _activeSweepTimestamp = null;
    _pendingSweepPoints.clear();
    _protocol.resetReceiveBuffer();
    _serialManager
        .drainInputBuffer()
        .then((_) => _protocol.resetReceiveBuffer());
    if (_isContinuousSweepRunning) {
      setState(() {
        _isContinuousSweepRunning = false;
      });
    }
  }

  Future<void> _applyFrequencyChange() {
    return _applyMeasurementConfigChange(clearDisplay: true);
  }

  Future<void> _applyMeasurementConfigChange({
    bool? forceContinuous,
    bool clearDisplay = false,
  }) async {
    if (!_commitFrequencyInputs()) {
      return;
    }
    if (!_isSweepWorkloadSupported()) {
      final fallbackRbwMode = forceContinuous != null
          ? _findSupportedRbwModeForCurrentSpan()
          : null;
      if (fallbackRbwMode != null && fallbackRbwMode != rbwMode.value) {
        _suppressBandwidthListener = true;
        try {
          rbwMode.value = fallbackRbwMode;
          _updateRbwField();
          _updateVbwField();
        } finally {
          _suppressBandwidthListener = false;
        }
        return _applyMeasurementConfigChange(
          forceContinuous: forceContinuous,
          clearDisplay: clearDisplay,
        );
      }

      _isSweepWorkloadSupported(showDialog: true);

      _measurementConfigGeneration++;
      _measurementConfigInFlight = false;
      _spectrumRequestInFlight = false;
      _continuousSweepTimer?.cancel();
      _spectrumRequestTimeoutTimer?.cancel();
      _protocol.stopSweep();
      _acceptSpectrumData = false;
      _activeSweepTimestamp = null;
      _pendingSweepPoints.clear();
      if (_isContinuousSweepRunning && mounted) {
        setState(() {
          _isContinuousSweepRunning = false;
        });
      }
      return;
    }

    final generation = ++_measurementConfigGeneration;
    final shouldContinue = forceContinuous ?? _isContinuousSweepRunning;
    _measurementConfigInFlight = true;
    _continuousSweepTimer?.cancel();
    _spectrumRequestTimeoutTimer?.cancel();
    _spectrumRequestInFlight = false;
    _acceptSpectrumData = false;
    _protocol.stopSweep();
    if (clearDisplay) {
      _clearSpectrumDisplay();
    }
    _activeSweepTimestamp = null;
    _pendingSweepPoints.clear();
    _zeroSpanData.clear();
    _zeroSpanStartTime = null;

    await Future.delayed(const Duration(milliseconds: 60));
    if (_awaitingTimeoutStatus) {
      await Future.delayed(const Duration(milliseconds: 250));
    }
    await _serialManager.drainInputBuffer();
    _protocol.resetReceiveBuffer();
    if (!mounted ||
        generation != _measurementConfigGeneration ||
        !_serialManager.isConnected) {
      if (generation == _measurementConfigGeneration) {
        _measurementConfigInFlight = false;
      }
      return;
    }

    final configApplied = await _syncCurrentDeviceConfig();
    if (!configApplied) {
      _measurementConfigInFlight = false;
      _acceptSpectrumData = false;
      return;
    }
    await Future.delayed(const Duration(milliseconds: 40));
    _protocol.resetReceiveBuffer();
    if (!mounted ||
        generation != _measurementConfigGeneration ||
        !_serialManager.isConnected) {
      if (generation == _measurementConfigGeneration) {
        _measurementConfigInFlight = false;
      }
      return;
    }

    _measurementConfigInFlight = false;
    _acceptSpectrumData = true;

    if (shouldContinue && mounted) {
      if (!_isContinuousSweepRunning) {
        setState(() {
          _isContinuousSweepRunning = true;
        });
      }
      await _requestSpectrumIfIdle();
      _continuousSweepTimer = Timer.periodic(
        Duration(milliseconds: (1000 / sweepSpeed.value).round()),
        (_) => _requestSpectrumIfIdle(),
      );
    } else {
      await _requestSpectrumIfIdle();
    }
  }

  void _showModeFlyout() {
    _modeFlyoutController.showFlyout(
      builder: (context) => FlyoutContent(
        child: SizedBox(
          width: 280,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text('标准模式'),
                subtitle: const Text('分段扫描，显示扫频进度（大扫宽推荐）'),
                trailing: _sweepMode == SweepMode.standard
                    ? const Icon(FluentIcons.check_mark)
                    : const SizedBox.shrink(),
                onPressed: () {
                  setState(() {
                    _sweepMode = SweepMode.standard;
                    _spectrumData.clear();
                  });
                  Navigator.pop(context);
                },
              ),
              ListTile(
                title: const Text('实时模式'),
                subtitle: const Text('全帧实时刷新（小扫宽推荐）'),
                trailing: _sweepMode == SweepMode.realTime
                    ? const Icon(FluentIcons.check_mark)
                    : const SizedBox.shrink(),
                onPressed: () {
                  setState(() => _sweepMode = SweepMode.realTime);
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 鍚戝乏瀵诲嘲锛堣烦杩囨渶灏忓嘲闂磋窛锛?
  double _findLeftPeak(double currentFreq) {
    if (_spectrumData.isEmpty) return currentFreq;

    final double minSpacing = _getMinPeakSpacing();
    // 绛涢€夊綋鍓嶉鐜囧乏渚т笖闂磋窛鈮ユ渶灏忛棿璺濈殑鐐?
    var leftData = _spectrumData
        .where((spot) => spot.x < currentFreq - minSpacing)
        .toList();

    if (leftData.isEmpty) return currentFreq;
    // 鎵惧埌宸︿晶鏈€澶у箙鍊肩殑鐐?
    return leftData.reduce((a, b) => a.y > b.y ? a : b).x;
  }

  // 鍚戝彸瀵诲嘲锛堣烦杩囨渶灏忓嘲闂磋窛锛?
  double _findRightPeak(double currentFreq) {
    if (_spectrumData.isEmpty) return currentFreq;

    final double minSpacing = _getMinPeakSpacing();
    // 绛涢€夊綋鍓嶉鐜囧彸渚т笖闂磋窛鈮ユ渶灏忛棿璺濈殑鐐?
    var rightData = _spectrumData
        .where((spot) => spot.x > currentFreq + minSpacing)
        .toList();

    if (rightData.isEmpty) return currentFreq;
    // 鎵惧埌鍙充晶鏈€澶у箙鍊肩殑鐐?
    return rightData.reduce((a, b) => a.y > b.y ? a : b).x;
  }

  void _selectMarker(Marker? marker) {
    setState(() {
      _currentMarker = marker;
    });
    if (marker != null) {
      _markerFreqController.text =
          _formatFreq(marker.freqHz, _markerFreqUnit.value);
    } else {
      _markerFreqController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final double startFreq = _confirmedStartHz;
    final double stopFreq = _confirmedStopHz;
    final double centerFreq = (startFreq + stopFreq) / 2;
    final double span = stopFreq - startFreq;

    final double refLevel = double.tryParse(refLevelController.text) ?? 0;
    final double scalePerGrid =
        (double.tryParse(scalePerGridController.text) ?? 10)
            .abs()
            .clamp(0.1, 1e6);
    final double maxDbmDisplay = refLevel;
    final double minDbmDisplay = refLevel - 10 * scalePerGrid;

    return ScaffoldPage(
      padding: const EdgeInsets.only(top: 0),
      header: CommandBar(
        overflowBehavior: CommandBarOverflowBehavior.wrap,
        primaryItems: [
          CommandBarButton(
            icon: Image.asset('assets/imgs/logo6.png', width: 127, height: 35),
            onPressed: null,
          ),
          CommandBarButton(
              icon: const Icon(FluentIcons.document),
              label: const Text('文件'),
              onPressed: () {}),

          // 模式鎸夐挳锛堝彧鏄剧ず鈥滄ā寮忊€濓級
          CommandBarButton(
            icon: FlyoutTarget(
              controller: _modeFlyoutController,
              child: const Icon(FluentIcons.settings),
            ),
            label: const Text('模式'),
            onPressed: _showModeFlyout,
          ),

          CommandBarButton(
              icon: const Icon(FluentIcons.toolbox),
              label: const Text('系统'),
              onPressed: () {}),
          CommandBarButton(
              icon: const Icon(FluentIcons.refresh),
              label: const Text('预设'),
              onPressed: () {
                _protocol.reset();
                _spectrumData.clear();
              }),
          CommandBarButton(
            icon: const Icon(FluentIcons.play),
            label: const Text('单次'),
            onPressed: () async {
              if (_isContinuousSweepRunning) {
                _stopContinuousSweep();
              }
              await _applyMeasurementConfigChange(forceContinuous: false);
            },
          ),
          CommandBarButton(
              icon: const Icon(FluentIcons.play_resume),
              label: const Text('连续'),
              onPressed: _startContinuousSweep),
          CommandBarButton(
            icon: Icon(_isContinuousSweepRunning
                ? FluentIcons.stop
                : FluentIcons.record2),
            label: const Text('停止'),
            onPressed: _stopContinuousSweep,
          ),
          CommandBarButton(
              icon: const Icon(FluentIcons.repeat_all),
              label: const Text('回放'),
              onPressed: () {}),
          CommandBarButton(
              icon: const Icon(FluentIcons.camera),
              label: const Text('截图'),
              onPressed: () {}),
          const CommandBarSeparator(),
          CommandBarButton(
            icon: FlyoutTarget(
              controller: _serialFlyoutController,
              child: ValueListenableBuilder<ConnectionStatus>(
                valueListenable: _serialManager.connectionStatus,
                builder: (context, status, child) {
                  Color color;
                  switch (status) {
                    // 浼犵粺 switch
                    case ConnectionStatus.connected:
                      color = material.Colors.green;
                      break;
                    case ConnectionStatus.disconnected:
                      color = material.Colors.red;
                      break;
                    case ConnectionStatus.noPorts:
                      color = material.Colors.grey;
                      break;
                  }
                  return Container(
                    width: 12,
                    height: 12,
                    decoration:
                        BoxDecoration(shape: BoxShape.circle, color: color),
                  );
                },
              ),
            ),
            label: const Text('串口'),
            onPressed: () => _serialFlyoutController.showFlyout(
              builder: (context) => SerialPortSelector(manager: _serialManager),
            ),
          ),
        ],
      ),
      content: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Acrylic(
              tint: material.Colors.black.withOpacity(0.8),
              child: SpectrumChart(
                data: _isZeroSpan ? _zeroSpanData : _spectrumData,
                minFreq: _isZeroSpan ? 0.0 : startFreq,
                maxFreq: _isZeroSpan
                    ? (_zeroSpanData.isNotEmpty
                        ? _zeroSpanData.last.x + 1.0
                        : 10.0)
                    : stopFreq,
                minDbm: minDbmDisplay,
                maxDbm: maxDbmDisplay,
                scalePerGrid: scalePerGrid,
                startFreqStr: _formatFreqAutoUnit(startFreq),
                stopFreqStr: _formatFreqAutoUnit(stopFreq),
                centerFreqStr: _formatFreqAutoUnit(centerFreq),
                spanStr: _formatFreqAutoUnit(span),
                sweepSpeedStr:
                    '${_currentSweepSpeed.toStringAsFixed(1)} packets/s',
                markers: _markers,
                isZeroSpan: _isZeroSpan,
                zeroSpanFreqStr:
                    _isZeroSpan ? _formatFreqAutoUnit(_confirmedStartHz) : '',
                zeroSpanElapsedStr: _isZeroSpan && _zeroSpanStartTime != null
                    ? '${DateTime.now().difference(_zeroSpanStartTime!).inSeconds} s'
                    : '',
              ),
            ),
          ),
          Container(
            width: 300,
            color: const Color.fromARGB(255, 66, 66, 66),
            padding: const EdgeInsets.all(8),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expander(
                    header: const Text('频率'),
                    content: Column(
                      children: [
                        _buildInputRow(
                            label: '起始频率：',
                            controller: startFreqController,
                            unitNotifier: startFreqUnit,
                            units: freqUnits,
                            onChanged: () => _lastFrequencyEditMode =
                                FrequencyEditMode.startStop,
                            onSubmitted: _updateFreqFromStartStop),
                        const SizedBox(height: 8),
                        _buildInputRow(
                            label: '终止频率：',
                            controller: stopFreqController,
                            unitNotifier: stopFreqUnit,
                            units: freqUnits,
                            onChanged: () => _lastFrequencyEditMode =
                                FrequencyEditMode.startStop,
                            onSubmitted: _updateFreqFromStartStop),
                        const SizedBox(height: 8),
                        _buildInputRow(
                            label: '中心频率：',
                            controller: centerFreqController,
                            unitNotifier: centerFreqUnit,
                            units: freqUnits,
                            onChanged: () => _lastFrequencyEditMode =
                                FrequencyEditMode.centerSpan,
                            onSubmitted: _updateFreqFromCenterSpan),
                        const SizedBox(height: 8),
                        _buildInputRow(
                            label: '扫描宽度：',
                            controller: spanController,
                            unitNotifier: spanUnit,
                            units: freqUnits,
                            onChanged: () => _lastFrequencyEditMode =
                                FrequencyEditMode.centerSpan,
                            onSubmitted: _updateFreqFromCenterSpan),
                      ],
                    ),
                  ),
                  Expander(
                    header: const Text('幅度'),
                    content: Column(
                      children: [
                        Row(
                          children: [
                            const SizedBox(
                                width: 100,
                                child: Text('参考电平：',
                                    style: TextStyle(
                                        color: material.Colors.white))),
                            Expanded(
                                child: TextBox(
                                    controller: refLevelController,
                                    onSubmitted: (v) =>
                                        _sendAmplitudeConfig())),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const SizedBox(
                                width: 100,
                                child: Text('衰减器：',
                                    style: TextStyle(
                                        color: material.Colors.white))),
                            Expanded(
                              child: ValueListenableBuilder<String>(
                                valueListenable: attenuatorValue,
                                builder: (context, value, child) =>
                                    ComboBox<String>(
                                  value: value,
                                  isExpanded: true,
                                  items: [
                                    '自动',
                                    '0dB',
                                    '0.25dB',
                                    '0.5dB',
                                    '1dB',
                                    '2dB',
                                    '4dB',
                                    '8dB',
                                    '16dB',
                                    '31.75dB'
                                  ]
                                      .map((o) => ComboBoxItem<String>(
                                          value: o, child: Text(o)))
                                      .toList(),
                                  onChanged: (nv) => nv != null
                                      ? attenuatorValue.value = nv
                                      : null,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const SizedBox(
                                width: 100,
                                child: Text('预放：',
                                    style: TextStyle(
                                        color: material.Colors.white))),
                            Expanded(
                              child: ValueListenableBuilder<String>(
                                valueListenable: preAmpValue,
                                builder: (context, value, child) =>
                                    ComboBox<String>(
                                  value: value,
                                  isExpanded: true,
                                  items: ['使能', '关闭', '自动']
                                      .map((o) => ComboBoxItem<String>(
                                          value: o, child: Text(o)))
                                      .toList(),
                                  onChanged: (nv) => nv != null
                                      ? preAmpValue.value = nv
                                      : null,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const SizedBox(
                                width: 100,
                                child: Text('VGA：',
                                    style: TextStyle(
                                        color: material.Colors.white))),
                            Expanded(
                              child: ValueListenableBuilder<String>(
                                valueListenable: vgaGainValue,
                                builder: (context, value, child) =>
                                    ComboBox<String>(
                                  value: value,
                                  isExpanded: true,
                                  items: [
                                    '-11 dB',
                                    '-10 dB',
                                    '-6 dB',
                                    '-3 dB',
                                    '0 dB',
                                    '3 dB',
                                    '6 dB',
                                    '10 dB',
                                    '20 dB',
                                    '30 dB',
                                    '34 dB'
                                  ]
                                      .map((o) => ComboBoxItem<String>(
                                          value: o, child: Text(o)))
                                      .toList(),
                                  onChanged: (nv) => nv != null
                                      ? vgaGainValue.value = nv
                                      : null,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Expander(
                    header: const Text('RF 前端'),
                    content: _buildRfFrontendPanel(),
                  ),
                  Expander(
                    header: const Text('BW'),
                    content: Column(
                      children: [
                        Row(
                          children: [
                            const SizedBox(
                                width: 100,
                                child: Text('RBW模式：',
                                    style: TextStyle(
                                        color: material.Colors.white))),
                            Expanded(
                              child: ValueListenableBuilder<String>(
                                valueListenable: rbwMode,
                                builder: (context, value, child) =>
                                    ComboBox<String>(
                                  value: value,
                                  isExpanded: true,
                                  items: [
                                    '10 kHz',
                                    '30 kHz',
                                    '100 kHz',
                                    '300 kHz',
                                    '1 MHz'
                                  ]
                                      .map((o) => ComboBoxItem<String>(
                                          value: o, child: Text(o)))
                                      .toList(),
                                  onChanged: (nv) =>
                                      nv != null ? rbwMode.value = nv : null,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ValueListenableBuilder<String>(
                          valueListenable: rbwMode,
                          builder: (context, mode, child) {
                            const bool isEnabled = false;
                            return _buildInputRow(
                              label: 'RBW：',
                              controller: rbwController,
                              unitNotifier: rbwUnit,
                              units: freqUnits,
                              enabled: isEnabled,
                              onSubmitted: null,
                            );
                          },
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const SizedBox(
                                width: 100,
                                child: Text('VBW模式：',
                                    style: TextStyle(
                                        color: material.Colors.white))),
                            Expanded(
                              child: ValueListenableBuilder<String>(
                                valueListenable: vbwMode,
                                builder: (context, value, child) =>
                                    ComboBox<String>(
                                  value: value,
                                  isExpanded: true,
                                  items: [
                                    '手动',
                                    'VBW=RBW',
                                    'VBW=0.1*RBW',
                                    'VBW=0.01*RBW',
                                    'VBW=10*RBW'
                                  ]
                                      .map((o) => ComboBoxItem<String>(
                                          value: o, child: Text(o)))
                                      .toList(),
                                  onChanged: (nv) =>
                                      nv != null ? vbwMode.value = nv : null,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ValueListenableBuilder<String>(
                          valueListenable: vbwMode,
                          builder: (context, mode, child) {
                            final bool isEnabled = mode == '手动';
                            return _buildInputRow(
                              label: 'VBW：',
                              controller: vbwController,
                              unitNotifier: vbwUnit,
                              units: freqUnits,
                              enabled: isEnabled,
                              onSubmitted:
                                  isEnabled ? _submitBandwidthConfig : null,
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  Expander(
                    header: const Text('检波'),
                    content: Column(
                      children: [
                        Row(
                          children: [
                            const SizedBox(
                                width: 100,
                                child: Text('检波方式：',
                                    style: TextStyle(
                                        color: material.Colors.white))),
                            Expanded(
                              child: ValueListenableBuilder<String>(
                                valueListenable: detectMode,
                                builder: (context, value, child) =>
                                    ComboBox<String>(
                                  value: value,
                                  isExpanded: true,
                                  items: [
                                    '取样',
                                    '平均',
                                    '正峰值',
                                    '负峰值',
                                    '最大功率',
                                    '均方根值'
                                  ]
                                      .map((o) => ComboBoxItem<String>(
                                          value: o, child: Text(o)))
                                      .toList(),
                                  onChanged: (nv) =>
                                      nv != null ? detectMode.value = nv : null,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Expander(
                    header: const Text('游标'),
                    content: Column(
                      children: [
                        ValueListenableBuilder<bool>(
                          valueListenable: autoPeakEnabled,
                          builder: (context, value, child) => Row(
                            children: [
                              const SizedBox(
                                  width: 100,
                                  child: Text('峰值搜索：',
                                      style: TextStyle(
                                          color: material.Colors.white))),
                              ToggleSwitch(
                                checked: value,
                                onChanged: (v) => autoPeakEnabled.value = v,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const SizedBox(
                                width: 100,
                                child: Text('当前游标：',
                                    style: TextStyle(
                                        color: material.Colors.white))),
                            Expanded(
                              child: ComboBox<int?>(
                                value: _currentMarker?.id,
                                isExpanded: true,
                                items: _markers
                                    .map((m) => ComboBoxItem<int?>(
                                        value: m.id, child: Text('游标 ${m.id}')))
                                    .toList(),
                                placeholder: const Text('无'),
                                onChanged: (id) {
                                  if (id == null) {
                                    _selectMarker(null);
                                  } else {
                                    _selectMarker(
                                        _markers.firstWhere((m) => m.id == id));
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (_currentMarker != null) ...[
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  ToggleSwitch(
                                    checked: _currentMarker!.enabled,
                                    onChanged: (v) => setState(
                                        () => _currentMarker!.enabled = v),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                            ],
                          ],
                        ),
                        const SizedBox(height: 8),
                        ValueListenableBuilder<bool>(
                          valueListenable: autoPeakEnabled,
                          builder: (context, autoEnabled, child) {
                            final bool manualEnabled = !autoEnabled;
                            return Row(
                              children: [
                                const SizedBox(
                                    width: 100,
                                    child: Text('游标操作：',
                                        style: TextStyle(
                                            color: material.Colors.white))),
                                Expanded(
                                  child: ComboBox<String>(
                                    placeholder: const Text('选择操作'),
                                    isExpanded: true,
                                    items: ['向左寻峰', '向右寻峰', '起始点', '结束点', '中间点']
                                        .map((o) => ComboBoxItem<String>(
                                            value: o, child: Text(o)))
                                        .toList(),
                                    onChanged: manualEnabled
                                        ? (action) {
                                            if (action == null ||
                                                _currentMarker == null) {
                                              return;
                                            }
                                            double newFreq =
                                                _currentMarker!.freqHz;
                                            switch (action) {
                                              case '起始点':
                                                newFreq =
                                                    _getCurrentStartFreq();
                                                break;
                                              case '结束点':
                                                newFreq = _getCurrentStopFreq();
                                                break;
                                              case '向左寻峰':
                                                newFreq = _findLeftPeak(
                                                    _currentMarker!.freqHz);
                                                break;
                                              case '向右寻峰':
                                                newFreq = _findRightPeak(
                                                    _currentMarker!.freqHz);
                                                break;
                                              case '中间点':
                                                newFreq =
                                                    _getCurrentCenterFreq();
                                                break;
                                            }
                                            _currentMarker!.freqHz = newFreq;
                                            _markerFreqController.text =
                                                _formatFreq(newFreq,
                                                    _markerFreqUnit.value);
                                            setState(() {});
                                          }
                                        : null,
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 8),
                        ValueListenableBuilder<bool>(
                          valueListenable: autoPeakEnabled,
                          builder: (context, autoEnabled, child) {
                            final bool manualEnabled = !autoEnabled;
                            return _buildInputRow(
                              label: '游标频点：',
                              controller: _markerFreqController,
                              unitNotifier: _markerFreqUnit,
                              units: freqUnits,
                              enabled: manualEnabled,
                              onSubmitted: manualEnabled
                                  ? () {
                                      final double? parsed = _parseFreq(
                                          _markerFreqController.text,
                                          _markerFreqUnit.value);
                                      if (parsed != null &&
                                          _currentMarker != null) {
                                        _currentMarker!.freqHz = parsed;
                                        setState(() {});
                                      }
                                    }
                                  : null,
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  const Expander(header: Text('测量'), content: Placeholder()),
                  const Expander(header: Text('系统'), content: Placeholder()),
                  Expander(
                    header: const Text('图形'),
                    content: Column(
                      children: [
                        Row(
                          children: [
                            const SizedBox(
                                width: 100,
                                child: Text('点数：',
                                    style: TextStyle(
                                        color: material.Colors.white))),
                            Expanded(
                              child: TextBox(
                                controller: pointCountController,
                                onSubmitted: (value) {
                                  pointCountController.text =
                                      (_getCurrentPointCount()).toString();
                                  _sendSweepConfig();
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const SizedBox(
                                width: 100,
                                child: Text('刻度/格：',
                                    style: TextStyle(
                                        color: material.Colors.white))),
                            Expanded(
                              child: TextBox(
                                controller: scalePerGridController,
                                onChanged: (value) => setState(() {}),
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Text('dB',
                                style: TextStyle(color: material.Colors.white)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomBar: Container(
        height: 30,
        color: material.Colors.grey[900],
        child: Row(
          children: [
            const SizedBox(width: 16),
            Text(
              '模式：${_sweepMode == SweepMode.standard ? "标准" : "实时"}      数据包速率：${_currentSweepSpeed.toStringAsFixed(1)} 包/秒      当前状态：正在扫描      系统温度：35℃',
              style: const TextStyle(color: material.Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputRow({
    required String label,
    required TextEditingController controller,
    required ValueNotifier<String> unitNotifier,
    required List<String> units,
    bool enabled = true,
    VoidCallback? onSubmitted,
    VoidCallback? onChanged,
    FocusNode? focusNode,
  }) {
    return Row(
      children: [
        SizedBox(
            width: 100,
            child: Text(label,
                style: const TextStyle(color: material.Colors.white))),
        Expanded(
          child: TextBox(
            controller: controller,
            focusNode: focusNode,
            enabled: enabled,
            textInputAction: TextInputAction.done,
            onChanged: enabled && onChanged != null ? (_) => onChanged() : null,
            onSubmitted: enabled && onSubmitted != null
                ? (v) {
                    controller.text = v.trim();
                    onSubmitted();
                  }
                : null,
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 80,
          child: ValueListenableBuilder<String>(
            valueListenable: unitNotifier,
            builder: (context, value, child) => ComboBox<String>(
              value: value,
              items: units
                  .map((u) => ComboBoxItem<String>(value: u, child: Text(u)))
                  .toList(),
              onChanged: (nv) {
                if (nv != null) {
                  unitNotifier.value = nv;
                  onChanged?.call();
                }
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRfFrontendPanel() {
    final status = _lastRfFrontendStatus;
    final appliedGpio = status == null
        ? '--'
        : '0x${status.appliedGpio.toRadixString(16).padLeft(2, '0')}';
    final errorText =
        status == null ? '--' : _rfFrontendErrorLabel(status.error);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildRfModeRow<RfLnaMode>(
          label: 'LNA：',
          value: _rfFrontendConfig.lnaMode,
          values: const [RfLnaMode.bypass, RfLnaMode.enable],
          labelBuilder: _rfLnaModeLabel,
          onChanged: (mode) => _updateRfFrontendConfig(
            _rfFrontendConfig.copyWith(lnaMode: mode),
          ),
        ),
        const SizedBox(height: 8),
        _buildRfModeRow<RfPathMode>(
          label: '路径：',
          value: _rfFrontendConfig.pathMode,
          values: const [RfPathMode.directIf, RfPathMode.mixerChain],
          labelBuilder: _rfPathModeLabel,
          onChanged: (mode) => _updateRfFrontendConfig(
            _rfFrontendConfig.copyWith(pathMode: mode),
          ),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            const SizedBox(
              width: 100,
              child: Text(
                '衰减：',
                style: TextStyle(color: material.Colors.white),
              ),
            ),
            Expanded(
              child: TextBox(
                controller: _rfAttenController,
                textAlign: TextAlign.right,
                onSubmitted: (_) => _submitRfAttenText(),
                onEditingComplete: _submitRfAttenText,
              ),
            ),
            const SizedBox(width: 6),
            const Text(
              'dB',
              style: TextStyle(color: material.Colors.white),
            ),
            const SizedBox(width: 8),
            SizedBox(
              width: 32,
              child: Button(
                onPressed: () {
                  final nextCode =
                      (_rfFrontendConfig.attenCode - 1).clamp(0, 127).toInt();
                  _updateRfFrontendConfig(
                    _rfFrontendConfig.copyWith(attenCode: nextCode),
                  );
                },
                child: const Text('-'),
              ),
            ),
            const SizedBox(width: 4),
            SizedBox(
              width: 32,
              child: Button(
                onPressed: () {
                  final nextCode =
                      (_rfFrontendConfig.attenCode + 1).clamp(0, 127).toInt();
                  _updateRfFrontendConfig(
                    _rfFrontendConfig.copyWith(attenCode: nextCode),
                  );
                },
                child: const Text('+'),
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Button(
              onPressed:
                  _rfFrontendCommandInFlight ? null : _sendRfFrontendConfig,
              child: const Text('应用'),
            ),
            const SizedBox(width: 8),
            Button(
              onPressed:
                  _rfFrontendCommandInFlight ? null : _queryRfFrontendStatus,
              child: const Text('查询'),
            ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          _rfFrontendMessage,
          style: const TextStyle(color: material.Colors.white),
        ),
        const SizedBox(height: 4),
        Text(
          'GPIO $appliedGpio    Error $errorText',
          style: TextStyle(color: material.Colors.grey[300], fontSize: 12),
        ),
      ],
    );
  }

  Widget _buildRfModeRow<T>({
    required String label,
    required T value,
    required List<T> values,
    required String Function(T) labelBuilder,
    required ValueChanged<T> onChanged,
  }) {
    return Row(
      children: [
        SizedBox(
          width: 100,
          child: Text(
            label,
            style: const TextStyle(color: material.Colors.white),
          ),
        ),
        Expanded(
          child: Row(
            children: values
                .map(
                  (item) => Expanded(
                    child: Padding(
                      padding: const EdgeInsets.only(right: 6),
                      child: ToggleButton(
                        checked: item == value,
                        onChanged: (_) => onChanged(item),
                        child: Center(child: Text(labelBuilder(item))),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
        ),
      ],
    );
  }
}
