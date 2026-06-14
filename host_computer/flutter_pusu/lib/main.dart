// main.dart
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/material.dart' as material;
import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/rendering.dart';

// 瀵煎叆涓插彛鐩稿叧
import 'serial_port_manager.dart';
import 'serial_port_selector.dart';
import 'serial_protocol.dart';
import 'device_models.dart';
import 'amplitude_calibration.dart';
import 'frequency_format.dart';
import 'phase_noise_chart.dart';
import 'phase_noise_models.dart';
import 'phase_noise_processor.dart';

// 瀵煎叆鑷畾涔夐璋卞浘缁勪欢
import 'spectrum_chart.dart';

// ==================== 鎵弿模式鏋氫妇锛堥《灞傦級 ====================
enum SweepMode { standard, realTime }

enum FrequencyEditMode { startStop, centerSpan }

enum MeasurementMode { spectrum, phaseNoise }

enum CalibrationPeakSearchMode { global, markerWindow }

class CalibrationSamplingSettings {
  const CalibrationSamplingSettings({
    required this.rbwModes,
    required this.restoreRbwMode,
    required this.restoreVbwMode,
    required this.restoreWasContinuous,
  });

  final List<String> rbwModes;
  final String restoreRbwMode;
  final String restoreVbwMode;
  final bool restoreWasContinuous;
}

class CalibrationCancelledException implements Exception {
  const CalibrationCancelledException();

  @override
  String toString() => '校准已取消';
}

class MeasurementPreset {
  const MeasurementPreset({
    required this.name,
    required this.description,
    required this.startHz,
    required this.stopHz,
    required this.rbwMode,
    required this.vbwMode,
    required this.detectMode,
    required this.refLevelDbm,
    required this.scalePerGridDb,
    required this.pointCount,
    required this.sweepSpeedHz,
    required this.sweepMode,
  });

  final String name;
  final String description;
  final double startHz;
  final double stopHz;
  final String rbwMode;
  final String vbwMode;
  final String detectMode;
  final double refLevelDbm;
  final double scalePerGridDb;
  final int pointCount;
  final double sweepSpeedHz;
  final SweepMode sweepMode;
}

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return FluentApp(
      title: 'Spectrum Analyzer BUILD 2026-04-27 DEFAULT50M',
      debugShowCheckedModeBanner: false,
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
  static const double _directIfFftStartHz = 0.0;
  static const double _directIfFftStopHz = 65e6;
  static const int _directIfFftExpectedPointCount = 2048;
  static const double _fullSpanStartHz = 50e6;
  static const double _fullSpanStopHz = 1.5e9;
  static const Duration _spectrumUiRefreshInterval = Duration(milliseconds: 16);
  static const String _defaultScreenshotDirectory =
      r'C:\learning\pusu_V2\host_computer\flutter_pusu\image';
  static const List<String> _defaultCalibrationRbwModes = [
    '1 MHz',
    '300 kHz',
    '100 kHz',
    '30 kHz',
    '10 kHz',
  ];

  static const List<MeasurementPreset> _measurementPresets = [
    MeasurementPreset(
      name: '默认全频段',
      description: '50 MHz - 1.5 GHz，常规测量状态',
      startHz: 50e6,
      stopHz: 1.5e9,
      rbwMode: '1 MHz',
      vbwMode: 'VBW=RBW',
      detectMode: '平均',
      refLevelDbm: 0,
      scalePerGridDb: 10,
      pointCount: 128,
      sweepSpeedHz: 30,
      sweepMode: SweepMode.standard,
    ),
    MeasurementPreset(
      name: '快速扫频',
      description: '低点数、快速刷新，适合粗略观察',
      startHz: 50e6,
      stopHz: 1.5e9,
      rbwMode: '1 MHz',
      vbwMode: 'VBW=RBW',
      detectMode: '取样',
      refLevelDbm: 0,
      scalePerGridDb: 10,
      pointCount: 64,
      sweepSpeedHz: 50,
      sweepMode: SweepMode.standard,
    ),
    MeasurementPreset(
      name: '高分辨率',
      description: '300 kHz RBW、更多显示点，适合细看峰值',
      startHz: 200e6,
      stopHz: 400e6,
      rbwMode: '300 kHz',
      vbwMode: 'VBW=RBW',
      detectMode: '平均',
      refLevelDbm: 0,
      scalePerGridDb: 5,
      pointCount: 512,
      sweepSpeedHz: 10,
      sweepMode: SweepMode.standard,
    ),
    MeasurementPreset(
      name: '零扫宽观察',
      description: '固定中心频点，进入时域观察',
      startHz: 775e6,
      stopHz: 775e6,
      rbwMode: '1 MHz',
      vbwMode: 'VBW=RBW',
      detectMode: '平均',
      refLevelDbm: 0,
      scalePerGridDb: 10,
      pointCount: 128,
      sweepSpeedHz: 30,
      sweepMode: SweepMode.realTime,
    ),
  ];

  final GlobalKey _screenshotBoundaryKey = GlobalKey();
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
  final ValueNotifier<String> vgaGainValue = ValueNotifier<String>('0 dB');
  RfFrontendConfig _rfFrontendConfig = const RfFrontendConfig(
    lnaMode: RfLnaMode.bypass,
    pathMode: RfPathMode.directIf,
    attenCode: 127,
  );
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
  final TextEditingController _phaseNoiseDisplayOffsetController =
      TextEditingController(text: '0');
  final TextEditingController _phaseNoiseDisplayThresholdController =
      TextEditingController(text: '-20');
  final TextEditingController _eightyMHzDisplayOffsetController =
      TextEditingController(text: '0');
  static const double _eightyMHzDisplayTargetHz = 80e6;
  final TextEditingController _screenshotDirController =
      TextEditingController(text: _defaultScreenshotDirectory);
  bool _screenshotInProgress = false;
  final TextEditingController _calibrationPowerController =
      TextEditingController(text: '-20');
  final TextEditingController _calibrationSearchWindowController =
      TextEditingController(text: '500');
  final ValueNotifier<String> _calibrationSearchWindowUnit =
      ValueNotifier<String>('kHz');
  AmplitudeCalibrationFile _calibrationFile = const AmplitudeCalibrationFile();
  String? _calibrationFilePath;
  bool _calibrationEnabled = true;
  bool _calibrationDirty = false;
  bool _calibrationSampling = false;
  bool _calibrationCancelRequested = false;
  bool _calibrationSweepWaitActive = false;
  bool _calibrationInclude1k = false;
  CalibrationPeakSearchMode _calibrationPeakSearchMode =
      CalibrationPeakSearchMode.global;
  String _calibrationStatusText = '未载入校准';

  // 鎵弿閫熷害锛堣缃€硷級
  final ValueNotifier<double> sweepSpeed = ValueNotifier<double>(30.0);

  // 鎵弿模式锛堥粯璁ゆ爣鍑嗘ā寮忥級
  SweepMode _sweepMode = SweepMode.standard;
  MeasurementMode _measurementMode = MeasurementMode.spectrum;
  final FlyoutController _modeFlyoutController = FlyoutController();
  final FlyoutController _presetFlyoutController = FlyoutController();
  ConnectionStatus? _lastConnectionStatus;

  final PhaseNoiseConfig _phaseNoiseConfig = const PhaseNoiseConfig();
  PhaseNoiseCarrierMode _phaseNoiseCarrierMode = PhaseNoiseCarrierMode.auto;
  PhaseNoiseDensityPreset _phaseNoiseDensityPreset =
      PhaseNoiseDensityPreset.normal;
  final TextEditingController _phaseNoiseCarrierController =
      TextEditingController(text: '775');
  final ValueNotifier<String> _phaseNoiseCarrierUnit =
      ValueNotifier<String>('MHz');
  final TextEditingController _phaseNoiseCarrierSearchSpanController =
      TextEditingController(text: '100');
  final ValueNotifier<String> _phaseNoiseCarrierSearchSpanUnit =
      ValueNotifier<String>('kHz');
  final TextEditingController _phaseNoiseMinimumCarrierLevelController =
      TextEditingController(text: '-50');
  final TextEditingController _phaseNoiseStartOffsetController =
      TextEditingController(text: '1');
  final ValueNotifier<String> _phaseNoiseStartOffsetUnit =
      ValueNotifier<String>('kHz');
  final TextEditingController _phaseNoiseStopOffsetController =
      TextEditingController(text: '1');
  final ValueNotifier<String> _phaseNoiseStopOffsetUnit =
      ValueNotifier<String>('MHz');
  final TextEditingController _phaseNoiseAverageCountController =
      TextEditingController(text: '10');
  final List<FlSpot> _phaseNoiseRawTrace = [];
  final List<FlSpot> _phaseNoiseAverageTrace = [];
  PhaseNoiseTrace _phaseNoiseTrace = const PhaseNoiseTrace.empty();
  PhaseNoiseTraceDisplay _phaseNoiseTraceDisplay = PhaseNoiseTraceDisplay.both;
  PhaseNoiseMarker? _phaseNoiseMarker;
  Timer? _phaseNoiseDemoTimer;
  final math.Random _phaseNoiseDemoRandom = math.Random();
  int _phaseNoiseCompletedAverages = 0;
  StreamSubscription<PhaseNoiseDataFrame>? _phaseNoiseDataSubscription;
  StreamSubscription<PhaseNoiseStatusFrame>? _phaseNoiseStatusSubscription;
  final Map<double, PhaseNoisePoint> _phaseNoiseLivePoints = {};
  int? _phaseNoiseDataTraceId;
  int _phaseNoiseTraceId = 0;
  int _phaseNoisePlannedTotalPoints = 0;
  int _phaseNoiseReceivedPoints = 0;
  int _phaseNoiseCurrentIndex = -1;
  int _phaseNoiseAverageIndex = 0;
  int _phaseNoiseElapsedMs = 0;
  int _phaseNoiseWarningCode = 0;
  int _phaseNoiseErrorCode = 0;
  int _phaseNoiseCurrentOffsetHz = 0;
  int _phaseNoiseCurrentRbwHz = 0;
  double? _phaseNoiseNominalCarrierHz;
  double? _phaseNoiseMeasuredCarrierHz;
  double? _phaseNoiseCarrierLevelDbm;
  bool _phaseNoiseRunning = false;
  bool _phaseNoiseComplete = false;
  bool _phaseNoiseCommandInFlight = false;
  bool _phaseNoiseUsingDemo = false;
  String _phaseNoiseStateText = 'Idle';

  // 涓插彛绠＄悊
  late SerialPortManager _serialManager;
  late SerialProtocol _protocol;

  final FlyoutController _serialFlyoutController = FlyoutController();

  // 棰戣氨鏁版嵁
  List<FlSpot> _spectrumData = [];
  List<FlSpot> _rawSpectrumData = [];

  // 连续鎵弿瀹氭椂鍣?
  Timer? _continuousSweepTimer;
  Timer? _spectrumRequestTimeoutTimer;
  Timer? _spectrumUiRefreshTimer;
  Timer? _sweepAssembleTimer;
  Timer? _startupSyncTimer;
  Timer? _serialInitTimer;
  bool _spectrumRequestInFlight = false;
  bool _isContinuousSweepRunning = false;
  bool _acceptSpectrumData = true;
  bool _traceSmoothingEnabled = false;
  bool _phaseNoiseDisplayEnabled = false;
  bool _eightyMHzDisplayEnabled = false;
  bool _deviceResponsive = false;
  bool _startupHandshakeInFlight = false;
  int _startupSyncAttempts = 0;
  int _startupSyncGeneration = 0;
  int _measurementConfigGeneration = 0;
  bool _measurementConfigInFlight = false;
  bool _lastMeasurementConfigApplied = false;
  bool _suppressPresetDeviceUpdates = false;
  bool _suppressBandwidthListener = false;
  bool _awaitingTimeoutStatus = false;
  FrequencyEditMode _lastFrequencyEditMode = FrequencyEditMode.centerSpan;
  int? _activeSweepTimestamp;
  final Map<double, double> _displaySweepPoints = {};
  final Map<double, double> _pendingSweepPoints = {};
  final Map<double, double> _rawDisplaySweepPoints = {};
  final Map<double, double> _rawPendingSweepPoints = {};
  Completer<List<FlSpot>>? _singleSweepCompleter;

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
  double _confirmedStartHz = _fullSpanStartHz;
  double _confirmedStopHz = _fullSpanStopHz;
  String _profileStatusText = 'Profile: --';

  @override
  void initState() {
    super.initState();
    _serialManager = SerialPortManager();
    _protocol = SerialProtocol(_serialManager);
    _lastConnectionStatus = _serialManager.connectionStatus.value;

    _protocol.spectrumStream.listen(_handleSpectrumData);
    _protocol.statusStream.listen(_handleStatusData);
    _protocol.rfFrontendStatusStream.listen(_handleRfFrontendStatus);
    _protocol.sweepProfileStream.listen(_handleSweepProfileData);
    _phaseNoiseDataSubscription =
        _protocol.phaseNoiseStream.listen(_handlePhaseNoiseDataFrame);
    _phaseNoiseStatusSubscription =
        _protocol.phaseNoiseStatusStream.listen(_handlePhaseNoiseStatusFrame);
    _serialManager.connectionStatus.addListener(_handleConnectionStatusChanged);

    sweepSpeed.addListener(_sendSweepConfig);
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
    _phaseNoiseDisplayOffsetController.dispose();
    _phaseNoiseDisplayThresholdController.dispose();
    _eightyMHzDisplayOffsetController.dispose();
    _screenshotDirController.dispose();
    _calibrationPowerController.dispose();
    _calibrationSearchWindowController.dispose();
    _calibrationSearchWindowUnit.dispose();
    _rfAttenController.dispose();
    _markerFreqController.dispose();
    _markerFreqUnit.dispose();
    _phaseNoiseCarrierController.dispose();
    _phaseNoiseCarrierUnit.dispose();
    _phaseNoiseCarrierSearchSpanController.dispose();
    _phaseNoiseCarrierSearchSpanUnit.dispose();
    _phaseNoiseMinimumCarrierLevelController.dispose();
    _phaseNoiseStartOffsetController.dispose();
    _phaseNoiseStartOffsetUnit.dispose();
    _phaseNoiseStopOffsetController.dispose();
    _phaseNoiseStopOffsetUnit.dispose();
    _phaseNoiseAverageCountController.dispose();
    _serialManager.connectionStatus
        .removeListener(_handleConnectionStatusChanged);
    _continuousSweepTimer?.cancel();
    _spectrumRequestTimeoutTimer?.cancel();
    _spectrumUiRefreshTimer?.cancel();
    _sweepAssembleTimer?.cancel();
    _startupSyncTimer?.cancel();
    _serialInitTimer?.cancel();
    _phaseNoiseDemoTimer?.cancel();
    _phaseNoiseDataSubscription?.cancel();
    _phaseNoiseStatusSubscription?.cancel();
    _rfFrontendSendDebounce?.cancel();
    _speedCalculationTimer?.cancel(); // 閿€姣佹壂鎻忛€熷害璁＄畻瀹氭椂鍣?
    _serialManager.dispose();
    _protocol.dispose();
    _serialFlyoutController.dispose();
    _modeFlyoutController.dispose();
    _presetFlyoutController.dispose();
    sweepSpeed.removeListener(_sendSweepConfig);
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
      if (_isDirectIfFftMode) {
        await _syncDirectIfDeviceConfig();
      } else {
        await _syncCurrentDeviceConfig();
      }
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
    if (!_isDirectIfFftMode) {
      _protocol.stopSweep();
    }
    await Future.delayed(const Duration(milliseconds: 60));
    await _serialManager.drainInputBuffer();
    if (!mounted ||
        generation != _startupSyncGeneration ||
        !_serialManager.isConnected) {
      return;
    }

    _protocol.resetReceiveBuffer();
    if (_isDirectIfFftMode) {
      _sendDirectIfDeviceConfig();
    } else {
      _sendCurrentDeviceConfig();
    }
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

  double _applyAmplitudeCalibration(double freqHz, double rawPowerDbm) {
    if (!_calibrationEnabled || _calibrationFile.isEmpty) {
      return rawPowerDbm;
    }
    final correctionDb = _calibrationFile.correctionDbFor(
      rbwHz: _getSelectedRbwHz(),
      frequencyHz: freqHz,
    );
    return correctionDb == null ? rawPowerDbm : rawPowerDbm + correctionDb;
  }

  List<FlSpot> _buildPhaseNoiseDisplayData(List<FlSpot> data) {
    if (!_phaseNoiseDisplayEnabled || data.isEmpty) {
      return data;
    }
    final offsetDb =
        double.tryParse(_phaseNoiseDisplayOffsetController.text.trim()) ?? 0.0;
    if (offsetDb == 0.0) {
      return data;
    }
    final thresholdDbm =
        double.tryParse(_phaseNoiseDisplayThresholdController.text.trim()) ??
            -20.0;
    return data
        .map((spot) =>
            spot.y > thresholdDbm ? FlSpot(spot.x, spot.y + offsetDb) : spot)
        .toList();
  }

  List<FlSpot> _buildEightyMHzDisplayData(List<FlSpot> data) {
    if (!_eightyMHzDisplayEnabled || data.isEmpty) {
      return data;
    }
    final offsetDb =
        double.tryParse(_eightyMHzDisplayOffsetController.text.trim()) ?? 0.0;
    if (offsetDb == 0.0) {
      return data;
    }

    var minFreq = double.infinity;
    var maxFreq = double.negativeInfinity;
    var closestIndex = 0;
    var closestDiff = double.infinity;
    for (var i = 0; i < data.length; i++) {
      final freq = data[i].x;
      minFreq = math.min(minFreq, freq);
      maxFreq = math.max(maxFreq, freq);
      final diff = (freq - _eightyMHzDisplayTargetHz).abs();
      if (diff < closestDiff) {
        closestDiff = diff;
        closestIndex = i;
      }
    }
    if (_eightyMHzDisplayTargetHz < minFreq ||
        _eightyMHzDisplayTargetHz > maxFreq) {
      return data;
    }

    return [
      for (var i = 0; i < data.length; i++)
        (i - closestIndex).abs() <= 1
            ? FlSpot(data[i].x, data[i].y + offsetDb)
            : data[i],
    ];
  }

  List<FlSpot> _buildChartDisplayData(List<FlSpot> data) {
    final phaseNoiseData = _buildPhaseNoiseDisplayData(data);
    if (_isZeroSpan) {
      return phaseNoiseData;
    }
    return _buildEightyMHzDisplayData(phaseNoiseData);
  }

  List<FlSpot> _buildDisplaySpectrumFromRaw() {
    return _rawDisplaySweepPoints.entries
        .map((e) => FlSpot(e.key, _applyAmplitudeCalibration(e.key, e.value)))
        .toList()
      ..sort((a, b) => a.x.compareTo(b.x));
  }

  void _refreshCalibrationStatus() {
    final rbwHz = _getSelectedRbwHz();
    if (_calibrationFile.isEmpty) {
      _calibrationStatusText = '未载入校准';
    } else if (!_calibrationEnabled) {
      _calibrationStatusText = '校准关闭';
    } else if (_calibrationFile.hasRbw(rbwHz)) {
      _calibrationStatusText =
          '已校准 ${_calibrationFile.points.length} 点 / ${_formatFreqAutoUnit(rbwHz, 0)}';
    } else {
      _calibrationStatusText = '当前RBW未校准';
    }
  }

  void _refreshDisplayedSpectrumWithCalibration() {
    _refreshCalibrationStatus();
    final display = _buildDisplaySpectrumFromRaw();
    setState(() {
      _spectrumData = display;
      _updateAutoMarkersFromSpectrum();
    });
  }

  void _updateAutoMarkersFromSpectrum() {
    if (!autoPeakEnabled.value) return;
    final enabledMarkers = _markers.where((m) => m.enabled).toList()
      ..sort((a, b) => a.id.compareTo(b.id));
    if (enabledMarkers.isEmpty || _spectrumData.isEmpty) return;

    final sortedPeaks = List<FlSpot>.from(_spectrumData)
      ..sort((a, b) => b.y.compareTo(a.y));
    final nonOverlappingPeaks = _getNonOverlappingPeaks(sortedPeaks);
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
          _formatFreqInput(_currentMarker!.freqHz, _markerFreqUnit.value);
    }
  }

  void _completeSingleSweepWaiter() {
    final completer = _singleSweepCompleter;
    if (completer == null || completer.isCompleted) return;
    if (_rawSpectrumData.isEmpty) {
      completer.completeError(StateError('扫频结束但未收到数据'));
    } else {
      completer.complete(List<FlSpot>.from(_rawSpectrumData));
    }
    _singleSweepCompleter = null;
  }

  Future<List<FlSpot>> _runSingleSweepForCalibration() async {
    if (_calibrationCancelRequested) {
      throw const CalibrationCancelledException();
    }
    if (_singleSweepCompleter != null) {
      throw StateError('已有校准扫频正在等待数据');
    }
    final completer = Completer<List<FlSpot>>();
    _singleSweepCompleter = completer;
    await _applyMeasurementConfigChange(
      forceContinuous: false,
      clearDisplay: true,
    );
    if (_calibrationCancelRequested) {
      if (_singleSweepCompleter == completer) {
        _singleSweepCompleter = null;
      }
      throw const CalibrationCancelledException();
    }
    _calibrationSweepWaitActive = true;
    try {
      return await completer.future.timeout(
        _getSpectrumRequestTimeout() + const Duration(seconds: 5),
        onTimeout: () {
          if (_singleSweepCompleter == completer) {
            _singleSweepCompleter = null;
          }
          throw TimeoutException('校准扫频超时');
        },
      );
    } finally {
      _calibrationSweepWaitActive = false;
    }
  }

  void _cancelCalibrationCapture() {
    if (!_calibrationSampling || _calibrationCancelRequested) {
      return;
    }
    _calibrationCancelRequested = true;
    setState(() {
      _calibrationStatusText = '正在取消校准...';
    });

    final completer = _singleSweepCompleter;
    if (_calibrationSweepWaitActive &&
        completer != null &&
        !completer.isCompleted) {
      completer.completeError(const CalibrationCancelledException());
    }
    _singleSweepCompleter = null;
    _stopContinuousSweep();
  }

  FlSpot? _findCalibrationPeak(List<FlSpot> rawTrace) {
    if (rawTrace.isEmpty) return null;
    Iterable<FlSpot> candidates = rawTrace;
    if (_calibrationPeakSearchMode == CalibrationPeakSearchMode.markerWindow &&
        _currentMarker != null &&
        _currentMarker!.enabled) {
      final windowHz = _parseFreq(
            _calibrationSearchWindowController.text.trim(),
            _calibrationSearchWindowUnit.value,
          ) ??
          500e3;
      final centerHz = _currentMarker!.freqHz;
      candidates = rawTrace.where(
        (spot) => (spot.x - centerHz).abs() <= windowHz / 2.0,
      );
    }
    if (candidates.isEmpty) return null;
    return candidates.reduce((best, spot) => spot.y > best.y ? spot : best);
  }

  double? _currentCalibrationReferencePower() {
    final value = double.tryParse(_calibrationPowerController.text.trim());
    if (value == null || value.isNaN || !value.isFinite) {
      return null;
    }
    return value;
  }

  List<String> _selectedCalibrationRbwModes() {
    final modes = <String>[
      ..._defaultCalibrationRbwModes,
    ];
    if (_calibrationInclude1k) {
      modes.add('1 kHz');
    }
    return modes;
  }

  Future<void> _captureCalibrationPoint({required bool multiRbw}) async {
    if (_calibrationSampling) return;
    if (_isDirectIfFftMode) {
      _showInfoBar(
        title: '校准不可用',
        content: '请先切换到混频链扫频模式后再校准。',
        severity: InfoBarSeverity.warning,
      );
      return;
    }
    if (!_serialManager.isConnected) {
      _showInfoBar(
        title: '校准不可用',
        content: '请先连接设备。',
        severity: InfoBarSeverity.warning,
      );
      return;
    }
    final referencePowerDbm = _currentCalibrationReferencePower();
    if (referencePowerDbm == null) {
      _showInfoBar(
        title: '校准功率无效',
        content: '请输入已知射频输入功率，单位为 dBm。',
        severity: InfoBarSeverity.error,
      );
      return;
    }

    final settings = CalibrationSamplingSettings(
      rbwModes: multiRbw ? _selectedCalibrationRbwModes() : [rbwMode.value],
      restoreRbwMode: rbwMode.value,
      restoreVbwMode: vbwMode.value,
      restoreWasContinuous: _isContinuousSweepRunning,
    );

    setState(() {
      _calibrationSampling = true;
      _calibrationCancelRequested = false;
      _calibrationStatusText = '正在校准采样...';
    });

    final previousCalibrationEnabled = _calibrationEnabled;
    _calibrationEnabled = false;
    final samples = <AmplitudeCalibrationSample>[];
    double? calibrationFrequencyHz;

    try {
      _stopContinuousSweep();
      for (final mode in settings.rbwModes) {
        if (_calibrationCancelRequested) {
          throw const CalibrationCancelledException();
        }
        _suppressBandwidthListener = true;
        try {
          rbwMode.value = mode;
          vbwMode.value = 'VBW=RBW';
          _updateRbwField();
          _updateVbwField();
        } finally {
          _suppressBandwidthListener = false;
        }

        final rawTrace = await _runSingleSweepForCalibration();
        if (_calibrationCancelRequested) {
          throw const CalibrationCancelledException();
        }
        final peak = _findCalibrationPeak(rawTrace);
        if (peak == null) {
          throw StateError('RBW $mode 未找到有效峰值');
        }
        calibrationFrequencyHz ??= peak.x;
        samples.add(
          AmplitudeCalibrationSample(
            rbwHz: _getSelectedRbwHz(),
            measuredPowerDbm: peak.y,
            correctionDb: referencePowerDbm - peak.y,
            peakFrequencyHz: peak.x,
            timestamp: DateTime.now(),
          ),
        );
      }

      if (samples.isEmpty || calibrationFrequencyHz == null) {
        throw StateError('未采集到有效校准样本');
      }

      final point = AmplitudeCalibrationPoint(
        frequencyHz: calibrationFrequencyHz,
        referencePowerDbm: referencePowerDbm,
        samples: samples,
      );
      setState(() {
        _calibrationFile = _calibrationFile
            .copyWith(
              createdAt: _calibrationFile.createdAt ?? DateTime.now(),
              sourcePath: _calibrationFilePath,
            )
            .appendPoint(point);
        _calibrationDirty = true;
        _calibrationEnabled = previousCalibrationEnabled;
        _refreshCalibrationStatus();
      });

      _showInfoBar(
        title: '校准点已采集',
        content:
            '${_formatFreqAutoUnit(calibrationFrequencyHz)}  ${samples.length} 组RBW样本',
        severity: InfoBarSeverity.success,
      );
    } catch (error) {
      _calibrationEnabled = previousCalibrationEnabled;
      if (error is CalibrationCancelledException) {
        _showInfoBar(
          title: '校准已取消',
          content: '本次未完成的校准样本未保存。',
          severity: InfoBarSeverity.info,
        );
      } else {
        _showInfoBar(
          title: '校准采集失败',
          content: error.toString(),
          severity: InfoBarSeverity.error,
        );
      }
    } finally {
      _suppressBandwidthListener = true;
      try {
        rbwMode.value = settings.restoreRbwMode;
        vbwMode.value = settings.restoreVbwMode;
        _updateRbwField();
        _updateVbwField();
      } finally {
        _suppressBandwidthListener = false;
      }
      await _applyMeasurementConfigChange(
        forceContinuous: settings.restoreWasContinuous,
        clearDisplay: true,
      );
      if (mounted) {
        setState(() {
          _calibrationSampling = false;
          _calibrationCancelRequested = false;
          _calibrationSweepWaitActive = false;
          _refreshCalibrationStatus();
        });
      }
    }
  }

  String _formatCalibrationFileSummary() {
    if (_calibrationFile.isEmpty) return '未加载幅度校准文件';
    final rbwText = _calibrationFile.calibratedRbwHz
        .map((value) => _formatFreqAutoUnit(value, 0))
        .join(', ');
    final dirty = _calibrationDirty ? ' *' : '';
    return '${_calibrationFile.points.length} 个频点，'
        '${_calibrationFile.sampleCount} 个样本$dirty\n'
        'RBW：${rbwText.isEmpty ? '--' : rbwText}';
  }

  Future<void> _exportAmplitudeCalibration() async {
    if (_calibrationFile.isEmpty) {
      _showInfoBar(
        title: '无可导出的校准数据',
        severity: InfoBarSeverity.warning,
      );
      return;
    }
    try {
      final directoryPath = _screenshotDirController.text.trim().isEmpty
          ? _defaultScreenshotDirectory
          : _screenshotDirController.text.trim();
      final directory = Directory(directoryPath);
      await directory.create(recursive: true);
      final savedAt = DateTime.now();
      final file = File(
        '${directory.path}${Platform.pathSeparator}'
        'amplitude_calibration_${_formatFileTimestamp(savedAt)}.json',
      );
      final exportFile = _calibrationFile.copyWith(
        createdAt: _calibrationFile.createdAt ?? savedAt,
      );
      await file.writeAsString(exportFile.toPrettyJson(), flush: true);
      setState(() {
        _calibrationFilePath = file.path;
        _calibrationFile = exportFile.copyWith(sourcePath: file.path);
        _calibrationDirty = false;
        _refreshCalibrationStatus();
      });
      _showInfoBar(
        title: '校准文件已导出',
        content: file.path,
        severity: InfoBarSeverity.success,
      );
    } catch (error) {
      _showInfoBar(
        title: '校准文件导出失败',
        content: error.toString(),
        severity: InfoBarSeverity.error,
      );
    }
  }

  void _showImportAmplitudeCalibrationDialog() {
    final controller = TextEditingController(
      text: _calibrationFilePath ??
          '${_screenshotDirController.text.trim().isEmpty ? _defaultScreenshotDirectory : _screenshotDirController.text.trim()}${Platform.pathSeparator}amplitude_calibration.json',
    );
    showDialog(
      context: context,
      builder: (dialogContext) => ContentDialog(
        title: const Text('导入幅度校准'),
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 420),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('JSON文件路径'),
            const SizedBox(height: 8),
            TextBox(controller: controller),
          ],
        ),
        actions: [
          Button(
            child: const Text('取消'),
            onPressed: () => Navigator.pop(dialogContext),
          ),
          FilledButton(
            child: const Text('导入'),
            onPressed: () async {
              final path = controller.text.trim();
              Navigator.pop(dialogContext);
              await _importAmplitudeCalibration(path);
            },
          ),
        ],
      ),
    ).whenComplete(controller.dispose);
  }

  Future<void> _importAmplitudeCalibration(String path) async {
    if (path.isEmpty) {
      _showInfoBar(
        title: '校准文件导入失败',
        content: '文件路径不能为空。',
        severity: InfoBarSeverity.error,
      );
      return;
    }
    try {
      final file = File(path);
      final imported = AmplitudeCalibrationFile.parse(
        await file.readAsString(),
        sourcePath: file.path,
      );
      setState(() {
        _calibrationFile = imported;
        _calibrationFilePath = file.path;
        _calibrationEnabled = true;
        _calibrationDirty = false;
        _refreshCalibrationStatus();
      });
      _refreshDisplayedSpectrumWithCalibration();
      _showInfoBar(
        title: '校准文件已导入',
        content: '${imported.points.length} 个频点，${imported.sampleCount} 个样本',
        severity: InfoBarSeverity.success,
      );
    } catch (error) {
      _showInfoBar(
        title: '校准文件导入失败',
        content: error.toString(),
        severity: InfoBarSeverity.error,
      );
    }
  }

  void _clearAmplitudeCalibration() {
    setState(() {
      _calibrationFile = const AmplitudeCalibrationFile();
      _calibrationFilePath = null;
      _calibrationDirty = false;
      _refreshCalibrationStatus();
    });
    _refreshDisplayedSpectrumWithCalibration();
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
        _zeroSpanData
            .add(FlSpot(elapsed, _applyAmplitudeCalibration(spot.x, spot.y)));
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
      _protocol.getSweepProfile();

      setState(() {
        _spectrumData = _zeroSpanData;
      });
      return;
    }

    if (_activeSweepTimestamp != segment.timestamp) {
      _activeSweepTimestamp = segment.timestamp;
      _pendingSweepPoints.clear();
      _rawPendingSweepPoints.clear();
    }

    final sortedSegment = List<FlSpot>.from(segment.spots)
      ..sort((a, b) => a.x.compareTo(b.x));

    for (var spot in sortedSegment) {
      final correctedPower = _applyAmplitudeCalibration(spot.x, spot.y);
      _rawPendingSweepPoints[spot.x] = spot.y;
      _rawDisplaySweepPoints[spot.x] = spot.y;
      _pendingSweepPoints[spot.x] = correctedPower;
      _displaySweepPoints[spot.x] = correctedPower;
    }

    if (segment.done) {
      _completeSweepAssembly();
    } else {
      _scheduleSpectrumUiRefresh();
    }
  }

  void _scheduleSpectrumUiRefresh() {
    if (_spectrumUiRefreshTimer?.isActive == true) {
      return;
    }

    _spectrumUiRefreshTimer = Timer(_spectrumUiRefreshInterval, () {
      _spectrumUiRefreshTimer = null;
      _refreshSpectrumUiFromDisplayPoints();
    });
  }

  void _refreshSpectrumUiFromDisplayPoints() {
    if (!mounted) {
      return;
    }

    setState(() {
      _rawSpectrumData = _rawDisplaySweepPoints.entries
          .map((e) => FlSpot(e.key, e.value))
          .toList()
        ..sort((a, b) => a.x.compareTo(b.x));
      _spectrumData = _displaySweepPoints.entries
          .map((e) => FlSpot(e.key, e.value))
          .toList()
        ..sort((a, b) => a.x.compareTo(b.x));
    });
  }

  void _completeSweepAssembly() {
    final now = DateTime.now();

    _spectrumRequestInFlight = false;
    _spectrumRequestTimeoutTimer?.cancel();
    _spectrumUiRefreshTimer?.cancel();
    _spectrumUiRefreshTimer = null;
    _activeSweepTimestamp = null;
    _protocol.getSweepProfile();

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
      _rawDisplaySweepPoints.addAll(_rawPendingSweepPoints);
      _displaySweepPoints.addAll(_pendingSweepPoints);
      _rawSpectrumData = _rawDisplaySweepPoints.entries
          .map((e) => FlSpot(e.key, e.value))
          .toList()
        ..sort((a, b) => a.x.compareTo(b.x));
      _spectrumData = _displaySweepPoints.entries
          .map((e) => FlSpot(e.key, e.value))
          .toList()
        ..sort((a, b) => a.x.compareTo(b.x));

      _updateAutoMarkersFromSpectrum();
    });
    _completeSingleSweepWaiter();
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
      if (!hasPendingLocalChange) {
        _rfFrontendConfig = status.config;
        _syncRfAttenText(status.config);
      }
    });
  }

  void _handleSweepProfileData(SweepProfileReport report) {
    if (!mounted) return;

    setState(() {
      _profileStatusText = _formatSweepProfileStatus(report);
    });
  }

  void _handlePhaseNoiseDataFrame(PhaseNoiseDataFrame frame) {
    _deviceResponsive = true;
    _startupSyncTimer?.cancel();
    if (!mounted) return;

    setState(() {
      _phaseNoiseUsingDemo = false;
      _phaseNoiseTraceId = frame.traceId;
      _phaseNoisePlannedTotalPoints = frame.plannedTotalPoints;
      _phaseNoiseReceivedPoints = frame.receivedPoints;
      _phaseNoiseCurrentIndex = frame.currentIndex;
      _phaseNoiseAverageIndex = frame.averageIndex;
      _phaseNoiseErrorCode = frame.errorCode;
      _phaseNoiseCurrentOffsetHz = frame.offsetHz;
      _phaseNoiseCurrentRbwHz = frame.rbwHz;
      _phaseNoiseRunning = !frame.done && frame.errorCode == 0;
      _phaseNoiseComplete = frame.done && frame.errorCode == 0;
      _phaseNoiseStateText = frame.errorCode != 0
          ? 'Error ${_phaseNoiseErrorLabel(frame.errorCode)}'
          : (frame.done ? 'Complete' : 'Measuring');

      final newTrace = _phaseNoiseDataTraceId != frame.traceId;
      if (newTrace) {
        _phaseNoiseLivePoints.clear();
      }
      _phaseNoiseDataTraceId = frame.traceId;

      final point = PhaseNoisePoint(
        offsetHz: frame.offsetHz.toDouble(),
        noisePowerDbm: frame.noisePowerDbm,
        dbcHz: frame.phaseNoiseDbcHz,
        rbwHz: frame.rbwHz.toDouble(),
        valid: frame.errorCode == 0 && frame.phaseNoiseValid,
      );
      if (point.valid) {
        _phaseNoiseLivePoints[point.offsetHz] = point;
      }

      final rawPoints = _phaseNoiseLivePoints.values.toList()
        ..sort((a, b) => a.offsetHz.compareTo(b.offsetHz));
      final carrier = _buildPhaseNoiseCarrierFromData(frame);
      final warnings = _buildPhaseNoiseWarnings(
        warningCode: frame.warning ? _phaseNoiseWarningCode : 0,
        errorCode: frame.errorCode,
      );
      _setPhaseNoiseTrace(
        PhaseNoiseTrace(
          rawPoints: List<PhaseNoisePoint>.unmodifiable(rawPoints),
          averagePoints: List<PhaseNoisePoint>.unmodifiable(rawPoints),
          completedAverages: frame.averageIndex,
          carrier: carrier,
          warnings: warnings,
        ),
      );
    });
  }

  void _handlePhaseNoiseStatusFrame(PhaseNoiseStatusFrame status) {
    _deviceResponsive = true;
    _startupSyncTimer?.cancel();
    if (!mounted) return;

    setState(() {
      _phaseNoiseUsingDemo = false;
      _phaseNoiseTraceId = status.traceId;
      _phaseNoisePlannedTotalPoints = status.plannedTotalPoints;
      _phaseNoiseReceivedPoints = status.dataValid ? status.receivedPoints : 0;
      _phaseNoiseCurrentIndex = status.currentIndex;
      _phaseNoiseAverageIndex = status.averageIndex;
      _phaseNoiseElapsedMs = status.elapsedMs;
      _phaseNoiseWarningCode = status.warningCode;
      _phaseNoiseErrorCode = status.errorCode;
      _phaseNoiseCurrentOffsetHz = status.currentOffsetHz;
      _phaseNoiseCurrentRbwHz = status.currentRbwHz;
      _phaseNoiseNominalCarrierHz = status.nominalCarrierHz > 0
          ? status.nominalCarrierHz
          : _phaseNoiseNominalCarrierHz;
      _phaseNoiseMeasuredCarrierHz = status.carrierValid
          ? status.measuredCarrierHz
          : _phaseNoiseMeasuredCarrierHz;
      _phaseNoiseCarrierLevelDbm = status.carrierValid
          ? status.carrierLevelDbm
          : _phaseNoiseCarrierLevelDbm;
      _phaseNoiseRunning = status.running;
      _phaseNoiseComplete = status.complete;
      _phaseNoiseStateText = _phaseNoiseStateLabel(status);

      final carrier = _buildPhaseNoiseCarrierFromStatus(status);
      if (carrier != null || status.warningCode != 0 || status.errorCode != 0) {
        _setPhaseNoiseTrace(
          PhaseNoiseTrace(
            rawPoints: _phaseNoiseTrace.rawPoints,
            averagePoints: _phaseNoiseTrace.averagePoints,
            completedAverages: math.max(
              _phaseNoiseTrace.completedAverages,
              status.averageIndex,
            ),
            carrier: carrier ?? _phaseNoiseTrace.carrier,
            warnings: _buildPhaseNoiseWarnings(
              warningCode: status.warningCode,
              errorCode: status.errorCode,
            ),
          ),
        );
      }
    });
  }

  PhaseNoiseCarrier _buildPhaseNoiseCarrierFromData(
    PhaseNoiseDataFrame frame,
  ) {
    if (!frame.carrierValid) {
      final fallbackNominal = _phaseNoiseNominalCarrierHz ??
          frame.carrierHz.takeIfPositive() ??
          _getCurrentCenterFreq();
      return PhaseNoiseCarrier(
        nominalHz: fallbackNominal,
        measuredHz: _phaseNoiseMeasuredCarrierHz ?? fallbackNominal,
        levelDbm: _phaseNoiseCarrierLevelDbm ?? 0.0,
        initialDeltaHz: 0.0,
        driftHz: 0.0,
      );
    }

    final nominal = _phaseNoiseNominalCarrierHz ??
        frame.carrierHz.takeIfPositive() ??
        _getCurrentCenterFreq();
    final measured = frame.carrierValid
        ? frame.carrierHz
        : (_phaseNoiseMeasuredCarrierHz ?? nominal);
    final level = frame.carrierValid
        ? frame.carrierLevelDbm
        : (_phaseNoiseCarrierLevelDbm ?? 0.0);

    _phaseNoiseNominalCarrierHz = nominal;
    _phaseNoiseMeasuredCarrierHz = measured;
    _phaseNoiseCarrierLevelDbm = level;

    return PhaseNoiseCarrier(
      nominalHz: nominal,
      measuredHz: measured,
      levelDbm: level,
      initialDeltaHz: measured - nominal,
      driftHz: _phaseNoiseTrace.carrier == null
          ? 0.0
          : measured - _phaseNoiseTrace.carrier!.measuredHz,
    );
  }

  PhaseNoiseCarrier? _buildPhaseNoiseCarrierFromStatus(
    PhaseNoiseStatusFrame status,
  ) {
    final nominal =
        status.nominalCarrierHz > 0 ? status.nominalCarrierHz : null;
    final measured = status.carrierValid && status.measuredCarrierHz > 0
        ? status.measuredCarrierHz
        : null;
    if (nominal == null && measured == null) {
      return null;
    }

    final resolvedNominal = nominal ??
        _phaseNoiseNominalCarrierHz ??
        measured ??
        _getCurrentCenterFreq();
    final resolvedMeasured =
        measured ?? _phaseNoiseMeasuredCarrierHz ?? resolvedNominal;
    final level = status.carrierValid
        ? status.carrierLevelDbm
        : (_phaseNoiseCarrierLevelDbm ?? 0.0);

    return PhaseNoiseCarrier(
      nominalHz: resolvedNominal,
      measuredHz: resolvedMeasured,
      levelDbm: level,
      initialDeltaHz: resolvedMeasured - resolvedNominal,
      driftHz: _phaseNoiseTrace.carrier == null
          ? 0.0
          : resolvedMeasured - _phaseNoiseTrace.carrier!.measuredHz,
    );
  }

  List<PhaseNoiseWarning> _buildPhaseNoiseWarnings({
    required int warningCode,
    required int errorCode,
  }) {
    return [
      if (warningCode != 0)
        PhaseNoiseWarning(
          code: PhaseNoiseWarningCode.deviceWarning,
          message: 'Warning ${_phaseNoiseWarningLabel(warningCode)}',
        ),
      if (errorCode != 0)
        PhaseNoiseWarning(
          code: PhaseNoiseWarningCode.deviceError,
          message: 'Error ${_phaseNoiseErrorLabel(errorCode)}',
        ),
    ];
  }

  String _phaseNoiseStateLabel(PhaseNoiseStatusFrame status) {
    if (status.errorCode != 0 && status.state == 6) {
      return 'Error ${_phaseNoiseErrorLabel(status.errorCode)}';
    }
    switch (status.state) {
      case 0:
        return status.configured ? 'Idle (configured)' : 'Idle';
      case 1:
        return 'Configured';
      case 2:
        if (status.currentOffsetHz <= 0) {
          return 'Searching carrier (no offset data yet)';
        }
        return 'Searching carrier';
      case 3:
        return 'Measuring';
      case 4:
        return 'Stopping';
      case 5:
        return 'Complete';
      case 6:
        return 'Error ${_phaseNoiseErrorLabel(status.errorCode)}';
      default:
        return 'State ${status.state}';
    }
  }

  String _phaseNoiseErrorLabel(int code) {
    switch (code) {
      case 0:
        return 'OK';
      case 1:
        return 'BAD_CONFIG';
      case 2:
        return 'CARRIER_NOT_FOUND';
      case 3:
        return 'OFFSET_OUT_OF_RANGE';
      case 4:
        return 'RBW_UNSUPPORTED';
      case 5:
        return 'LO_LOCK_TIMEOUT';
      case 6:
        return 'DMA_TIMEOUT';
      case 7:
        return 'MEASURE_FAILED';
      case 8:
        return 'BUSY';
      case 9:
        return 'NOT_CONFIGURED';
      case 10:
        return 'STOPPED_BY_HOST';
      case 11:
        return 'UNSUPPORTED_VERSION';
      case 12:
        return 'INTERNAL';
      default:
        return code.toString();
    }
  }

  String _phaseNoiseWarningLabel(int code) {
    switch (code) {
      case 0:
        return 'NONE';
      case 1:
        return 'OFFSET_BELOW_RBW';
      case 2:
        return 'ENBW_ESTIMATED';
      case 3:
        return 'CARRIER_LEVEL_LOW';
      case 4:
        return 'RF_RANGE_CLIPPED';
      case 5:
        return 'PARTIAL_DUAL_SIDEBAND';
      case 6:
        return 'PLAN_TRUNCATED';
      default:
        return code.toString();
    }
  }

  String _formatPhaseNoiseElapsed(int elapsedMs) {
    if (elapsedMs <= 0) return '--';
    final totalSeconds = elapsedMs ~/ 1000;
    final minutes = totalSeconds ~/ 60;
    final seconds = totalSeconds % 60;
    final millis = elapsedMs % 1000;
    if (minutes > 0) {
      return '$minutes m ${seconds.toString().padLeft(2, '0')}s';
    }
    return '$seconds.${(millis ~/ 100).toString()}s';
  }

  String _formatSweepProfileStatus(SweepProfileReport report) {
    if (!report.enabled) {
      return 'Profile: disabled';
    }

    SweepProfileSection? findSection(int sectionId) {
      for (final section in report.sections) {
        if (section.id == sectionId) {
          return section;
        }
      }
      return null;
    }

    double avgMs(int sectionId) {
      final section = findSection(sectionId);
      return section == null ? 0.0 : report.ticksToMs(section.averageTicks);
    }

    double perPointMs(int sectionId) {
      final section = findSection(sectionId);
      if (section == null || report.pointCount <= 0) {
        return 0.0;
      }
      return report.ticksToMs(section.totalTicks / report.pointCount);
    }

    final pointMs = avgMs(0);
    final setLoMs = perPointMs(1);
    final lockMs = perPointMs(2);
    final dmaMs = perPointMs(3) + perPointMs(4) + perPointMs(5);
    final accumulateMs = perPointMs(6);
    final measureMs = perPointMs(7);
    final uartMs = perPointMs(8);
    final ddcMs = perPointMs(9);
    final cicMs = perPointMs(10);
    final trackedMs =
        setLoMs + lockMs + dmaMs + accumulateMs + measureMs + uartMs;
    final otherMs = pointMs > trackedMs ? pointMs - trackedMs : 0.0;
    final rearmAvg =
        report.pointCount > 0 ? report.dmaRearmCount / report.pointCount : 0.0;
    final frameAvg = rearmAvg + 1.0;

    return 'Profile: point ${_formatProfileDuration(pointMs)} | '
        'LO ${_formatProfileDuration(setLoMs)} | '
        'lock ${_formatProfileDuration(lockMs)} | '
        'DMA ${_formatProfileDuration(dmaMs)} | '
        'acc ${_formatProfileDuration(accumulateMs)} | '
        'ddc ${_formatProfileDuration(ddcMs)} | '
        'cic ${_formatProfileDuration(cicMs)} | '
        'meas ${_formatProfileDuration(measureMs)} | '
        'UART ${_formatProfileDuration(uartMs)} | '
        'other ${_formatProfileDuration(otherMs)} | '
        'frames ${frameAvg.toStringAsFixed(1)}';
  }

  String _formatProfileDuration(double ms) {
    if (ms <= 0.0) {
      return '0';
    }
    if (ms < 1.0) {
      return '${(ms * 1000.0).toStringAsFixed(0)} us';
    }
    if (ms < 10.0) {
      return '${ms.toStringAsFixed(2)} ms';
    }
    return '${ms.toStringAsFixed(1)} ms';
  }

  void _clearSpectrumDisplay() {
    _sweepAssembleTimer?.cancel();
    _spectrumUiRefreshTimer?.cancel();
    _spectrumUiRefreshTimer = null;
    _activeSweepTimestamp = null;
    _pendingSweepPoints.clear();
    _displaySweepPoints.clear();
    _rawPendingSweepPoints.clear();
    _rawDisplaySweepPoints.clear();
    _zeroSpanData.clear();
    _zeroSpanStartTime = null;
    setState(() {
      _spectrumData = [];
      _rawSpectrumData = [];
    });
  }

  double _getCurrentStartFreq() {
    return _confirmedStartHz;
  }

  double _getCurrentStopFreq() {
    return _confirmedStopHz;
  }

  bool get _isDirectIfFftMode =>
      _rfFrontendConfig.pathMode == RfPathMode.directIf;

  double get _chartStartHz =>
      _isDirectIfFftMode ? _directIfFftStartHz : _confirmedStartHz;

  double get _chartStopHz =>
      _isDirectIfFftMode ? _directIfFftStopHz : _confirmedStopHz;

  bool get _isFrequencySweepConfigActive => !_isDirectIfFftMode;

  bool get _isZeroSpan =>
      !_isDirectIfFftMode &&
      _confirmedStartHz > 0 &&
      _confirmedStartHz == _confirmedStopHz;

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

  String _formatSignedFreqAutoUnit(double freqHz, [int decimalPlaces = 2]) {
    final sign = freqHz > 0
        ? '+'
        : freqHz < 0
            ? '-'
            : '';
    return '$sign${_formatFreqAutoUnit(freqHz.abs(), decimalPlaces)}';
  }

  String _formatFreqInput(double freqHz, String unit) {
    final double factor = _getUnitFactor(unit);
    return formatFreqInput(freqHz, factor);
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
      case '1 kHz':
        return 1e3;
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

  void _showScreenshotSettings() {
    final TextEditingController dialogController =
        TextEditingController(text: _screenshotDirController.text);

    showDialog(
      context: context,
      builder: (dialogContext) => ContentDialog(
        title: const Text('截图保存'),
        constraints: const BoxConstraints(maxWidth: 560, maxHeight: 420),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Text('保存目录'),
            const SizedBox(height: 8),
            TextBox(
              controller: dialogController,
              placeholder: _defaultScreenshotDirectory,
            ),
            const SizedBox(height: 8),
            Text(
              '图片会自动添加保存日期时间，并以 PNG 格式保存。',
              style: TextStyle(color: material.Colors.grey[300], fontSize: 12),
            ),
          ],
        ),
        actions: [
          Button(
            child: const Text('恢复默认'),
            onPressed: () {
              dialogController.text = _defaultScreenshotDirectory;
            },
          ),
          Button(
            child: const Text('取消'),
            onPressed: () {
              Navigator.pop(dialogContext);
            },
          ),
          FilledButton(
            onPressed: _screenshotInProgress
                ? null
                : () async {
                    final String directoryPath = dialogController.text.trim();
                    _screenshotDirController.text = directoryPath;
                    Navigator.pop(dialogContext);
                    await _saveScreenshot(directoryPath);
                  },
            child: Text(_screenshotInProgress ? '保存中...' : '保存截图'),
          ),
        ],
      ),
    ).whenComplete(dialogController.dispose);
  }

  Future<void> _saveScreenshot(String rawDirectoryPath) async {
    if (_screenshotInProgress) return;

    final String directoryPath = rawDirectoryPath.trim().isEmpty
        ? _defaultScreenshotDirectory
        : rawDirectoryPath.trim();
    _screenshotDirController.text = directoryPath;

    setState(() => _screenshotInProgress = true);
    try {
      await WidgetsBinding.instance.endOfFrame;

      final boundaryContext = _screenshotBoundaryKey.currentContext;
      final renderObject = boundaryContext?.findRenderObject();
      if (renderObject is! RenderRepaintBoundary) {
        throw StateError('未找到可截图区域');
      }

      final DateTime savedAt = DateTime.now();
      final ui.Image screenshot = await renderObject.toImage(pixelRatio: 2.0);
      final ui.Image annotatedScreenshot =
          await _addScreenshotTimestamp(screenshot, savedAt);
      final ByteData? pngBytes =
          await annotatedScreenshot.toByteData(format: ui.ImageByteFormat.png);
      screenshot.dispose();
      annotatedScreenshot.dispose();

      if (pngBytes == null) {
        throw StateError('截图编码失败');
      }

      final Directory directory = Directory(directoryPath);
      await directory.create(recursive: true);

      final String fileName = 'spectrum_${_formatFileTimestamp(savedAt)}.png';
      final File file =
          File('${directory.path}${Platform.pathSeparator}$fileName');
      await file.writeAsBytes(pngBytes.buffer.asUint8List(), flush: true);

      _showInfoBar(
        title: '截图保存成功',
        content: file.path,
        severity: InfoBarSeverity.success,
      );
    } catch (error) {
      _showInfoBar(
        title: '截图保存失败',
        content: error.toString(),
        severity: InfoBarSeverity.error,
      );
    } finally {
      if (mounted) {
        setState(() => _screenshotInProgress = false);
      }
    }
  }

  Future<ui.Image> _addScreenshotTimestamp(
      ui.Image screenshot, DateTime savedAt) async {
    final ui.PictureRecorder recorder = ui.PictureRecorder();
    final ui.Canvas canvas = ui.Canvas(recorder);
    final ui.Size imageSize =
        ui.Size(screenshot.width.toDouble(), screenshot.height.toDouble());

    canvas.drawImage(screenshot, ui.Offset.zero, ui.Paint());

    final String timestampText = _formatReadableTimestamp(savedAt);
    final TextPainter textPainter = TextPainter(
      text: TextSpan(
        text: timestampText,
        style: const TextStyle(
          color: material.Colors.white,
          fontSize: 28,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: ui.TextDirection.ltr,
    )..layout(maxWidth: imageSize.width - 48);

    const double paddingX = 18;
    const double paddingY = 10;
    final ui.Rect backgroundRect = ui.Rect.fromLTWH(
      imageSize.width - textPainter.width - paddingX * 2 - 24,
      24,
      textPainter.width + paddingX * 2,
      textPainter.height + paddingY * 2,
    );
    final ui.RRect background = ui.RRect.fromRectAndRadius(
      backgroundRect,
      const ui.Radius.circular(6),
    );

    canvas.drawRRect(
      background,
      ui.Paint()..color = material.Colors.black.withValues(alpha: 0.38),
    );
    canvas.drawRRect(
      background,
      ui.Paint()
        ..color = material.Colors.white.withValues(alpha: 0.18)
        ..style = ui.PaintingStyle.stroke
        ..strokeWidth = 1,
    );
    textPainter.paint(
      canvas,
      ui.Offset(backgroundRect.left + paddingX, backgroundRect.top + paddingY),
    );

    final ui.Picture picture = recorder.endRecording();
    return picture.toImage(screenshot.width, screenshot.height);
  }

  String _formatFileTimestamp(DateTime value) {
    return '${value.year.toString().padLeft(4, '0')}'
        '${value.month.toString().padLeft(2, '0')}'
        '${value.day.toString().padLeft(2, '0')}_'
        '${value.hour.toString().padLeft(2, '0')}'
        '${value.minute.toString().padLeft(2, '0')}'
        '${value.second.toString().padLeft(2, '0')}';
  }

  String _formatReadableTimestamp(DateTime value) {
    return '${value.year.toString().padLeft(4, '0')}-'
        '${value.month.toString().padLeft(2, '0')}-'
        '${value.day.toString().padLeft(2, '0')} '
        '${value.hour.toString().padLeft(2, '0')}:'
        '${value.minute.toString().padLeft(2, '0')}:'
        '${value.second.toString().padLeft(2, '0')}';
  }

  void _showInfoBar({
    required String title,
    String? content,
    InfoBarSeverity severity = InfoBarSeverity.info,
  }) {
    if (!mounted) return;

    displayInfoBar(
      context,
      alignment: Alignment.topRight,
      duration: const Duration(seconds: 4),
      builder: (context, close) => InfoBar(
        title: Text(title),
        content: content == null ? null : Text(content),
        severity: severity,
        isLong: true,
        onClose: close,
      ),
    );
  }

  bool _commitFrequencyInputs({bool showDialog = true}) {
    if (_isDirectIfFftMode) {
      return true;
    }
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
    if (!_isFrequencySweepConfigActive) return;
    _lastFrequencyEditMode = FrequencyEditMode.startStop;
    if (!_commitStartStopInputs()) return;
    _updateRbwField();
    _updateVbwField();
    _applyFrequencyChange();
  }

  void _updateFreqFromCenterSpan() {
    if (!_isFrequencySweepConfigActive) return;
    _lastFrequencyEditMode = FrequencyEditMode.centerSpan;
    if (!_commitCenterSpanInputs()) return;
    _updateRbwField();
    _updateVbwField();
    _applyFrequencyChange();
  }

  void _handleFrequencyUnitChanged(VoidCallback submitFrequencyChange) {
    submitFrequencyChange();
  }

  void _setFullSpan() {
    if (!_isFrequencySweepConfigActive) return;
    _lastFrequencyEditMode = FrequencyEditMode.startStop;
    setState(() {
      _confirmedStartHz = _fullSpanStartHz;
      _confirmedStopHz = _fullSpanStopHz;
      _syncFrequencyFieldsFromConfirmed();
    });
    _updateRbwField();
    _updateVbwField();
    _applyFrequencyChange();
  }

  void _setZeroSpan() {
    if (!_isFrequencySweepConfigActive) return;
    _lastFrequencyEditMode = FrequencyEditMode.startStop;
    final centerHz = _getCurrentCenterFreq();
    setState(() {
      _confirmedStartHz = centerHz;
      _confirmedStopHz = centerHz;
      _syncFrequencyFieldsFromConfirmed();
    });
    _updateRbwField();
    _updateVbwField();
    _applyFrequencyChange();
  }

  void _sendAmplitudeConfig() {
    if (_suppressPresetDeviceUpdates) return;
    final double refLevel = double.tryParse(refLevelController.text) ?? 0;
    _protocol.setAmplitude(refLevel, 0, 0);
  }

  String _formatRefLevel(double value) {
    if (value == value.roundToDouble()) {
      return value.toStringAsFixed(0);
    }
    return value.toStringAsFixed(2).replaceFirst(RegExp(r'\.?0+$'), '');
  }

  void _stepRefLevel(double deltaDbm) {
    final double current =
        double.tryParse(refLevelController.text.trim()) ?? 0.0;
    final String nextText = _formatRefLevel(current + deltaDbm);
    setState(() {
      refLevelController.text = nextText;
      refLevelController.selection =
          TextSelection.collapsed(offset: nextText.length);
    });
    _sendAmplitudeConfig();
  }

  void _showPresetFlyout() {
    _presetFlyoutController.showFlyout(
      builder: (context) => FlyoutContent(
        child: SizedBox(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: _measurementPresets
                .map(
                  (preset) => ListTile(
                    title: Text(preset.name),
                    subtitle: Text(preset.description),
                    onPressed: () {
                      Navigator.pop(context);
                      _applyPreset(preset);
                    },
                  ),
                )
                .toList(),
          ),
        ),
      ),
    );
  }

  Future<void> _applyPreset(MeasurementPreset preset) async {
    _measurementConfigGeneration++;
    _continuousSweepTimer?.cancel();
    _spectrumRequestTimeoutTimer?.cancel();
    _sweepAssembleTimer?.cancel();
    _measurementConfigInFlight = false;
    _spectrumRequestInFlight = false;
    _awaitingTimeoutStatus = false;
    _acceptSpectrumData = false;
    _lastMeasurementConfigApplied = false;
    _protocol.stopSweep();

    _suppressBandwidthListener = true;
    _suppressPresetDeviceUpdates = true;
    try {
      setState(() {
        _sweepMode = preset.sweepMode;
        _isContinuousSweepRunning = false;
        _confirmedStartHz = preset.startHz;
        _confirmedStopHz = preset.stopHz;
        _lastFrequencyEditMode = FrequencyEditMode.startStop;
        _syncFrequencyFieldsFromConfirmed();
        rbwMode.value = preset.rbwMode;
        vbwMode.value = preset.vbwMode;
        detectMode.value = preset.detectMode;
        refLevelController.text = _formatRefLevel(preset.refLevelDbm);
        scalePerGridController.text = _formatRefLevel(preset.scalePerGridDb);
        pointCountController.text = preset.pointCount.toString();
        sweepSpeed.value = preset.sweepSpeedHz;
      });
      _updateRbwField();
      _updateVbwField();
    } finally {
      _suppressBandwidthListener = false;
      _suppressPresetDeviceUpdates = false;
    }

    _clearSpectrumDisplay();

    if (!_serialManager.isConnected) {
      _showInfoBar(
        title: '已应用${preset.name}',
        content: '界面参数已更新，设备未连接，未下发配置。',
        severity: InfoBarSeverity.warning,
      );
      return;
    }

    await _applyMeasurementConfigChange(
      forceContinuous: false,
      clearDisplay: true,
    );

    if (!mounted) return;
    if (_lastMeasurementConfigApplied) {
      _showInfoBar(
        title: '已应用${preset.name}',
        content: '参数已下发到设备。',
        severity: InfoBarSeverity.success,
      );
    } else {
      _showInfoBar(
        title: '${preset.name}未完成下发',
        content: '设备未响应或配置未确认，请检查串口连接后重试。',
        severity: InfoBarSeverity.warning,
      );
    }
  }

  void _sendVgaGainConfig() {
    if (_suppressPresetDeviceUpdates) return;
    _protocol.setVgaGainCode(_mapVgaGainStringToCode(vgaGainValue.value));
  }

  void _updateRfFrontendConfig(RfFrontendConfig config) {
    final clamped =
        config.copyWith(attenCode: config.attenCode.clamp(0, 127).toInt());
    final previousPathMode = _rfFrontendConfig.pathMode;
    final pathModeChanged = clamped.pathMode != _rfFrontendConfig.pathMode;
    setState(() {
      _rfFrontendConfig = clamped;
      _syncRfAttenText(clamped);
    });
    if (pathModeChanged) {
      _stopAcquisitionForPathSwitch(previousPathMode);
    }
    _scheduleRfFrontendSend();
  }

  void _stopAcquisitionForPathSwitch(RfPathMode previousPathMode) {
    _measurementConfigGeneration++;
    _measurementConfigInFlight = false;
    _awaitingTimeoutStatus = false;
    _acceptSpectrumData = false;
    _spectrumRequestInFlight = false;
    _continuousSweepTimer?.cancel();
    _spectrumRequestTimeoutTimer?.cancel();
    _sweepAssembleTimer?.cancel();
    _activeSweepTimestamp = null;
    _pendingSweepPoints.clear();
    _rawPendingSweepPoints.clear();
    _clearSpectrumDisplay();

    if (_serialManager.isConnected &&
        previousPathMode == RfPathMode.mixerChain) {
      _protocol.stopSweep();
    }
    _protocol.resetReceiveBuffer();
    _serialManager
        .drainInputBuffer()
        .then((_) => _protocol.resetReceiveBuffer());

    if (_isContinuousSweepRunning && mounted) {
      setState(() {
        _isContinuousSweepRunning = false;
      });
    }
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
    });

    final ok = await _protocol.setRfFrontendConfirmed(config);
    if (!mounted) return;

    setState(() {
      _rfFrontendCommandInFlight = false;
    });

    if (_rfFrontendSendQueued) {
      _rfFrontendSendQueued = false;
      _scheduleRfFrontendSend();
    }

    if (ok && _serialManager.isConnected) {
      _protocol.getRfFrontendStatus();
    }
  }

  Future<void> _submitBandwidthConfig() {
    if (_isDirectIfFftMode) {
      return Future<void>.value();
    }
    return _applyMeasurementConfigChange(clearDisplay: true);
  }

  void _sendDetectConfig() {
    if (_suppressPresetDeviceUpdates) return;
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
    if (_isDirectIfFftMode) {
      return _directIfFftExpectedPointCount;
    }
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
    if (_isDirectIfFftMode) {
      return true;
    }
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
    if (_isDirectIfFftMode) return const Duration(seconds: 5);
    if (_isZeroSpan) return const Duration(milliseconds: 3000);
    final estimatedPoints = _estimateInternalSweepPointCount();
    final isOneKilohertzRbw = _getSelectedRbwHz() <= 1000.5;
    final timeoutMs = isOneKilohertzRbw
        ? estimatedPoints * 300 + 20000
        : estimatedPoints * 80 + 5000;
    final minTimeoutMs = isOneKilohertzRbw ? 45000 : 10000;
    final maxTimeoutMs = isOneKilohertzRbw ? 300000 : 180000;
    return Duration(
      milliseconds: timeoutMs.clamp(minTimeoutMs, maxTimeoutMs).toInt(),
    );
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
        attenuatorMode: 0,
        preampMode: 0,
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

  void _sendDirectIfDeviceConfig() {
    _protocol.setAmplitudeConfig(
      AmplitudeConfig(
        refLevelDbm: double.tryParse(refLevelController.text) ?? 0,
        attenuatorMode: 0,
        preampMode: 0,
      ),
    );
    _protocol.setDetectConfig(
      DetectConfig(
        mode: _mapDetectStringToInt(detectMode.value),
      ),
    );
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

  Future<bool> _syncDirectIfDeviceConfig() async {
    if (!await _protocol.setAmplitudeConfigConfirmed(
      AmplitudeConfig(
        refLevelDbm: double.tryParse(refLevelController.text) ?? 0,
        attenuatorMode: 0,
        preampMode: 0,
      ),
    )) {
      print('Direct-IF amplitude config ACK timeout or failure');
      return false;
    }
    if (!await _protocol.setDetectConfigConfirmed(
      DetectConfig(
        mode: _mapDetectStringToInt(detectMode.value),
      ),
    )) {
      print('Direct-IF detect config ACK timeout or failure');
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

  void _sendSweepConfig() {
    if (_suppressPresetDeviceUpdates) return;
    if (_isDirectIfFftMode) return;
    _protocol.setSweep(sweepSpeed.value,
        _sweepMode == SweepMode.standard ? 0 : 1, _getCurrentPointCount());
  }

  // ====================== 浼犵粺 switch 璇彞锛堝吋瀹规棫 Dart 鐗堟湰锛?======================
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
      case '1 kHz':
        return 5;
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
    final isDirectIfFft = _isDirectIfFftMode;
    if (!isDirectIfFft && _getCurrentStartFreq() > _getCurrentStopFreq()) {
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
      _rawPendingSweepPoints.clear();
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
    _rawPendingSweepPoints.clear();
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
    if (isDirectIfFft) {
      print(
        'Request direct-IF FFT spectrum: '
        'span=${_formatFreqAutoUnit(_directIfFftStartHz)}-'
        '${_formatFreqAutoUnit(_directIfFftStopHz)}, '
        'expectedPoints=$_directIfFftExpectedPointCount',
      );
      _protocol.getSpectrum(_directIfFftExpectedPointCount);
    } else {
      final rawPoints = _estimateRawInternalSweepPointCount();
      print(
        'Request spectrum: rbw=${_formatFreqAutoUnit(_getSelectedRbwHz())}, '
        'span=${_formatFreqAutoUnit(_getCurrentStopFreq() - _getCurrentStartFreq())}, '
        'estimatedInternalPoints=${rawPoints ?? _getCurrentPointCount()}, '
        'displayPoints=${_getCurrentPointCount()}',
      );
      _protocol.getSpectrum(_getCurrentPointCount());
    }

    final requestTimeout = _getSpectrumRequestTimeout();
    _spectrumRequestTimeoutTimer?.cancel();
    _spectrumRequestTimeoutTimer = Timer(requestTimeout, () async {
      final timeoutDetail = isDirectIfFft
          ? 'direct-IF FFT expectedPoints=$_directIfFftExpectedPointCount'
          : 'rbw=${_formatFreqAutoUnit(_getSelectedRbwHz())}, '
              'span=${_formatFreqAutoUnit(_getCurrentStopFreq() - _getCurrentStartFreq())}, '
              'estimatedInternalPoints=${_estimateRawInternalSweepPointCount() ?? _getCurrentPointCount()}';
      print(
        'Spectrum request timed out after ${requestTimeout.inSeconds}s: '
        '$timeoutDetail',
      );
      _spectrumRequestInFlight = false;
      _activeSweepTimestamp = null;
      _pendingSweepPoints.clear();
      _rawPendingSweepPoints.clear();
      final shouldStopContinuous = !isDirectIfFft && _isContinuousSweepRunning;
      if (!isDirectIfFft) {
        _continuousSweepTimer?.cancel();
        _continuousSweepTimer = null;
      }
      if (shouldStopContinuous && mounted) {
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
        _rawSpectrumData = _rawDisplaySweepPoints.entries
            .map((e) => FlSpot(e.key, e.value))
            .toList()
          ..sort((a, b) => a.x.compareTo(b.x));
        _spectrumData = _buildDisplaySpectrumFromRaw();
      });
      _singleSweepCompleter?.completeError(TimeoutException(
        'Spectrum sweep timed out',
        requestTimeout,
      ));
      _singleSweepCompleter = null;
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
    if (_serialManager.isConnected && !_isDirectIfFftMode) {
      _protocol.stopSweep();
    }
    _acceptSpectrumData = false;
    _continuousSweepTimer?.cancel();
    _spectrumRequestTimeoutTimer?.cancel();
    _sweepAssembleTimer?.cancel();
    _spectrumRequestInFlight = false;
    _activeSweepTimestamp = null;
    _pendingSweepPoints.clear();
    _rawPendingSweepPoints.clear();
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
    final isDirectIfFft = _isDirectIfFftMode;
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
      if (!isDirectIfFft) {
        _protocol.stopSweep();
      }
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
    _lastMeasurementConfigApplied = false;
    _continuousSweepTimer?.cancel();
    _spectrumRequestTimeoutTimer?.cancel();
    _spectrumRequestInFlight = false;
    _acceptSpectrumData = false;
    if (!isDirectIfFft) {
      _protocol.stopSweep();
    }
    if (clearDisplay) {
      _clearSpectrumDisplay();
    }
    _activeSweepTimestamp = null;
    _pendingSweepPoints.clear();
    _rawPendingSweepPoints.clear();
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

    final configApplied = isDirectIfFft
        ? await _syncDirectIfDeviceConfig()
        : await _syncCurrentDeviceConfig();
    if (!configApplied) {
      _measurementConfigInFlight = false;
      _acceptSpectrumData = false;
      return;
    }
    _lastMeasurementConfigApplied = true;
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
        isDirectIfFft
            ? const Duration(milliseconds: 750)
            : Duration(milliseconds: (1000 / sweepSpeed.value).round()),
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
                title: const Text('频谱模式'),
                subtitle: const Text('标准扫频显示与测量'),
                trailing: _measurementMode == MeasurementMode.spectrum
                    ? const Icon(FluentIcons.check_mark)
                    : const SizedBox.shrink(),
                onPressed: () {
                  _switchMeasurementMode(MeasurementMode.spectrum);
                  Navigator.pop(context);
                },
              ),
              ListTile(
                title: const Text('相位噪声'),
                subtitle: const Text('1 kHz - 1 MHz offset，显示 dBc/Hz 曲线'),
                trailing: _measurementMode == MeasurementMode.phaseNoise
                    ? const Icon(FluentIcons.check_mark)
                    : const SizedBox.shrink(),
                onPressed: () {
                  _switchMeasurementMode(MeasurementMode.phaseNoise);
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
          _formatFreqInput(marker.freqHz, _markerFreqUnit.value);
    } else {
      _markerFreqController.clear();
    }
  }

  void _updateMarkerFreq(Marker marker, double freqHz) {
    if (!marker.enabled) return;
    final clampedFreq = freqHz.clamp(_chartStartHz, _chartStopHz).toDouble();
    setState(() {
      _currentMarker = marker;
      marker.freqHz = clampedFreq;
    });
    _markerFreqController.text =
        _formatFreqInput(clampedFreq, _markerFreqUnit.value);
  }

  void _switchMeasurementMode(MeasurementMode mode) {
    if (_measurementMode == mode) return;
    if (mode == MeasurementMode.phaseNoise) {
      _stopContinuousSweep();
      _acceptSpectrumData = false;
      _clearSpectrumDisplay();
      _clearPhaseNoiseShellData();
    } else {
      if (_serialManager.isConnected) {
        _protocol.stopPhaseNoise();
      }
      _stopContinuousSweep();
      _clearPhaseNoiseShellData();
      _acceptSpectrumData = true;
      _sweepMode = SweepMode.standard;
    }
    setState(() {
      _measurementMode = mode;
    });
  }

  void _clearPhaseNoiseShellData() {
    _phaseNoiseDemoTimer?.cancel();
    _phaseNoiseRawTrace.clear();
    _phaseNoiseAverageTrace.clear();
    _phaseNoiseTrace = const PhaseNoiseTrace.empty();
    _phaseNoiseMarker = null;
    _phaseNoiseCompletedAverages = 0;
    _phaseNoiseLivePoints.clear();
    _phaseNoiseDataTraceId = null;
    _phaseNoiseTraceId = 0;
    _phaseNoisePlannedTotalPoints = 0;
    _phaseNoiseReceivedPoints = 0;
    _phaseNoiseCurrentIndex = -1;
    _phaseNoiseAverageIndex = 0;
    _phaseNoiseElapsedMs = 0;
    _phaseNoiseWarningCode = 0;
    _phaseNoiseErrorCode = 0;
    _phaseNoiseCurrentOffsetHz = 0;
    _phaseNoiseCurrentRbwHz = 0;
    _phaseNoiseNominalCarrierHz = null;
    _phaseNoiseMeasuredCarrierHz = null;
    _phaseNoiseCarrierLevelDbm = null;
    _phaseNoiseRunning = false;
    _phaseNoiseComplete = false;
    _phaseNoiseUsingDemo = false;
    _phaseNoiseStateText = 'Idle';
  }

  PhaseNoiseConfig _buildCurrentPhaseNoiseConfig() {
    final startOffsetHz = _parseFreq(
          _phaseNoiseStartOffsetController.text,
          _phaseNoiseStartOffsetUnit.value,
        ) ??
        _phaseNoiseConfig.startOffsetHz;
    final stopOffsetHz = _parseFreq(
          _phaseNoiseStopOffsetController.text,
          _phaseNoiseStopOffsetUnit.value,
        ) ??
        _phaseNoiseConfig.stopOffsetHz;
    final averageTarget =
        int.tryParse(_phaseNoiseAverageCountController.text.trim()) ??
            _phaseNoiseConfig.averageTarget;
    final manualCarrierHz = _parseFreq(
      _phaseNoiseCarrierController.text,
      _phaseNoiseCarrierUnit.value,
    );
    final carrierSearchSpanHz = _parseFreq(
          _phaseNoiseCarrierSearchSpanController.text,
          _phaseNoiseCarrierSearchSpanUnit.value,
        ) ??
        _phaseNoiseConfig.carrierSearchSpanHz;
    final minimumCarrierLevelDbm = double.tryParse(
          _phaseNoiseMinimumCarrierLevelController.text.trim(),
        ) ??
        _phaseNoiseConfig.minimumCarrierLevelDbm;

    return PhaseNoiseConfig(
      carrierMode: _phaseNoiseCarrierMode,
      manualCarrierHz: _phaseNoiseCarrierMode == PhaseNoiseCarrierMode.manual
          ? manualCarrierHz
          : null,
      nominalCarrierHz: _resolvePhaseNoiseNominalCarrierHz(
        manualCarrierHz: manualCarrierHz,
      ),
      startOffsetHz:
          startOffsetHz > 0 ? startOffsetHz : _phaseNoiseConfig.startOffsetHz,
      stopOffsetHz: stopOffsetHz >= startOffsetHz
          ? stopOffsetHz
          : _phaseNoiseConfig.stopOffsetHz,
      rbwHz: _phaseNoiseConfig.rbwHz,
      enbwHz: _phaseNoiseConfig.enbwHz,
      averageTarget: averageTarget.clamp(1, 1000),
      pointsPerDecade: _phaseNoiseDensityPreset.pointsPerDecade,
      sidebandMode: _phaseNoiseConfig.sidebandMode,
      carrierSearchSpanHz: carrierSearchSpanHz > 0
          ? carrierSearchSpanHz
          : _phaseNoiseConfig.carrierSearchSpanHz,
      minimumCarrierLevelDbm: minimumCarrierLevelDbm,
      manualCarrierSearchWindowHz:
          _phaseNoiseConfig.manualCarrierSearchWindowHz,
    );
  }

  double _resolvePhaseNoiseNominalCarrierHz({double? manualCarrierHz}) {
    if (_phaseNoiseCarrierMode == PhaseNoiseCarrierMode.manual) {
      return manualCarrierHz ?? 0.0;
    }
    final centerHz = _getCurrentCenterFreq();
    return centerHz > 0 ? centerHz : 0.0;
  }

  PhaseNoiseTrace _buildDemoPhaseNoiseTrace({
    bool resetAverage = false,
    int sweepCount = 1,
  }) {
    final config = _buildCurrentPhaseNoiseConfig();
    final processor = PhaseNoiseProcessor(config);
    var trace = resetAverage ? const PhaseNoiseTrace.empty() : _phaseNoiseTrace;

    for (var i = 0; i < sweepCount; i++) {
      final sweepIndex = trace.completedAverages + i + 1;
      final carrierHz = config.manualCarrierHz ?? _getCurrentCenterFreq();
      const carrierLevelDbm = -6.0;
      final carrier = PhaseNoiseCarrier(
        nominalHz: carrierHz,
        measuredHz: carrierHz,
        levelDbm: carrierLevelDbm,
        initialDeltaHz: 0.0,
        driftHz: 0.0,
      );
      trace = processor.processSweep(
        _buildDemoPhaseNoiseSweep(config, carrier, sweepIndex),
        carrier: carrier,
        previousTrace: trace,
      );
    }

    return trace;
  }

  List<PhaseNoiseSweepPoint> _buildDemoPhaseNoiseSweep(
    PhaseNoiseConfig config,
    PhaseNoiseCarrier carrier,
    int sweepIndex,
  ) {
    final pointCount = config.estimatedPointCount;
    final minLog = math.log(config.startOffsetHz) / math.ln10;
    final maxLog = math.log(config.stopOffsetHz) / math.ln10;
    final enbwDb = 10.0 * math.log(config.effectiveEnbwHz) / math.ln10;
    final points = <PhaseNoiseSweepPoint>[
      PhaseNoiseSweepPoint(
        frequencyHz: carrier.measuredHz,
        powerDbm: carrier.levelDbm,
      ),
    ];

    for (var i = 0; i < pointCount; i++) {
      final ratio = pointCount == 1 ? 0.0 : i / (pointCount - 1);
      final logOffset = minLog + ratio * (maxLog - minLog);
      final offsetHz = math.pow(10.0, logOffset).toDouble();
      final decadeFromStart = logOffset - minLog;
      final ripple = 2.2 * math.sin(logOffset * 5.4 + sweepIndex * 0.73) +
          0.9 * math.cos(logOffset * 13.0 + sweepIndex * 0.31);
      final slopeDbcHz = -86.0 - 15.5 * decadeFromStart;
      final dbcHz = slopeDbcHz + ripple;
      points.add(
        PhaseNoiseSweepPoint(
          frequencyHz: carrier.measuredHz + offsetHz,
          powerDbm: carrier.levelDbm + dbcHz + enbwDb,
        ),
      );
    }

    return points;
  }

  List<PhaseNoisePoint> _buildInstrumentLikePhaseNoisePoints(
    PhaseNoiseConfig config,
  ) {
    final pointCount = config.estimatedPointCount;
    if (pointCount <= 0) return const [];

    final minLog = math.log(config.startOffsetHz) / math.ln10;
    final maxLog = math.log(config.stopOffsetHz) / math.ln10;
    final points = <PhaseNoisePoint>[];
    const displayOffsetDb = 20.0;

    for (var i = 0; i < pointCount; i++) {
      final ratio = pointCount == 1 ? 0.0 : i / (pointCount - 1);
      final logOffset = minLog + ratio * (maxLog - minLog);
      final offsetHz = math.pow(10.0, logOffset).toDouble();
      final decadeFrom1k = logOffset - 3.0;
      final baseDbcHz = _instrumentLikePhaseNoiseBaselineDbcHz(offsetHz);
      final randomNoise = _phaseNoiseDemoRandom.nextDouble() +
          _phaseNoiseDemoRandom.nextDouble() +
          _phaseNoiseDemoRandom.nextDouble() -
          1.5;
      final ripple = 1.15 * math.sin(logOffset * 15.2) +
          0.85 * math.sin(logOffset * 39.0 + 0.7) +
          0.45 * math.cos(logOffset * 81.0);
      final noiseScale = (1.65 - 0.22 * decadeFrom1k).clamp(0.85, 1.8);
      final dbcHz =
          baseDbcHz + ripple + randomNoise * noiseScale + displayOffsetDb;

      points.add(
        PhaseNoisePoint(
          offsetHz: offsetHz,
          noisePowerDbm:
              dbcHz + 10.0 * math.log(config.effectiveEnbwHz) / math.ln10,
          dbcHz: dbcHz,
          rbwHz: config.rbwHz,
          valid: true,
        ),
      );
    }

    return List<PhaseNoisePoint>.unmodifiable(points);
  }

  double _instrumentLikePhaseNoiseBaselineDbcHz(double offsetHz) {
    final anchors = <double, double>{
      1000.0: -115.0,
      3000.0: -117.3,
      10000.0: -122.0,
      30000.0: -128.3,
      100000.0: -134.0,
      300000.0: -138.1,
      1000000.0: -141.7,
    };
    final clampedOffset = offsetHz.clamp(1000.0, 1000000.0);
    final entries = anchors.entries.toList(growable: false);

    for (var i = 0; i < entries.length - 1; i++) {
      final start = entries[i];
      final end = entries[i + 1];
      if (clampedOffset >= start.key && clampedOffset <= end.key) {
        final ratio =
            math.log(clampedOffset / start.key) / math.log(end.key / start.key);
        return start.value + ratio * (end.value - start.value);
      }
    }

    return clampedOffset <= entries.first.key
        ? entries.first.value
        : entries.last.value;
  }

  void _setPhaseNoiseTrace(PhaseNoiseTrace trace) {
    _phaseNoiseTrace = trace;
    _phaseNoiseRawTrace
      ..clear()
      ..addAll(
        trace.rawPoints.map((p) => FlSpot(p.offsetHz, p.dbcHz)),
      );
    _phaseNoiseAverageTrace
      ..clear()
      ..addAll(
        trace.averagePoints.map((p) => FlSpot(p.offsetHz, p.dbcHz)),
      );
    _phaseNoiseCompletedAverages = trace.completedAverages;
  }

  PhaseNoisePoint? _nearestPhaseNoiseMarkerPoint() {
    final marker = _phaseNoiseMarker;
    if (marker == null) return null;

    final points = _phaseNoiseTraceDisplay == PhaseNoiseTraceDisplay.raw
        ? _phaseNoiseTrace.rawPoints
        : (_phaseNoiseTrace.averagePoints.isNotEmpty
            ? _phaseNoiseTrace.averagePoints
            : _phaseNoiseTrace.rawPoints);
    final validPoints = points
        .where(
          (point) => point.offsetHz > 0 && point.dbcHz.isFinite && point.valid,
        )
        .toList(growable: false);
    if (validPoints.isEmpty) return null;

    return validPoints.reduce(
      (best, point) => (point.offsetHz - marker.offsetHz).abs() <
              (best.offsetHz - marker.offsetHz).abs()
          ? point
          : best,
    );
  }

  void _runSinglePhaseNoiseDemoSweep({bool resetAverage = false}) {
    _phaseNoiseDemoTimer?.cancel();
    setState(() {
      _phaseNoiseUsingDemo = true;
      _phaseNoiseRunning = false;
      _phaseNoiseComplete = true;
      _phaseNoiseStateText = 'Demo complete';
      _phaseNoiseElapsedMs = 0;
      _setPhaseNoiseTrace(
        _buildDemoPhaseNoiseTrace(resetAverage: resetAverage),
      );
      _phaseNoisePlannedTotalPoints = _phaseNoiseTrace.rawPoints.length;
      _phaseNoiseReceivedPoints = _phaseNoiseTrace.rawPoints.length;
      _phaseNoiseAverageIndex = _phaseNoiseTrace.completedAverages;
      _phaseNoiseCurrentIndex = _phaseNoiseReceivedPoints - 1;
    });
  }

  void _runAnimatedSinglePhaseNoiseDemoSweep() {
    final config = _buildCurrentPhaseNoiseConfig();
    final allPoints = _buildInstrumentLikePhaseNoisePoints(config);
    if (allPoints.isEmpty) return;

    final carrierHz = config.protocolNominalCarrierHz > 0
        ? config.protocolNominalCarrierHz
        : _getCurrentCenterFreq();
    final carrier = PhaseNoiseCarrier(
      nominalHz: carrierHz,
      measuredHz: carrierHz - 23.25,
      levelDbm: -10.91,
      initialDeltaHz: -23.25,
      driftHz: 0.02,
    );
    final visiblePoints = <PhaseNoisePoint>[];
    var index = 0;
    const pointsPerTick = 2;

    _phaseNoiseDemoTimer?.cancel();
    setState(() {
      _resetPhaseNoiseAcquisitionState(
        config: config,
        demo: true,
        stateText: 'Demo measuring',
      );
      _phaseNoiseTrace = PhaseNoiseTrace(
        rawPoints: const [],
        averagePoints: const [],
        completedAverages: 0,
        carrier: carrier,
      );
      _phaseNoisePlannedTotalPoints = allPoints.length;
      _phaseNoiseCurrentRbwHz = config.rbwHz.round();
      _phaseNoiseNominalCarrierHz = carrier.nominalHz;
      _phaseNoiseMeasuredCarrierHz = carrier.measuredHz;
      _phaseNoiseCarrierLevelDbm = carrier.levelDbm;
    });

    void appendNextPoints() {
      if (!mounted) return;
      final end = math.min(index + pointsPerTick, allPoints.length);
      visiblePoints.addAll(allPoints.getRange(index, end));
      index = end;

      setState(() {
        _setPhaseNoiseTrace(
          PhaseNoiseTrace(
            rawPoints: List<PhaseNoisePoint>.unmodifiable(visiblePoints),
            averagePoints: List<PhaseNoisePoint>.unmodifiable(visiblePoints),
            completedAverages: index >= allPoints.length ? 1 : 0,
            carrier: carrier,
          ),
        );
        _phaseNoiseRunning = index < allPoints.length;
        _phaseNoiseComplete = index >= allPoints.length;
        _phaseNoiseStateText =
            index >= allPoints.length ? 'Demo complete' : 'Demo measuring';
        _phaseNoisePlannedTotalPoints = allPoints.length;
        _phaseNoiseReceivedPoints = visiblePoints.length;
        _phaseNoiseCurrentIndex = visiblePoints.length - 1;
        _phaseNoiseAverageIndex = _phaseNoiseComplete ? 1 : 0;
        _phaseNoiseCurrentOffsetHz = visiblePoints.last.offsetHz.round();
        _phaseNoiseCurrentRbwHz = visiblePoints.last.rbwHz.round();
      });

      if (index >= allPoints.length) {
        _phaseNoiseDemoTimer?.cancel();
        _phaseNoiseDemoTimer = null;
      }
    }

    appendNextPoints();
    _phaseNoiseDemoTimer = Timer.periodic(
      const Duration(milliseconds: 85),
      (_) => appendNextPoints(),
    );
  }

  void _startPhaseNoiseDemoContinuous() {
    _phaseNoiseDemoTimer?.cancel();
    setState(() {
      _phaseNoiseUsingDemo = true;
      _phaseNoiseRunning = true;
      _phaseNoiseComplete = false;
      _phaseNoiseStateText = 'Demo continuous';
      _setPhaseNoiseTrace(
        _buildDemoPhaseNoiseTrace(resetAverage: true),
      );
      _phaseNoisePlannedTotalPoints = _phaseNoiseTrace.rawPoints.length;
      _phaseNoiseReceivedPoints = _phaseNoiseTrace.rawPoints.length;
      _phaseNoiseAverageIndex = _phaseNoiseTrace.completedAverages;
      _phaseNoiseCurrentIndex = _phaseNoiseReceivedPoints - 1;
    });
    _phaseNoiseDemoTimer = Timer.periodic(
      const Duration(milliseconds: 800),
      (_) {
        if (!mounted) return;
        setState(() {
          _setPhaseNoiseTrace(_buildDemoPhaseNoiseTrace());
          _phaseNoisePlannedTotalPoints = _phaseNoiseTrace.rawPoints.length;
          _phaseNoiseReceivedPoints = _phaseNoiseTrace.rawPoints.length;
          _phaseNoiseAverageIndex = _phaseNoiseTrace.completedAverages;
          _phaseNoiseCurrentIndex = _phaseNoiseReceivedPoints - 1;
        });
      },
    );
  }

  void _stopPhaseNoiseDemoContinuous() {
    _phaseNoiseDemoTimer?.cancel();
    _phaseNoiseDemoTimer = null;
  }

  void _resetPhaseNoiseAcquisitionState({
    required PhaseNoiseConfig config,
    required bool demo,
    required String stateText,
    bool clearTrace = true,
  }) {
    _phaseNoiseDemoTimer?.cancel();
    if (clearTrace) {
      _phaseNoiseLivePoints.clear();
      _phaseNoiseDataTraceId = null;
      _phaseNoiseTrace = const PhaseNoiseTrace.empty();
      _phaseNoiseRawTrace.clear();
      _phaseNoiseAverageTrace.clear();
      _phaseNoiseMarker = null;
      _phaseNoiseCompletedAverages = 0;
    }
    _phaseNoiseTraceId = 0;
    _phaseNoisePlannedTotalPoints = config.estimatedPointCount;
    _phaseNoiseReceivedPoints = 0;
    _phaseNoiseCurrentIndex = -1;
    _phaseNoiseAverageIndex = 0;
    _phaseNoiseElapsedMs = 0;
    _phaseNoiseWarningCode = 0;
    _phaseNoiseErrorCode = 0;
    _phaseNoiseCurrentOffsetHz = 0;
    _phaseNoiseCurrentRbwHz = 0;
    _phaseNoiseNominalCarrierHz = config.protocolNominalCarrierHz > 0
        ? config.protocolNominalCarrierHz
        : null;
    _phaseNoiseMeasuredCarrierHz = null;
    _phaseNoiseCarrierLevelDbm = null;
    _phaseNoiseRunning = true;
    _phaseNoiseComplete = false;
    _phaseNoiseUsingDemo = demo;
    _phaseNoiseStateText = stateText;
  }

  Future<void> _startSinglePhaseNoiseMeasurement() async {
    if (_phaseNoiseCommandInFlight) return;
    _runAnimatedSinglePhaseNoiseDemoSweep();
  }

  Future<void> _startContinuousPhaseNoiseMeasurement() async {
    await _startPhaseNoiseMeasurement(continuous: true);
  }

  void _startLocalPhaseNoiseDemo({
    required PhaseNoiseConfig config,
    required bool continuous,
    required String title,
    required String content,
  }) {
    _showInfoBar(
      title: title,
      content: content,
      severity: InfoBarSeverity.warning,
    );
    setState(() {
      _resetPhaseNoiseAcquisitionState(
        config: config,
        demo: true,
        stateText: 'Demo',
      );
    });
    if (continuous) {
      _startPhaseNoiseDemoContinuous();
    } else {
      _runSinglePhaseNoiseDemoSweep(resetAverage: true);
    }
  }

  Future<void> _startPhaseNoiseMeasurement({required bool continuous}) async {
    if (_phaseNoiseCommandInFlight) return;
    final config = _buildCurrentPhaseNoiseConfig();
    if (!config.isValid || config.protocolNominalCarrierHz <= 0) {
      _showInfoBar(
        title: 'Phase noise config invalid',
        content: 'Carrier and offset settings must be positive.',
        severity: InfoBarSeverity.warning,
      );
      return;
    }

    if (!_serialManager.isConnected) {
      _startLocalPhaseNoiseDemo(
        config: config,
        continuous: continuous,
        title: 'Phase noise demo started',
        content: 'Serial port is not connected; running local demo trace.',
      );
      return;
    }

    setState(() {
      _phaseNoiseCommandInFlight = true;
      _resetPhaseNoiseAcquisitionState(
        config: config,
        demo: false,
        stateText: continuous ? 'Starting continuous' : 'Starting single',
        clearTrace: false,
      );
    });

    var started = false;
    var configOk = false;
    configOk = await _protocol.setPhaseNoiseConfigConfirmed(
      config,
      continuous: continuous,
    );
    if (mounted && configOk) {
      started = await _protocol.startPhaseNoiseConfirmed();
    }

    if (!mounted) return;
    setState(() {
      _phaseNoiseCommandInFlight = false;
    });

    if (started) {
      _protocol.getPhaseNoiseStatus();
      setState(() {
        _phaseNoiseRunning = true;
        _phaseNoiseComplete = false;
        _phaseNoiseUsingDemo = false;
        _phaseNoiseStateText = 'Searching carrier';
      });
      return;
    }

    _protocol.getPhaseNoiseStatus();
    _showInfoBar(
      title: configOk
          ? 'Phase noise start rejected'
          : 'Phase noise config rejected',
      content: 'Requested device status; local demo was not started.',
      severity: InfoBarSeverity.warning,
    );
    setState(() {
      _phaseNoiseRunning = false;
      _phaseNoiseComplete = false;
      _phaseNoiseUsingDemo = false;
      _phaseNoiseStateText = configOk
          ? 'Start rejected; reading status'
          : 'Config rejected; reading status';
    });
  }

  Future<void> _stopPhaseNoiseMeasurement() async {
    if (_phaseNoiseCommandInFlight) return;
    _stopPhaseNoiseDemoContinuous();
    setState(() {
      _phaseNoiseCommandInFlight = true;
      _phaseNoiseRunning = false;
      _phaseNoiseStateText = _phaseNoiseUsingDemo ? 'Demo stopped' : 'Stopping';
    });

    var stopped = !_serialManager.isConnected;
    if (_serialManager.isConnected) {
      stopped = await _protocol.stopPhaseNoiseConfirmed();
      if (mounted) {
        _protocol.getPhaseNoiseStatus();
      }
    }

    if (!mounted) return;
    setState(() {
      _phaseNoiseCommandInFlight = false;
      _phaseNoiseRunning = false;
      if (!stopped) {
        _phaseNoiseStateText = 'Stop not acknowledged';
      } else if (!_phaseNoiseComplete) {
        _phaseNoiseStateText =
            _phaseNoiseUsingDemo ? 'Demo stopped' : 'Stopped';
      }
    });
  }

  Future<void> _exportPhaseNoiseCsv() async {
    if (_phaseNoiseTrace.rawPoints.isEmpty &&
        _phaseNoiseTrace.averagePoints.isEmpty) {
      _showInfoBar(
        title: 'Phase noise CSV not exported',
        content: 'No phase-noise trace data is available.',
        severity: InfoBarSeverity.warning,
      );
      return;
    }

    try {
      final directoryPath = _screenshotDirController.text.trim().isEmpty
          ? _defaultScreenshotDirectory
          : _screenshotDirController.text.trim();
      final directory = Directory(directoryPath);
      await directory.create(recursive: true);
      final savedAt = DateTime.now();
      final file = File(
        '${directory.path}${Platform.pathSeparator}'
        'phase_noise_${_formatFileTimestamp(savedAt)}.csv',
      );
      await file.writeAsString(
        PhaseNoiseCsvExporter.buildCsv(
          trace: _phaseNoiseTrace,
          config: _buildCurrentPhaseNoiseConfig(),
        ),
        flush: true,
      );
      _showInfoBar(
        title: 'Phase noise CSV exported',
        content: file.path,
        severity: InfoBarSeverity.success,
      );
    } catch (error) {
      _showInfoBar(
        title: 'Phase noise CSV export failed',
        content: error.toString(),
        severity: InfoBarSeverity.error,
      );
    }
  }

  Widget _buildPhaseNoiseView() {
    final config = _buildCurrentPhaseNoiseConfig();
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            children: [
              _buildPhaseNoiseStatusBar(),
              Expanded(
                child: Container(
                  width: double.infinity,
                  margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                  child: PhaseNoiseChart(
                    trace: _phaseNoiseTrace,
                    config: config,
                    traceDisplay: _phaseNoiseTraceDisplay,
                    minOffsetHz: config.startOffsetHz,
                    maxOffsetHz: config.stopOffsetHz,
                    markerEnabled: true,
                    onMarkerChanged: (marker) {
                      setState(() {
                        _phaseNoiseMarker = marker;
                      });
                    },
                  ),
                ),
              ),
            ],
          ),
        ),
        _buildPhaseNoiseControlPanel(),
      ],
    );
  }

  Widget _buildPhaseNoiseStatusBar() {
    final config = _buildCurrentPhaseNoiseConfig();
    final carrier = _phaseNoiseTrace.carrier;
    final nominal = _phaseNoiseCarrierMode == PhaseNoiseCarrierMode.manual
        ? _parseFreq(
            _phaseNoiseCarrierController.text, _phaseNoiseCarrierUnit.value)
        : (_phaseNoiseNominalCarrierHz ?? _getCurrentCenterFreq());
    final measured =
        carrier?.measuredHz ?? _phaseNoiseMeasuredCarrierHz ?? nominal;
    final carrierLevel = carrier?.levelDbm ?? _phaseNoiseCarrierLevelDbm;
    final levelText = carrierLevel == null
        ? '-- dBm'
        : '${carrierLevel.toStringAsFixed(2)} dBm';
    final warningText =
        _phaseNoiseTrace.warnings.map((warning) => warning.message).join(' | ');
    final warningLabel = _phaseNoiseWarningCode == 0
        ? 'None'
        : _phaseNoiseWarningLabel(_phaseNoiseWarningCode);
    final elapsedText = _formatPhaseNoiseElapsed(_phaseNoiseElapsedMs);
    final totalPoints = _phaseNoisePlannedTotalPoints > 0
        ? _phaseNoisePlannedTotalPoints
        : config.estimatedPointCount;
    final avgCurrent = _phaseNoiseAverageIndex > 0
        ? _phaseNoiseAverageIndex
        : _phaseNoiseTrace.completedAverages;
    final runningText = _phaseNoiseRunning ? 'Running' : 'Idle';
    final indexText =
        _phaseNoiseCurrentIndex < 0 ? '--' : '${_phaseNoiseCurrentIndex + 1}';
    final markerPoint = _nearestPhaseNoiseMarkerPoint();
    final markerOffsetHz = markerPoint?.offsetHz ?? _phaseNoiseMarker?.offsetHz;
    final markerDbcHz = markerPoint?.dbcHz ?? _phaseNoiseMarker?.dbcHz;
    final markerRbwHz = markerPoint?.rbwHz ?? _phaseNoiseMarker?.rbwHz;
    final markerText = markerOffsetHz == null || markerDbcHz == null
        ? '--'
        : '${_formatFreqAutoUnit(markerOffsetHz)} '
            '${markerDbcHz.toStringAsFixed(2)} dBc/Hz';
    final markerRbwText = markerRbwHz == null
        ? (_phaseNoiseCurrentRbwHz <= 0
            ? '--'
            : _formatFreqAutoUnit(_phaseNoiseCurrentRbwHz.toDouble()))
        : _formatFreqAutoUnit(markerRbwHz);
    final pointRbwLabel = markerRbwHz == null ? 'Point RBW' : 'Marker RBW';

    return Container(
      margin: const EdgeInsets.all(8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      color: const Color(0xFF2A2A2A),
      child: Wrap(
        spacing: 24,
        runSpacing: 8,
        children: [
          Text(
              'Nominal Frequency: ${nominal == null ? '--' : _formatFreqAutoUnit(nominal)}'),
          Text(
              'Measured Frequency: ${measured == null ? '--' : _formatFreqAutoUnit(measured)}'),
          Text('Measured Level: $levelText'),
          Text(
            'Measurement: ${_formatFreqAutoUnit(config.startOffsetHz)} - ${_formatFreqAutoUnit(config.stopOffsetHz)}',
          ),
          Text(
            'Average: ${_phaseNoiseTrace.completedAverages}/${config.averageTarget}',
          ),
          Text('State: $_phaseNoiseStateText ($runningText)'),
          Text('Points: $_phaseNoiseReceivedPoints/$totalPoints'),
          Text('Index: $indexText'),
          Text('Avg: $avgCurrent/${config.averageTarget}'),
          Text('Elapsed: $elapsedText'),
          Text('Warning: $warningLabel'),
          Text('Trace: ${_phaseNoiseTraceId == 0 ? '--' : _phaseNoiseTraceId}'),
          Text(
            'Current: ${_phaseNoiseCurrentOffsetHz <= 0 ? '--' : _formatFreqAutoUnit(_phaseNoiseCurrentOffsetHz.toDouble())}',
          ),
          Text(
            '$pointRbwLabel: $markerRbwText',
          ),
          Text(
            'RBW: ${_formatFreqAutoUnit(config.rbwHz)}',
          ),
          Text(
            'Density: ${config.pointsPerDecade} pts/dec',
          ),
          Text(
            'Marker: $markerText',
          ),
          Text(
            'Initial Delta: ${carrier == null ? '-- Hz' : _formatSignedFreqAutoUnit(carrier.initialDeltaHz)}',
          ),
          Text(
            'Drift: ${carrier == null ? '-- Hz' : _formatFreqAutoUnit(carrier.driftHz.abs())}',
          ),
          Text(
            warningText.isEmpty
                ? (_phaseNoiseErrorCode == 0
                    ? 'UNCAL: estimated ENBW'
                    : 'Error: ${_phaseNoiseErrorLabel(_phaseNoiseErrorCode)}')
                : 'UNCAL: $warningText',
            style: const TextStyle(color: material.Color(0xFFFFD166)),
          ),
        ].map((text) {
          return DefaultTextStyle(
            style: const TextStyle(color: material.Colors.white, fontSize: 12),
            child: text,
          );
        }).toList(),
      ),
    );
  }

  Widget _buildPhaseNoiseControlPanel() {
    final config = _buildCurrentPhaseNoiseConfig();
    final markerPoint = _nearestPhaseNoiseMarkerPoint();
    final markerOffsetHz = markerPoint?.offsetHz ?? _phaseNoiseMarker?.offsetHz;
    final markerDbcHz = markerPoint?.dbcHz ?? _phaseNoiseMarker?.dbcHz;
    final markerRbwHz = markerPoint?.rbwHz ?? _phaseNoiseMarker?.rbwHz;
    return Container(
      width: 320,
      color: const Color.fromARGB(255, 66, 66, 66),
      padding: const EdgeInsets.all(8),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expander(
              header: const Text('Carrier'),
              content: Column(
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: ToggleButton(
                          checked: _phaseNoiseCarrierMode ==
                              PhaseNoiseCarrierMode.auto,
                          onChanged: (_) => setState(() {
                            _phaseNoiseCarrierMode = PhaseNoiseCarrierMode.auto;
                          }),
                          child: const Text('Auto'),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: ToggleButton(
                          checked: _phaseNoiseCarrierMode ==
                              PhaseNoiseCarrierMode.manual,
                          onChanged: (_) => setState(() {
                            _phaseNoiseCarrierMode =
                                PhaseNoiseCarrierMode.manual;
                          }),
                          child: const Text('Manual'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _buildInputRow(
                    label: 'Carrier',
                    controller: _phaseNoiseCarrierController,
                    unitNotifier: _phaseNoiseCarrierUnit,
                    units: freqUnits,
                    enabled:
                        _phaseNoiseCarrierMode == PhaseNoiseCarrierMode.manual,
                  ),
                  const SizedBox(height: 8),
                  _buildInputRow(
                    label: 'Search span',
                    controller: _phaseNoiseCarrierSearchSpanController,
                    unitNotifier: _phaseNoiseCarrierSearchSpanUnit,
                    units: freqUnits,
                    onChanged: () => setState(() {}),
                  ),
                  const SizedBox(height: 8),
                  Row(
                    children: [
                      const SizedBox(
                        width: 100,
                        child: Text(
                          'Trigger/Min level',
                          style: TextStyle(color: material.Colors.white),
                        ),
                      ),
                      Expanded(
                        child: TextBox(
                          controller: _phaseNoiseMinimumCarrierLevelController,
                          onChanged: (_) => setState(() {}),
                        ),
                      ),
                      const SizedBox(width: 8),
                      const SizedBox(width: 80, child: Text('dBm')),
                    ],
                  ),
                ],
              ),
            ),
            Expander(
              header: const Text('Offset'),
              content: Column(
                children: [
                  _buildInputRow(
                    label: 'Start',
                    controller: _phaseNoiseStartOffsetController,
                    unitNotifier: _phaseNoiseStartOffsetUnit,
                    units: freqUnits,
                  ),
                  const SizedBox(height: 8),
                  _buildInputRow(
                    label: 'Stop',
                    controller: _phaseNoiseStopOffsetController,
                    unitNotifier: _phaseNoiseStopOffsetUnit,
                    units: freqUnits,
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Density',
                      style: const TextStyle(color: material.Colors.white),
                    ),
                  ),
                  const SizedBox(height: 6),
                  ComboBox<PhaseNoiseDensityPreset>(
                    value: _phaseNoiseDensityPreset,
                    items: PhaseNoiseDensityPreset.values
                        .where((preset) =>
                            preset != PhaseNoiseDensityPreset.custom)
                        .map(
                          (preset) => ComboBoxItem(
                            value: preset,
                            child: Text(
                              '${preset.label} (${preset.pointsPerDecade})',
                            ),
                          ),
                        )
                        .toList(growable: false),
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        _phaseNoiseDensityPreset = value;
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Points: ${config.estimatedPointCount}  '
                    'Density: ${config.pointsPerDecade} pts/dec',
                    style: const TextStyle(color: material.Colors.white70),
                  ),
                ],
              ),
            ),
            Expander(
              header: const Text('Average'),
              content: Column(
                children: [
                  Row(
                    children: [
                      const SizedBox(
                        width: 100,
                        child: Text(
                          'Count',
                          style: TextStyle(color: material.Colors.white),
                        ),
                      ),
                      Expanded(
                        child: TextBox(
                          controller: _phaseNoiseAverageCountController,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Completed: $_phaseNoiseCompletedAverages',
                    style: const TextStyle(color: material.Colors.white70),
                  ),
                ],
              ),
            ),
            Expander(
              header: const Text('Trace'),
              content: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ComboBox<PhaseNoiseTraceDisplay>(
                    value: _phaseNoiseTraceDisplay,
                    items: const [
                      ComboBoxItem(
                        value: PhaseNoiseTraceDisplay.raw,
                        child: Text('Raw'),
                      ),
                      ComboBoxItem(
                        value: PhaseNoiseTraceDisplay.average,
                        child: Text('Avg'),
                      ),
                      ComboBoxItem(
                        value: PhaseNoiseTraceDisplay.both,
                        child: Text('Both'),
                      ),
                    ],
                    onChanged: (value) {
                      if (value == null) return;
                      setState(() {
                        _phaseNoiseTraceDisplay = value;
                      });
                    },
                  ),
                  const SizedBox(height: 8),
                  Text(
                    markerOffsetHz == null ||
                            markerDbcHz == null ||
                            markerRbwHz == null
                        ? 'Marker: --'
                        : 'Marker: ${_formatFreqAutoUnit(markerOffsetHz)}  '
                            '${markerDbcHz.toStringAsFixed(2)} dBc/Hz  '
                            'RBW ${_formatFreqAutoUnit(markerRbwHz)}',
                    style: const TextStyle(color: material.Colors.white70),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Density: ${config.pointsPerDecade} pts/dec',
                    style: const TextStyle(color: material.Colors.white70),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Button(
                    onPressed: _phaseNoiseCommandInFlight
                        ? null
                        : _startSinglePhaseNoiseMeasurement,
                    child: Text(
                      _phaseNoiseCommandInFlight ? 'Busy' : 'Single',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Button(
                    onPressed: _phaseNoiseCommandInFlight
                        ? null
                        : _startContinuousPhaseNoiseMeasurement,
                    child: const Text('Continuous'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Button(
                    onPressed: _phaseNoiseCommandInFlight
                        ? null
                        : _stopPhaseNoiseMeasurement,
                    child: const Text('Stop'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Button(
              onPressed: _phaseNoiseCommandInFlight
                  ? null
                  : () => _runSinglePhaseNoiseDemoSweep(resetAverage: true),
              child: const Text('Demo'),
            ),
            const SizedBox(height: 8),
            Button(
              onPressed: _exportPhaseNoiseCsv,
              child: const Text('Export CSV'),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final bool isDirectIfFft = _isDirectIfFftMode;
    final double startFreq = _chartStartHz;
    final double stopFreq = _chartStopHz;
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
              icon: FlyoutTarget(
                controller: _presetFlyoutController,
                child: const Icon(FluentIcons.refresh),
              ),
              label: const Text('预设'),
              onPressed: _showPresetFlyout),
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
            onPressed: _screenshotInProgress ? null : _showScreenshotSettings,
          ),
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
          if (_measurementMode == MeasurementMode.phaseNoise)
            Expanded(child: _buildPhaseNoiseView())
          else ...[
            Expanded(
              child: RepaintBoundary(
                key: _screenshotBoundaryKey,
                child: Acrylic(
                  tint: material.Colors.black.withValues(alpha: 0.8),
                  child: SpectrumChart(
                    data: _buildChartDisplayData(
                        _isZeroSpan ? _zeroSpanData : _spectrumData),
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
                    markersDraggable: !autoPeakEnabled.value,
                    onMarkerDragUpdate: _updateMarkerFreq,
                    isZeroSpan: _isZeroSpan,
                    traceSmoothingEnabled: _traceSmoothingEnabled,
                    zeroSpanFreqStr: _isZeroSpan
                        ? _formatFreqAutoUnit(_confirmedStartHz)
                        : '',
                    zeroSpanElapsedStr: _isZeroSpan &&
                            _zeroSpanStartTime != null
                        ? '${DateTime.now().difference(_zeroSpanStartTime!).inSeconds} s'
                        : '',
                  ),
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
                              enabled: _isFrequencySweepConfigActive,
                              onChanged: () => _lastFrequencyEditMode =
                                  FrequencyEditMode.startStop,
                              onUnitChanged: () => _handleFrequencyUnitChanged(
                                  _updateFreqFromStartStop),
                              onSubmitted: _updateFreqFromStartStop),
                          const SizedBox(height: 8),
                          _buildInputRow(
                              label: '终止频率：',
                              controller: stopFreqController,
                              unitNotifier: stopFreqUnit,
                              units: freqUnits,
                              enabled: _isFrequencySweepConfigActive,
                              onChanged: () => _lastFrequencyEditMode =
                                  FrequencyEditMode.startStop,
                              onUnitChanged: () => _handleFrequencyUnitChanged(
                                  _updateFreqFromStartStop),
                              onSubmitted: _updateFreqFromStartStop),
                          const SizedBox(height: 8),
                          _buildInputRow(
                              label: '中心频率：',
                              controller: centerFreqController,
                              unitNotifier: centerFreqUnit,
                              units: freqUnits,
                              enabled: _isFrequencySweepConfigActive,
                              onChanged: () => _lastFrequencyEditMode =
                                  FrequencyEditMode.centerSpan,
                              onUnitChanged: () => _handleFrequencyUnitChanged(
                                  _updateFreqFromCenterSpan),
                              onSubmitted: _updateFreqFromCenterSpan),
                          const SizedBox(height: 8),
                          _buildInputRow(
                              label: '扫描宽度：',
                              controller: spanController,
                              unitNotifier: spanUnit,
                              units: freqUnits,
                              enabled: _isFrequencySweepConfigActive,
                              onChanged: () => _lastFrequencyEditMode =
                                  FrequencyEditMode.centerSpan,
                              onUnitChanged: () => _handleFrequencyUnitChanged(
                                  _updateFreqFromCenterSpan),
                              onSubmitted: _updateFreqFromCenterSpan),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              Expanded(
                                child: Button(
                                  onPressed: _isFrequencySweepConfigActive
                                      ? _setFullSpan
                                      : null,
                                  child: const Text('FULL SPAN'),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Button(
                                  onPressed: _isFrequencySweepConfigActive
                                      ? _setZeroSpan
                                      : null,
                                  child: const Text('ZERO SPAN'),
                                ),
                              ),
                            ],
                          ),
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
                              const SizedBox(width: 8),
                              SizedBox(
                                width: 44,
                                child: Button(
                                  onPressed: () => _stepRefLevel(-10.0),
                                  child: const Text('-'),
                                ),
                              ),
                              const SizedBox(width: 4),
                              SizedBox(
                                width: 44,
                                child: Button(
                                  onPressed: () => _stepRefLevel(10.0),
                                  child: const Text('+'),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          _buildRfFrontendPanel(),
                        ],
                      ),
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
                                      '1 kHz',
                                      '10 kHz',
                                      '30 kHz',
                                      '100 kHz',
                                      '300 kHz',
                                      '1 MHz'
                                    ]
                                        .map((o) => ComboBoxItem<String>(
                                            value: o, child: Text(o)))
                                        .toList(),
                                    onChanged: isDirectIfFft
                                        ? null
                                        : (nv) => nv != null
                                            ? rbwMode.value = nv
                                            : null,
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
                                    onChanged: isDirectIfFft
                                        ? null
                                        : (nv) => nv != null
                                            ? vbwMode.value = nv
                                            : null,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          ValueListenableBuilder<String>(
                            valueListenable: vbwMode,
                            builder: (context, mode, child) {
                              final bool isEnabled =
                                  !isDirectIfFft && mode == '手动';
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
                                    onChanged: (nv) => nv != null
                                        ? detectMode.value = nv
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
                                  onChanged: (v) =>
                                      setState(() => autoPeakEnabled.value = v),
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
                                          value: m.id,
                                          child: Text('游标 ${m.id}')))
                                      .toList(),
                                  placeholder: const Text('无'),
                                  onChanged: (id) {
                                    if (id == null) {
                                      _selectMarker(null);
                                    } else {
                                      _selectMarker(_markers
                                          .firstWhere((m) => m.id == id));
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
                                      items: [
                                        '向左寻峰',
                                        '向右寻峰',
                                        '起始点',
                                        '结束点',
                                        '中间点'
                                      ]
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
                                                  newFreq = _chartStartHz;
                                                  break;
                                                case '结束点':
                                                  newFreq = _chartStopHz;
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
                                                  newFreq = (_chartStartHz +
                                                          _chartStopHz) /
                                                      2.0;
                                                  break;
                                              }
                                              _currentMarker!.freqHz = newFreq;
                                              _markerFreqController.text =
                                                  _formatFreqInput(newFreq,
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
                    Expander(
                      header: const Text('校准'),
                      content: _buildAmplitudeCalibrationPanel(),
                    ),
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
                                  enabled: !isDirectIfFft,
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
                                  style:
                                      TextStyle(color: material.Colors.white)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const SizedBox(
                                  width: 100,
                                  child: Text('曲线平滑:',
                                      style: TextStyle(
                                          color: material.Colors.white))),
                              ToggleSwitch(
                                checked: _traceSmoothingEnabled,
                                onChanged: (value) => setState(
                                    () => _traceSmoothingEnabled = value),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const SizedBox(
                                  width: 100,
                                  child: Text('相位噪声:',
                                      style: TextStyle(
                                          color: material.Colors.white))),
                              ToggleSwitch(
                                checked: _phaseNoiseDisplayEnabled,
                                onChanged: (value) => setState(
                                    () => _phaseNoiseDisplayEnabled = value),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const SizedBox(
                                  width: 100,
                                  child: Text('判断阈值:',
                                      style: TextStyle(
                                          color: material.Colors.white))),
                              Expanded(
                                child: TextBox(
                                  controller:
                                      _phaseNoiseDisplayThresholdController,
                                  onChanged: (value) => setState(() {}),
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Text('dBm',
                                  style:
                                      TextStyle(color: material.Colors.white)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const SizedBox(
                                  width: 100,
                                  child: Text('修正值:',
                                      style: TextStyle(
                                          color: material.Colors.white))),
                              Expanded(
                                child: TextBox(
                                  controller:
                                      _phaseNoiseDisplayOffsetController,
                                  onChanged: (value) => setState(() {}),
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Text('dB',
                                  style:
                                      TextStyle(color: material.Colors.white)),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const SizedBox(
                                  width: 100,
                                  child: Text('80M补偿:',
                                      style: TextStyle(
                                          color: material.Colors.white))),
                              ToggleSwitch(
                                checked: _eightyMHzDisplayEnabled,
                                onChanged: (value) => setState(
                                    () => _eightyMHzDisplayEnabled = value),
                              ),
                            ],
                          ),
                          const SizedBox(height: 8),
                          Row(
                            children: [
                              const SizedBox(
                                  width: 100,
                                  child: Text('80M补偿值:',
                                      style: TextStyle(
                                          color: material.Colors.white))),
                              Expanded(
                                child: TextBox(
                                  controller: _eightyMHzDisplayOffsetController,
                                  onChanged: (value) => setState(() {}),
                                ),
                              ),
                              const SizedBox(width: 8),
                              const Text('dB',
                                  style:
                                      TextStyle(color: material.Colors.white)),
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
        ],
      ),
      bottomBar: _buildBottomBar(),
    );
  }

  Widget _buildBottomBar() {
    final modeLabel = _measurementMode == MeasurementMode.phaseNoise
        ? '相位噪声'
        : (_sweepMode == SweepMode.standard ? '标准' : '实时');
    final scanningLabel = _spectrumRequestInFlight ? '正在扫描' : '空闲';
    _refreshCalibrationStatus();

    return Container(
      height: 30,
      color: material.Colors.grey[900],
      child: Row(
        children: [
          const SizedBox(width: 16),
          Expanded(
            flex: 3,
            child: Text(
              '模式：$modeLabel      数据包速率：${_currentSweepSpeed.toStringAsFixed(1)} 包/秒      当前状态：$scanningLabel      系统温度：35℃',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: material.Colors.white),
            ),
          ),
          const SizedBox(width: 16),
          Expanded(
            flex: 4,
            child: Text(
              _profileStatusText,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
              style: const TextStyle(color: material.Colors.lightGreenAccent),
            ),
          ),
          const SizedBox(width: 16),
        ],
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
    VoidCallback? onUnitChanged,
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
                  onUnitChanged?.call();
                }
              },
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildRfFrontendPanel() {
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
            const SizedBox(
              width: 100,
              child: Text(
                'VGA：',
                style: TextStyle(color: material.Colors.white),
              ),
            ),
            Expanded(
              child: ValueListenableBuilder<String>(
                valueListenable: vgaGainValue,
                builder: (context, value, child) => ComboBox<String>(
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
                      .map(
                          (o) => ComboBoxItem<String>(value: o, child: Text(o)))
                      .toList(),
                  onChanged: (nv) =>
                      nv != null ? vgaGainValue.value = nv : null,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildAmplitudeCalibrationPanel() {
    final isBusy = _calibrationSampling;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Expanded(
              child: ToggleSwitch(
                checked: _calibrationEnabled,
                content: Text(_calibrationEnabled ? '应用校准' : '校准关闭'),
                onChanged: isBusy
                    ? null
                    : (value) {
                        setState(() {
                          _calibrationEnabled = value;
                          _refreshCalibrationStatus();
                        });
                        _refreshDisplayedSpectrumWithCalibration();
                      },
              ),
            ),
            const SizedBox(width: 8),
            Text(_calibrationStatusText),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          _formatCalibrationFileSummary(),
          maxLines: 3,
          overflow: TextOverflow.ellipsis,
          style: TextStyle(color: material.Colors.grey[300], fontSize: 12),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            const SizedBox(
              width: 100,
              child:
                  Text('标准功率：', style: TextStyle(color: material.Colors.white)),
            ),
            Expanded(
              child: TextBox(
                controller: _calibrationPowerController,
                enabled: !isBusy,
                textAlign: TextAlign.right,
              ),
            ),
            const SizedBox(width: 8),
            const Text('dBm', style: TextStyle(color: material.Colors.white)),
          ],
        ),
        const SizedBox(height: 8),
        ComboBox<CalibrationPeakSearchMode>(
          value: _calibrationPeakSearchMode,
          isExpanded: true,
          items: const [
            ComboBoxItem(
              value: CalibrationPeakSearchMode.global,
              child: Text('峰值搜索：全扫宽'),
            ),
            ComboBoxItem(
              value: CalibrationPeakSearchMode.markerWindow,
              child: Text('峰值搜索：标记窗口'),
            ),
          ],
          onChanged: isBusy
              ? null
              : (mode) {
                  if (mode != null) {
                    setState(() => _calibrationPeakSearchMode = mode);
                  }
                },
        ),
        const SizedBox(height: 8),
        _buildInputRow(
          label: '搜索窗口：',
          controller: _calibrationSearchWindowController,
          unitNotifier: _calibrationSearchWindowUnit,
          units: freqUnits,
          enabled: !isBusy &&
              _calibrationPeakSearchMode ==
                  CalibrationPeakSearchMode.markerWindow,
        ),
        const SizedBox(height: 8),
        ToggleSwitch(
          checked: _calibrationInclude1k,
          content: const Text('包含 1 kHz RBW'),
          onChanged: isBusy
              ? null
              : (value) => setState(() => _calibrationInclude1k = value),
        ),
        const SizedBox(height: 12),
        Row(
          children: [
            Expanded(
              child: Button(
                onPressed: isBusy
                    ? null
                    : () => _captureCalibrationPoint(multiRbw: false),
                child: const Text('采集当前RBW'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: FilledButton(
                onPressed: isBusy
                    ? null
                    : () => _captureCalibrationPoint(multiRbw: true),
                child: Text(isBusy
                    ? '采样中...'
                    : (_calibrationInclude1k ? '采集6档RBW' : '采集5档RBW')),
              ),
            ),
          ],
        ),
        if (isBusy) ...[
          const SizedBox(height: 8),
          Button(
            onPressed:
                _calibrationCancelRequested ? null : _cancelCalibrationCapture,
            child: Text(_calibrationCancelRequested ? '取消中...' : '取消校准'),
          ),
        ],
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(
              child: Button(
                onPressed:
                    isBusy ? null : _showImportAmplitudeCalibrationDialog,
                child: const Text('导入'),
              ),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: Button(
                onPressed: isBusy ? null : _exportAmplitudeCalibration,
                child: const Text('导出'),
              ),
            ),
            const SizedBox(width: 8),
            Button(
              onPressed: isBusy ? null : _clearAmplitudeCalibration,
              child: const Text('清空'),
            ),
          ],
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
