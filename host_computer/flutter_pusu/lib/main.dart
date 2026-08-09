// main.dart
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/material.dart' as material;
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;
import 'package:file_selector/file_selector.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/rendering.dart';
import 'package:window_manager/window_manager.dart';

// 瀵煎叆涓插彛鐩稿叧
import 'serial_port_manager.dart';
import 'serial_port_selector.dart';
import 'serial_protocol.dart';
import 'device_models.dart';
import 'amplitude_calibration.dart';
import 'calibration_sweep_policy.dart';
import 'frequency_format.dart';
import 'phase_noise_chart.dart';
import 'phase_noise_models.dart';
import 'phase_noise_processor.dart';
import 'fixed_frequency_compensation.dart';
import 'realtime_spectrum_page.dart';
import 'ai/ai_assistant_panel.dart';
import 'agent/instrument_agent.dart';
import 'agent/spectrum_analysis.dart';
import 'agent/spectrum_comparison.dart';
import 'agent/test_session_store.dart';
import 'resizable_panel_divider.dart';
import 'windows_title_bar.dart';

// 瀵煎叆鑷畾涔夐璋卞浘缁勪欢
import 'spectrum_chart.dart';

// ==================== 鎵弿模式鏋氫妇锛堥《灞傦級 ====================
enum SweepMode { standard, realTime }

enum FrequencyEditMode { startStop, centerSpan }

enum MeasurementMode { spectrum, phaseNoise, realtimeSpectrum }

enum CalibrationPeakSearchMode { global, markerWindow }

class CalibrationSamplingSettings {
  const CalibrationSamplingSettings({
    required this.rbwModes,
    required this.restoreRbwMode,
    required this.restoreVbwMode,
    required this.restoreWasContinuous,
    required this.restoreStartHz,
    required this.restoreStopHz,
    required this.restoreFrequencyEditMode,
  });

  final List<String> rbwModes;
  final String restoreRbwMode;
  final String restoreVbwMode;
  final bool restoreWasContinuous;
  final double restoreStartHz;
  final double restoreStopHz;
  final FrequencyEditMode restoreFrequencyEditMode;
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

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  if (Platform.isWindows) {
    await windowManager.ensureInitialized();
    const windowOptions = WindowOptions(
      minimumSize: ui.Size(960, 600),
      titleBarStyle: TitleBarStyle.hidden,
      windowButtonVisibility: false,
    );
    unawaited(
      windowManager.waitUntilReadyToShow(windowOptions, () async {
        await windowManager.show();
        await windowManager.focus();
      }),
    );
  }
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
  static const double _defaultPhaseNoiseCarrierHz =
      PhaseNoiseConfig.defaultCarrierHz;
  static const int _defaultSpectrumPointCount = 128;
  static const int _maxInternalSweepPointCount = 10000;
  static const bool _enforceInternalSweepPointLimit = bool.fromEnvironment(
    'PUSU_ENFORCE_SWEEP_POINT_LIMIT',
    defaultValue: false,
  );
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

  final GlobalKey _spectrumScreenshotBoundaryKey = GlobalKey();
  final GlobalKey _phaseNoiseScreenshotBoundaryKey = GlobalKey();
  final GlobalKey _realtimeScreenshotBoundaryKey = GlobalKey();
  final GlobalKey<AiAssistantPanelState> _aiAssistantKey =
      GlobalKey<AiAssistantPanelState>();
  final GlobalKey<RealtimeSpectrumPageState> _realtimeSpectrumPageKey =
      GlobalKey<RealtimeSpectrumPageState>();
  bool _aiAssistantVisible = false;
  bool _aiAssistantListening = false;
  bool _modeSwitchInFlight = false;
  double _settingsPanelWidth = 300;
  double _aiPanelWidth = 420;
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
      TextEditingController(text: '-20');
  final TextEditingController _phaseNoiseDisplayThresholdController =
      TextEditingController(text: '-40');
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
      TextEditingController(text: '1');
  final ValueNotifier<String> _phaseNoiseCarrierUnit =
      ValueNotifier<String>('GHz');
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
  final Map<double, PhaseNoisePoint> _phaseNoiseRawLivePoints = {};
  final Map<double, PhaseNoisePoint> _phaseNoiseAverageLivePoints = {};
  final PhaseNoiseRollingAverager _phaseNoiseRollingAverager =
      PhaseNoiseRollingAverager(windowSize: 10);
  int? _phaseNoiseDataTraceId;
  int _phaseNoiseAverageWindowTarget = 10;
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
  String _phaseNoiseStateText = '空闲';

  // 涓插彛绠＄悊
  late SerialPortManager _serialManager;
  late SerialProtocol _protocol;
  late InstrumentAgentGateway _instrumentAgentGateway;
  late AgentTestSessionStore _agentTestSessionStore;
  late Future<AgentTestSession?> _agentSessionRestoreFuture;

  final FlyoutController _serialFlyoutController = FlyoutController();

  // 棰戣氨鏁版嵁
  List<FlSpot> _spectrumData = [];
  List<FlSpot> _rawSpectrumData = [];
  List<FlSpot> _agentReferenceSpectrumData = <FlSpot>[];
  String _agentReferenceSpectrumLabel = '';
  List<SpectrumLimitLine> _agentSpectrumLimitLines = <SpectrumLimitLine>[];
  Map<String, dynamic>? _lastAgentLimitEvaluation;
  double? _agentMaximumNoiseFloorDbm;
  double? _agentMinimumMainPeakDbm;
  double? _agentMinimumSpurSuppressionDb;

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
  bool _fixedFrequencyCompensationEnabled = true;
  Map<double, double> _fixedFrequencyCompensationValues = <double, double>{};
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
  SweepProfileReport? _lastSweepProfileReport;
  Completer<SweepProfileReport>? _sweepProfileCompleter;

  @override
  void initState() {
    super.initState();
    _serialManager = SerialPortManager();
    _protocol = SerialProtocol(_serialManager);
    _agentTestSessionStore = AgentTestSessionStore(_agentSessionsDirectory());
    _agentSessionRestoreFuture = _agentTestSessionStore.restoreActiveSession();
    _instrumentAgentGateway = InstrumentAgentGateway(
      snapshotProvider: _buildInstrumentAgentSnapshot,
      setFrequency: _agentSetFrequency,
      setBandwidth: _agentSetBandwidth,
      setDetector: _agentSetDetector,
      setMeasurementMode: _agentSetMeasurementMode,
      configureSpectrumFrontend: _agentConfigureSpectrumFrontend,
      applySpectrumPreset: _agentApplySpectrumPreset,
      startSingleSweep: _agentStartSingleSweep,
      startContinuousSweep: _agentStartContinuousSweep,
      stopMeasurement: _agentStopMeasurement,
      startPhaseNoiseMeasurement: _agentStartPhaseNoiseMeasurement,
      stopPhaseNoiseMeasurement: _agentStopPhaseNoiseMeasurement,
      getPhaseNoiseState: _agentGetPhaseNoiseState,
      configurePhaseNoise: _agentConfigurePhaseNoise,
      analyzePhaseNoise: _agentAnalyzePhaseNoise,
      getPhaseNoiseSnapshot: _agentGetPhaseNoiseSnapshot,
      startRealtimeSpectrum: _agentStartRealtimeSpectrum,
      stopRealtimeSpectrum: _agentStopRealtimeSpectrum,
      getSpectrumSnapshot: _agentGetSpectrumSnapshot,
      analyzeSpectrum: _agentAnalyzeSpectrum,
      placePeakMarkers: _agentPlacePeakMarkers,
      getRealtimeSpectrumState: _agentGetRealtimeSpectrumState,
      configureRealtimeSpectrum: _agentConfigureRealtimeSpectrum,
      getRealtimeSpectrumSnapshot: _agentGetRealtimeSpectrumSnapshot,
      getRealtimeWaterfallHistory: _agentGetRealtimeWaterfallHistory,
      analyzeRealtimeSpectrum: _agentAnalyzeRealtimeSpectrum,
      placeRealtimePeakMarkers: _agentPlaceRealtimePeakMarkers,
      saveMeasurement: _agentSaveMeasurement,
      saveRealtimeMeasurement: _agentSaveRealtimeMeasurement,
      savePhaseNoiseMeasurement: _agentSavePhaseNoiseMeasurement,
      getSweepProfile: _agentGetSweepProfile,
      captureScreenshot: _agentCaptureScreenshot,
      getTestSession: _agentGetTestSession,
      startTestSession: _agentStartTestSession,
      addTestNote: _agentAddTestNote,
      endTestSession: _agentEndTestSession,
      listTestSessions: _agentListTestSessions,
      listMeasurements: _agentListMeasurements,
      loadMeasurement: _agentLoadMeasurement,
      compareMeasurements: _agentCompareMeasurements,
      evaluateSpectrumLimits: _agentEvaluateSpectrumLimits,
      clearAnalysisOverlays: _agentClearAnalysisOverlays,
      exportTestReport: _agentExportTestReport,
    );
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
            -40.0;
    return data
        .map((spot) =>
            spot.y < thresholdDbm ? FlSpot(spot.x, spot.y + offsetDb) : spot)
        .toList();
  }

  List<FlSpot> _buildChartDisplayData(List<FlSpot> data) {
    return _buildPhaseNoiseDisplayData(data);
  }

  List<FlSpot> _buildActualSpectrumData(
    List<FlSpot> data, {
    bool sweepComplete = false,
  }) {
    if (!_fixedFrequencyCompensationEnabled) return data;
    final targetsHz = fixedFrequencyCompensationTargetsForRbw(
      _getSelectedRbwHz(),
    );
    final replacements = buildFixedFrequencyCompensationValues(
      data,
      targetsHz: targetsHz,
      allowFollowingFallback: sweepComplete,
    );
    if (sweepComplete) {
      _fixedFrequencyCompensationValues = replacements;
    } else {
      for (final entry in _fixedFrequencyCompensationValues.entries) {
        replacements.putIfAbsent(entry.key, () => entry.value);
      }
    }
    return applyFixedFrequencyCompensation(
      data,
      replacements,
      targetsHz: targetsHz,
    );
  }

  void _setFixedFrequencyCompensationEnabled(bool enabled) {
    if (_fixedFrequencyCompensationEnabled == enabled) return;
    final rawData = _displaySweepPoints.entries
        .map((e) => FlSpot(e.key, e.value))
        .toList()
      ..sort((a, b) => a.x.compareTo(b.x));
    setState(() {
      _fixedFrequencyCompensationEnabled = enabled;
      if (!_isZeroSpan) {
        _spectrumData = _buildActualSpectrumData(rawData);
        _updateAutoMarkersFromSpectrum();
      }
    });
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
    _fixedFrequencyCompensationValues = <double, double>{};
    setState(() {
      _spectrumData = _buildActualSpectrumData(display);
      _updateAutoMarkersFromSpectrum();
      _refreshAgentLimitEvaluation();
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

  FlSpot? _findCalibrationPeak(
    List<FlSpot> rawTrace, {
    bool applyConfiguredSearchWindow = true,
  }) {
    if (rawTrace.isEmpty) return null;
    Iterable<FlSpot> candidates = rawTrace;
    if (applyConfiguredSearchWindow &&
        _calibrationPeakSearchMode == CalibrationPeakSearchMode.markerWindow &&
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

  void _setCalibrationSweepRange(double startHz, double stopHz) {
    _lastFrequencyEditMode = FrequencyEditMode.startStop;
    _confirmedStartHz = startHz;
    _confirmedStopHz = stopHz;
    _syncFrequencyFieldsFromConfirmed();
  }

  void _setCalibrationCenterSpan(double centerHz, double spanHz) {
    _lastFrequencyEditMode = FrequencyEditMode.centerSpan;
    _confirmedStartHz = centerHz - spanHz / 2.0;
    _confirmedStopHz = centerHz + spanHz / 2.0;
    _syncFrequencyFieldsFromConfirmed();
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
      restoreStartHz: _confirmedStartHz,
      restoreStopHz: _confirmedStopHz,
      restoreFrequencyEditMode: _lastFrequencyEditMode,
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
    FlSpot? previousPeak;

    try {
      _stopContinuousSweep();
      for (var index = 0; index < settings.rbwModes.length; index++) {
        final mode = settings.rbwModes[index];
        if (_calibrationCancelRequested) {
          throw const CalibrationCancelledException();
        }

        double? sweepSpanHz;
        if (multiRbw) {
          if (index == 0) {
            _setCalibrationSweepRange(
              settings.restoreStartHz,
              settings.restoreStopHz,
            );
          } else {
            sweepSpanHz = CalibrationSweepPolicy.spanHzForMode(mode);
            if (previousPeak == null || sweepSpanHz == null) {
              throw StateError('RBW $mode 缺少逐级校准扫宽配置');
            }
            _setCalibrationCenterSpan(previousPeak.x, sweepSpanHz);
          }
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

        var rawTrace = await _runSingleSweepForCalibration();
        if (_calibrationCancelRequested) {
          throw const CalibrationCancelledException();
        }
        var peak = _findCalibrationPeak(
          rawTrace,
          applyConfiguredSearchWindow: !multiRbw || index == 0,
        );
        if (peak == null) {
          throw StateError('RBW $mode 未找到有效峰值');
        }

        if (multiRbw &&
            index > 0 &&
            sweepSpanHz != null &&
            previousPeak != null &&
            CalibrationSweepPolicy.shouldRetryForPowerDrop(
              previousPeakDbm: previousPeak.y,
              currentPeakDbm: peak.y,
            )) {
          final firstPeak = peak;
          final retrySpanHz = CalibrationSweepPolicy.retrySpanHz(sweepSpanHz);
          setState(() {
            _calibrationStatusText =
                '$mode 峰值下降超过 ${CalibrationSweepPolicy.powerDropRetryDb.toStringAsFixed(0)} dB，扩大扫宽重试...';
          });
          _setCalibrationCenterSpan(previousPeak.x, retrySpanHz);
          rawTrace = await _runSingleSweepForCalibration();
          if (_calibrationCancelRequested) {
            throw const CalibrationCancelledException();
          }
          final retryPeak = _findCalibrationPeak(
            rawTrace,
            applyConfiguredSearchWindow: false,
          );
          if (retryPeak != null && retryPeak.y > firstPeak.y) {
            peak = retryPeak;
          }
        }

        calibrationFrequencyHz = peak.x;
        samples.add(
          AmplitudeCalibrationSample(
            rbwHz: _getSelectedRbwHz(),
            measuredPowerDbm: peak.y,
            correctionDb: referencePowerDbm - peak.y,
            peakFrequencyHz: peak.x,
            timestamp: DateTime.now(),
          ),
        );
        previousPeak = peak;
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
        _lastFrequencyEditMode = settings.restoreFrequencyEditMode;
        _confirmedStartHz = settings.restoreStartHz;
        _confirmedStopHz = settings.restoreStopHz;
        _syncFrequencyFieldsFromConfirmed();
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
      final savedAt = DateTime.now();
      final initialDirectory = _screenshotDirController.text.trim().isEmpty
          ? _defaultScreenshotDirectory
          : _screenshotDirController.text.trim();
      final location = await getSaveLocation(
        acceptedTypeGroups: const [
          XTypeGroup(label: 'JSON 校准文件', extensions: ['json']),
        ],
        initialDirectory: initialDirectory,
        suggestedName:
            'amplitude_calibration_${_formatFileTimestamp(savedAt)}.json',
        confirmButtonText: '导出',
        canCreateDirectories: true,
      );
      if (location == null) return;
      final file = File(location.path);
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

  Future<void> _showImportAmplitudeCalibrationDialog() async {
    final currentPath = _calibrationFilePath;
    final initialDirectory = currentPath == null
        ? (_screenshotDirController.text.trim().isEmpty
            ? _defaultScreenshotDirectory
            : _screenshotDirController.text.trim())
        : File(currentPath).parent.path;
    try {
      final selected = await openFile(
        acceptedTypeGroups: const [
          XTypeGroup(label: 'JSON 校准文件', extensions: ['json']),
        ],
        initialDirectory: initialDirectory,
        confirmButtonText: '导入',
      );
      if (selected == null) return;
      await _importAmplitudeCalibration(selected.path);
    } catch (error) {
      _showInfoBar(
        title: '无法打开文件选择窗口',
        content: error.toString(),
        severity: InfoBarSeverity.error,
      );
    }
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
      _spectrumData = _buildActualSpectrumData(_spectrumData);
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

    final completedData = _displaySweepPoints.entries
        .map((e) => FlSpot(e.key, e.value))
        .toList()
      ..sort((a, b) => a.x.compareTo(b.x));
    final actualCompletedData =
        _buildActualSpectrumData(completedData, sweepComplete: true);

    setState(() {
      _rawDisplaySweepPoints.addAll(_rawPendingSweepPoints);
      _displaySweepPoints.addAll(_pendingSweepPoints);
      _rawSpectrumData = _rawDisplaySweepPoints.entries
          .map((e) => FlSpot(e.key, e.value))
          .toList()
        ..sort((a, b) => a.x.compareTo(b.x));
      _spectrumData = actualCompletedData;

      _updateAutoMarkersFromSpectrum();
      _refreshAgentLimitEvaluation();
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
      _lastSweepProfileReport = report;
      _profileStatusText = _formatSweepProfileStatus(report);
    });
    final completer = _sweepProfileCompleter;
    if (completer != null && !completer.isCompleted) {
      completer.complete(report);
    }
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
          ? '错误 ${_phaseNoiseErrorLabel(frame.errorCode)}'
          : (frame.done ? '完成' : '测量中');

      final newTrace = _phaseNoiseDataTraceId != frame.traceId;
      if (newTrace) {
        _phaseNoiseRawLivePoints.clear();
        _phaseNoiseAverageLivePoints.clear();
        _phaseNoiseRollingAverager.reset(
          windowSize: _phaseNoiseAverageWindowTarget,
        );
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
        if (frame.containsRawMeasurement) {
          _phaseNoiseRawLivePoints[point.offsetHz] = point;
          _phaseNoiseAverageLivePoints[point.offsetHz] =
              _phaseNoiseRollingAverager.add(point);
        } else {
          _phaseNoiseAverageLivePoints[point.offsetHz] = point;
        }
      }

      final rawPoints = _phaseNoiseRawLivePoints.values.toList()
        ..sort((a, b) => a.offsetHz.compareTo(b.offsetHz));
      final averagePoints = _phaseNoiseAverageLivePoints.values.toList()
        ..sort((a, b) => a.offsetHz.compareTo(b.offsetHz));
      final carrier = _buildPhaseNoiseCarrierFromData(frame);
      final warnings = _buildPhaseNoiseWarnings(
        warningCode: frame.warning ? _phaseNoiseWarningCode : 0,
        errorCode: frame.errorCode,
      );
      _setPhaseNoiseTrace(
        PhaseNoiseTrace(
          rawPoints: List<PhaseNoisePoint>.unmodifiable(rawPoints),
          averagePoints: List<PhaseNoisePoint>.unmodifiable(averagePoints),
          completedAverages: math.min(
            frame.averageIndex,
            _phaseNoiseAverageWindowTarget,
          ),
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
            completedAverages: _phaseNoiseTrace.completedAverages,
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
          message: '警告 ${_phaseNoiseWarningLabel(warningCode)}',
        ),
      if (errorCode != 0)
        PhaseNoiseWarning(
          code: PhaseNoiseWarningCode.deviceError,
          message: '错误 ${_phaseNoiseErrorLabel(errorCode)}',
        ),
    ];
  }

  String _phaseNoiseStateLabel(PhaseNoiseStatusFrame status) {
    if (status.errorCode != 0 && status.state == 6) {
      return '错误 ${_phaseNoiseErrorLabel(status.errorCode)}';
    }
    switch (status.state) {
      case 0:
        return status.configured ? '空闲（已配置）' : '空闲';
      case 1:
        return '已配置';
      case 2:
        if (status.currentOffsetHz <= 0) {
          return '搜索载波（尚无频偏数据）';
        }
        return '搜索载波';
      case 3:
        return '测量中';
      case 4:
        return '停止中';
      case 5:
        return '完成';
      case 6:
        return '错误 ${_phaseNoiseErrorLabel(status.errorCode)}';
      default:
        return '状态 ${status.state}';
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
        return '无';
      case 1:
        return '频偏低于 RBW';
      case 2:
        return 'ENBW 为估算值';
      case 3:
        return '载波电平过低';
      case 4:
        return 'RF 范围已限幅';
      case 5:
        return '双边带数据不完整';
      case 6:
        return '扫描计划已截断';
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

  String _bottomProfileStatusText() {
    final measText = _phaseNoiseDisplayEnabled ? 'meas 1ms' : 'meas 0ms';
    final segments = _profileStatusText
        .split('|')
        .map((segment) => segment.trim())
        .where((segment) => segment.isNotEmpty)
        .toList();
    final measIndex =
        segments.indexWhere((segment) => segment.startsWith('meas '));

    if (measIndex >= 0) {
      segments[measIndex] = measText;
    } else {
      segments.add(measText);
    }
    return segments.join(' | ');
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
    _fixedFrequencyCompensationValues.clear();
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

  Future<void> _showScreenshotSettings() async {
    try {
      final currentDirectory = _screenshotDirController.text.trim().isEmpty
          ? _defaultScreenshotDirectory
          : _screenshotDirController.text.trim();
      final selectedDirectory = await getDirectoryPath(
        initialDirectory: currentDirectory,
        confirmButtonText: '选择截图保存文件夹',
        canCreateDirectories: true,
      );
      if (selectedDirectory == null) return;
      _screenshotDirController.text = selectedDirectory;
      await _saveScreenshot(selectedDirectory);
    } catch (error) {
      _showInfoBar(
        title: '无法打开文件夹选择窗口',
        content: error.toString(),
        severity: InfoBarSeverity.error,
      );
    }
  }

  Future<void> _saveScreenshot(String rawDirectoryPath) async {
    try {
      final file = await _captureCurrentMeasurementScreenshot(rawDirectoryPath);
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
    }
  }

  GlobalKey get _activeScreenshotBoundaryKey => switch (_measurementMode) {
        MeasurementMode.spectrum => _spectrumScreenshotBoundaryKey,
        MeasurementMode.phaseNoise => _phaseNoiseScreenshotBoundaryKey,
        MeasurementMode.realtimeSpectrum => _realtimeScreenshotBoundaryKey,
      };

  String get _activeScreenshotPrefix => switch (_measurementMode) {
        MeasurementMode.spectrum => 'spectrum',
        MeasurementMode.phaseNoise => 'phase_noise',
        MeasurementMode.realtimeSpectrum => 'realtime_spectrum',
      };

  Future<File> _captureCurrentMeasurementScreenshot(
    String rawDirectoryPath,
  ) async {
    if (_screenshotInProgress) {
      throw StateError('已有截图任务正在进行');
    }
    final directoryPath = rawDirectoryPath.trim().isEmpty
        ? _defaultScreenshotDirectory
        : rawDirectoryPath.trim();
    _screenshotDirController.text = directoryPath;
    setState(() => _screenshotInProgress = true);
    try {
      await WidgetsBinding.instance.endOfFrame;
      final boundaryContext = _activeScreenshotBoundaryKey.currentContext;
      final renderObject = boundaryContext?.findRenderObject();
      if (renderObject is! RenderRepaintBoundary) {
        throw StateError('未找到当前测量模式的可截图区域');
      }

      final savedAt = DateTime.now();
      final screenshot = await renderObject.toImage(pixelRatio: 2.0);
      final annotatedScreenshot =
          await _addScreenshotTimestamp(screenshot, savedAt);
      final pngBytes =
          await annotatedScreenshot.toByteData(format: ui.ImageByteFormat.png);
      screenshot.dispose();
      annotatedScreenshot.dispose();
      if (pngBytes == null) throw StateError('截图编码失败');

      final directory = Directory(directoryPath);
      await directory.create(recursive: true);
      final fileName =
          '${_activeScreenshotPrefix}_${_formatFileTimestamp(savedAt)}.png';
      final file = File('${directory.path}${Platform.pathSeparator}$fileName');
      await file.writeAsBytes(pngBytes.buffer.asUint8List(), flush: true);
      return file;
    } finally {
      if (mounted) setState(() => _screenshotInProgress = false);
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
    if (!_enforceInternalSweepPointLimit) {
      return true;
    }
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

  String _rfPathModeAgentName(RfPathMode mode) => switch (mode) {
        RfPathMode.directIf => 'direct_if',
        RfPathMode.mixerChain => 'mixer_chain',
        RfPathMode.auto => 'auto',
      };

  String _rfLnaModeAgentName(RfLnaMode mode) => switch (mode) {
        RfLnaMode.bypass => 'bypass',
        RfLnaMode.enable => 'enable',
        RfLnaMode.auto => 'auto',
      };

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
        _spectrumData =
            _buildActualSpectrumData(_buildDisplaySpectrumFromRaw());
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

  Future<bool> _stopContinuousSweep() async {
    _measurementConfigGeneration++;
    _measurementConfigInFlight = false;
    _awaitingTimeoutStatus = false;
    var stopped = true;
    if (_serialManager.isConnected && !_isDirectIfFftMode) {
      stopped = await _protocol.stopSweepConfirmed();
    }
    _acceptSpectrumData = false;
    _continuousSweepTimer?.cancel();
    _spectrumRequestTimeoutTimer?.cancel();
    _sweepAssembleTimer?.cancel();
    _spectrumRequestInFlight = false;
    _activeSweepTimestamp = null;
    _pendingSweepPoints.clear();
    _rawPendingSweepPoints.clear();
    if (_serialManager.isConnected) {
      await _serialManager.drainInputBuffer();
    }
    _protocol.resetReceiveBuffer();
    if (_isContinuousSweepRunning) {
      setState(() {
        _isContinuousSweepRunning = false;
      });
    }
    return stopped;
  }

  bool get _activeToolbarMeasurementRunning => switch (_measurementMode) {
        MeasurementMode.spectrum =>
          _spectrumRequestInFlight || _isContinuousSweepRunning,
        MeasurementMode.phaseNoise => _phaseNoiseRunning,
        MeasurementMode.realtimeSpectrum =>
          _realtimeSpectrumPageKey.currentState?.isRunning ?? false,
      };

  bool get _activeToolbarMeasurementBusy =>
      _modeSwitchInFlight ||
      (_measurementMode == MeasurementMode.phaseNoise &&
          _phaseNoiseCommandInFlight);

  Future<void> _handleToolbarSingleMeasurement() async {
    switch (_measurementMode) {
      case MeasurementMode.spectrum:
        if (_isContinuousSweepRunning) {
          final stopped = await _stopContinuousSweep();
          if (!stopped) return;
        }
        await _applyMeasurementConfigChange(forceContinuous: false);
        return;
      case MeasurementMode.phaseNoise:
        await _startSinglePhaseNoiseMeasurement();
        return;
      case MeasurementMode.realtimeSpectrum:
        return;
    }
  }

  Future<void> _handleToolbarContinuousMeasurement() async {
    switch (_measurementMode) {
      case MeasurementMode.spectrum:
        await _startContinuousSweep();
        return;
      case MeasurementMode.phaseNoise:
        await _startContinuousPhaseNoiseMeasurement();
        return;
      case MeasurementMode.realtimeSpectrum:
        return;
    }
  }

  Future<void> _handleToolbarStopMeasurement() async {
    switch (_measurementMode) {
      case MeasurementMode.spectrum:
        await _stopContinuousSweep();
        return;
      case MeasurementMode.phaseNoise:
        await _stopPhaseNoiseMeasurement();
        return;
      case MeasurementMode.realtimeSpectrum:
        return;
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
                onPressed: _modeSwitchInFlight
                    ? null
                    : () {
                        Navigator.pop(context);
                        unawaited(
                          _switchMeasurementMode(MeasurementMode.spectrum),
                        );
                      },
              ),
              ListTile(
                title: const Text('相位噪声'),
                subtitle: const Text('1 kHz - 1 MHz offset，显示 dBc/Hz 曲线'),
                trailing: _measurementMode == MeasurementMode.phaseNoise
                    ? const Icon(FluentIcons.check_mark)
                    : const SizedBox.shrink(),
                onPressed: _modeSwitchInFlight
                    ? null
                    : () {
                        Navigator.pop(context);
                        unawaited(
                          _switchMeasurementMode(MeasurementMode.phaseNoise),
                        );
                      },
              ),
              ListTile(
                title: const Text('实时频谱'),
                subtitle: const Text(
                    '10 MHz span, IF FFT 4096, latest/avg/max/waterfall'),
                trailing: _measurementMode == MeasurementMode.realtimeSpectrum
                    ? const Icon(FluentIcons.check_mark)
                    : const SizedBox.shrink(),
                onPressed: _modeSwitchInFlight
                    ? null
                    : () {
                        Navigator.pop(context);
                        unawaited(
                          _switchMeasurementMode(
                            MeasurementMode.realtimeSpectrum,
                          ),
                        );
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

  Future<void> _switchMeasurementMode(MeasurementMode mode) async {
    if (_measurementMode == mode || _modeSwitchInFlight) return;
    final previousMode = _measurementMode;
    final realtimeFrontend = previousMode == MeasurementMode.realtimeSpectrum
        ? _realtimeSpectrumPageKey.currentState?.agentConfiguration
        : null;
    setState(() {
      _modeSwitchInFlight = true;
    });

    try {
      final stopped = await _stopActiveMeasurementForModeSwitch();
      if (!stopped) {
        _showInfoBar(
          title: '模式切换已取消',
          content: '${_measurementModeLabel(previousMode)}任务未确认停止，请重试。',
          severity: InfoBarSeverity.warning,
        );
        return;
      }
      if (!mounted) return;
      _updateMeasurementModeUi(mode);
      if (mode != MeasurementMode.realtimeSpectrum &&
          realtimeFrontend != null) {
        _syncSweepFrontendFromRealtime(realtimeFrontend);
      }
    } finally {
      if (mounted) {
        setState(() {
          _modeSwitchInFlight = false;
        });
      }
    }
  }

  void _syncSweepFrontendFromRealtime(Map<String, dynamic> state) {
    final attenuation = (state['attenuation_db'] as num?)?.toDouble();
    final lnaEnabled = state['lna_enabled'];
    final vgaDb = (state['vga_db'] as num?)?.toDouble();
    var config = _rfFrontendConfig;
    if (attenuation != null && attenuation.isFinite) {
      config = config.copyWith(
        attenCode: (attenuation / 0.25).round().clamp(0, 127),
        pathMode: RfPathMode.mixerChain,
      );
    }
    if (lnaEnabled is bool) {
      config = config.copyWith(
        lnaMode: lnaEnabled ? RfLnaMode.enable : RfLnaMode.bypass,
        pathMode: RfPathMode.mixerChain,
      );
    }
    final vgaLabel = vgaDb == null ? null : _vgaLabelForDb(vgaDb);
    _suppressPresetDeviceUpdates = true;
    try {
      setState(() {
        _rfFrontendConfig = config;
        _syncRfAttenText(config);
        if (vgaLabel != null) vgaGainValue.value = vgaLabel;
      });
    } finally {
      _suppressPresetDeviceUpdates = false;
    }
  }

  String? _vgaLabelForDb(double value) {
    const labels = <String>[
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
      '34 dB',
    ];
    for (final label in labels) {
      if ((double.parse(label.split(' ').first) - value).abs() < 1e-9) {
        return label;
      }
    }
    return null;
  }

  Future<bool> _stopActiveMeasurementForModeSwitch() async {
    switch (_measurementMode) {
      case MeasurementMode.spectrum:
        return _stopContinuousSweep();
      case MeasurementMode.phaseNoise:
        return _stopPhaseNoiseSafely();
      case MeasurementMode.realtimeSpectrum:
        if (!_serialManager.isConnected) return true;
        return _realtimeSpectrumPageKey.currentState?.stopFromAgent() ??
            _protocol.stopRealtimeSpectrumConfirmed();
    }
  }

  String _measurementModeLabel(MeasurementMode mode) => switch (mode) {
        MeasurementMode.spectrum => '扫频',
        MeasurementMode.phaseNoise => '相位噪声',
        MeasurementMode.realtimeSpectrum => '实时频谱',
      };

  void _updateMeasurementModeUi(MeasurementMode mode) {
    if (mode == MeasurementMode.phaseNoise ||
        mode == MeasurementMode.realtimeSpectrum) {
      _acceptSpectrumData = false;
      _clearSpectrumDisplay();
      _clearPhaseNoiseShellData();
    } else {
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
    _phaseNoiseRawLivePoints.clear();
    _phaseNoiseAverageLivePoints.clear();
    _phaseNoiseRollingAverager.reset(
      windowSize: _phaseNoiseAverageWindowTarget,
    );
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
    _phaseNoiseStateText = '空闲';
  }

  PhaseNoiseConfig _buildCurrentPhaseNoiseConfig() {
    final parsedStartOffsetHz = _parseFreq(
          _phaseNoiseStartOffsetController.text,
          _phaseNoiseStartOffsetUnit.value,
        ) ??
        _phaseNoiseConfig.startOffsetHz;
    final startOffsetHz = math.max(
      parsedStartOffsetHz,
      PhaseNoiseConfig.minimumOffsetHz,
    );
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
      startOffsetHz: startOffsetHz,
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

  void _enforcePhaseNoiseStartOffsetMinimum() {
    final offsetHz = _parseFreq(
      _phaseNoiseStartOffsetController.text,
      _phaseNoiseStartOffsetUnit.value,
    );
    if (offsetHz != null && offsetHz < PhaseNoiseConfig.minimumOffsetHz) {
      _setFreqField(
        _phaseNoiseStartOffsetController,
        _phaseNoiseStartOffsetUnit,
        PhaseNoiseConfig.minimumOffsetHz,
      );
    }
    if (mounted) setState(() {});
  }

  double _resolvePhaseNoiseNominalCarrierHz({double? manualCarrierHz}) {
    return manualCarrierHz ?? _defaultPhaseNoiseCarrierHz;
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

  // Retained for developers to exercise the chart without exposing a UI entry.
  // ignore: unused_element
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
        stateText: '演示测量中',
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
        _phaseNoiseStateText = index >= allPoints.length ? '演示完成' : '演示测量中';
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
    _phaseNoiseAverageWindowTarget = config.averageTarget;
    if (clearTrace) {
      _phaseNoiseRawLivePoints.clear();
      _phaseNoiseAverageLivePoints.clear();
      _phaseNoiseRollingAverager.reset(
        windowSize: _phaseNoiseAverageWindowTarget,
      );
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
    await _startPhaseNoiseMeasurement(continuous: false);
  }

  Future<void> _startContinuousPhaseNoiseMeasurement() async {
    await _startPhaseNoiseMeasurement(continuous: true);
  }

  Future<void> _startPhaseNoiseMeasurement({required bool continuous}) async {
    if (_phaseNoiseCommandInFlight) return;
    final config = _buildCurrentPhaseNoiseConfig();
    if (!config.isValid || config.protocolNominalCarrierHz <= 0) {
      _showInfoBar(
        title: '相位噪声配置无效',
        content: '载波必须为正值，起始频偏不得低于 1 kHz，终止频偏不得小于起始频偏。',
        severity: InfoBarSeverity.warning,
      );
      return;
    }

    if (!_serialManager.isConnected) {
      _showInfoBar(
        title: '串口未连接',
        content: '开始相位噪声测量前，请先连接 PuSu 设备。',
        severity: InfoBarSeverity.warning,
      );
      setState(() {
        _phaseNoiseUsingDemo = false;
        _phaseNoiseRunning = false;
        _phaseNoiseComplete = false;
        _phaseNoiseStateText = '串口未连接';
      });
      return;
    }

    setState(() {
      _phaseNoiseCommandInFlight = true;
      _resetPhaseNoiseAcquisitionState(
        config: config,
        demo: false,
        stateText: '正在停止频谱扫描',
        clearTrace: false,
      );
    });

    final sweepStopped = await _stopContinuousSweep();
    if (!mounted) return;
    if (!sweepStopped) {
      setState(() {
        _phaseNoiseCommandInFlight = false;
        _phaseNoiseRunning = false;
        _phaseNoiseStateText = '频谱扫描停止失败';
      });
      _showInfoBar(
        title: '频谱扫描停止失败',
        content: '设备未确认 DMA 已释放；相位噪声测量未启动。',
        severity: InfoBarSeverity.warning,
      );
      return;
    }

    setState(() {
      _phaseNoiseStateText = continuous ? '正在启动连续测量' : '正在启动单次测量';
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
        _phaseNoiseStateText = '搜索载波';
      });
      return;
    }

    _protocol.getPhaseNoiseStatus();
    _showInfoBar(
      title: configOk ? '相位噪声启动失败' : '相位噪声配置被拒绝',
      content: '已请求读取设备状态；未启动本地演示。',
      severity: InfoBarSeverity.warning,
    );
    setState(() {
      _phaseNoiseRunning = false;
      _phaseNoiseComplete = false;
      _phaseNoiseUsingDemo = false;
      _phaseNoiseStateText = configOk ? '启动失败，正在读取状态' : '配置被拒绝，正在读取状态';
    });
  }

  Future<void> _stopPhaseNoiseMeasurement() async {
    await _stopPhaseNoiseSafely();
  }

  Future<bool> _stopPhaseNoiseSafely() async {
    if (_phaseNoiseCommandInFlight) return false;

    final phaseNoiseWasRunning = _phaseNoiseRunning;
    final demoWasRunning = _phaseNoiseUsingDemo && phaseNoiseWasRunning;
    _stopPhaseNoiseDemoContinuous();

    // Older builds routed the global phase-noise toolbar to the spectrum
    // sweep handlers. Recover that mismatched state before changing modes.
    if (_spectrumRequestInFlight || _isContinuousSweepRunning) {
      final sweepStopped = await _stopContinuousSweep();
      if (!sweepStopped) {
        if (mounted) {
          setState(() {
            _phaseNoiseStateText = '频谱扫描未确认停止';
          });
        }
        return false;
      }
    }

    // Switching away from an idle phase-noise page does not require a device
    // STOP ACK. Only a workload that was actually started must be confirmed.
    if (!phaseNoiseWasRunning) {
      if (mounted) {
        setState(() {
          _phaseNoiseCommandInFlight = false;
          if (!_phaseNoiseComplete) {
            _phaseNoiseStateText = '空闲';
          }
        });
      }
      return true;
    }

    if (demoWasRunning || !_serialManager.isConnected) {
      if (mounted) {
        setState(() {
          _phaseNoiseRunning = false;
          _phaseNoiseCommandInFlight = false;
          _phaseNoiseStateText = demoWasRunning ? '演示已停止' : '已停止';
        });
      }
      return true;
    }

    if (mounted) {
      setState(() {
        _phaseNoiseCommandInFlight = true;
        _phaseNoiseStateText = '停止中';
      });
    }
    final stopped = await _protocol.stopPhaseNoiseConfirmed();
    if (mounted) {
      _protocol.getPhaseNoiseStatus();
      setState(() {
        _phaseNoiseCommandInFlight = false;
        if (stopped) {
          _phaseNoiseRunning = false;
          if (!_phaseNoiseComplete) {
            _phaseNoiseStateText = '已停止';
          }
        } else {
          // Keep the running flag set so another mode switch cannot bypass
          // the required STOP acknowledgement after a timeout.
          _phaseNoiseRunning = true;
          _phaseNoiseStateText = '设备未确认停止';
        }
      });
    }
    return stopped;
  }

  Future<void> _exportPhaseNoiseCsv() async {
    if (_phaseNoiseTrace.rawPoints.isEmpty &&
        _phaseNoiseTrace.averagePoints.isEmpty) {
      _showInfoBar(
        title: '未导出相位噪声 CSV',
        content: '当前没有可导出的相位噪声曲线数据。',
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
        title: '相位噪声 CSV 已导出',
        content: file.path,
        severity: InfoBarSeverity.success,
      );
    } catch (error) {
      _showInfoBar(
        title: '相位噪声 CSV 导出失败',
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
        ResizablePanelDivider(
          onDragDelta: _resizeSettingsPanel,
          tooltip: '拖动调整仪器工具栏宽度',
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
        : (_phaseNoiseNominalCarrierHz ?? _defaultPhaseNoiseCarrierHz);
    final measured =
        carrier?.measuredHz ?? _phaseNoiseMeasuredCarrierHz ?? nominal;
    final carrierLevel = carrier?.levelDbm ?? _phaseNoiseCarrierLevelDbm;
    final levelText = carrierLevel == null
        ? '-- dBm'
        : '${carrierLevel.toStringAsFixed(2)} dBm';
    final warningText =
        _phaseNoiseTrace.warnings.map((warning) => warning.message).join(' | ');
    final warningLabel = _phaseNoiseWarningCode == 0
        ? '无'
        : _phaseNoiseWarningLabel(_phaseNoiseWarningCode);
    final elapsedText = _formatPhaseNoiseElapsed(_phaseNoiseElapsedMs);
    final totalPoints = _phaseNoisePlannedTotalPoints > 0
        ? _phaseNoisePlannedTotalPoints
        : config.estimatedPointCount;
    final sweepCurrent =
        _phaseNoiseAverageIndex > 0 ? _phaseNoiseAverageIndex : 0;
    final runningText = _phaseNoiseRunning ? '运行中' : '空闲';
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
    final pointRbwLabel = markerRbwHz == null ? '当前点 RBW' : 'Marker RBW';

    return Container(
      margin: const EdgeInsets.all(8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      color: const Color(0xFF2A2A2A),
      child: Wrap(
        spacing: 24,
        runSpacing: 8,
        children: [
          Text(
              '标称频率: ${nominal == null ? '--' : _formatFreqAutoUnit(nominal)}'),
          Text(
              '实测频率: ${measured == null ? '--' : _formatFreqAutoUnit(measured)}'),
          Text('实测电平: $levelText'),
          Text(
            '测量范围: ${_formatFreqAutoUnit(config.startOffsetHz)} - ${_formatFreqAutoUnit(config.stopOffsetHz)}',
          ),
          Text(
            '平均窗口: ${_phaseNoiseTrace.completedAverages}/${config.averageTarget}',
          ),
          Text('状态: $_phaseNoiseStateText ($runningText)'),
          Text('点数: $_phaseNoiseReceivedPoints/$totalPoints'),
          Text('索引: $indexText'),
          Text('扫描轮次: $sweepCurrent'),
          Text('已用时间: $elapsedText'),
          Text('警告: $warningLabel'),
          Text('曲线编号: ${_phaseNoiseTraceId == 0 ? '--' : _phaseNoiseTraceId}'),
          Text(
            '当前频偏: ${_phaseNoiseCurrentOffsetHz <= 0 ? '--' : _formatFreqAutoUnit(_phaseNoiseCurrentOffsetHz.toDouble())}',
          ),
          Text(
            '$pointRbwLabel: $markerRbwText',
          ),
          Text(
            'RBW: ${_formatFreqAutoUnit(config.rbwHz)}',
          ),
          Text(
            '点密度: ${config.pointsPerDecade} pts/dec',
          ),
          Text(
            'Marker: $markerText',
          ),
          Text(
            '初始偏差: ${carrier == null ? '-- Hz' : _formatSignedFreqAutoUnit(carrier.initialDeltaHz)}',
          ),
          Text(
            '频率漂移: ${carrier == null ? '-- Hz' : _formatFreqAutoUnit(carrier.driftHz.abs())}',
          ),
          Text(
            warningText.isEmpty
                ? (_phaseNoiseErrorCode == 0
                    ? 'ENBW: 根据当前 RBW 滤波器计算'
                    : '错误: ${_phaseNoiseErrorLabel(_phaseNoiseErrorCode)}')
                : '警告: $warningText',
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
      width: _settingsPanelWidth,
      color: const Color.fromARGB(255, 66, 66, 66),
      padding: const EdgeInsets.all(8),
      child: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expander(
              initiallyExpanded: true,
              header: const Text('载波'),
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
                          child: const Text('自动'),
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
                          child: const Text('手动'),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  _buildInputRow(
                    label: '载波',
                    controller: _phaseNoiseCarrierController,
                    unitNotifier: _phaseNoiseCarrierUnit,
                    units: freqUnits,
                    enabled:
                        _phaseNoiseCarrierMode == PhaseNoiseCarrierMode.manual,
                  ),
                  const SizedBox(height: 8),
                  _buildInputRow(
                    label: '搜索范围',
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
                          '触发/最低电平',
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
              initiallyExpanded: true,
              header: const Text('射频前端'),
              content: _buildRfFrontendPanel(
                showPath: false,
                attenuationLabelTogglesPhaseNoiseDisplay: false,
              ),
            ),
            Expander(
              header: const Text('频偏'),
              content: Column(
                children: [
                  _buildInputRow(
                    label: '起始',
                    controller: _phaseNoiseStartOffsetController,
                    unitNotifier: _phaseNoiseStartOffsetUnit,
                    units: freqUnits,
                    onChanged: _enforcePhaseNoiseStartOffsetMinimum,
                  ),
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: EdgeInsets.only(left: 100, top: 4),
                      child: Text(
                        '最小 1 kHz',
                        style: TextStyle(
                          color: material.Colors.white70,
                          fontSize: 11,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 8),
                  _buildInputRow(
                    label: '终止',
                    controller: _phaseNoiseStopOffsetController,
                    unitNotifier: _phaseNoiseStopOffsetUnit,
                    units: freqUnits,
                  ),
                  const SizedBox(height: 12),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      '点密度',
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
                    '点数: ${config.estimatedPointCount}  '
                    '点密度: ${config.pointsPerDecade} pts/dec',
                    style: const TextStyle(color: material.Colors.white70),
                  ),
                ],
              ),
            ),
            Expander(
              header: const Text('平均'),
              content: Column(
                children: [
                  Row(
                    children: [
                      const SizedBox(
                        width: 100,
                        child: Text(
                          '次数',
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
                    '窗口已填充: $_phaseNoiseCompletedAverages/${config.averageTarget}',
                    style: const TextStyle(color: material.Colors.white70),
                  ),
                ],
              ),
            ),
            Expander(
              header: const Text('曲线'),
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
                        child: Text('Raw + Avg'),
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
                    '点密度: ${config.pointsPerDecade} pts/dec',
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
                      _phaseNoiseCommandInFlight ? '忙碌' : '单次',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Button(
                    onPressed: _phaseNoiseCommandInFlight
                        ? null
                        : _startContinuousPhaseNoiseMeasurement,
                    child: const Text('连续'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Button(
                    onPressed: _phaseNoiseCommandInFlight
                        ? null
                        : _stopPhaseNoiseMeasurement,
                    child: const Text('停止'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Button(
              onPressed: _exportPhaseNoiseCsv,
              child: const Text('导出 CSV'),
            ),
          ],
        ),
      ),
    );
  }

  InstrumentAgentSnapshot _buildInstrumentAgentSnapshot() {
    final mode = switch (_measurementMode) {
      MeasurementMode.spectrum =>
        _isDirectIfFftMode ? 'spectrum_direct_if' : 'spectrum',
      MeasurementMode.phaseNoise => 'phase_noise',
      MeasurementMode.realtimeSpectrum => 'realtime_spectrum',
    };
    final realtimeState = _realtimeSpectrumPageKey.currentState;
    final sweepRunning = switch (_measurementMode) {
      MeasurementMode.spectrum =>
        _spectrumRequestInFlight || _isContinuousSweepRunning,
      MeasurementMode.phaseNoise => _phaseNoiseRunning,
      MeasurementMode.realtimeSpectrum => realtimeState?.isRunning ?? false,
    };
    final modeDetails = switch (_measurementMode) {
      MeasurementMode.spectrum => <String, dynamic>{
          'definition': '传统可配置起止频率、RBW/VBW 和检波方式的扫频频谱',
          'amplitude_unit': 'dBm',
          'supports_single_sweep': true,
          'supports_continuous_sweep': true,
          'rf_frontend': <String, dynamic>{
            'path_mode': _rfPathModeAgentName(_rfFrontendConfig.pathMode),
            'lna_mode': _rfLnaModeAgentName(_rfFrontendConfig.lnaMode),
            'attenuation_db': _rfFrontendConfig.attenDb,
            'vga_db': double.tryParse(vgaGainValue.value.split(' ').first) ?? 0,
          },
          'sweep_speed_hz': sweepSpeed.value,
          'scale_db_per_div':
              double.tryParse(scalePerGridController.text) ?? 10,
          'profile_status': _profileStatusText,
        },
      MeasurementMode.phaseNoise => <String, dynamic>{
          'definition': '围绕载波按频偏显示相位噪声密度，不是普通频谱',
          ..._phaseNoiseAgentState(),
        },
      MeasurementMode.realtimeSpectrum => <String, dynamic>{
          'definition': '固定 10 MHz Span 的实时 IF FFT，包含最新/平均/最大保持/瀑布图',
          ...(realtimeState?.agentConfiguration ??
              <String, dynamic>{
                'amplitude_unit': 'dBFS',
                'span_hz': 10e6,
                'fft_size': 4096,
                'state': '页面初始化中',
              }),
        },
    };
    return InstrumentAgentSnapshot(
      connected: _serialManager.isConnected,
      deviceResponsive: _deviceResponsive,
      measurementMode: mode,
      startHz: _confirmedStartHz,
      stopHz: _confirmedStopHz,
      rbwHz: _getSelectedRbwHz(),
      vbwMode: vbwMode.value,
      vbwHz: _parseFreq(vbwController.text, vbwUnit.value) ?? 0,
      detector: detectMode.value,
      referenceDbm: double.tryParse(refLevelController.text) ?? 0,
      pointCount: _getCurrentPointCount(),
      sweepRunning: sweepRunning,
      continuousSweep: _measurementMode == MeasurementMode.spectrum &&
          _isContinuousSweepRunning,
      minimumFrequencyHz: _fullSpanStartHz,
      maximumFrequencyHz: _fullSpanStopHz,
      modeDetails: modeDetails,
    );
  }

  Map<String, dynamic> _phaseNoiseAgentState() {
    final config = _buildCurrentPhaseNoiseConfig();
    return <String, dynamic>{
      'measurement_mode': 'phase_noise',
      'amplitude_unit': 'dBc/Hz',
      'carrier_mode': _phaseNoiseCarrierMode.name,
      'carrier_hz': config.protocolNominalCarrierHz,
      'carrier_search_span_hz': config.carrierSearchSpanHz,
      'minimum_carrier_level_dbm': config.minimumCarrierLevelDbm,
      'start_offset_hz': config.startOffsetHz,
      'stop_offset_hz': config.stopOffsetHz,
      'density': _phaseNoiseDensityPreset.name,
      'points_per_decade': config.pointsPerDecade,
      'estimated_point_count': config.estimatedPointCount,
      'average_count': config.averageTarget,
      'completed_averages': _phaseNoiseCompletedAverages,
      'trace_display': _phaseNoiseTraceDisplay.name,
      'raw_point_count': _phaseNoiseTrace.rawPoints.length,
      'average_point_count': _phaseNoiseTrace.averagePoints.length,
      'running': _phaseNoiseRunning,
      'complete': _phaseNoiseComplete,
      'state': _phaseNoiseStateText,
      'error_code': _phaseNoiseErrorCode,
      'warning_code': _phaseNoiseWarningCode,
      'carrier_detected': _phaseNoiseErrorCode == 2
          ? false
          : (_phaseNoiseMeasuredCarrierHz != null ? true : null),
      'measured_carrier_hz': _phaseNoiseMeasuredCarrierHz,
      'carrier_level_dbm': _phaseNoiseCarrierLevelDbm,
      'current_offset_hz': _phaseNoiseCurrentOffsetHz,
      'received_points': _phaseNoiseReceivedPoints,
      'planned_total_points': _phaseNoisePlannedTotalPoints,
      if (_phaseNoiseErrorCode == 2) 'terminal_reason': 'no_signal_input',
    };
  }

  Future<InstrumentActionOutcome> _agentSetMeasurementMode(String mode) async {
    final target = switch (mode) {
      'spectrum' => MeasurementMode.spectrum,
      'phase_noise' => MeasurementMode.phaseNoise,
      'realtime_spectrum' => MeasurementMode.realtimeSpectrum,
      _ => null,
    };
    if (target == null) {
      return const InstrumentActionOutcome(
        success: false,
        message: '不支持的测量模式',
      );
    }
    if (target == _measurementMode) {
      final effectiveMode = _buildInstrumentAgentSnapshot().measurementMode;
      return InstrumentActionOutcome(
        success: true,
        message: '当前已经处于 $effectiveMode 模式',
        data: <String, dynamic>{
          'measurement_mode': effectiveMode,
          'requested_mode': mode,
          'changed': false,
        },
      );
    }

    var stopped = true;
    if (_serialManager.isConnected) {
      if (!_deviceResponsive) {
        return const InstrumentActionOutcome(
          success: false,
          message: '仪器当前无响应，未切换测量模式',
        );
      }
      stopped = await _stopActiveMeasurementForModeSwitch();
    }
    if (!stopped) {
      return const InstrumentActionOutcome(
        success: false,
        message: '当前测量未收到停止 ACK，出于安全考虑未切换模式',
      );
    }
    if (!mounted) {
      return const InstrumentActionOutcome(
        success: false,
        message: '页面已经关闭，无法切换测量模式',
      );
    }
    _updateMeasurementModeUi(target);
    await WidgetsBinding.instance.endOfFrame;
    return InstrumentActionOutcome(
      success: true,
      message: '顶部工具栏测量模式已切换为 $mode',
      data: <String, dynamic>{
        'measurement_mode': mode,
        'changed': true,
        'previous_measurement_stopped': stopped,
        'device_ack': _serialManager.isConnected ? stopped : null,
      },
    );
  }

  Future<InstrumentActionOutcome> _agentStartPhaseNoiseMeasurement(
    bool continuous,
    bool waitForCarrier,
  ) async {
    await _startPhaseNoiseMeasurement(continuous: continuous);
    var carrierWaitTimedOut = false;
    if (waitForCarrier &&
        _phaseNoiseRunning &&
        _phaseNoiseErrorCode == 0 &&
        _phaseNoiseMeasuredCarrierHz == null) {
      _protocol.getPhaseNoiseStatus();
      final deadline = DateTime.now().add(const Duration(seconds: 8));
      while (mounted &&
          _phaseNoiseRunning &&
          _phaseNoiseErrorCode == 0 &&
          _phaseNoiseMeasuredCarrierHz == null &&
          DateTime.now().isBefore(deadline)) {
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
      carrierWaitTimedOut = _phaseNoiseRunning &&
          _phaseNoiseErrorCode == 0 &&
          _phaseNoiseMeasuredCarrierHz == null;
    }
    final noSignalInput = _phaseNoiseErrorCode == 2;
    return InstrumentActionOutcome(
      success: _phaseNoiseRunning && !noSignalInput && !carrierWaitTimedOut,
      message: noSignalInput
          ? '未检测到信号输入'
          : (carrierWaitTimedOut
              ? '载波检测尚未完成，暂时无法分析'
              : (_phaseNoiseRunning
                  ? '相位噪声${continuous ? '连续' : '单次'}测量已启动'
                  : '相位噪声测量启动失败：$_phaseNoiseStateText')),
      data: <String, dynamic>{
        'measurement_mode': 'phase_noise',
        'continuous': continuous,
        'running': _phaseNoiseRunning,
        'state': _phaseNoiseStateText,
        'amplitude_unit': 'dBc/Hz',
        'error_code': _phaseNoiseErrorCode,
        'carrier_detected': noSignalInput
            ? false
            : (_phaseNoiseMeasuredCarrierHz != null ? true : null),
        'background_measurement': _phaseNoiseRunning,
        'measurement_complete': _phaseNoiseComplete,
        if (noSignalInput) 'terminal_reason': 'no_signal_input',
        if (carrierWaitTimedOut) 'terminal_reason': 'carrier_detection_timeout',
        if (_phaseNoiseRunning) 'retry_on_next_user_request': true,
        if (_phaseNoiseRunning || waitForCarrier) 'polling_allowed': false,
      },
    );
  }

  Future<InstrumentActionOutcome> _agentGetPhaseNoiseState() async {
    return InstrumentActionOutcome(
      success: true,
      message: '已读取相位噪声配置和测量状态',
      data: _phaseNoiseAgentState(),
    );
  }

  Future<InstrumentActionOutcome> _agentConfigurePhaseNoise(
    Map<String, dynamic> arguments,
  ) async {
    var stoppedRunningMeasurement = false;
    if (_phaseNoiseCommandInFlight) {
      return const InstrumentActionOutcome(
        success: false,
        message: '相位噪声命令正在执行，请稍后重试',
      );
    }
    if (_phaseNoiseRunning) {
      final stopped = await _protocol.stopPhaseNoiseConfirmed();
      if (!stopped) {
        return const InstrumentActionOutcome(
          success: false,
          message: '当前相位噪声测量未收到停止 ACK，未修改配置',
        );
      }
      stoppedRunningMeasurement = true;
    }
    if (!mounted) {
      return const InstrumentActionOutcome(
        success: false,
        message: '页面已经关闭，无法配置相位噪声',
      );
    }

    double? number(String key) => (arguments[key] as num?)?.toDouble();
    final current = _buildCurrentPhaseNoiseConfig();
    final targetStart = number('start_offset_hz') ?? current.startOffsetHz;
    final targetStop = number('stop_offset_hz') ?? current.stopOffsetHz;
    if (targetStart < PhaseNoiseConfig.minimumOffsetHz) {
      return const InstrumentActionOutcome(
        success: false,
        message: '相位噪声起始频偏不得低于 1 kHz，未修改配置',
      );
    }
    if (targetStop < targetStart) {
      return const InstrumentActionOutcome(
        success: false,
        message: '终止频偏不能小于起始频偏，未修改配置',
      );
    }

    final carrierHz = number('carrier_hz');
    final carrierMode = carrierHz != null
        ? PhaseNoiseCarrierMode.manual
        : switch (arguments['carrier_mode']?.toString()) {
            'manual' => PhaseNoiseCarrierMode.manual,
            'auto' => PhaseNoiseCarrierMode.auto,
            _ => _phaseNoiseCarrierMode,
          };
    final density = switch (arguments['density']?.toString()) {
      'fast' => PhaseNoiseDensityPreset.fast,
      'normal' => PhaseNoiseDensityPreset.normal,
      'fine' => PhaseNoiseDensityPreset.fine,
      _ => _phaseNoiseDensityPreset,
    };
    final traceDisplay = switch (arguments['trace_display']?.toString()) {
      'raw' => PhaseNoiseTraceDisplay.raw,
      'average' => PhaseNoiseTraceDisplay.average,
      'both' => PhaseNoiseTraceDisplay.both,
      _ => _phaseNoiseTraceDisplay,
    };

    setState(() {
      _clearPhaseNoiseShellData();
      _phaseNoiseCarrierMode = carrierMode;
      if (carrierHz != null) {
        _setFreqField(
          _phaseNoiseCarrierController,
          _phaseNoiseCarrierUnit,
          carrierHz,
        );
      }
      final searchSpan = number('carrier_search_span_hz');
      if (searchSpan != null) {
        _setFreqField(
          _phaseNoiseCarrierSearchSpanController,
          _phaseNoiseCarrierSearchSpanUnit,
          searchSpan,
        );
      }
      final minimumLevel = number('minimum_carrier_level_dbm');
      if (minimumLevel != null) {
        _phaseNoiseMinimumCarrierLevelController.text = minimumLevel.toString();
      }
      _setFreqField(
        _phaseNoiseStartOffsetController,
        _phaseNoiseStartOffsetUnit,
        targetStart,
      );
      _setFreqField(
        _phaseNoiseStopOffsetController,
        _phaseNoiseStopOffsetUnit,
        targetStop,
      );
      final averageCount = arguments['average_count'];
      if (averageCount is int) {
        _phaseNoiseAverageCountController.text = averageCount.toString();
      }
      _phaseNoiseDensityPreset = density;
      _phaseNoiseTraceDisplay = traceDisplay;
      _phaseNoiseStateText = '配置已更新，等待启动';
    });

    return InstrumentActionOutcome(
      success: true,
      message: '相位噪声页面配置已更新',
      data: <String, dynamic>{
        ..._phaseNoiseAgentState(),
        'stopped_previous_measurement': stoppedRunningMeasurement,
        'device_ack': stoppedRunningMeasurement ? true : null,
        'configuration_staged': true,
      },
    );
  }

  Future<InstrumentActionOutcome> _agentAnalyzePhaseNoise(
    String trace,
    double offsetHz,
    int waitTimeoutMs,
  ) async {
    final config = _buildCurrentPhaseNoiseConfig();
    if (offsetHz < config.startOffsetHz || offsetHz > config.stopOffsetHz) {
      return InstrumentActionOutcome(
        success: false,
        message: '请求频偏不在当前测量范围内',
        data: <String, dynamic>{
          ..._phaseNoiseAgentState(),
          'requested_offset_hz': offsetHz,
          'terminal_reason': 'offset_out_of_configured_range',
          'polling_allowed': false,
        },
      );
    }

    ({String name, PhaseNoisePoint point})? result() {
      final candidates = switch (trace) {
        'raw' => <({String name, List<PhaseNoisePoint> points})>[
            (name: 'raw', points: _phaseNoiseTrace.rawPoints),
          ],
        'average' => <({String name, List<PhaseNoisePoint> points})>[
            (name: 'average', points: _phaseNoiseTrace.averagePoints),
          ],
        _ => <({String name, List<PhaseNoisePoint> points})>[
            (name: 'average', points: _phaseNoiseTrace.averagePoints),
            (name: 'raw', points: _phaseNoiseTrace.rawPoints),
          ],
      };
      for (final candidate in candidates) {
        final valid = candidate.points
            .where((point) => point.valid && point.dbcHz.isFinite)
            .toList(growable: false);
        if (valid.isEmpty) continue;
        final nearest = valid.reduce(
          (best, point) => (point.offsetHz - offsetHz).abs() <
                  (best.offsetHz - offsetHz).abs()
              ? point
              : best,
        );
        final relativeError = (nearest.offsetHz - offsetHz).abs() / offsetHz;
        if (relativeError <= 0.15) {
          return (name: candidate.name, point: nearest);
        }
      }
      return null;
    }

    var selected = result();
    final deadline = DateTime.now().add(Duration(milliseconds: waitTimeoutMs));
    while (selected == null &&
        _phaseNoiseErrorCode == 0 &&
        waitTimeoutMs > 0 &&
        DateTime.now().isBefore(deadline)) {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      selected = result();
    }

    if (_phaseNoiseErrorCode == 2) {
      return InstrumentActionOutcome(
        success: false,
        message: '未检测到信号输入',
        data: <String, dynamic>{
          ..._phaseNoiseAgentState(),
          'requested_offset_hz': offsetHz,
          'terminal_reason': 'no_signal_input',
          'polling_allowed': false,
        },
      );
    }
    if (_phaseNoiseErrorCode != 0) {
      return InstrumentActionOutcome(
        success: false,
        message: '相位噪声测量失败：$_phaseNoiseStateText',
        data: <String, dynamic>{
          ..._phaseNoiseAgentState(),
          'requested_offset_hz': offsetHz,
          'terminal_reason': 'phase_noise_measurement_error',
          'polling_allowed': false,
        },
      );
    }
    if (selected == null) {
      final measurementPending = _phaseNoiseRunning && !_phaseNoiseComplete;
      return InstrumentActionOutcome(
        success: false,
        message:
            measurementPending ? '相位噪声测量仍在后台进行，指定频偏暂时没有数据' : '指定频偏暂时没有测量数据',
        data: <String, dynamic>{
          ..._phaseNoiseAgentState(),
          'requested_offset_hz': offsetHz,
          'terminal_reason': 'phase_noise_data_not_ready',
          'measurement_pending': measurementPending,
          'retry_on_next_user_request': measurementPending,
          'polling_allowed': false,
        },
      );
    }

    final point = selected.point;
    return InstrumentActionOutcome(
      success: true,
      message: '${_formatFreqAutoUnit(offsetHz)} 频偏处相位噪声为 '
          '${point.dbcHz.toStringAsFixed(2)} dBc/Hz',
      data: <String, dynamic>{
        ..._phaseNoiseAgentState(),
        'trace': selected.name,
        'requested_offset_hz': offsetHz,
        'measured_offset_hz': point.offsetHz,
        'phase_noise_dbc_per_hz': point.dbcHz,
        'noise_power_dbm': point.noisePowerDbm,
        'rbw_hz': point.rbwHz,
      },
    );
  }

  ({String name, List<PhaseNoisePoint> points})? _phaseNoiseTraceForAgent(
      String trace) {
    final candidates = switch (trace) {
      'raw' => <({String name, List<PhaseNoisePoint> points})>[
          (name: 'raw', points: _phaseNoiseTrace.rawPoints),
        ],
      'average' => <({String name, List<PhaseNoisePoint> points})>[
          (name: 'average', points: _phaseNoiseTrace.averagePoints),
        ],
      _ => <({String name, List<PhaseNoisePoint> points})>[
          (name: 'average', points: _phaseNoiseTrace.averagePoints),
          (name: 'raw', points: _phaseNoiseTrace.rawPoints),
        ],
    };
    for (final candidate in candidates) {
      final points = candidate.points
          .where(
            (point) =>
                point.valid &&
                point.offsetHz > 0 &&
                point.offsetHz.isFinite &&
                point.dbcHz.isFinite,
          )
          .toList()
        ..sort((a, b) => a.offsetHz.compareTo(b.offsetHz));
      if (points.isNotEmpty) return (name: candidate.name, points: points);
    }
    return null;
  }

  List<PhaseNoisePoint> _downsamplePhaseNoiseForAgent(
    List<PhaseNoisePoint> points,
    int maximumPoints,
  ) {
    if (points.length <= maximumPoints) return List.of(points);
    final sampled = <PhaseNoisePoint>[];
    final bucketSize = points.length / maximumPoints;
    for (var bucket = 0; bucket < maximumPoints; bucket++) {
      final start = (bucket * bucketSize).floor();
      final stop = math.min(
        points.length,
        ((bucket + 1) * bucketSize).ceil(),
      );
      if (start >= stop) continue;
      var worst = points[start];
      for (var index = start + 1; index < stop; index++) {
        if (points[index].dbcHz > worst.dbcHz) worst = points[index];
      }
      sampled.add(worst);
    }
    sampled.sort((a, b) => a.offsetHz.compareTo(b.offsetHz));
    return sampled;
  }

  Map<String, dynamic> _phaseNoisePointForAgent(PhaseNoisePoint point) =>
      <String, dynamic>{
        'offset_hz': point.offsetHz,
        'phase_noise_dbc_per_hz': point.dbcHz,
        'noise_power_dbm':
            point.noisePowerDbm.isFinite ? point.noisePowerDbm : null,
        'rbw_hz': point.rbwHz.isFinite ? point.rbwHz : null,
      };

  Map<String, dynamic> _phaseNoiseTraceSummary(
    String trace,
    List<PhaseNoisePoint> points,
  ) {
    final minimum = points.reduce(
      (best, point) => point.dbcHz < best.dbcHz ? point : best,
    );
    final maximum = points.reduce(
      (best, point) => point.dbcHz > best.dbcHz ? point : best,
    );
    return <String, dynamic>{
      'measurement_mode': 'phase_noise',
      'amplitude_unit': 'dBc/Hz',
      'trace': trace,
      'point_count': points.length,
      'start_offset_hz': points.first.offsetHz,
      'stop_offset_hz': points.last.offsetHz,
      'minimum_dbc_per_hz': minimum.dbcHz,
      'minimum_offset_hz': minimum.offsetHz,
      'maximum_dbc_per_hz': maximum.dbcHz,
      'maximum_offset_hz': maximum.offsetHz,
      'complete': _phaseNoiseComplete,
      'completed_averages': _phaseNoiseCompletedAverages,
      'carrier_hz': _phaseNoiseMeasuredCarrierHz,
      'carrier_level_dbm': _phaseNoiseCarrierLevelDbm,
    };
  }

  Future<InstrumentActionOutcome> _agentGetPhaseNoiseSnapshot(
    String trace,
    int maximumPoints,
  ) async {
    final selected = _phaseNoiseTraceForAgent(trace);
    if (selected == null) {
      return InstrumentActionOutcome(
        success: false,
        message: _phaseNoiseRunning ? '相位噪声测量仍在进行，当前曲线尚无有效数据' : '当前没有相位噪声曲线数据',
        data: <String, dynamic>{
          ..._phaseNoiseAgentState(),
          'requested_trace': trace,
          'measurement_pending': _phaseNoiseRunning && !_phaseNoiseComplete,
        },
      );
    }
    final sampled =
        _downsamplePhaseNoiseForAgent(selected.points, maximumPoints);
    return InstrumentActionOutcome(
      success: true,
      message: '已读取相位噪声 ${selected.name} 曲线，共 ${selected.points.length} 点',
      data: <String, dynamic>{
        ..._phaseNoiseTraceSummary(selected.name, selected.points),
        'returned_point_count': sampled.length,
        'downsampled': sampled.length < selected.points.length,
        'points': sampled.map(_phaseNoisePointForAgent).toList(),
      },
    );
  }

  Future<InstrumentActionOutcome> _agentStopPhaseNoiseMeasurement() async {
    final acknowledged = await _protocol.stopPhaseNoiseConfirmed();
    if (mounted) {
      setState(() {
        _phaseNoiseRunning = false;
        _phaseNoiseCommandInFlight = false;
        _phaseNoiseStateText = acknowledged ? '已停止' : '设备未确认停止';
      });
    }
    return InstrumentActionOutcome(
      success: acknowledged,
      message: acknowledged ? '设备已确认停止相位噪声测量' : '相位噪声停止命令未收到 ACK',
      data: <String, dynamic>{
        'measurement_mode': 'phase_noise',
        'device_ack': acknowledged,
      },
    );
  }

  Future<InstrumentActionOutcome> _agentStartRealtimeSpectrum(
    double centerHz,
  ) async {
    final page = _realtimeSpectrumPageKey.currentState;
    if (page == null) {
      return const InstrumentActionOutcome(
        success: false,
        message: '实时频谱页面尚未初始化，请先切换到 realtime_spectrum 模式',
      );
    }
    final started = await page.startFromAgent(centerHz);
    return InstrumentActionOutcome(
      success: started,
      message: started ? '实时频谱已启动' : '实时频谱启动失败：${page.agentStatus}',
      data: <String, dynamic>{
        'measurement_mode': 'realtime_spectrum',
        'center_hz': centerHz,
        'span_hz': 10e6,
        'fft_size': 4096,
        'amplitude_unit': 'dBFS',
        'running': page.isRunning,
        'state': page.agentStatus,
      },
    );
  }

  Future<InstrumentActionOutcome> _agentStopRealtimeSpectrum() async {
    final page = _realtimeSpectrumPageKey.currentState;
    final stopped = await (page?.stopFromAgent() ??
        _protocol.stopRealtimeSpectrumConfirmed());
    return InstrumentActionOutcome(
      success: stopped,
      message: stopped ? '设备已确认停止实时频谱' : '实时频谱停止失败或未进入空闲状态',
      data: <String, dynamic>{
        'measurement_mode': 'realtime_spectrum',
        'device_ack': stopped,
        'state': page?.agentStatus,
      },
    );
  }

  InstrumentActionOutcome _realtimePageUnavailableOutcome() =>
      const InstrumentActionOutcome(
        success: false,
        message: '实时频谱页面尚未初始化，请先切换到 realtime_spectrum 模式',
      );

  Future<InstrumentActionOutcome> _agentGetRealtimeSpectrumState() async {
    final page = _realtimeSpectrumPageKey.currentState;
    if (page == null) return _realtimePageUnavailableOutcome();
    return InstrumentActionOutcome(
      success: true,
      message: '已读取实时频谱页面状态（幅度单位 dBFS）',
      data: page.agentConfiguration,
    );
  }

  Future<InstrumentActionOutcome> _agentConfigureRealtimeSpectrum(
    Map<String, dynamic> arguments,
  ) async {
    final page = _realtimeSpectrumPageKey.currentState;
    if (page == null) return _realtimePageUnavailableOutcome();
    double? number(String key) => (arguments[key] as num?)?.toDouble();
    final configuration = await page.configureFromAgent(
      centerHz: number('center_hz'),
      averageEnabled: arguments['average_enabled'] as bool?,
      maxHoldEnabled: arguments['max_hold_enabled'] as bool?,
      markerEnabled: arguments['marker_enabled'] as bool?,
      lnaEnabled: arguments['lna_enabled'] as bool?,
      attenuationDb: number('attenuation_db'),
      vgaDb: number('vga_db'),
      referenceDbfs: number('reference_dbfs'),
      waterfallFloorDbfs: number('waterfall_floor_dbfs'),
      waterfallReferenceDbfs: number('waterfall_reference_dbfs'),
      resetAverage: arguments['reset_average'] == true,
      resetMaxHold: arguments['reset_max_hold'] == true,
    );
    return InstrumentActionOutcome(
      success: true,
      message: '实时频谱页面配置已更新',
      data: configuration,
    );
  }

  Future<InstrumentActionOutcome> _agentGetRealtimeSpectrumSnapshot(
    String trace,
    int maximumPoints,
  ) async {
    final page = _realtimeSpectrumPageKey.currentState;
    if (page == null) return _realtimePageUnavailableOutcome();
    return InstrumentActionOutcome(
      success: true,
      message: '已读取实时频谱 $trace 曲线（幅度单位 dBFS）',
      data: page.snapshotForAgent(
        trace: trace,
        maximumPoints: maximumPoints,
      ),
    );
  }

  Future<InstrumentActionOutcome> _agentGetRealtimeWaterfallHistory(
    int maximumRows,
    double? lookbackSeconds,
    int maximumPointsPerRow,
  ) async {
    final page = _realtimeSpectrumPageKey.currentState;
    if (page == null) return _realtimePageUnavailableOutcome();
    return InstrumentActionOutcome(
      success: true,
      message: '已读取实时频谱瀑布历史数据',
      data: page.waterfallHistoryForAgent(
        maximumRows: maximumRows,
        lookbackSeconds: lookbackSeconds,
        maximumPointsPerRow: maximumPointsPerRow,
      ),
    );
  }

  Future<InstrumentActionOutcome> _agentAnalyzeRealtimeSpectrum(
    String trace,
    int peakCount,
    double thresholdAboveNoiseDb,
  ) async {
    final page = _realtimeSpectrumPageKey.currentState;
    if (page == null) return _realtimePageUnavailableOutcome();
    final analysis = page.analyzeForAgent(
      trace: trace,
      peakCount: peakCount,
      thresholdAboveNoiseDb: thresholdAboveNoiseDb,
    );
    return InstrumentActionOutcome(
      success: true,
      message: '已完成实时频谱 $trace 曲线分析（幅度单位 dBFS）',
      data: analysis.toJson(),
    );
  }

  Future<InstrumentActionOutcome> _agentPlaceRealtimePeakMarkers(
    String trace,
    int peakCount,
    double thresholdAboveNoiseDb,
  ) async {
    final page = _realtimeSpectrumPageKey.currentState;
    if (page == null) return _realtimePageUnavailableOutcome();
    final analysis = page.placePeakMarkersFromAgent(
      trace: trace,
      peakCount: peakCount,
      thresholdAboveNoiseDb: thresholdAboveNoiseDb,
    );
    return InstrumentActionOutcome(
      success: true,
      message: '已在实时频谱图上放置 ${analysis.peaks.length} 个峰值 Marker',
      data: analysis.toJson(),
    );
  }

  Future<InstrumentActionOutcome> _agentSetFrequency(
    double centerHz,
    double spanHz,
  ) async {
    if (_isContinuousSweepRunning && !await _stopContinuousSweep()) {
      return const InstrumentActionOutcome(
        success: false,
        message: '停止当前连续扫描失败，未修改频率',
      );
    }
    final startHz = centerHz - spanHz / 2;
    final stopHz = centerHz + spanHz / 2;
    final config = FrequencyConfig(
      startHz: startHz,
      stopHz: stopHz,
      centerHz: centerHz,
      spanHz: spanHz,
    );
    final acknowledged = await _protocol.setFreqConfigConfirmed(config);
    if (!acknowledged) {
      return const InstrumentActionOutcome(
        success: false,
        message: '频率配置未收到设备 ACK，界面参数未修改',
      );
    }
    if (!mounted) {
      return const InstrumentActionOutcome(
        success: false,
        message: '页面已经关闭，无法同步界面状态',
      );
    }
    setState(() {
      _confirmedStartHz = startHz;
      _confirmedStopHz = stopHz;
      _lastFrequencyEditMode = FrequencyEditMode.centerSpan;
      _syncFrequencyFieldsFromConfirmed();
    });
    _clearSpectrumDisplay();
    return InstrumentActionOutcome(
      success: true,
      message: '设备已确认频率配置',
      data: <String, dynamic>{
        'center_hz': centerHz,
        'span_hz': spanHz,
        'start_hz': startHz,
        'stop_hz': stopHz,
        'device_ack': true,
      },
    );
  }

  Future<InstrumentActionOutcome> _agentSetBandwidth(
    double rbwHz,
    String requestedVbwMode,
    double? requestedVbwHz,
  ) async {
    final rbwLabel = _agentRbwLabel(rbwHz);
    final vbwLabel = _agentVbwLabel(requestedVbwMode);
    if (rbwLabel == null || vbwLabel == null) {
      return const InstrumentActionOutcome(
        success: false,
        message: 'RBW 或 VBW 模式不受当前上位机支持',
      );
    }
    final effectiveVbwHz = switch (requestedVbwMode) {
      'manual' => requestedVbwHz!,
      'rbw_x_0_1' => rbwHz * 0.1,
      'rbw_x_0_01' => rbwHz * 0.01,
      'rbw_x_10' => rbwHz * 10,
      _ => rbwHz,
    };
    final config = BandwidthConfig(
      rbwMode: _mapRbwModeStringToInt(rbwLabel),
      rbwHz: rbwHz,
      vbwMode: _mapVbwModeStringToInt(vbwLabel),
      vbwHz: effectiveVbwHz,
    );
    final acknowledged = await _protocol.setBandwidthConfigConfirmed(config);
    if (!acknowledged) {
      return const InstrumentActionOutcome(
        success: false,
        message: '带宽配置未收到设备 ACK，界面参数未修改',
      );
    }
    if (!mounted) {
      return const InstrumentActionOutcome(
        success: false,
        message: '页面已经关闭，无法同步界面状态',
      );
    }
    _suppressBandwidthListener = true;
    try {
      rbwMode.value = rbwLabel;
      vbwMode.value = vbwLabel;
      _updateRbwField();
      _updateVbwField();
      if (requestedVbwMode == 'manual') {
        vbwController.text = effectiveVbwHz.toStringAsFixed(0);
        vbwUnit.value = 'Hz';
      }
    } finally {
      _suppressBandwidthListener = false;
    }
    if (mounted) setState(() {});
    return InstrumentActionOutcome(
      success: true,
      message: '设备已确认带宽配置',
      data: <String, dynamic>{
        'rbw_hz': rbwHz,
        'vbw_mode': requestedVbwMode,
        'vbw_hz': effectiveVbwHz,
        'device_ack': true,
      },
    );
  }

  Future<InstrumentActionOutcome> _agentSetDetector(String detector) async {
    final label = switch (detector) {
      'average' => '平均',
      'sample' => '取样',
      'positive_peak' => '正峰值',
      'negative_peak' => '负峰值',
      'maximum_power' => '最大功率',
      'rms' => '均方根值',
      _ => null,
    };
    if (label == null) {
      return const InstrumentActionOutcome(
        success: false,
        message: '不支持的检波方式',
      );
    }
    final acknowledged = await _protocol.setDetectConfigConfirmed(
      DetectConfig(mode: _mapDetectStringToInt(label)),
    );
    if (!acknowledged) {
      return const InstrumentActionOutcome(
        success: false,
        message: '检波配置未收到设备 ACK，界面参数未修改',
      );
    }
    detectMode.removeListener(_sendDetectConfig);
    try {
      detectMode.value = label;
    } finally {
      detectMode.addListener(_sendDetectConfig);
    }
    if (mounted) setState(() {});
    return InstrumentActionOutcome(
      success: true,
      message: '设备已确认检波配置',
      data: <String, dynamic>{
        'detector': detector,
        'display_label': label,
        'device_ack': true,
      },
    );
  }

  Future<InstrumentActionOutcome> _agentConfigureSpectrumFrontend(
    Map<String, dynamic> arguments,
  ) async {
    final requestedPath = switch (arguments['path_mode']?.toString()) {
      'direct_if' => RfPathMode.directIf,
      'mixer_chain' => RfPathMode.mixerChain,
      'auto' => RfPathMode.auto,
      _ => null,
    };
    final requestedLna = switch (arguments['lna_mode']?.toString()) {
      'bypass' => RfLnaMode.bypass,
      'enable' => RfLnaMode.enable,
      'auto' => RfLnaMode.auto,
      _ => null,
    };
    final attenuationDb = (arguments['attenuation_db'] as num?)?.toDouble();
    final vgaDb = (arguments['vga_db'] as num?)?.toDouble();
    final referenceDbm = (arguments['reference_dbm'] as num?)?.toDouble();
    var requestedFrontend = _rfFrontendConfig.copyWith(
      pathMode: requestedPath,
      lnaMode: requestedLna,
      attenCode: attenuationDb == null
          ? null
          : (attenuationDb / 0.25).round().clamp(0, 127).toInt(),
    );
    requestedFrontend = requestedFrontend.copyWith(
      attenCode: requestedFrontend.attenCode.clamp(0, 127).toInt(),
    );
    final frontendRequested =
        requestedPath != null || requestedLna != null || attenuationDb != null;
    final shouldStop = _spectrumRequestInFlight || _isContinuousSweepRunning;
    final pathChanged =
        requestedPath != null && requestedPath != _rfFrontendConfig.pathMode;
    final requiresAcquisitionBoundary = shouldStop || pathChanged;
    if ((frontendRequested || vgaDb != null || referenceDbm != null) &&
        requiresAcquisitionBoundary &&
        !await _stopContinuousSweep()) {
      return const InstrumentActionOutcome(
        success: false,
        message: '当前扫描未确认停止，未修改 RF 前端',
      );
    }

    var frontendAcknowledged = !frontendRequested;
    var referenceAcknowledged = referenceDbm == null;
    var vgaSent = false;
    if (frontendRequested) {
      frontendAcknowledged =
          await _protocol.setRfFrontendConfirmed(requestedFrontend);
      if (!frontendAcknowledged) {
        return const InstrumentActionOutcome(
          success: false,
          message: 'RF 前端配置未收到设备 ACK，界面参数未修改',
          data: <String, dynamic>{'rf_frontend_acknowledged': false},
        );
      }
      if (!mounted) {
        return const InstrumentActionOutcome(
          success: false,
          message: '页面已经关闭，无法同步 RF 前端状态',
        );
      }
      _suppressPresetDeviceUpdates = true;
      try {
        setState(() {
          _rfFrontendConfig = requestedFrontend;
          _syncRfAttenText(requestedFrontend);
        });
      } finally {
        _suppressPresetDeviceUpdates = false;
      }
      _clearSpectrumDisplay();
      _protocol.getRfFrontendStatus();
    }

    if (referenceDbm != null) {
      referenceAcknowledged = await _protocol.setAmplitudeConfigConfirmed(
        AmplitudeConfig(
          refLevelDbm: referenceDbm,
          attenuatorMode: 0,
          preampMode: 0,
        ),
      );
      if (!referenceAcknowledged) {
        return InstrumentActionOutcome(
          success: false,
          message: 'RF 前端已确认，但参考电平未收到 ACK',
          data: <String, dynamic>{
            'rf_frontend_acknowledged': frontendAcknowledged,
            'reference_acknowledged': false,
            'partial_apply': frontendRequested,
          },
        );
      }
      if (mounted) {
        setState(() {
          refLevelController.text = _formatRefLevel(referenceDbm);
        });
      }
    }

    if (vgaDb != null) {
      final label = _vgaLabelForDb(vgaDb)!;
      _protocol.setVgaGainCode(_mapVgaGainStringToCode(label));
      _suppressPresetDeviceUpdates = true;
      try {
        vgaGainValue.value = label;
      } finally {
        _suppressPresetDeviceUpdates = false;
      }
      vgaSent = true;
    }

    return InstrumentActionOutcome(
      success: true,
      message: vgaSent ? 'RF 前端配置已确认；VGA 命令已发送（协议无 ACK）' : 'RF 前端配置已获设备确认',
      data: <String, dynamic>{
        'measurement_mode': _buildInstrumentAgentSnapshot().measurementMode,
        'path_mode': _rfPathModeAgentName(requestedFrontend.pathMode),
        'lna_mode': _rfLnaModeAgentName(requestedFrontend.lnaMode),
        'attenuation_db': requestedFrontend.attenDb,
        'vga_db':
            vgaDb ?? double.tryParse(vgaGainValue.value.split(' ').first) ?? 0,
        'reference_dbm':
            referenceDbm ?? double.tryParse(refLevelController.text) ?? 0,
        'rf_frontend_acknowledged': frontendAcknowledged,
        'reference_acknowledged': referenceAcknowledged,
        'vga_sent_without_ack': vgaSent,
        'previous_measurement_stopped': shouldStop,
        'path_switch_boundary_applied': pathChanged,
      },
    );
  }

  Future<InstrumentActionOutcome> _agentApplySpectrumPreset(
    String presetId,
  ) async {
    final preset = switch (presetId) {
      'default_full_span' => _measurementPresets[0],
      'fast_full_span' => _measurementPresets[1],
      'high_resolution' => _measurementPresets[2],
      'zero_span_observation' => _measurementPresets[3],
      _ => null,
    };
    if (preset == null) {
      return const InstrumentActionOutcome(
        success: false,
        message: '不支持的标准扫频预设',
      );
    }
    if (_rfFrontendConfig.pathMode == RfPathMode.directIf) {
      final frontend = await _agentConfigureSpectrumFrontend(
        const <String, dynamic>{'path_mode': 'mixer_chain'},
      );
      if (!frontend.success) {
        return InstrumentActionOutcome(
          success: false,
          message: '应用预设前切换混频链失败：${frontend.message}',
          data: frontend.data,
        );
      }
    }
    await _applyPreset(preset);
    if (!_lastMeasurementConfigApplied) {
      return InstrumentActionOutcome(
        success: false,
        message: '${preset.name}参数未全部收到设备 ACK',
        data: <String, dynamic>{
          'preset': presetId,
          'display_name': preset.name,
          'config_acknowledged': false,
        },
      );
    }
    return InstrumentActionOutcome(
      success: true,
      message: '已完整应用${preset.name}预设',
      data: <String, dynamic>{
        'preset': presetId,
        'display_name': preset.name,
        'start_hz': preset.startHz,
        'stop_hz': preset.stopHz,
        'rbw_hz': _getRbwHzForMode(preset.rbwMode),
        'vbw_mode': preset.vbwMode,
        'detector': preset.detectMode,
        'reference_dbm': preset.refLevelDbm,
        'scale_db_per_div': preset.scalePerGridDb,
        'point_count': preset.pointCount,
        'sweep_speed_hz': preset.sweepSpeedHz,
        'path_mode': _rfPathModeAgentName(_rfFrontendConfig.pathMode),
        'config_acknowledged': true,
      },
    );
  }

  String _sweepProfileSectionName(int id) => switch (id) {
        0 => 'point_total',
        1 => 'set_lo',
        2 => 'lock',
        3 => 'dma_prepare',
        4 => 'dma_wait',
        5 => 'dma_finish',
        6 => 'accumulate',
        7 => 'measure',
        8 => 'uart',
        9 => 'ddc',
        10 => 'cic',
        _ => 'section_$id',
      };

  Map<String, dynamic> _sweepProfileForAgent(
    SweepProfileReport report, {
    required bool refreshed,
  }) =>
      <String, dynamic>{
        'measurement_mode': 'spectrum',
        'refreshed': refreshed,
        'version': report.version,
        'enabled': report.enabled,
        'rbw_mode': report.rbwMode,
        'counts_per_second': report.countsPerSecond,
        'sweep_count': report.sweepCount,
        'point_count': report.pointCount,
        'dma_rearm_count': report.dmaRearmCount,
        'status_text': _formatSweepProfileStatus(report),
        'sections': report.sections
            .map(
              (section) => <String, dynamic>{
                'id': section.id,
                'name': _sweepProfileSectionName(section.id),
                'count': section.count,
                'total_ticks': section.totalTicks,
                'minimum_ticks': section.minTicks,
                'maximum_ticks': section.maxTicks,
                'average_ticks': section.averageTicks,
                'average_ms': report.ticksToMs(section.averageTicks),
                'per_sweep_point_ms': report.pointCount <= 0
                    ? null
                    : report.ticksToMs(
                        section.totalTicks / report.pointCount,
                      ),
              },
            )
            .toList(),
      };

  Future<InstrumentActionOutcome> _agentGetSweepProfile() async {
    if (_sweepProfileCompleter != null) {
      return const InstrumentActionOutcome(
        success: false,
        message: '已有 Profile 读取请求正在等待设备返回',
      );
    }
    final completer = Completer<SweepProfileReport>();
    _sweepProfileCompleter = completer;
    try {
      _protocol.getSweepProfile();
      final report = await completer.future.timeout(const Duration(seconds: 3));
      return InstrumentActionOutcome(
        success: true,
        message: report.enabled ? '已刷新标准扫频 Profile' : '设备 Profile 当前未启用',
        data: _sweepProfileForAgent(report, refreshed: true),
      );
    } on TimeoutException {
      final previous = _lastSweepProfileReport;
      if (previous != null) {
        return InstrumentActionOutcome(
          success: true,
          message: '设备未返回新的 Profile，已提供最近一次缓存结果',
          data: _sweepProfileForAgent(previous, refreshed: false),
        );
      }
      return const InstrumentActionOutcome(
        success: false,
        message: '等待设备返回扫频 Profile 超时，且没有可用缓存',
      );
    } finally {
      if (identical(_sweepProfileCompleter, completer)) {
        _sweepProfileCompleter = null;
      }
    }
  }

  Future<InstrumentActionOutcome> _agentStartSingleSweep() async {
    if (_singleSweepCompleter != null) {
      return const InstrumentActionOutcome(
        success: false,
        message: '已有单次扫描正在等待数据，请稍后重试',
      );
    }

    final completer = Completer<List<FlSpot>>();
    _singleSweepCompleter = completer;
    try {
      await _applyMeasurementConfigChange(
        forceContinuous: false,
        clearDisplay: true,
      );
      if (!_lastMeasurementConfigApplied) {
        return const InstrumentActionOutcome(
          success: false,
          message: '配置未确认，单次扫描未启动',
          data: <String, dynamic>{
            'continuous': false,
            'config_acknowledged': false,
            'sweep_completed': false,
          },
        );
      }
      if (!completer.isCompleted && !_spectrumRequestInFlight) {
        return const InstrumentActionOutcome(
          success: false,
          message: '配置已确认，但扫描请求未能启动',
          data: <String, dynamic>{
            'continuous': false,
            'config_acknowledged': true,
            'sweep_completed': false,
          },
        );
      }

      final points = await completer.future.timeout(
        _getSpectrumRequestTimeout() + const Duration(seconds: 5),
      );
      return InstrumentActionOutcome(
        success: true,
        message: '单次扫描已完成，共收到 ${points.length} 个频谱点',
        data: <String, dynamic>{
          'continuous': false,
          'config_acknowledged': true,
          'sweep_completed': true,
          'point_count': points.length,
          if (points.isNotEmpty) 'start_hz': points.first.x,
          if (points.isNotEmpty) 'stop_hz': points.last.x,
          'completed_at': DateTime.now().toIso8601String(),
        },
      );
    } on TimeoutException {
      return const InstrumentActionOutcome(
        success: false,
        message: '单次扫描等待数据超时',
        data: <String, dynamic>{
          'continuous': false,
          'config_acknowledged': true,
          'sweep_completed': false,
        },
      );
    } on StateError catch (error) {
      return InstrumentActionOutcome(
        success: false,
        message: error.message.toString(),
        data: const <String, dynamic>{
          'continuous': false,
          'sweep_completed': false,
        },
      );
    } finally {
      if (identical(_singleSweepCompleter, completer)) {
        _singleSweepCompleter = null;
      }
    }
  }

  Future<InstrumentActionOutcome> _agentStartContinuousSweep() async {
    await _startContinuousSweep();
    final success = _lastMeasurementConfigApplied && _isContinuousSweepRunning;
    return InstrumentActionOutcome(
      success: success,
      message: success ? '配置已获 ACK，连续扫描已启动' : '连续扫描启动失败',
      data: <String, dynamic>{
        'continuous': true,
        'config_acknowledged': _lastMeasurementConfigApplied,
      },
    );
  }

  Future<InstrumentActionOutcome> _agentStopMeasurement() async {
    final acknowledged = await _stopContinuousSweep();
    return InstrumentActionOutcome(
      success: acknowledged,
      message: acknowledged ? '设备已确认停止测量' : '停止命令未收到设备 ACK',
      data: <String, dynamic>{'device_ack': acknowledged},
    );
  }

  List<AgentSpectrumPoint> _currentAgentSpectrumPoints() {
    final points = _spectrumData
        .map(
          (spot) => AgentSpectrumPoint(
            frequencyHz: spot.x,
            powerDbm: spot.y,
          ),
        )
        .toList();
    points.sort((a, b) => a.frequencyHz.compareTo(b.frequencyHz));
    return points;
  }

  Future<InstrumentActionOutcome> _agentGetSpectrumSnapshot(
    int maximumPoints,
  ) async {
    final points = _currentAgentSpectrumPoints();
    if (points.isEmpty) {
      return const InstrumentActionOutcome(
        success: false,
        message: '当前没有可读取的频谱数据，请先完成一次扫描',
      );
    }

    final sampled = AgentSpectrumAnalyzer.downsample(points, maximumPoints);
    final now = DateTime.now();
    final lastArrival = _lastSpectrumArrivalTime;
    return InstrumentActionOutcome(
      success: true,
      message: '已读取当前频谱快照（${points.length} 点，返回 ${sampled.length} 点）',
      data: <String, dynamic>{
        'captured_at': now.toIso8601String(),
        'last_data_at': lastArrival?.toIso8601String(),
        'data_age_ms': lastArrival == null
            ? null
            : now.difference(lastArrival).inMilliseconds,
        'original_point_count': points.length,
        'returned_point_count': sampled.length,
        'start_hz': points.first.frequencyHz,
        'stop_hz': points.last.frequencyHz,
        'instrument_state': _buildInstrumentAgentSnapshot().toJson(),
        'points': sampled.map((point) => point.toJson()).toList(),
      },
    );
  }

  Future<InstrumentActionOutcome> _agentAnalyzeSpectrum(
    int peakCount,
    double thresholdAboveNoiseDb,
  ) async {
    final points = _currentAgentSpectrumPoints();
    if (points.isEmpty) {
      return const InstrumentActionOutcome(
        success: false,
        message: '当前没有可分析的频谱数据，请先完成一次扫描',
      );
    }

    final analysis = AgentSpectrumAnalyzer.analyze(
      points,
      peakCount: peakCount,
      thresholdAboveNoiseDb: thresholdAboveNoiseDb,
    );
    return InstrumentActionOutcome(
      success: true,
      message: '频谱分析完成：噪声底 '
          '${analysis.noiseFloorDbm.toStringAsFixed(2)} dBm，'
          '找到 ${analysis.peaks.length} 个峰值',
      data: <String, dynamic>{
        ...analysis.toJson(),
        'threshold_above_noise_db': thresholdAboveNoiseDb,
        'analyzed_at': DateTime.now().toIso8601String(),
      },
    );
  }

  Future<InstrumentActionOutcome> _agentPlacePeakMarkers(
    int peakCount,
    double thresholdAboveNoiseDb,
  ) async {
    final points = _currentAgentSpectrumPoints();
    if (points.isEmpty) {
      return const InstrumentActionOutcome(
        success: false,
        message: '当前没有可标记的频谱数据，请先完成一次扫描',
      );
    }
    final analysis = AgentSpectrumAnalyzer.analyze(
      points,
      peakCount: peakCount,
      thresholdAboveNoiseDb: thresholdAboveNoiseDb,
    );
    if (analysis.peaks.isEmpty) {
      return InstrumentActionOutcome(
        success: false,
        message: '没有找到高于噪声底 ${thresholdAboveNoiseDb.toStringAsFixed(1)} dB 的峰值',
        data: analysis.toJson(),
      );
    }
    if (!mounted) {
      return const InstrumentActionOutcome(
        success: false,
        message: '页面已经关闭，无法放置 Marker',
      );
    }

    autoPeakEnabled.value = false;
    setState(() {
      for (var index = 0; index < _markers.length; index++) {
        final marker = _markers[index];
        if (index < analysis.peaks.length) {
          marker
            ..enabled = true
            ..freqHz = analysis.peaks[index].frequencyHz;
        } else {
          marker.enabled = false;
        }
      }
      _currentMarker = _markers.first;
    });
    _markerFreqController.text = _formatFreqInput(
      _currentMarker!.freqHz,
      _markerFreqUnit.value,
    );

    final markers = <Map<String, dynamic>>[];
    for (var index = 0; index < analysis.peaks.length; index++) {
      markers.add(<String, dynamic>{
        'marker_id': _markers[index].id,
        ...analysis.peaks[index].toJson(),
      });
    }
    return InstrumentActionOutcome(
      success: true,
      message: '已在频谱图上放置 ${markers.length} 个峰值 Marker',
      data: <String, dynamic>{
        'noise_floor_dbm': analysis.noiseFloorDbm,
        'markers': markers,
      },
    );
  }

  Future<InstrumentActionOutcome> _agentSaveMeasurement(
    String label,
    String note,
  ) async {
    final points = _currentAgentSpectrumPoints();
    if (points.isEmpty) {
      return const InstrumentActionOutcome(
        success: false,
        message: '当前没有可保存的频谱数据，请先完成一次扫描',
      );
    }

    final now = DateTime.now();
    final analysis = AgentSpectrumAnalyzer.analyze(points);
    await _agentSessionRestoreFuture;
    final directory = _agentTestSessionStore.activeSessionDirectory ??
        _agentSessionsDirectory();
    await directory.create(recursive: true);

    final safeLabel = _sanitizeAgentFileLabel(label);
    final baseName = '${_formatFileTimestamp(now)}_'
        '${now.millisecond.toString().padLeft(3, '0')}_$safeLabel';
    final jsonFile =
        File('${directory.path}${Platform.pathSeparator}$baseName.json');
    final csvFile =
        File('${directory.path}${Platform.pathSeparator}$baseName.csv');
    final record = <String, dynamic>{
      'file_version': 1,
      'saved_at': now.toIso8601String(),
      'label': label,
      'note': note,
      'last_data_at': _lastSpectrumArrivalTime?.toIso8601String(),
      'instrument_state': _buildInstrumentAgentSnapshot().toJson(),
      'analysis': analysis.toJson(),
      if (_lastAgentLimitEvaluation != null)
        'limit_evaluation': _lastAgentLimitEvaluation,
      'spectrum_points': points.map((point) => point.toJson()).toList(),
    };
    const encoder = JsonEncoder.withIndent('  ');
    await jsonFile.writeAsString(encoder.convert(record), flush: true);

    final csv = StringBuffer('\ufefffrequency_hz,power_dbm\r\n');
    for (final point in points) {
      csv
        ..write(point.frequencyHz.toStringAsFixed(6))
        ..write(',')
        ..write(point.powerDbm.toStringAsFixed(6))
        ..write('\r\n');
    }
    await csvFile.writeAsString(csv.toString(), flush: true);

    final activeSession = _agentTestSessionStore.activeSession;
    if (activeSession != null) {
      await _agentTestSessionStore.registerMeasurement(
        label: label,
        savedAt: now,
        jsonPath: jsonFile.path,
        csvPath: csvFile.path,
        analysis: analysis.toJson(),
        limitEvaluation: _lastAgentLimitEvaluation,
      );
    }

    return InstrumentActionOutcome(
      success: true,
      message: '测试记录已保存为 JSON 和 CSV',
      data: <String, dynamic>{
        'label': label,
        'saved_at': now.toIso8601String(),
        'point_count': points.length,
        'json_path': jsonFile.path,
        'csv_path': csvFile.path,
        'analysis': analysis.toJson(),
        'session_id': activeSession?.id,
      },
    );
  }

  Future<InstrumentActionOutcome> _agentSaveRealtimeMeasurement(
    String label,
    String note,
    String trace,
    bool includeWaterfall,
    int waterfallRows,
  ) async {
    final page = _realtimeSpectrumPageKey.currentState;
    if (page == null) return _realtimePageUnavailableOutcome();
    final samples = page.samplesForAgent(trace);
    if (samples.isEmpty) {
      return InstrumentActionOutcome(
        success: false,
        message: '实时频谱 $trace 曲线暂无可保存数据',
      );
    }

    final now = DateTime.now();
    final analysis = page.analyzeForAgent(
      trace: trace,
      peakCount: 5,
      thresholdAboveNoiseDb: 6,
    );
    final waterfall = includeWaterfall
        ? page.waterfallHistoryForAgent(
            maximumRows: waterfallRows,
            lookbackSeconds: null,
            maximumPointsPerRow: 128,
          )
        : null;
    await _agentSessionRestoreFuture;
    final directory = _agentTestSessionStore.activeSessionDirectory ??
        _agentSessionsDirectory();
    await directory.create(recursive: true);

    final safeLabel = _sanitizeAgentFileLabel(label);
    final baseName = '${_formatFileTimestamp(now)}_'
        '${now.millisecond.toString().padLeft(3, '0')}_rt_$safeLabel';
    final jsonFile =
        File('${directory.path}${Platform.pathSeparator}$baseName.json');
    final csvFile =
        File('${directory.path}${Platform.pathSeparator}$baseName.csv');
    final record = <String, dynamic>{
      'file_version': 1,
      'saved_at': now.toIso8601String(),
      'label': label,
      'note': note,
      'measurement_mode': 'realtime_spectrum',
      'amplitude_unit': 'dBFS',
      'trace': trace,
      'instrument_state': _buildInstrumentAgentSnapshot().toJson(),
      'realtime_configuration': page.agentConfiguration,
      'analysis': analysis.toJson(),
      'realtime_spectrum_points':
          samples.map((sample) => sample.toJson()).toList(),
      if (waterfall != null) 'waterfall_history': waterfall,
    };
    const encoder = JsonEncoder.withIndent('  ');
    await jsonFile.writeAsString(encoder.convert(record), flush: true);

    final csv = StringBuffer('\ufefffrequency_hz,level_dbfs\r\n');
    for (final sample in samples) {
      csv
        ..write(sample.frequencyHz.toStringAsFixed(6))
        ..write(',')
        ..write(sample.levelDbfs.toStringAsFixed(6))
        ..write('\r\n');
    }
    await csvFile.writeAsString(csv.toString(), flush: true);

    final activeSession = _agentTestSessionStore.activeSession;
    if (activeSession != null) {
      await _agentTestSessionStore.registerMeasurement(
        label: label,
        savedAt: now,
        jsonPath: jsonFile.path,
        csvPath: csvFile.path,
        analysis: analysis.toJson(),
        measurementMode: 'realtime_spectrum',
        amplitudeUnit: 'dBFS',
      );
    }
    return InstrumentActionOutcome(
      success: true,
      message: '实时频谱测试记录已保存为 JSON 和 CSV',
      data: <String, dynamic>{
        'measurement_mode': 'realtime_spectrum',
        'amplitude_unit': 'dBFS',
        'trace': trace,
        'point_count': samples.length,
        'waterfall_included': waterfall != null,
        'json_path': jsonFile.path,
        'csv_path': csvFile.path,
        'analysis': analysis.toJson(),
        'session_id': activeSession?.id,
      },
    );
  }

  Future<InstrumentActionOutcome> _agentSavePhaseNoiseMeasurement(
    String label,
    String note,
    String trace,
  ) async {
    final selected = _phaseNoiseTraceForAgent(trace);
    if (selected == null) {
      return const InstrumentActionOutcome(
        success: false,
        message: '当前没有可保存的相位噪声曲线数据',
      );
    }
    final now = DateTime.now();
    final analysis = _phaseNoiseTraceSummary(selected.name, selected.points);
    await _agentSessionRestoreFuture;
    final directory = _agentTestSessionStore.activeSessionDirectory ??
        _agentSessionsDirectory();
    await directory.create(recursive: true);

    final safeLabel = _sanitizeAgentFileLabel(label);
    final baseName = '${_formatFileTimestamp(now)}_'
        '${now.millisecond.toString().padLeft(3, '0')}_pn_$safeLabel';
    final jsonFile =
        File('${directory.path}${Platform.pathSeparator}$baseName.json');
    final csvFile =
        File('${directory.path}${Platform.pathSeparator}$baseName.csv');
    final record = <String, dynamic>{
      'file_version': 1,
      'saved_at': now.toIso8601String(),
      'label': label,
      'note': note,
      'measurement_mode': 'phase_noise',
      'amplitude_unit': 'dBc/Hz',
      'trace': selected.name,
      'instrument_state': _buildInstrumentAgentSnapshot().toJson(),
      'phase_noise_state': _phaseNoiseAgentState(),
      'analysis': analysis,
      'phase_noise_points':
          selected.points.map(_phaseNoisePointForAgent).toList(),
    };
    const encoder = JsonEncoder.withIndent('  ');
    await jsonFile.writeAsString(encoder.convert(record), flush: true);

    final csv = StringBuffer(
      '\ufeffoffset_hz,phase_noise_dbc_per_hz,noise_power_dbm,rbw_hz\r\n',
    );
    for (final point in selected.points) {
      csv
        ..write(point.offsetHz.toStringAsFixed(6))
        ..write(',')
        ..write(point.dbcHz.toStringAsFixed(6))
        ..write(',')
        ..write(point.noisePowerDbm.isFinite
            ? point.noisePowerDbm.toStringAsFixed(6)
            : '')
        ..write(',')
        ..write(point.rbwHz.isFinite ? point.rbwHz.toStringAsFixed(6) : '')
        ..write('\r\n');
    }
    await csvFile.writeAsString(csv.toString(), flush: true);

    final activeSession = _agentTestSessionStore.activeSession;
    if (activeSession != null) {
      await _agentTestSessionStore.registerMeasurement(
        label: label,
        savedAt: now,
        jsonPath: jsonFile.path,
        csvPath: csvFile.path,
        analysis: analysis,
        measurementMode: 'phase_noise',
        amplitudeUnit: 'dBc/Hz',
      );
    }
    return InstrumentActionOutcome(
      success: true,
      message: '相位噪声测试记录已保存为 JSON 和 CSV',
      data: <String, dynamic>{
        'measurement_mode': 'phase_noise',
        'amplitude_unit': 'dBc/Hz',
        'trace': selected.name,
        'point_count': selected.points.length,
        'complete': _phaseNoiseComplete,
        'json_path': jsonFile.path,
        'csv_path': csvFile.path,
        'analysis': analysis,
        'session_id': activeSession?.id,
      },
    );
  }

  Future<InstrumentActionOutcome> _agentCaptureScreenshot() async {
    try {
      final directoryPath = _screenshotDirController.text.trim().isEmpty
          ? _defaultScreenshotDirectory
          : _screenshotDirController.text.trim();
      final file = await _captureCurrentMeasurementScreenshot(directoryPath);
      return InstrumentActionOutcome(
        success: true,
        message: '当前测量页面截图已保存',
        data: <String, dynamic>{
          'measurement_mode': _buildInstrumentAgentSnapshot().measurementMode,
          'file_path': file.path,
        },
      );
    } catch (error) {
      return InstrumentActionOutcome(
        success: false,
        message: '截图保存失败：$error',
      );
    }
  }

  Directory _agentSessionsDirectory() {
    final userHome = Platform.environment['USERPROFILE'] ??
        Platform.environment['HOME'] ??
        Directory.current.path;
    return Directory(
      '$userHome${Platform.pathSeparator}Documents${Platform.pathSeparator}'
      'PuSuSA${Platform.pathSeparator}AI Sessions',
    );
  }

  Future<InstrumentActionOutcome> _agentGetTestSession() async {
    await _agentSessionRestoreFuture;
    final session = _agentTestSessionStore.activeSession;
    if (session == null) {
      return const InstrumentActionOutcome(
        success: true,
        message: '当前没有进行中的测试会话',
        data: <String, dynamic>{'active_session': null},
      );
    }
    return InstrumentActionOutcome(
      success: true,
      message: '已读取当前测试会话“${session.name}”',
      data: <String, dynamic>{'active_session': session.toJson()},
    );
  }

  Future<InstrumentActionOutcome> _agentStartTestSession(
    String name,
    String objective,
  ) async {
    await _agentSessionRestoreFuture;
    try {
      final session = await _agentTestSessionStore.start(
        name: name,
        objective: objective,
      );
      return InstrumentActionOutcome(
        success: true,
        message: '测试会话“${session.name}”已开始',
        data: <String, dynamic>{
          'session': session.toJson(),
          'directory': _agentTestSessionStore.activeSessionDirectory?.path,
        },
      );
    } on StateError catch (error) {
      return InstrumentActionOutcome(
        success: false,
        message: error.message.toString(),
      );
    }
  }

  Future<InstrumentActionOutcome> _agentAddTestNote(String note) async {
    await _agentSessionRestoreFuture;
    try {
      final session = await _agentTestSessionStore.addNote(note);
      return InstrumentActionOutcome(
        success: true,
        message: '测试备注已追加到“${session.name}”',
        data: <String, dynamic>{
          'session_id': session.id,
          'note_count': session.notes.length,
        },
      );
    } on StateError catch (error) {
      return InstrumentActionOutcome(
        success: false,
        message: error.message.toString(),
      );
    }
  }

  Future<InstrumentActionOutcome> _agentEndTestSession(String summary) async {
    await _agentSessionRestoreFuture;
    try {
      final session = await _agentTestSessionStore.end(summary: summary);
      return InstrumentActionOutcome(
        success: true,
        message: '测试会话“${session.name}”已结束并保存',
        data: <String, dynamic>{'session': session.toJson()},
      );
    } on StateError catch (error) {
      return InstrumentActionOutcome(
        success: false,
        message: error.message.toString(),
      );
    }
  }

  Future<InstrumentActionOutcome> _agentListTestSessions(int limit) async {
    await _agentSessionRestoreFuture;
    final sessions = await _agentTestSessionStore.list(limit: limit);
    return InstrumentActionOutcome(
      success: true,
      message:
          sessions.isEmpty ? '还没有历史测试会话' : '已读取最近 ${sessions.length} 个测试会话',
      data: <String, dynamic>{
        'sessions': sessions
            .map(
              (session) => <String, dynamic>{
                'id': session.id,
                'name': session.name,
                'objective': session.objective,
                'status': session.status,
                'started_at': session.startedAt.toIso8601String(),
                'ended_at': session.endedAt?.toIso8601String(),
                'note_count': session.notes.length,
                'measurement_count': session.measurements.length,
              },
            )
            .toList(),
      },
    );
  }

  Future<InstrumentActionOutcome> _agentListMeasurements(int limit) async {
    await _agentSessionRestoreFuture;
    final measurements =
        await _agentTestSessionStore.listMeasurements(limit: limit);
    return InstrumentActionOutcome(
      success: true,
      message: measurements.isEmpty
          ? '还没有保存过测量记录'
          : '已读取最近 ${measurements.length} 条测量记录',
      data: <String, dynamic>{'measurements': measurements},
    );
  }

  Future<InstrumentActionOutcome> _agentLoadMeasurement(
    String measurementId,
  ) async {
    await _agentSessionRestoreFuture;
    try {
      final record =
          await _agentTestSessionStore.loadMeasurement(measurementId);
      final points = _agentPointsFromMeasurementRecord(record);
      if (points.isEmpty) {
        return const InstrumentActionOutcome(
          success: false,
          message: '历史测量中没有有效的频谱点',
        );
      }
      final displayPoints = AgentSpectrumAnalyzer.downsample(points, 2048);
      if (!mounted) {
        return const InstrumentActionOutcome(
          success: false,
          message: '页面已经关闭，无法显示历史参考曲线',
        );
      }
      setState(() {
        _agentReferenceSpectrumData = displayPoints
            .map((point) => FlSpot(point.frequencyHz, point.powerDbm))
            .toList();
        _agentReferenceSpectrumLabel =
            record['label']?.toString() ?? measurementId;
      });
      return InstrumentActionOutcome(
        success: true,
        message: '历史测量“$_agentReferenceSpectrumLabel”已作为参考曲线显示',
        data: <String, dynamic>{
          'measurement_id': measurementId,
          'label': record['label'],
          'saved_at': record['saved_at'],
          'point_count': points.length,
          'display_point_count': displayPoints.length,
          'analysis': record['analysis'],
        },
      );
    } on StateError catch (error) {
      return InstrumentActionOutcome(
        success: false,
        message: error.message.toString(),
      );
    }
  }

  Future<InstrumentActionOutcome> _agentCompareMeasurements(
    String firstMeasurementId,
    String secondMeasurementId,
  ) async {
    await _agentSessionRestoreFuture;
    try {
      final first = await _agentMeasurementPoints(firstMeasurementId);
      final second = await _agentMeasurementPoints(secondMeasurementId);
      final comparison = AgentSpectrumComparator.compare(first, second);
      return InstrumentActionOutcome(
        success: true,
        message: '频谱对比完成：平均变化 '
            '${comparison.meanDeltaDb.toStringAsFixed(2)} dB，最大绝对差值 '
            '${comparison.maximumAbsoluteDeltaDb.toStringAsFixed(2)} dB',
        data: <String, dynamic>{
          'first_measurement_id': firstMeasurementId,
          'second_measurement_id': secondMeasurementId,
          ...comparison.toJson(),
        },
      );
    } on ArgumentError catch (error) {
      return InstrumentActionOutcome(
        success: false,
        message: error.message?.toString() ?? error.toString(),
      );
    } on StateError catch (error) {
      return InstrumentActionOutcome(
        success: false,
        message: error.message.toString(),
      );
    }
  }

  Future<List<AgentSpectrumPoint>> _agentMeasurementPoints(String id) async {
    if (id.trim().toLowerCase() == 'current') {
      final current = _currentAgentSpectrumPoints();
      if (current.isEmpty) {
        throw StateError('当前没有可用于对比的频谱数据');
      }
      return current;
    }
    final record = await _agentTestSessionStore.loadMeasurement(id);
    final points = _agentPointsFromMeasurementRecord(record);
    if (points.isEmpty) throw StateError('测量记录 $id 没有有效频谱点');
    return points;
  }

  List<AgentSpectrumPoint> _agentPointsFromMeasurementRecord(
    Map<String, dynamic> record,
  ) {
    final rawPoints = record['spectrum_points'];
    if (rawPoints is! List) return <AgentSpectrumPoint>[];
    final points = <AgentSpectrumPoint>[];
    for (final rawPoint in rawPoints.whereType<Map>()) {
      final frequency =
          double.tryParse(rawPoint['frequency_hz']?.toString() ?? '');
      final power = double.tryParse(rawPoint['power_dbm']?.toString() ?? '');
      if (frequency != null &&
          power != null &&
          frequency.isFinite &&
          power.isFinite) {
        points.add(
          AgentSpectrumPoint(frequencyHz: frequency, powerDbm: power),
        );
      }
    }
    points.sort((a, b) => a.frequencyHz.compareTo(b.frequencyHz));
    return points;
  }

  Future<InstrumentActionOutcome> _agentEvaluateSpectrumLimits(
    double? maximumNoiseFloorDbm,
    double? minimumMainPeakDbm,
    double? minimumSpurSuppressionDb,
  ) async {
    if (_measurementMode != MeasurementMode.spectrum || _isZeroSpan) {
      return const InstrumentActionOutcome(
        success: false,
        message: '频谱限值判定仅支持标准非零扫宽频谱模式',
      );
    }
    final points = _currentAgentSpectrumPoints();
    if (points.isEmpty) {
      return const InstrumentActionOutcome(
        success: false,
        message: '当前没有可执行限值判定的频谱数据',
      );
    }
    final evaluation = AgentSpectrumLimitEvaluator.evaluate(
      points,
      maximumNoiseFloorDbm: maximumNoiseFloorDbm,
      minimumMainPeakDbm: minimumMainPeakDbm,
      minimumSpurSuppressionDb: minimumSpurSuppressionDb,
    );
    if (mounted) {
      setState(() {
        _agentMaximumNoiseFloorDbm = maximumNoiseFloorDbm;
        _agentMinimumMainPeakDbm = minimumMainPeakDbm;
        _agentMinimumSpurSuppressionDb = minimumSpurSuppressionDb;
        _applyAgentLimitEvaluation(evaluation);
      });
    }
    return InstrumentActionOutcome(
      success: true,
      message: evaluation.passed ? '频谱限值判定：PASS' : '频谱限值判定：FAIL',
      data: evaluation.toJson(),
    );
  }

  void _refreshAgentLimitEvaluation() {
    if (_agentMaximumNoiseFloorDbm == null &&
        _agentMinimumMainPeakDbm == null &&
        _agentMinimumSpurSuppressionDb == null) {
      return;
    }
    final points = _currentAgentSpectrumPoints();
    if (points.isEmpty) return;
    final evaluation = AgentSpectrumLimitEvaluator.evaluate(
      points,
      maximumNoiseFloorDbm: _agentMaximumNoiseFloorDbm,
      minimumMainPeakDbm: _agentMinimumMainPeakDbm,
      minimumSpurSuppressionDb: _agentMinimumSpurSuppressionDb,
    );
    _applyAgentLimitEvaluation(evaluation);
  }

  void _applyAgentLimitEvaluation(AgentSpectrumLimitEvaluation evaluation) {
    final checkByName = <String, Map<String, dynamic>>{
      for (final check in evaluation.checks) check['name'].toString(): check,
    };
    final lines = <SpectrumLimitLine>[];
    SpectrumLimitLine limitLine(String name, String label, double powerDbm) {
      final passed = checkByName[name]?['passed'] == true;
      return SpectrumLimitLine(
        label: '$label ${passed ? 'PASS' : 'FAIL'}',
        powerDbm: powerDbm,
        color: passed ? material.Colors.greenAccent : material.Colors.redAccent,
      );
    }

    if (_agentMaximumNoiseFloorDbm != null) {
      lines.add(limitLine(
        'maximum_noise_floor_dbm',
        '噪声底上限',
        _agentMaximumNoiseFloorDbm!,
      ));
    }
    if (_agentMinimumMainPeakDbm != null) {
      lines.add(limitLine(
        'minimum_main_peak_dbm',
        '主峰下限',
        _agentMinimumMainPeakDbm!,
      ));
    }
    if (_agentMinimumSpurSuppressionDb != null) {
      final mainPeakPower = evaluation.analysis.peaks.isEmpty
          ? evaluation.analysis.maximumDbm
          : evaluation.analysis.peaks.first.powerDbm;
      lines.add(limitLine(
        'minimum_spur_suppression_db',
        '杂散上限',
        mainPeakPower - _agentMinimumSpurSuppressionDb!,
      ));
    }
    _agentSpectrumLimitLines = lines;
    _lastAgentLimitEvaluation = evaluation.toJson();
  }

  Future<InstrumentActionOutcome> _agentClearAnalysisOverlays() async {
    if (!mounted) {
      return const InstrumentActionOutcome(
        success: false,
        message: '页面已经关闭，无法清除分析叠加层',
      );
    }
    setState(() {
      _agentReferenceSpectrumData = <FlSpot>[];
      _agentReferenceSpectrumLabel = '';
      _agentSpectrumLimitLines = <SpectrumLimitLine>[];
      _lastAgentLimitEvaluation = null;
      _agentMaximumNoiseFloorDbm = null;
      _agentMinimumMainPeakDbm = null;
      _agentMinimumSpurSuppressionDb = null;
    });
    return const InstrumentActionOutcome(
      success: true,
      message: '历史参考曲线和限值线已清除',
    );
  }

  Future<InstrumentActionOutcome> _agentExportTestReport(
    String sessionId,
  ) async {
    await _agentSessionRestoreFuture;
    final effectiveId = sessionId.isNotEmpty
        ? sessionId
        : _agentTestSessionStore.activeSession?.id ?? '';
    if (effectiveId.isEmpty) {
      return const InstrumentActionOutcome(
        success: false,
        message: '当前没有测试会话，请提供 list_test_sessions 返回的 session_id',
      );
    }
    try {
      final path = await _agentTestSessionStore.exportHtmlReport(effectiveId);
      return InstrumentActionOutcome(
        success: true,
        message: 'HTML 测试报告已导出',
        data: <String, dynamic>{
          'session_id': effectiveId,
          'report_path': path,
        },
      );
    } on StateError catch (error) {
      return InstrumentActionOutcome(
        success: false,
        message: error.message.toString(),
      );
    }
  }

  String _sanitizeAgentFileLabel(String label) {
    final sanitized = label
        .trim()
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
        .replaceAll(RegExp(r'[. ]+$'), '')
        .replaceAll(RegExp(r'\s+'), '_');
    if (sanitized.isEmpty) return 'measurement';
    return sanitized.length <= 48 ? sanitized : sanitized.substring(0, 48);
  }

  String? _agentRbwLabel(double rbwHz) {
    return switch (rbwHz.round()) {
      1000 => '1 kHz',
      10000 => '10 kHz',
      30000 => '30 kHz',
      100000 => '100 kHz',
      300000 => '300 kHz',
      1000000 => '1 MHz',
      _ => null,
    };
  }

  String? _agentVbwLabel(String mode) {
    return switch (mode) {
      'follow_rbw' => 'VBW=RBW',
      'manual' => '手动',
      'rbw_x_0_1' => 'VBW=0.1*RBW',
      'rbw_x_0_01' => 'VBW=0.01*RBW',
      'rbw_x_10' => 'VBW=10*RBW',
      _ => null,
    };
  }

  void _resizeSettingsPanel(double dragDelta) {
    final availableWidth = MediaQuery.sizeOf(context).width;
    final aiReserved = _aiAssistantVisible ? _aiPanelWidth + 7 : 0.0;
    final maximum = math.max(
      240.0,
      math.min(520.0, availableWidth - aiReserved - 360.0),
    );
    setState(() {
      _settingsPanelWidth =
          (_settingsPanelWidth - dragDelta).clamp(240.0, maximum).toDouble();
    });
  }

  void _resizeAiPanel(double dragDelta) {
    final availableWidth = MediaQuery.sizeOf(context).width;
    final maximum = math.max(
      320.0,
      math.min(720.0, availableWidth - _settingsPanelWidth - 360.0),
    );
    setState(() {
      _aiPanelWidth =
          (_aiPanelWidth - dragDelta).clamp(320.0, maximum).toDouble();
    });
  }

  void _handleAiToolbarPressed() {
    if (_aiAssistantVisible) {
      unawaited(_hideAiAssistant());
      return;
    }

    setState(() => _aiAssistantVisible = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _aiAssistantKey.currentState?.showPanel();
    });
  }

  void _closeAiAssistant() {
    unawaited(_hideAiAssistant());
  }

  Future<void> _hideAiAssistant() async {
    if (!mounted) return;
    setState(() {
      _aiAssistantVisible = false;
      _aiAssistantListening = false;
    });
    await _aiAssistantKey.currentState?.prepareToHide();
  }

  void _handleAiListeningChanged(bool listening) {
    if (!mounted || _aiAssistantListening == listening) return;
    setState(() => _aiAssistantListening = listening);
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

    return Stack(
      children: [
        Positioned.fill(
          child: ScaffoldPage(
            padding: const EdgeInsets.only(top: 0),
            header: WindowsTitleBar(
              child: CommandBar(
                overflowBehavior: CommandBarOverflowBehavior.noWrap,
                primaryItems: [
                  CommandBarButton(
                    icon: Image.asset('assets/imgs/logo6.png',
                        width: 127, height: 35),
                    onPressed: null,
                  ),
                  // 模式鎸夐挳锛堝彧鏄剧ず鈥滄ā寮忊€濓級
                  CommandBarButton(
                    icon: FlyoutTarget(
                      controller: _modeFlyoutController,
                      child: const Icon(FluentIcons.settings),
                    ),
                    label: const Text('模式'),
                    onPressed:
                        _activeToolbarMeasurementBusy ? null : _showModeFlyout,
                  ),

                  CommandBarButton(
                      icon: FlyoutTarget(
                        controller: _presetFlyoutController,
                        child: const Icon(FluentIcons.refresh),
                      ),
                      label: const Text('预设'),
                      onPressed:
                          _measurementMode == MeasurementMode.realtimeSpectrum
                              ? null
                              : _showPresetFlyout),
                  CommandBarButton(
                    icon: const Icon(FluentIcons.play),
                    label: const Text('单次'),
                    onPressed:
                        _measurementMode == MeasurementMode.realtimeSpectrum ||
                                _activeToolbarMeasurementBusy
                            ? null
                            : _handleToolbarSingleMeasurement,
                  ),
                  CommandBarButton(
                    icon: const Icon(FluentIcons.play_resume),
                    label: const Text('连续'),
                    onPressed:
                        _measurementMode == MeasurementMode.realtimeSpectrum ||
                                _activeToolbarMeasurementBusy
                            ? null
                            : _handleToolbarContinuousMeasurement,
                  ),
                  CommandBarButton(
                    icon: Icon(_activeToolbarMeasurementRunning
                        ? FluentIcons.stop
                        : FluentIcons.record2),
                    label: const Text('停止'),
                    onPressed:
                        _measurementMode == MeasurementMode.realtimeSpectrum ||
                                _activeToolbarMeasurementBusy
                            ? null
                            : _handleToolbarStopMeasurement,
                  ),
                  CommandBarButton(
                    icon: const Icon(FluentIcons.camera),
                    label: const Text('截图'),
                    onPressed:
                        _screenshotInProgress ? null : _showScreenshotSettings,
                  ),
                  CommandBarButton(
                    icon: Icon(
                      _aiAssistantListening
                          ? material.Icons.stop_circle_rounded
                          : material.Icons.auto_awesome_rounded,
                      color: _aiAssistantListening
                          ? const Color(0xFFE5484D)
                          : (_aiAssistantVisible
                              ? const Color(0xFF65A9FF)
                              : null),
                    ),
                    label: Text(_aiAssistantListening ? 'AI 录音' : 'AI 助手'),
                    onPressed: _handleAiToolbarPressed,
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
                            decoration: BoxDecoration(
                                shape: BoxShape.circle, color: color),
                          );
                        },
                      ),
                    ),
                    label: const Text('端口'),
                    onPressed: () => _serialFlyoutController.showFlyout(
                      builder: (context) =>
                          SerialPortSelector(manager: _serialManager),
                    ),
                  ),
                ],
              ),
            ),
            content: Row(
              children: [
                Expanded(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      if (_measurementMode == MeasurementMode.phaseNoise)
                        Expanded(
                          child: RepaintBoundary(
                            key: _phaseNoiseScreenshotBoundaryKey,
                            child: _buildPhaseNoiseView(),
                          ),
                        )
                      else if (_measurementMode ==
                          MeasurementMode.realtimeSpectrum)
                        Expanded(
                          child: RepaintBoundary(
                            key: _realtimeScreenshotBoundaryKey,
                            child: RealtimeSpectrumPage(
                              key: _realtimeSpectrumPageKey,
                              protocol: _protocol,
                              connected: _serialManager.isConnected,
                              initialRfConfig: _rfFrontendConfig,
                              initialVgaLabel: vgaGainValue.value,
                              sidebarWidth: _settingsPanelWidth,
                              onSidebarDragDelta: _resizeSettingsPanel,
                            ),
                          ),
                        )
                      else ...[
                        Expanded(
                          child: RepaintBoundary(
                            key: _spectrumScreenshotBoundaryKey,
                            child: Acrylic(
                              tint:
                                  material.Colors.black.withValues(alpha: 0.8),
                              child: SpectrumChart(
                                data: _buildChartDisplayData(_isZeroSpan
                                    ? _zeroSpanData
                                    : _spectrumData),
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
                                referenceData: _agentReferenceSpectrumData,
                                referenceLabel: _agentReferenceSpectrumLabel,
                                limitLines: _agentSpectrumLimitLines,
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
                        ResizablePanelDivider(
                          onDragDelta: _resizeSettingsPanel,
                          tooltip: '拖动调整仪器工具栏宽度',
                        ),
                        Container(
                          width: _settingsPanelWidth,
                          color: const Color.fromARGB(255, 66, 66, 66),
                          padding: const EdgeInsets.all(8),
                          child: SingleChildScrollView(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                Expander(
                                  initiallyExpanded: true,
                                  header: const Text('频率'),
                                  content: Column(
                                    children: [
                                      _buildInputRow(
                                          label: '起始频率：',
                                          controller: startFreqController,
                                          unitNotifier: startFreqUnit,
                                          units: freqUnits,
                                          enabled:
                                              _isFrequencySweepConfigActive,
                                          onChanged: () =>
                                              _lastFrequencyEditMode =
                                                  FrequencyEditMode.startStop,
                                          onUnitChanged: () =>
                                              _handleFrequencyUnitChanged(
                                                  _updateFreqFromStartStop),
                                          onSubmitted:
                                              _updateFreqFromStartStop),
                                      const SizedBox(height: 8),
                                      _buildInputRow(
                                          label: '终止频率：',
                                          controller: stopFreqController,
                                          unitNotifier: stopFreqUnit,
                                          units: freqUnits,
                                          enabled:
                                              _isFrequencySweepConfigActive,
                                          onChanged: () =>
                                              _lastFrequencyEditMode =
                                                  FrequencyEditMode.startStop,
                                          onUnitChanged: () =>
                                              _handleFrequencyUnitChanged(
                                                  _updateFreqFromStartStop),
                                          onSubmitted:
                                              _updateFreqFromStartStop),
                                      const SizedBox(height: 8),
                                      _buildInputRow(
                                          label: '中心频率：',
                                          controller: centerFreqController,
                                          unitNotifier: centerFreqUnit,
                                          units: freqUnits,
                                          enabled:
                                              _isFrequencySweepConfigActive,
                                          onChanged: () =>
                                              _lastFrequencyEditMode =
                                                  FrequencyEditMode.centerSpan,
                                          onUnitChanged: () =>
                                              _handleFrequencyUnitChanged(
                                                  _updateFreqFromCenterSpan),
                                          onSubmitted:
                                              _updateFreqFromCenterSpan),
                                      const SizedBox(height: 8),
                                      _buildInputRow(
                                          label: '扫描宽度：',
                                          controller: spanController,
                                          unitNotifier: spanUnit,
                                          units: freqUnits,
                                          enabled:
                                              _isFrequencySweepConfigActive,
                                          onChanged: () =>
                                              _lastFrequencyEditMode =
                                                  FrequencyEditMode.centerSpan,
                                          onUnitChanged: () =>
                                              _handleFrequencyUnitChanged(
                                                  _updateFreqFromCenterSpan),
                                          onSubmitted:
                                              _updateFreqFromCenterSpan),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          Expanded(
                                            child: Button(
                                              onPressed:
                                                  _isFrequencySweepConfigActive
                                                      ? _setFullSpan
                                                      : null,
                                              child: const Text('FULL SPAN'),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Button(
                                              onPressed:
                                                  _isFrequencySweepConfigActive
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
                                  initiallyExpanded: true,
                                  header: const Text('幅度'),
                                  content: Column(
                                    children: [
                                      Row(
                                        children: [
                                          const SizedBox(
                                              width: 100,
                                              child: Text('参考电平：',
                                                  style: TextStyle(
                                                      color: material
                                                          .Colors.white))),
                                          Expanded(
                                              child: TextBox(
                                                  controller:
                                                      refLevelController,
                                                  onSubmitted: (v) =>
                                                      _sendAmplitudeConfig())),
                                          const SizedBox(width: 8),
                                          SizedBox(
                                            width: 44,
                                            child: Button(
                                              onPressed: () =>
                                                  _stepRefLevel(-10.0),
                                              child: const Text('-'),
                                            ),
                                          ),
                                          const SizedBox(width: 4),
                                          SizedBox(
                                            width: 44,
                                            child: Button(
                                              onPressed: () =>
                                                  _stepRefLevel(10.0),
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
                                  initiallyExpanded: true,
                                  header: const Text('BW'),
                                  content: Column(
                                    children: [
                                      Row(
                                        children: [
                                          const SizedBox(
                                              width: 100,
                                              child: Text('RBW模式：',
                                                  style: TextStyle(
                                                      color: material
                                                          .Colors.white))),
                                          Expanded(
                                            child:
                                                ValueListenableBuilder<String>(
                                              valueListenable: rbwMode,
                                              builder:
                                                  (context, value, child) =>
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
                                                    .map((o) =>
                                                        ComboBoxItem<String>(
                                                            value: o,
                                                            child: Text(o)))
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
                                                      color: material
                                                          .Colors.white))),
                                          Expanded(
                                            child:
                                                ValueListenableBuilder<String>(
                                              valueListenable: vbwMode,
                                              builder:
                                                  (context, value, child) =>
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
                                                    .map((o) =>
                                                        ComboBoxItem<String>(
                                                            value: o,
                                                            child: Text(o)))
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
                                            onSubmitted: isEnabled
                                                ? _submitBandwidthConfig
                                                : null,
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
                                                      color: material
                                                          .Colors.white))),
                                          Expanded(
                                            child:
                                                ValueListenableBuilder<String>(
                                              valueListenable: detectMode,
                                              builder:
                                                  (context, value, child) =>
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
                                                    .map((o) =>
                                                        ComboBoxItem<String>(
                                                            value: o,
                                                            child: Text(o)))
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
                                                        color: material
                                                            .Colors.white))),
                                            ToggleSwitch(
                                              checked: value,
                                              onChanged: (v) => setState(() =>
                                                  autoPeakEnabled.value = v),
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
                                                      color: material
                                                          .Colors.white))),
                                          Expanded(
                                            child: ComboBox<int?>(
                                              value: _currentMarker?.id,
                                              isExpanded: true,
                                              items: _markers
                                                  .map((m) =>
                                                      ComboBoxItem<int?>(
                                                          value: m.id,
                                                          child: Text(
                                                              '游标 ${m.id}')))
                                                  .toList(),
                                              placeholder: const Text('无'),
                                              onChanged: (id) {
                                                if (id == null) {
                                                  _selectMarker(null);
                                                } else {
                                                  _selectMarker(
                                                      _markers.firstWhere(
                                                          (m) => m.id == id));
                                                }
                                              },
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          if (_currentMarker != null) ...[
                                            Row(
                                              mainAxisAlignment:
                                                  MainAxisAlignment.end,
                                              children: [
                                                ToggleSwitch(
                                                  checked:
                                                      _currentMarker!.enabled,
                                                  onChanged: (v) => setState(
                                                      () => _currentMarker!
                                                          .enabled = v),
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
                                          final bool manualEnabled =
                                              !autoEnabled;
                                          return Row(
                                            children: [
                                              const SizedBox(
                                                  width: 100,
                                                  child: Text('游标操作：',
                                                      style: TextStyle(
                                                          color: material
                                                              .Colors.white))),
                                              Expanded(
                                                child: ComboBox<String>(
                                                  placeholder:
                                                      const Text('选择操作'),
                                                  isExpanded: true,
                                                  items: [
                                                    '向左寻峰',
                                                    '向右寻峰',
                                                    '起始点',
                                                    '结束点',
                                                    '中间点'
                                                  ]
                                                      .map((o) =>
                                                          ComboBoxItem<String>(
                                                              value: o,
                                                              child: Text(o)))
                                                      .toList(),
                                                  onChanged: manualEnabled
                                                      ? (action) {
                                                          if (action == null ||
                                                              _currentMarker ==
                                                                  null) {
                                                            return;
                                                          }
                                                          double newFreq =
                                                              _currentMarker!
                                                                  .freqHz;
                                                          switch (action) {
                                                            case '起始点':
                                                              newFreq =
                                                                  _chartStartHz;
                                                              break;
                                                            case '结束点':
                                                              newFreq =
                                                                  _chartStopHz;
                                                              break;
                                                            case '向左寻峰':
                                                              newFreq = _findLeftPeak(
                                                                  _currentMarker!
                                                                      .freqHz);
                                                              break;
                                                            case '向右寻峰':
                                                              newFreq = _findRightPeak(
                                                                  _currentMarker!
                                                                      .freqHz);
                                                              break;
                                                            case '中间点':
                                                              newFreq =
                                                                  (_chartStartHz +
                                                                          _chartStopHz) /
                                                                      2.0;
                                                              break;
                                                          }
                                                          _currentMarker!
                                                              .freqHz = newFreq;
                                                          _markerFreqController
                                                                  .text =
                                                              _formatFreqInput(
                                                                  newFreq,
                                                                  _markerFreqUnit
                                                                      .value);
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
                                          final bool manualEnabled =
                                              !autoEnabled;
                                          return _buildInputRow(
                                            label: '游标频点：',
                                            controller: _markerFreqController,
                                            unitNotifier: _markerFreqUnit,
                                            units: freqUnits,
                                            enabled: manualEnabled,
                                            onSubmitted: manualEnabled
                                                ? () {
                                                    final double? parsed =
                                                        _parseFreq(
                                                            _markerFreqController
                                                                .text,
                                                            _markerFreqUnit
                                                                .value);
                                                    if (parsed != null &&
                                                        _currentMarker !=
                                                            null) {
                                                      _currentMarker!.freqHz =
                                                          parsed;
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
                                const Expander(
                                    header: Text('系统'), content: Placeholder()),
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
                                                      color: material
                                                          .Colors.white))),
                                          Expanded(
                                            child: TextBox(
                                              controller: pointCountController,
                                              enabled: !isDirectIfFft,
                                              onSubmitted: (value) {
                                                pointCountController.text =
                                                    (_getCurrentPointCount())
                                                        .toString();
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
                                                      color: material
                                                          .Colors.white))),
                                          Expanded(
                                            child: TextBox(
                                              controller:
                                                  scalePerGridController,
                                              onChanged: (value) =>
                                                  setState(() {}),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          const Text('dB',
                                              style: TextStyle(
                                                  color:
                                                      material.Colors.white)),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          const SizedBox(
                                              width: 100,
                                              child: Text('曲线平滑:',
                                                  style: TextStyle(
                                                      color: material
                                                          .Colors.white))),
                                          ToggleSwitch(
                                            checked: _traceSmoothingEnabled,
                                            onChanged: (value) => setState(() =>
                                                _traceSmoothingEnabled = value),
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
                                                      color: material
                                                          .Colors.white))),
                                          ToggleSwitch(
                                            checked: _phaseNoiseDisplayEnabled,
                                            onChanged: (value) => setState(() =>
                                                _phaseNoiseDisplayEnabled =
                                                    value),
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
                                                      color: material
                                                          .Colors.white))),
                                          Expanded(
                                            child: TextBox(
                                              controller:
                                                  _phaseNoiseDisplayThresholdController,
                                              onChanged: (value) =>
                                                  setState(() {}),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          const Text('dBm',
                                              style: TextStyle(
                                                  color:
                                                      material.Colors.white)),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          const SizedBox(
                                              width: 100,
                                              child: Text('修正值:',
                                                  style: TextStyle(
                                                      color: material
                                                          .Colors.white))),
                                          Expanded(
                                            child: TextBox(
                                              controller:
                                                  _phaseNoiseDisplayOffsetController,
                                              onChanged: (value) =>
                                                  setState(() {}),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          const Text('dB',
                                              style: TextStyle(
                                                  color:
                                                      material.Colors.white)),
                                        ],
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          const SizedBox(
                                              width: 100,
                                              child: Text('固定频点补偿:',
                                                  style: TextStyle(
                                                      color: material
                                                          .Colors.white))),
                                          ToggleSwitch(
                                            checked:
                                                _fixedFrequencyCompensationEnabled,
                                            onChanged:
                                                _setFixedFrequencyCompensationEnabled,
                                          ),
                                        ],
                                      ),
                                      const SizedBox(height: 4),
                                      const Text(
                                        '79.5 / 80 / 80.5 MHz，1.13 / 1.17 GHz\n'
                                        'RBW 300 kHz：增加 79.85 / 80.15 MHz',
                                        style: TextStyle(
                                            color: material.Colors.white54,
                                            fontSize: 11),
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
                ),
                if (_aiAssistantVisible)
                  ResizablePanelDivider(
                    onDragDelta: _resizeAiPanel,
                    tooltip: '拖动调整 AI 面板宽度',
                  ),
                Visibility(
                  visible: _aiAssistantVisible,
                  maintainState: true,
                  maintainAnimation: true,
                  maintainSize: false,
                  child: SizedBox(
                    width: _aiPanelWidth,
                    child: AiAssistantPanel(
                      key: _aiAssistantKey,
                      onClose: _closeAiAssistant,
                      onListeningChanged: _handleAiListeningChanged,
                      instrumentAgent: _instrumentAgentGateway,
                    ),
                  ),
                ),
              ],
            ),
            bottomBar: _buildBottomBar(),
          ),
        ),
        if (Platform.isWindows)
          const Positioned(
            top: 0,
            right: 0,
            width: WindowsTitleBar.controlsWidth,
            height: 64,
            child: WindowsWindowControls(),
          ),
      ],
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
              _bottomProfileStatusText(),
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
          width: 88,
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

  Widget _buildRfFrontendPanel({
    bool showPath = true,
    bool attenuationLabelTogglesPhaseNoiseDisplay = true,
  }) {
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
        if (showPath) ...[
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
        ],
        const SizedBox(height: 8),
        Row(
          children: [
            SizedBox(
              width: 100,
              child: attenuationLabelTogglesPhaseNoiseDisplay
                  ? Semantics(
                      button: true,
                      toggled: _phaseNoiseDisplayEnabled,
                      label: '衰减修正',
                      child: MouseRegion(
                        cursor: material.SystemMouseCursors.click,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: () => setState(() {
                            _phaseNoiseDisplayEnabled =
                                !_phaseNoiseDisplayEnabled;
                          }),
                          child: const Text(
                            '衰减：',
                            style: TextStyle(color: material.Colors.white),
                          ),
                        ),
                      ),
                    )
                  : const Text(
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
