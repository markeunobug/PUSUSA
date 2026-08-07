import 'dart:async';

enum InstrumentAgentMode { chat, assisted, agent }

extension InstrumentAgentModeLabel on InstrumentAgentMode {
  String get label => switch (this) {
        InstrumentAgentMode.chat => '问答',
        InstrumentAgentMode.assisted => '辅助',
        InstrumentAgentMode.agent => 'Agent',
      };

  String get description => switch (this) {
        InstrumentAgentMode.chat => '只回答问题，不允许操作仪器',
        InstrumentAgentMode.assisted => '每批配置操作都需要确认',
        InstrumentAgentMode.agent => '自动执行工具计划，无需逐批确认',
      };
}

class InstrumentAgentSnapshot {
  const InstrumentAgentSnapshot({
    required this.connected,
    required this.deviceResponsive,
    required this.measurementMode,
    required this.startHz,
    required this.stopHz,
    required this.rbwHz,
    required this.vbwMode,
    required this.vbwHz,
    required this.detector,
    required this.referenceDbm,
    required this.pointCount,
    required this.sweepRunning,
    required this.continuousSweep,
    required this.minimumFrequencyHz,
    required this.maximumFrequencyHz,
    this.modeDetails = const <String, dynamic>{},
  });

  final bool connected;
  final bool deviceResponsive;
  final String measurementMode;
  final double startHz;
  final double stopHz;
  final double rbwHz;
  final String vbwMode;
  final double vbwHz;
  final String detector;
  final double referenceDbm;
  final int pointCount;
  final bool sweepRunning;
  final bool continuousSweep;
  final double minimumFrequencyHz;
  final double maximumFrequencyHz;
  final Map<String, dynamic> modeDetails;

  double get centerHz => (startHz + stopHz) / 2.0;
  double get spanHz => stopHz - startHz;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'connected': connected,
        'device_responsive': deviceResponsive,
        'measurement_mode': measurementMode,
        'frequency': <String, dynamic>{
          'start_hz': startHz,
          'stop_hz': stopHz,
          'center_hz': centerHz,
          'span_hz': spanHz,
          'minimum_hz': minimumFrequencyHz,
          'maximum_hz': maximumFrequencyHz,
        },
        'bandwidth': <String, dynamic>{
          'rbw_hz': rbwHz,
          'vbw_mode': vbwMode,
          'vbw_hz': vbwHz,
        },
        'detector': detector,
        'reference_dbm': referenceDbm,
        'point_count': pointCount,
        'sweep_running': sweepRunning,
        'continuous_sweep': continuousSweep,
        'mode_details': modeDetails,
      };
}

class InstrumentToolCall {
  const InstrumentToolCall({
    required this.id,
    required this.name,
    required this.arguments,
  });

  final String id;
  final String name;
  final Map<String, dynamic> arguments;
}

class InstrumentActionOutcome {
  const InstrumentActionOutcome({
    required this.success,
    required this.message,
    this.data = const <String, dynamic>{},
  });

  final bool success;
  final String message;
  final Map<String, dynamic> data;
}

class InstrumentToolResult {
  const InstrumentToolResult({
    required this.callId,
    required this.toolName,
    required this.success,
    required this.message,
    required this.data,
  });

  final String callId;
  final String toolName;
  final bool success;
  final String message;
  final Map<String, dynamic> data;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'success': success,
        'message': message,
        'data': data,
      };
}

typedef InstrumentSnapshotProvider = InstrumentAgentSnapshot Function();
typedef SetFrequencyAction = Future<InstrumentActionOutcome> Function(
  double centerHz,
  double spanHz,
);
typedef SetBandwidthAction = Future<InstrumentActionOutcome> Function(
  double rbwHz,
  String vbwMode,
  double? vbwHz,
);
typedef SetDetectorAction = Future<InstrumentActionOutcome> Function(
  String detector,
);
typedef SetMeasurementModeAction = Future<InstrumentActionOutcome> Function(
  String mode,
);
typedef StartPhaseNoiseMeasurementAction = Future<InstrumentActionOutcome>
    Function(bool continuous, bool waitForCarrier);
typedef ConfigurePhaseNoiseAction = Future<InstrumentActionOutcome> Function(
  Map<String, dynamic> arguments,
);
typedef AnalyzePhaseNoiseAction = Future<InstrumentActionOutcome> Function(
  String trace,
  double offsetHz,
  int waitTimeoutMs,
);
typedef StartRealtimeSpectrumAction = Future<InstrumentActionOutcome> Function(
  double centerHz,
);
typedef SimpleInstrumentAction = Future<InstrumentActionOutcome> Function();
typedef SpectrumSnapshotAction = Future<InstrumentActionOutcome> Function(
  int maximumPoints,
);
typedef AnalyzeSpectrumAction = Future<InstrumentActionOutcome> Function(
  int peakCount,
  double thresholdAboveNoiseDb,
);
typedef GetRealtimeSpectrumStateAction = Future<InstrumentActionOutcome>
    Function();
typedef ConfigureRealtimeSpectrumAction = Future<InstrumentActionOutcome>
    Function(Map<String, dynamic> arguments);
typedef RealtimeSpectrumSnapshotAction = Future<InstrumentActionOutcome>
    Function(String trace, int maximumPoints);
typedef RealtimeSpectrumWaterfallHistoryAction = Future<InstrumentActionOutcome>
    Function(
  int maximumRows,
  double? lookbackSeconds,
  int maximumPointsPerRow,
);
typedef AnalyzeRealtimeSpectrumAction = Future<InstrumentActionOutcome>
    Function(
  String trace,
  int peakCount,
  double thresholdAboveNoiseDb,
);
typedef SaveMeasurementAction = Future<InstrumentActionOutcome> Function(
  String label,
  String note,
);
typedef SaveRealtimeMeasurementAction = Future<InstrumentActionOutcome>
    Function(
  String label,
  String note,
  String trace,
  bool includeWaterfall,
  int waterfallRows,
);
typedef CaptureScreenshotAction = Future<InstrumentActionOutcome> Function();
typedef GetTestSessionAction = Future<InstrumentActionOutcome> Function();
typedef StartTestSessionAction = Future<InstrumentActionOutcome> Function(
  String name,
  String objective,
);
typedef AddTestNoteAction = Future<InstrumentActionOutcome> Function(
  String note,
);
typedef EndTestSessionAction = Future<InstrumentActionOutcome> Function(
  String summary,
);
typedef ListTestSessionsAction = Future<InstrumentActionOutcome> Function(
  int limit,
);
typedef ListMeasurementsAction = Future<InstrumentActionOutcome> Function(
  int limit,
);
typedef LoadMeasurementAction = Future<InstrumentActionOutcome> Function(
  String measurementId,
);
typedef CompareMeasurementsAction = Future<InstrumentActionOutcome> Function(
  String firstMeasurementId,
  String secondMeasurementId,
);
typedef EvaluateSpectrumLimitsAction = Future<InstrumentActionOutcome> Function(
  double? maximumNoiseFloorDbm,
  double? minimumMainPeakDbm,
  double? minimumSpurSuppressionDb,
);
typedef ExportTestReportAction = Future<InstrumentActionOutcome> Function(
  String sessionId,
);

class InstrumentAgentGateway {
  InstrumentAgentGateway({
    required InstrumentSnapshotProvider snapshotProvider,
    required SetFrequencyAction setFrequency,
    required SetBandwidthAction setBandwidth,
    required SetDetectorAction setDetector,
    required SetMeasurementModeAction setMeasurementMode,
    required SimpleInstrumentAction startSingleSweep,
    required SimpleInstrumentAction startContinuousSweep,
    required SimpleInstrumentAction stopMeasurement,
    required StartPhaseNoiseMeasurementAction startPhaseNoiseMeasurement,
    required SimpleInstrumentAction stopPhaseNoiseMeasurement,
    required SimpleInstrumentAction getPhaseNoiseState,
    required ConfigurePhaseNoiseAction configurePhaseNoise,
    required AnalyzePhaseNoiseAction analyzePhaseNoise,
    required StartRealtimeSpectrumAction startRealtimeSpectrum,
    required SimpleInstrumentAction stopRealtimeSpectrum,
    required SpectrumSnapshotAction getSpectrumSnapshot,
    required AnalyzeSpectrumAction analyzeSpectrum,
    required AnalyzeSpectrumAction placePeakMarkers,
    required GetRealtimeSpectrumStateAction getRealtimeSpectrumState,
    required ConfigureRealtimeSpectrumAction configureRealtimeSpectrum,
    required RealtimeSpectrumSnapshotAction getRealtimeSpectrumSnapshot,
    required RealtimeSpectrumWaterfallHistoryAction getRealtimeWaterfallHistory,
    required AnalyzeRealtimeSpectrumAction analyzeRealtimeSpectrum,
    required AnalyzeRealtimeSpectrumAction placeRealtimePeakMarkers,
    required SaveMeasurementAction saveMeasurement,
    required SaveRealtimeMeasurementAction saveRealtimeMeasurement,
    required CaptureScreenshotAction captureScreenshot,
    required GetTestSessionAction getTestSession,
    required StartTestSessionAction startTestSession,
    required AddTestNoteAction addTestNote,
    required EndTestSessionAction endTestSession,
    required ListTestSessionsAction listTestSessions,
    required ListMeasurementsAction listMeasurements,
    required LoadMeasurementAction loadMeasurement,
    required CompareMeasurementsAction compareMeasurements,
    required EvaluateSpectrumLimitsAction evaluateSpectrumLimits,
    required SimpleInstrumentAction clearAnalysisOverlays,
    required ExportTestReportAction exportTestReport,
  })  : _snapshotProvider = snapshotProvider,
        _setFrequency = setFrequency,
        _setBandwidth = setBandwidth,
        _setDetector = setDetector,
        _setMeasurementMode = setMeasurementMode,
        _startSingleSweep = startSingleSweep,
        _startContinuousSweep = startContinuousSweep,
        _stopMeasurement = stopMeasurement,
        _startPhaseNoiseMeasurement = startPhaseNoiseMeasurement,
        _stopPhaseNoiseMeasurement = stopPhaseNoiseMeasurement,
        _getPhaseNoiseState = getPhaseNoiseState,
        _configurePhaseNoise = configurePhaseNoise,
        _analyzePhaseNoise = analyzePhaseNoise,
        _startRealtimeSpectrum = startRealtimeSpectrum,
        _stopRealtimeSpectrum = stopRealtimeSpectrum,
        _getSpectrumSnapshot = getSpectrumSnapshot,
        _analyzeSpectrum = analyzeSpectrum,
        _placePeakMarkers = placePeakMarkers,
        _getRealtimeSpectrumState = getRealtimeSpectrumState,
        _configureRealtimeSpectrum = configureRealtimeSpectrum,
        _getRealtimeSpectrumSnapshot = getRealtimeSpectrumSnapshot,
        _getRealtimeWaterfallHistory = getRealtimeWaterfallHistory,
        _analyzeRealtimeSpectrum = analyzeRealtimeSpectrum,
        _placeRealtimePeakMarkers = placeRealtimePeakMarkers,
        _saveMeasurement = saveMeasurement,
        _saveRealtimeMeasurement = saveRealtimeMeasurement,
        _captureScreenshot = captureScreenshot,
        _getTestSession = getTestSession,
        _startTestSession = startTestSession,
        _addTestNote = addTestNote,
        _endTestSession = endTestSession,
        _listTestSessions = listTestSessions,
        _listMeasurements = listMeasurements,
        _loadMeasurement = loadMeasurement,
        _compareMeasurements = compareMeasurements,
        _evaluateSpectrumLimits = evaluateSpectrumLimits,
        _clearAnalysisOverlays = clearAnalysisOverlays,
        _exportTestReport = exportTestReport;

  static const List<double> supportedRbwHz = <double>[
    1e3,
    10e3,
    30e3,
    100e3,
    300e3,
    1e6,
  ];

  static const List<String> supportedDetectors = <String>[
    'average',
    'sample',
    'positive_peak',
    'negative_peak',
    'maximum_power',
    'rms',
  ];

  final InstrumentSnapshotProvider _snapshotProvider;
  final SetFrequencyAction _setFrequency;
  final SetBandwidthAction _setBandwidth;
  final SetDetectorAction _setDetector;
  final SetMeasurementModeAction _setMeasurementMode;
  final SimpleInstrumentAction _startSingleSweep;
  final SimpleInstrumentAction _startContinuousSweep;
  final SimpleInstrumentAction _stopMeasurement;
  final StartPhaseNoiseMeasurementAction _startPhaseNoiseMeasurement;
  final SimpleInstrumentAction _stopPhaseNoiseMeasurement;
  final SimpleInstrumentAction _getPhaseNoiseState;
  final ConfigurePhaseNoiseAction _configurePhaseNoise;
  final AnalyzePhaseNoiseAction _analyzePhaseNoise;
  final StartRealtimeSpectrumAction _startRealtimeSpectrum;
  final SimpleInstrumentAction _stopRealtimeSpectrum;
  final SpectrumSnapshotAction _getSpectrumSnapshot;
  final AnalyzeSpectrumAction _analyzeSpectrum;
  final AnalyzeSpectrumAction _placePeakMarkers;
  final GetRealtimeSpectrumStateAction _getRealtimeSpectrumState;
  final ConfigureRealtimeSpectrumAction _configureRealtimeSpectrum;
  final RealtimeSpectrumSnapshotAction _getRealtimeSpectrumSnapshot;
  final RealtimeSpectrumWaterfallHistoryAction _getRealtimeWaterfallHistory;
  final AnalyzeRealtimeSpectrumAction _analyzeRealtimeSpectrum;
  final AnalyzeRealtimeSpectrumAction _placeRealtimePeakMarkers;
  final SaveMeasurementAction _saveMeasurement;
  final SaveRealtimeMeasurementAction _saveRealtimeMeasurement;
  final CaptureScreenshotAction _captureScreenshot;
  final GetTestSessionAction _getTestSession;
  final StartTestSessionAction _startTestSession;
  final AddTestNoteAction _addTestNote;
  final EndTestSessionAction _endTestSession;
  final ListTestSessionsAction _listTestSessions;
  final ListMeasurementsAction _listMeasurements;
  final LoadMeasurementAction _loadMeasurement;
  final CompareMeasurementsAction _compareMeasurements;
  final EvaluateSpectrumLimitsAction _evaluateSpectrumLimits;
  final SimpleInstrumentAction _clearAnalysisOverlays;
  final ExportTestReportAction _exportTestReport;

  bool _commandInFlight = false;

  InstrumentAgentSnapshot get snapshot => _snapshotProvider();

  List<Map<String, dynamic>> get toolDefinitions {
    final definitions = <Map<String, dynamic>>[
      _functionTool(
        name: 'get_instrument_state',
        description: '读取当前顶部工具栏测量模式及该模式的专用状态。三个模式彼此独立。',
        properties: const <String, dynamic>{},
      ),
      _functionTool(
        name: 'set_measurement_mode',
        description: '切换顶部工具栏测量模式，只切换功能页面，不等同于启动测量。'
            'spectrum 是标准扫频 dBm 曲线；phase_noise 是载波相位噪声 dBc/Hz；'
            'realtime_spectrum 是固定 10 MHz Span、FFT 4096、瀑布图的实时 IF 频谱。',
        properties: <String, dynamic>{
          'mode': <String, dynamic>{
            'type': 'string',
            'enum': <String>[
              'spectrum',
              'phase_noise',
              'realtime_spectrum',
            ],
          },
        },
        required: const <String>['mode'],
      ),
      _functionTool(
        name: 'set_frequency',
        description: '设置标准频谱模式的中心频率和扫宽。单位必须为 Hz。',
        properties: <String, dynamic>{
          'center_hz': <String, dynamic>{
            'type': 'number',
            'description': '中心频率，单位 Hz',
          },
          'span_hz': <String, dynamic>{
            'type': 'number',
            'description': '扫宽，单位 Hz，必须大于等于 0',
          },
        },
        required: const <String>['center_hz', 'span_hz'],
      ),
      _functionTool(
        name: 'set_bandwidth',
        description: '设置 RBW 和 VBW。RBW 只允许 1k/10k/30k/100k/300k/1M Hz。',
        properties: <String, dynamic>{
          'rbw_hz': <String, dynamic>{
            'type': 'number',
            'enum': supportedRbwHz,
            'description': '分辨率带宽，单位 Hz',
          },
          'vbw_mode': <String, dynamic>{
            'type': 'string',
            'enum': <String>[
              'follow_rbw',
              'manual',
              'rbw_x_0_1',
              'rbw_x_0_01',
              'rbw_x_10',
            ],
          },
          'vbw_hz': <String, dynamic>{
            'type': 'number',
            'description': '仅 manual 模式需要，单位 Hz',
          },
        },
        required: const <String>['rbw_hz', 'vbw_mode'],
      ),
      _functionTool(
        name: 'set_detector',
        description: '设置频谱检波方式。',
        properties: <String, dynamic>{
          'detector': <String, dynamic>{
            'type': 'string',
            'enum': supportedDetectors,
          },
        },
        required: const <String>['detector'],
      ),
      _functionTool(
        name: 'start_single_sweep',
        description: '仅在 spectrum 标准频谱模式中，应用当前配置并执行一次单次扫频。'
            '工具返回成功时整次扫描已经完成，随后可以立即调用 analyze_spectrum 或 get_spectrum_snapshot。'
            '不是实时频谱。',
        properties: const <String, dynamic>{},
      ),
      _functionTool(
        name: 'start_continuous_sweep',
        description: '仅在 spectrum 标准频谱模式中，周期执行传统扫频。不是 realtime_spectrum。',
        properties: const <String, dynamic>{},
      ),
      _functionTool(
        name: 'start_phase_noise_measurement',
        description: '仅在 phase_noise 模式中启动相位噪声测量，纵轴单位为 dBc/Hz。'
            '成功返回只表示测量已启动；扫频和平均在设备后台继续，不等待整次测量完成。',
        properties: <String, dynamic>{
          'continuous': <String, dynamic>{
            'type': 'boolean',
            'description': 'true 连续平均测量，false 单次测量；默认 true',
          },
          'wait_for_carrier': <String, dynamic>{
            'type': 'boolean',
            'description': '仅用于立即检测载波；耗时相位噪声测量、配置或单纯启动时必须为 false',
          },
        },
      ),
      _functionTool(
        name: 'stop_phase_noise_measurement',
        description: '停止 phase_noise 相位噪声测量。',
        properties: const <String, dynamic>{},
      ),
      _functionTool(
        name: 'get_phase_noise_state',
        description: '读取 phase_noise 页面配置、载波检测状态、测量进度和错误状态，不读取普通频谱。'
            '耗时测量中每个用户回合最多调用一次；仍在运行时直接向用户报告进度，不要连续轮询。',
        properties: const <String, dynamic>{},
      ),
      _functionTool(
        name: 'configure_phase_noise',
        description: '配置 phase_noise 页面。用于设置载波目标、搜索范围、最低载波电平、频偏范围、点密度和平均次数。'
            '配置只更新页面参数；启动时由 start_phase_noise_measurement 通过设备 ACK 应用。',
        properties: <String, dynamic>{
          'carrier_mode': <String, dynamic>{
            'type': 'string',
            'enum': <String>['auto', 'manual'],
          },
          'carrier_hz': <String, dynamic>{
            'type': 'number',
            'minimum': 50e6,
            'maximum': 1.5e9,
            'description': '目标载波频率，单位 Hz。指定频率时通常同时设 carrier_mode=manual',
          },
          'carrier_search_span_hz': <String, dynamic>{
            'type': 'number',
            'minimum': 1,
            'maximum': 100e6,
          },
          'minimum_carrier_level_dbm': <String, dynamic>{
            'type': 'number',
            'minimum': -140,
            'maximum': 30,
          },
          'start_offset_hz': <String, dynamic>{
            'type': 'number',
            'minimum': 1e3,
            'maximum': 100e6,
            'description': '起始载波频偏，最小 1 kHz',
          },
          'stop_offset_hz': <String, dynamic>{
            'type': 'number',
            'minimum': 1e3,
            'maximum': 100e6,
          },
          'density': <String, dynamic>{
            'type': 'string',
            'enum': <String>['fast', 'normal', 'fine'],
          },
          'average_count': <String, dynamic>{
            'type': 'integer',
            'minimum': 1,
            'maximum': 1000,
          },
          'trace_display': <String, dynamic>{
            'type': 'string',
            'enum': <String>['raw', 'average', 'both'],
          },
        },
      ),
      _functionTool(
        name: 'analyze_phase_noise',
        description: '读取 phase_noise 测量结果在指定频偏处的相位噪声，单位 dBc/Hz。'
            '长测量必须先确认 complete=true，再读取已有数据；若未检测到载波则立即返回无信号。',
        properties: <String, dynamic>{
          'offset_hz': <String, dynamic>{
            'type': 'number',
            'minimum': 1e3,
            'maximum': 100e6,
            'description': '需要分析的载波频偏，单位 Hz，最小 1 kHz',
          },
          'trace': <String, dynamic>{
            'type': 'string',
            'enum': <String>['auto', 'raw', 'average'],
            'description': '默认 auto，优先平均曲线，无平均数据时使用原始曲线',
          },
          'wait_timeout_ms': <String, dynamic>{
            'type': 'integer',
            'minimum': 0,
            'maximum': 30000,
            'description': '等待指定频偏数据的最长时间，默认 0 ms。长测量必须使用 0，禁止靠此参数等待整次测量',
          },
        },
        required: const <String>['offset_hz'],
      ),
      _functionTool(
        name: 'start_realtime_spectrum',
        description: '仅在 realtime_spectrum 模式中配置中心频率并启动实时 IF FFT。'
            '该模式固定 10 MHz Span、FFT 4096，包含 latest/average/max-hold/waterfall。',
        properties: <String, dynamic>{
          'center_hz': <String, dynamic>{
            'type': 'number',
            'minimum': 50e6,
            'maximum': 1.5e9,
            'description': '实时频谱中心频率，单位 Hz',
          },
        },
        required: const <String>['center_hz'],
      ),
      _functionTool(
        name: 'stop_realtime_spectrum',
        description: '停止 realtime_spectrum 实时 IF FFT。',
        properties: const <String, dynamic>{},
      ),
      _functionTool(
        name: 'get_realtime_spectrum_state',
        description: '读取 realtime_spectrum 页面独立配置、运行状态、帧统计和 dBFS 显示状态。',
        properties: const <String, dynamic>{},
      ),
      _functionTool(
        name: 'configure_realtime_spectrum',
        description: '配置 realtime_spectrum 页面。固定 Span 10 MHz、FFT 4096，'
            '中心频率、前端和显示参数均独立于标准扫频。运行中修改硬件参数时会执行安全的 STOP/ACK/重启事务。',
        properties: <String, dynamic>{
          'center_hz': <String, dynamic>{
            'type': 'number',
            'minimum': 50e6,
            'maximum': 1.5e9,
            'description': '中心频率，单位 Hz；省略则不修改',
          },
          'average_enabled': <String, dynamic>{'type': 'boolean'},
          'max_hold_enabled': <String, dynamic>{'type': 'boolean'},
          'marker_enabled': <String, dynamic>{'type': 'boolean'},
          'lna_enabled': <String, dynamic>{'type': 'boolean'},
          'attenuation_db': <String, dynamic>{
            'type': 'number',
            'minimum': 0,
            'maximum': 31.75,
            'description': 'DSA 衰减，单位 dB，步进 0.25 dB',
          },
          'vga_db': <String, dynamic>{
            'type': 'number',
            'enum': <double>[-11, -10, -6, -3, 0, 3, 6, 10, 20, 30, 34],
          },
          'reference_dbfs': <String, dynamic>{
            'type': 'number',
            'minimum': -140,
            'maximum': 0,
          },
          'waterfall_floor_dbfs': <String, dynamic>{
            'type': 'number',
            'minimum': -160,
            'maximum': -10,
          },
          'waterfall_reference_dbfs': <String, dynamic>{
            'type': 'number',
            'minimum': -150,
            'maximum': 0,
          },
          'reset_average': <String, dynamic>{'type': 'boolean'},
          'reset_max_hold': <String, dynamic>{'type': 'boolean'},
        },
      ),
      _functionTool(
        name: 'get_realtime_spectrum_snapshot',
        description: '读取 realtime_spectrum 的 latest、average 或 max_hold dBFS 曲线，'
            '返回保峰降采样点，不会发起新的测量。',
        properties: <String, dynamic>{
          'trace': <String, dynamic>{
            'type': 'string',
            'enum': <String>['latest', 'average', 'max_hold'],
            'description': '默认 latest；average/max_hold 必须先启用并收到数据',
          },
          'maximum_points': <String, dynamic>{
            'type': 'integer',
            'minimum': 16,
            'maximum': 315,
            'description': '最多返回点数，默认 128',
          },
        },
      ),
      _functionTool(
        name: 'get_realtime_waterfall_history',
        description: '读取 realtime_spectrum 最近时间窗口内的瀑布历史行。'
            '返回 newest_first 的 dBFS 矩阵、采集时间、序号和统一频率轴，'
            '不会发起新的测量。默认返回最近 20 行，每行降采样到 64 点。',
        properties: <String, dynamic>{
          'maximum_rows': <String, dynamic>{
            'type': 'integer',
            'minimum': 1,
            'maximum': 60,
            'description': '最多返回多少行，默认 20',
          },
          'lookback_seconds': <String, dynamic>{
            'type': 'number',
            'minimum': 0.1,
            'maximum': 300,
            'description': '只读取最近多少秒内的行；省略表示不按时间过滤',
          },
          'maximum_points_per_row': <String, dynamic>{
            'type': 'integer',
            'minimum': 16,
            'maximum': 128,
            'description': '每行最多返回多少个频率点，默认 64',
          },
        },
      ),
      _functionTool(
        name: 'analyze_realtime_spectrum',
        description: '在本地分析 realtime_spectrum 指定 trace 的 dBFS 噪声底和局部峰值。'
            '不得把结果解释为 dBm。',
        properties: <String, dynamic>{
          'trace': <String, dynamic>{
            'type': 'string',
            'enum': <String>['latest', 'average', 'max_hold'],
          },
          'peak_count': <String, dynamic>{
            'type': 'integer',
            'minimum': 1,
            'maximum': 8,
          },
          'threshold_above_noise_db': <String, dynamic>{
            'type': 'number',
            'minimum': 0,
            'maximum': 100,
          },
        },
      ),
      _functionTool(
        name: 'place_realtime_peak_markers',
        description: '分析 realtime_spectrum 指定 trace，并在实时频谱图上放置峰值 Marker。',
        properties: <String, dynamic>{
          'trace': <String, dynamic>{
            'type': 'string',
            'enum': <String>['latest', 'average', 'max_hold'],
          },
          'peak_count': <String, dynamic>{
            'type': 'integer',
            'minimum': 1,
            'maximum': 8,
          },
          'threshold_above_noise_db': <String, dynamic>{
            'type': 'number',
            'minimum': 0,
            'maximum': 100,
          },
        },
      ),
      _functionTool(
        name: 'stop_measurement',
        description: '停止当前标准频谱扫描。',
        properties: const <String, dynamic>{},
      ),
      _functionTool(
        name: 'get_spectrum_snapshot',
        description: '仅分析 spectrum 标准扫频页面当前已显示的 dBm 数据摘要和降采样点。'
            '不适用于 phase_noise 或 realtime_spectrum，也不会重新发起扫描。',
        properties: <String, dynamic>{
          'maximum_points': <String, dynamic>{
            'type': 'integer',
            'minimum': 16,
            'maximum': 512,
            'description': '最多返回多少个降采样点，默认 128',
          },
        },
      ),
      _functionTool(
        name: 'analyze_spectrum',
        description: '仅对 spectrum 标准扫频 dBm 曲线在本地计算稳健噪声底和最强局部峰值。'
            '不适用于相位噪声或实时 IF FFT。',
        properties: <String, dynamic>{
          'peak_count': <String, dynamic>{
            'type': 'integer',
            'minimum': 1,
            'maximum': 8,
            'description': '返回峰值数量，默认 5',
          },
          'threshold_above_noise_db': <String, dynamic>{
            'type': 'number',
            'minimum': 0,
            'maximum': 100,
            'description': '峰值至少高于噪声底多少 dB，默认 6',
          },
        },
      ),
      _functionTool(
        name: 'place_peak_markers',
        description: '根据本地峰值分析结果，在频谱图上放置并启用 AI Marker。',
        properties: <String, dynamic>{
          'peak_count': <String, dynamic>{
            'type': 'integer',
            'minimum': 1,
            'maximum': 8,
          },
          'threshold_above_noise_db': <String, dynamic>{
            'type': 'number',
            'minimum': 0,
            'maximum': 100,
          },
        },
      ),
      _functionTool(
        name: 'save_measurement',
        description: '仅保存 spectrum 标准扫频 dBm 数据。把当前配置、分析摘要和完整曲线保存为 JSON 与 CSV。'
            '不得用于 phase_noise 或 realtime_spectrum。',
        properties: <String, dynamic>{
          'label': <String, dynamic>{
            'type': 'string',
            'description': '简短测试名称',
          },
          'note': <String, dynamic>{
            'type': 'string',
            'description': '可选测试说明',
          },
        },
        required: const <String>['label'],
      ),
      _functionTool(
        name: 'save_realtime_measurement',
        description: '仅保存 realtime_spectrum 实时频谱数据。'
            '按 dBFS 保存 latest、average 或 max_hold 完整曲线，可选附带最近瀑布历史；'
            '不得调用 save_measurement 代替。',
        properties: <String, dynamic>{
          'label': <String, dynamic>{
            'type': 'string',
            'description': '简短测试名称',
          },
          'note': <String, dynamic>{
            'type': 'string',
            'description': '可选测试说明',
          },
          'trace': <String, dynamic>{
            'type': 'string',
            'enum': <String>['latest', 'average', 'max_hold'],
            'description': '保存的曲线，默认 average',
          },
          'include_waterfall': <String, dynamic>{
            'type': 'boolean',
            'description': '是否把瀑布历史写入 JSON，默认 false',
          },
          'waterfall_rows': <String, dynamic>{
            'type': 'integer',
            'minimum': 1,
            'maximum': 60,
            'description': '附带的最近瀑布行数，默认 20',
          },
        },
        required: const <String>['label'],
      ),
      _functionTool(
        name: 'capture_screenshot',
        description: '截取当前测量页面并保存为 PNG。支持 spectrum、phase_noise 和 '
            'realtime_spectrum 三种模式，使用软件截图目录并自动添加时间戳。',
        properties: const <String, dynamic>{},
      ),
      _functionTool(
        name: 'get_test_session',
        description: '读取当前进行中的测试会话、备注和已保存测量数量。',
        properties: const <String, dynamic>{},
      ),
      _functionTool(
        name: 'start_test_session',
        description: '开始一个新的持久化测试会话。会话用于归档后续测试备注和测量记录。',
        properties: <String, dynamic>{
          'name': <String, dynamic>{
            'type': 'string',
            'description': '简短测试名称',
          },
          'objective': <String, dynamic>{
            'type': 'string',
            'description': '测试目标或验收条件',
          },
        },
        required: const <String>['name'],
      ),
      _functionTool(
        name: 'add_test_note',
        description: '向当前测试会话追加带时间戳的测试备注。',
        properties: <String, dynamic>{
          'note': <String, dynamic>{'type': 'string'},
        },
        required: const <String>['note'],
      ),
      _functionTool(
        name: 'end_test_session',
        description: '结束当前测试会话，可附带最终结论。不会删除任何测量记录。',
        properties: <String, dynamic>{
          'summary': <String, dynamic>{
            'type': 'string',
            'description': '可选的测试结论',
          },
        },
      ),
      _functionTool(
        name: 'list_test_sessions',
        description: '列出最近的测试会话摘要，用于查询历史记录。',
        properties: <String, dynamic>{
          'limit': <String, dynamic>{
            'type': 'integer',
            'minimum': 1,
            'maximum': 50,
          },
        },
      ),
      _functionTool(
        name: 'list_measurements',
        description: '列出最近保存的频谱测量 ID、名称、时间和分析摘要。',
        properties: <String, dynamic>{
          'limit': <String, dynamic>{
            'type': 'integer',
            'minimum': 1,
            'maximum': 100,
          },
        },
      ),
      _functionTool(
        name: 'load_measurement',
        description: '按 measurement_id 加载历史频谱，并作为青色虚线参考曲线显示在当前频谱图上。',
        properties: <String, dynamic>{
          'measurement_id': <String, dynamic>{'type': 'string'},
        },
        required: const <String>['measurement_id'],
      ),
      _functionTool(
        name: 'compare_measurements',
        description:
            '在本地对齐并比较两条频谱。ID 可使用 list_measurements 返回值或 current 代表当前显示曲线。',
        properties: <String, dynamic>{
          'first_measurement_id': <String, dynamic>{'type': 'string'},
          'second_measurement_id': <String, dynamic>{'type': 'string'},
        },
        required: const <String>[
          'first_measurement_id',
          'second_measurement_id',
        ],
      ),
      _functionTool(
        name: 'evaluate_spectrum_limits',
        description: '按给定限值对当前频谱执行本地 Pass/Fail 判定，并在图中显示限值线。至少提供一项条件。',
        properties: <String, dynamic>{
          'maximum_noise_floor_dbm': <String, dynamic>{
            'type': 'number',
            'description': '允许的最高噪声底，实际值必须小于等于该值',
          },
          'minimum_main_peak_dbm': <String, dynamic>{
            'type': 'number',
            'description': '主峰最低功率，实际值必须大于等于该值',
          },
          'minimum_spur_suppression_db': <String, dynamic>{
            'type': 'number',
            'minimum': 0,
            'maximum': 200,
            'description': '主峰相对第二强峰的最小抑制度',
          },
        },
      ),
      _functionTool(
        name: 'clear_analysis_overlays',
        description: '清除 AI 加载的历史参考曲线和限值线，不清除当前实测频谱。',
        properties: const <String, dynamic>{},
      ),
      _functionTool(
        name: 'export_test_report',
        description: '为指定测试会话导出可直接在浏览器打开的 HTML 测试报告。session_id 为空时使用当前会话。',
        properties: <String, dynamic>{
          'session_id': <String, dynamic>{
            'type': 'string',
            'description': '测试会话 ID，可从 list_test_sessions 获取',
          },
        },
      ),
    ];
    final mode = snapshot.measurementMode;
    return definitions.where((definition) {
      final function = definition['function'];
      final name = function is Map ? function['name'] : null;
      if (name == 'save_measurement') return mode == 'spectrum';
      if (name == 'save_realtime_measurement') {
        return mode == 'realtime_spectrum';
      }
      return true;
    }).toList(growable: false);
  }

  bool isReadOnly(String toolName) => <String>{
        'get_instrument_state',
        'get_phase_noise_state',
        'analyze_phase_noise',
        'get_spectrum_snapshot',
        'analyze_spectrum',
        'get_realtime_spectrum_state',
        'get_realtime_spectrum_snapshot',
        'get_realtime_waterfall_history',
        'analyze_realtime_spectrum',
        'get_test_session',
        'list_test_sessions',
        'list_measurements',
        'compare_measurements',
      }.contains(toolName);

  String describeCall(InstrumentToolCall call) {
    switch (call.name) {
      case 'get_instrument_state':
        return '读取仪器当前状态';
      case 'set_measurement_mode':
        return '切换顶部测量模式为 ${call.arguments['mode'] ?? '--'}';
      case 'set_frequency':
        return '设置中心频率 ${_formatHz(_number(call.arguments['center_hz']))}，'
            '扫宽 ${_formatHz(_number(call.arguments['span_hz']))}';
      case 'set_bandwidth':
        final vbwMode = call.arguments['vbw_mode']?.toString() ?? '--';
        return '设置 RBW ${_formatHz(_number(call.arguments['rbw_hz']))}，'
            'VBW $vbwMode';
      case 'set_detector':
        return '设置检波方式为 ${call.arguments['detector'] ?? '--'}';
      case 'start_single_sweep':
        return '启动单次扫描';
      case 'start_continuous_sweep':
        return '启动连续扫描';
      case 'stop_measurement':
        return '停止当前测量';
      case 'start_phase_noise_measurement':
        return '启动${call.arguments['continuous'] == false ? '单次' : '连续'}相位噪声测量';
      case 'stop_phase_noise_measurement':
        return '停止相位噪声测量';
      case 'get_phase_noise_state':
        return '读取相位噪声配置和测量状态';
      case 'configure_phase_noise':
        return '配置相位噪声载波、频偏范围和平均参数';
      case 'analyze_phase_noise':
        return '读取 ${_formatHz(_number(call.arguments['offset_hz']))} 频偏处的相位噪声';
      case 'start_realtime_spectrum':
        return '启动实时频谱，中心频率 '
            '${_formatHz(_number(call.arguments['center_hz']))}';
      case 'stop_realtime_spectrum':
        return '停止实时频谱';
      case 'get_realtime_spectrum_state':
        return '读取实时频谱页面配置和状态';
      case 'configure_realtime_spectrum':
        return '配置实时频谱页面参数';
      case 'get_realtime_spectrum_snapshot':
        return '读取实时频谱 ${call.arguments['trace'] ?? 'latest'} 曲线快照';
      case 'get_realtime_waterfall_history':
        return '读取实时频谱瀑布历史数据';
      case 'analyze_realtime_spectrum':
        return '分析实时频谱 ${call.arguments['trace'] ?? 'latest'} 曲线的 dBFS 噪声底和峰值';
      case 'place_realtime_peak_markers':
        return '在实时频谱图上标记 ${call.arguments['trace'] ?? 'latest'} 曲线峰值';
      case 'save_realtime_measurement':
        return '保存实时频谱 ${call.arguments['trace'] ?? 'average'} dBFS 测量记录';
      case 'capture_screenshot':
        return '截取当前${snapshot.measurementMode}测量页面';
      case 'get_spectrum_snapshot':
        return '读取当前频谱快照';
      case 'analyze_spectrum':
        return '分析当前频谱的噪声底和前 ${_integer(call.arguments['peak_count'], 5)} 个峰值';
      case 'place_peak_markers':
        return '在图上标记前 ${_integer(call.arguments['peak_count'], 5)} 个峰值';
      case 'save_measurement':
        return '保存测试记录“${call.arguments['label'] ?? '未命名测试'}”';
      case 'get_test_session':
        return '读取当前测试会话';
      case 'start_test_session':
        return '开始测试会话“${call.arguments['name'] ?? '未命名测试'}”';
      case 'add_test_note':
        return '向当前测试会话追加备注';
      case 'end_test_session':
        return '结束当前测试会话';
      case 'list_test_sessions':
        return '列出最近 ${_integer(call.arguments['limit'], 20)} 个测试会话';
      case 'list_measurements':
        return '列出最近 ${_integer(call.arguments['limit'], 20)} 条测量记录';
      case 'load_measurement':
        return '加载历史测量 ${call.arguments['measurement_id'] ?? '--'} 作为参考曲线';
      case 'compare_measurements':
        return '对比测量 ${call.arguments['first_measurement_id'] ?? '--'} 与 '
            '${call.arguments['second_measurement_id'] ?? '--'}';
      case 'evaluate_spectrum_limits':
        return '按指定条件执行频谱 Pass/Fail 判定并显示限值线';
      case 'clear_analysis_overlays':
        return '清除历史参考曲线和限值线';
      case 'export_test_report':
        return '导出测试会话 ${call.arguments['session_id'] ?? '当前会话'} 的 HTML 报告';
      default:
        return '未知工具：${call.name}';
    }
  }

  Future<InstrumentToolResult> execute(InstrumentToolCall call) async {
    if (_commandInFlight) {
      return _result(
          call,
          const InstrumentActionOutcome(
            success: false,
            message: '已有仪器命令正在执行，请稍后重试',
          ));
    }

    if (call.name == 'get_instrument_state') {
      final state = snapshot;
      return InstrumentToolResult(
        callId: call.id,
        toolName: call.name,
        success: true,
        message: '已读取仪器状态',
        data: state.toJson(),
      );
    }

    final validation = _validateMutation(call);
    if (validation != null) return _result(call, validation);

    _commandInFlight = true;
    try {
      final outcome = switch (call.name) {
        'set_frequency' => await _setFrequency(
            _number(call.arguments['center_hz'])!,
            _number(call.arguments['span_hz'])!,
          ),
        'set_bandwidth' => await _setBandwidth(
            _number(call.arguments['rbw_hz'])!,
            call.arguments['vbw_mode'].toString(),
            _number(call.arguments['vbw_hz']),
          ),
        'set_detector' =>
          await _setDetector(call.arguments['detector'].toString()),
        'set_measurement_mode' =>
          await _setMeasurementMode(call.arguments['mode'].toString()),
        'start_single_sweep' => await _startSingleSweep(),
        'start_continuous_sweep' => await _startContinuousSweep(),
        'stop_measurement' => await _stopMeasurement(),
        'start_phase_noise_measurement' => await _startPhaseNoiseMeasurement(
            call.arguments['continuous'] != false,
            call.arguments['wait_for_carrier'] == true,
          ),
        'stop_phase_noise_measurement' => await _stopPhaseNoiseMeasurement(),
        'get_phase_noise_state' => await _getPhaseNoiseState(),
        'configure_phase_noise' => await _configurePhaseNoise(call.arguments),
        'analyze_phase_noise' => await _analyzePhaseNoise(
            call.arguments['trace']?.toString() ?? 'auto',
            _number(call.arguments['offset_hz'])!,
            _integer(call.arguments['wait_timeout_ms'], 0),
          ),
        'start_realtime_spectrum' => await _startRealtimeSpectrum(
            _number(call.arguments['center_hz'])!,
          ),
        'stop_realtime_spectrum' => await _stopRealtimeSpectrum(),
        'get_realtime_spectrum_state' => await _getRealtimeSpectrumState(),
        'configure_realtime_spectrum' =>
          await _configureRealtimeSpectrum(call.arguments),
        'get_realtime_spectrum_snapshot' => await _getRealtimeSpectrumSnapshot(
            call.arguments['trace']?.toString() ?? 'latest',
            _integer(call.arguments['maximum_points'], 128),
          ),
        'get_realtime_waterfall_history' => await _getRealtimeWaterfallHistory(
            _integer(call.arguments['maximum_rows'], 20),
            _number(call.arguments['lookback_seconds']),
            _integer(call.arguments['maximum_points_per_row'], 64),
          ),
        'save_realtime_measurement' => await _saveRealtimeMeasurement(
            call.arguments['label']?.toString().trim() ?? '',
            call.arguments['note']?.toString().trim() ?? '',
            call.arguments['trace']?.toString() ?? 'average',
            call.arguments['include_waterfall'] == true,
            _integer(call.arguments['waterfall_rows'], 20),
          ),
        'capture_screenshot' => await _captureScreenshot(),
        'analyze_realtime_spectrum' => await _analyzeRealtimeSpectrum(
            call.arguments['trace']?.toString() ?? 'latest',
            _integer(call.arguments['peak_count'], 5),
            _number(call.arguments['threshold_above_noise_db']) ?? 6,
          ),
        'place_realtime_peak_markers' => await _placeRealtimePeakMarkers(
            call.arguments['trace']?.toString() ?? 'latest',
            _integer(call.arguments['peak_count'], 5),
            _number(call.arguments['threshold_above_noise_db']) ?? 6,
          ),
        'get_spectrum_snapshot' => await _getSpectrumSnapshot(
            _integer(call.arguments['maximum_points'], 128),
          ),
        'analyze_spectrum' => await _analyzeSpectrum(
            _integer(call.arguments['peak_count'], 5),
            _number(call.arguments['threshold_above_noise_db']) ?? 6,
          ),
        'place_peak_markers' => await _placePeakMarkers(
            _integer(call.arguments['peak_count'], 5),
            _number(call.arguments['threshold_above_noise_db']) ?? 6,
          ),
        'save_measurement' => await _saveMeasurement(
            call.arguments['label']?.toString().trim() ?? '',
            call.arguments['note']?.toString().trim() ?? '',
          ),
        'get_test_session' => await _getTestSession(),
        'start_test_session' => await _startTestSession(
            call.arguments['name']?.toString().trim() ?? '',
            call.arguments['objective']?.toString().trim() ?? '',
          ),
        'add_test_note' => await _addTestNote(
            call.arguments['note']?.toString().trim() ?? '',
          ),
        'end_test_session' => await _endTestSession(
            call.arguments['summary']?.toString().trim() ?? '',
          ),
        'list_test_sessions' => await _listTestSessions(
            _integer(call.arguments['limit'], 20),
          ),
        'list_measurements' => await _listMeasurements(
            _integer(call.arguments['limit'], 20),
          ),
        'load_measurement' => await _loadMeasurement(
            call.arguments['measurement_id']?.toString().trim() ?? '',
          ),
        'compare_measurements' => await _compareMeasurements(
            call.arguments['first_measurement_id']?.toString().trim() ?? '',
            call.arguments['second_measurement_id']?.toString().trim() ?? '',
          ),
        'evaluate_spectrum_limits' => await _evaluateSpectrumLimits(
            _number(call.arguments['maximum_noise_floor_dbm']),
            _number(call.arguments['minimum_main_peak_dbm']),
            _number(call.arguments['minimum_spur_suppression_db']),
          ),
        'clear_analysis_overlays' => await _clearAnalysisOverlays(),
        'export_test_report' => await _exportTestReport(
            call.arguments['session_id']?.toString().trim() ?? '',
          ),
        _ => const InstrumentActionOutcome(
            success: false,
            message: '不支持的仪器工具',
          ),
      };
      return _result(call, outcome);
    } on TimeoutException {
      return _result(
          call,
          const InstrumentActionOutcome(
            success: false,
            message: '仪器操作超时，未确认配置已经生效',
          ));
    } catch (error) {
      return _result(
          call,
          InstrumentActionOutcome(
            success: false,
            message: '仪器操作异常：$error',
          ));
    } finally {
      _commandInFlight = false;
    }
  }

  InstrumentActionOutcome? _validateMutation(InstrumentToolCall call) {
    final state = snapshot;
    final configuresRealtimeHardware = call.name ==
            'configure_realtime_spectrum' &&
        (<String>{
              'lna_enabled',
              'attenuation_db',
              'vga_db',
            }.any(call.arguments.containsKey) ||
            (state.sweepRunning && call.arguments.containsKey('center_hz')));
    final configuresRunningPhaseNoise =
        call.name == 'configure_phase_noise' && state.sweepRunning;
    final requiresLiveInstrument = <String>{
          'set_frequency',
          'set_bandwidth',
          'set_detector',
          'start_single_sweep',
          'start_continuous_sweep',
          'stop_measurement',
          'start_phase_noise_measurement',
          'stop_phase_noise_measurement',
          'start_realtime_spectrum',
          'stop_realtime_spectrum',
        }.contains(call.name) ||
        configuresRealtimeHardware ||
        configuresRunningPhaseNoise;
    if (requiresLiveInstrument && !state.connected) {
      return const InstrumentActionOutcome(
        success: false,
        message: '串口未连接，不能执行仪器操作',
      );
    }
    if (requiresLiveInstrument && !state.deviceResponsive) {
      return const InstrumentActionOutcome(
        success: false,
        message: '仪器尚未完成握手或当前无响应',
      );
    }
    final requiresSpectrumMode = <String>{
      'set_frequency',
      'set_bandwidth',
      'set_detector',
      'start_single_sweep',
      'start_continuous_sweep',
      'stop_measurement',
    }.contains(call.name);
    final requiresPhaseNoiseMode = <String>{
      'start_phase_noise_measurement',
      'stop_phase_noise_measurement',
      'get_phase_noise_state',
      'configure_phase_noise',
      'analyze_phase_noise',
    }.contains(call.name);
    final requiresRealtimeMode = <String>{
      'start_realtime_spectrum',
      'stop_realtime_spectrum',
      'get_realtime_spectrum_state',
      'configure_realtime_spectrum',
      'get_realtime_spectrum_snapshot',
      'get_realtime_waterfall_history',
      'analyze_realtime_spectrum',
      'place_realtime_peak_markers',
      'save_realtime_measurement',
    }.contains(call.name);
    if (requiresSpectrumMode && state.measurementMode != 'spectrum') {
      return InstrumentActionOutcome(
        success: false,
        message: '当前处于 ${state.measurementMode}，该工具只属于 spectrum 标准频谱模式',
      );
    }
    if (requiresPhaseNoiseMode && state.measurementMode != 'phase_noise') {
      return InstrumentActionOutcome(
        success: false,
        message: '当前处于 ${state.measurementMode}，请先切换到 phase_noise 模式',
      );
    }
    if (requiresRealtimeMode && state.measurementMode != 'realtime_spectrum') {
      return InstrumentActionOutcome(
        success: false,
        message: '当前处于 ${state.measurementMode}，请先切换到 realtime_spectrum 模式',
      );
    }
    final requiresStandardSpectrumData = <String>{
      'get_spectrum_snapshot',
      'analyze_spectrum',
      'place_peak_markers',
      'save_measurement',
      'load_measurement',
      'evaluate_spectrum_limits',
    }.contains(call.name);
    if (requiresStandardSpectrumData && state.measurementMode != 'spectrum') {
      return InstrumentActionOutcome(
        success: false,
        message: '该工具只处理 spectrum 标准扫频 dBm 数据；当前模式为 ${state.measurementMode}',
      );
    }

    switch (call.name) {
      case 'set_measurement_mode':
        const modes = <String>{
          'spectrum',
          'phase_noise',
          'realtime_spectrum',
        };
        if (!modes.contains(call.arguments['mode'])) {
          return const InstrumentActionOutcome(
            success: false,
            message: '不支持的测量模式',
          );
        }
        return null;
      case 'set_frequency':
        final center = _number(call.arguments['center_hz']);
        final span = _number(call.arguments['span_hz']);
        if (center == null || span == null || span < 0) {
          return const InstrumentActionOutcome(
            success: false,
            message: '中心频率或扫宽参数无效',
          );
        }
        final start = center - span / 2;
        final stop = center + span / 2;
        if (start < state.minimumFrequencyHz ||
            stop > state.maximumFrequencyHz) {
          return InstrumentActionOutcome(
            success: false,
            message: '请求范围 ${_formatHz(start)}–${_formatHz(stop)} 超出仪器范围 '
                '${_formatHz(state.minimumFrequencyHz)}–${_formatHz(state.maximumFrequencyHz)}',
          );
        }
        return null;
      case 'set_bandwidth':
        final rbw = _number(call.arguments['rbw_hz']);
        final vbwMode = call.arguments['vbw_mode']?.toString();
        if (rbw == null || !supportedRbwHz.contains(rbw)) {
          return const InstrumentActionOutcome(
            success: false,
            message: 'RBW 不在仪器支持列表中',
          );
        }
        const modes = <String>{
          'follow_rbw',
          'manual',
          'rbw_x_0_1',
          'rbw_x_0_01',
          'rbw_x_10',
        };
        if (!modes.contains(vbwMode)) {
          return const InstrumentActionOutcome(
            success: false,
            message: 'VBW 模式无效',
          );
        }
        if (vbwMode == 'manual' &&
            (_number(call.arguments['vbw_hz']) ?? 0) <= 0) {
          return const InstrumentActionOutcome(
            success: false,
            message: '手动 VBW 模式必须提供大于 0 的 vbw_hz',
          );
        }
        return null;
      case 'set_detector':
        if (!supportedDetectors.contains(call.arguments['detector'])) {
          return const InstrumentActionOutcome(
            success: false,
            message: '不支持的检波方式',
          );
        }
        return null;
      case 'start_single_sweep':
      case 'start_continuous_sweep':
      case 'stop_measurement':
      case 'stop_phase_noise_measurement':
      case 'stop_realtime_spectrum':
        return null;
      case 'start_phase_noise_measurement':
        for (final key in const <String>['continuous', 'wait_for_carrier']) {
          if (call.arguments.containsKey(key) && call.arguments[key] is! bool) {
            return InstrumentActionOutcome(
              success: false,
              message: '$key 必须是布尔值',
            );
          }
        }
        return null;
      case 'get_phase_noise_state':
        return null;
      case 'configure_phase_noise':
        final carrierMode = call.arguments['carrier_mode']?.toString();
        if (carrierMode != null &&
            !const <String>{'auto', 'manual'}.contains(carrierMode)) {
          return const InstrumentActionOutcome(
            success: false,
            message: 'carrier_mode 必须是 auto 或 manual',
          );
        }
        final carrierHz = _number(call.arguments['carrier_hz']);
        if (call.arguments.containsKey('carrier_hz') &&
            (carrierHz == null || carrierHz < 50e6 || carrierHz > 1.5e9)) {
          return const InstrumentActionOutcome(
            success: false,
            message: '相位噪声载波频率必须在 50 MHz–1.5 GHz 之间',
          );
        }
        for (final key in const <String>['carrier_search_span_hz']) {
          final value = _number(call.arguments[key]);
          if (call.arguments.containsKey(key) &&
              (value == null || value < 1 || value > 100e6)) {
            return InstrumentActionOutcome(
              success: false,
              message: '$key 必须在 1 Hz–100 MHz 之间',
            );
          }
        }
        for (final key in const <String>[
          'start_offset_hz',
          'stop_offset_hz',
        ]) {
          final value = _number(call.arguments[key]);
          if (call.arguments.containsKey(key) &&
              (value == null || value < 1e3 || value > 100e6)) {
            return InstrumentActionOutcome(
              success: false,
              message: '$key 必须在 1 kHz–100 MHz 之间',
            );
          }
        }
        final startOffset = _number(call.arguments['start_offset_hz']);
        final stopOffset = _number(call.arguments['stop_offset_hz']);
        if (startOffset != null &&
            stopOffset != null &&
            stopOffset < startOffset) {
          return const InstrumentActionOutcome(
            success: false,
            message: 'stop_offset_hz 不能小于 start_offset_hz',
          );
        }
        final minimumLevel =
            _number(call.arguments['minimum_carrier_level_dbm']);
        if (call.arguments.containsKey('minimum_carrier_level_dbm') &&
            (minimumLevel == null ||
                minimumLevel < -140 ||
                minimumLevel > 30)) {
          return const InstrumentActionOutcome(
            success: false,
            message: 'minimum_carrier_level_dbm 必须在 -140–30 dBm 之间',
          );
        }
        final density = call.arguments['density']?.toString();
        if (density != null &&
            !const <String>{'fast', 'normal', 'fine'}.contains(density)) {
          return const InstrumentActionOutcome(
            success: false,
            message: 'density 必须是 fast、normal 或 fine',
          );
        }
        final traceDisplay = call.arguments['trace_display']?.toString();
        if (traceDisplay != null &&
            !const <String>{'raw', 'average', 'both'}.contains(traceDisplay)) {
          return const InstrumentActionOutcome(
            success: false,
            message: 'trace_display 必须是 raw、average 或 both',
          );
        }
        final averageCount = call.arguments['average_count'];
        if (averageCount != null &&
            (averageCount is! int || averageCount < 1 || averageCount > 1000)) {
          return const InstrumentActionOutcome(
            success: false,
            message: 'average_count 必须是 1–1000 的整数',
          );
        }
        return null;
      case 'analyze_phase_noise':
        final offsetHz = _number(call.arguments['offset_hz']);
        final trace = call.arguments['trace']?.toString() ?? 'auto';
        final timeout = call.arguments['wait_timeout_ms'] ?? 10000;
        if (offsetHz == null || offsetHz < 1e3 || offsetHz > 100e6) {
          return const InstrumentActionOutcome(
            success: false,
            message: 'offset_hz 必须在 1 kHz–100 MHz 之间',
          );
        }
        if (!const <String>{'auto', 'raw', 'average'}.contains(trace)) {
          return const InstrumentActionOutcome(
            success: false,
            message: 'trace 必须是 auto、raw 或 average',
          );
        }
        if (timeout is! int || timeout < 0 || timeout > 30000) {
          return const InstrumentActionOutcome(
            success: false,
            message: 'wait_timeout_ms 必须是 0–30000 的整数',
          );
        }
        return null;
      case 'get_realtime_spectrum_state':
        return null;
      case 'configure_realtime_spectrum':
        for (final key in const <String>[
          'average_enabled',
          'max_hold_enabled',
          'marker_enabled',
          'lna_enabled',
          'reset_average',
          'reset_max_hold',
        ]) {
          if (call.arguments.containsKey(key) && call.arguments[key] is! bool) {
            return InstrumentActionOutcome(
              success: false,
              message: '$key 必须是布尔值',
            );
          }
        }
        final centerHz = _number(call.arguments['center_hz']);
        if (call.arguments.containsKey('center_hz') &&
            (centerHz == null || centerHz < 50e6 || centerHz > 1.5e9)) {
          return const InstrumentActionOutcome(
            success: false,
            message: '实时频谱中心频率必须在 50 MHz–1.5 GHz 之间',
          );
        }
        final attenuationDb = _number(call.arguments['attenuation_db']);
        if (call.arguments.containsKey('attenuation_db') &&
            (attenuationDb == null ||
                attenuationDb < 0 ||
                attenuationDb > 31.75 ||
                ((attenuationDb * 4).round() - attenuationDb * 4).abs() >
                    1e-9)) {
          return const InstrumentActionOutcome(
            success: false,
            message: '实时频谱 DSA 必须在 0–31.75 dB 之间且步进为 0.25 dB',
          );
        }
        const vgaValues = <double>[
          -11,
          -10,
          -6,
          -3,
          0,
          3,
          6,
          10,
          20,
          30,
          34,
        ];
        final vgaDb = _number(call.arguments['vga_db']);
        if (call.arguments.containsKey('vga_db') &&
            (vgaDb == null || !vgaValues.contains(vgaDb))) {
          return const InstrumentActionOutcome(
            success: false,
            message: '实时频谱 VGA 不在设备支持列表中',
          );
        }
        final referenceDbfs = _number(call.arguments['reference_dbfs']);
        if (call.arguments.containsKey('reference_dbfs') &&
            (referenceDbfs == null ||
                referenceDbfs < -140 ||
                referenceDbfs > 0)) {
          return const InstrumentActionOutcome(
            success: false,
            message: 'reference_dbfs 必须在 -140–0 dBFS 之间',
          );
        }
        final waterfallFloor = _number(call.arguments['waterfall_floor_dbfs']);
        final waterfallReference =
            _number(call.arguments['waterfall_reference_dbfs']);
        if ((call.arguments.containsKey('waterfall_floor_dbfs') &&
                (waterfallFloor == null ||
                    waterfallFloor < -160 ||
                    waterfallFloor > -10)) ||
            (call.arguments.containsKey('waterfall_reference_dbfs') &&
                (waterfallReference == null ||
                    waterfallReference < -150 ||
                    waterfallReference > 0)) ||
            (waterfallFloor != null &&
                waterfallReference != null &&
                waterfallFloor > waterfallReference - 10)) {
          return const InstrumentActionOutcome(
            success: false,
            message: '瀑布图范围无效，floor 必须至少比 reference 低 10 dB',
          );
        }
        return null;
      case 'start_realtime_spectrum':
        final centerHz = _number(call.arguments['center_hz']);
        if (centerHz == null ||
            centerHz < state.minimumFrequencyHz ||
            centerHz > state.maximumFrequencyHz) {
          return const InstrumentActionOutcome(
            success: false,
            message: '实时频谱中心频率超出 50 MHz–1.5 GHz 范围',
          );
        }
        return null;
      case 'get_spectrum_snapshot':
        final maximumPoints = _integer(call.arguments['maximum_points'], 128);
        if (maximumPoints < 16 || maximumPoints > 512) {
          return const InstrumentActionOutcome(
            success: false,
            message: 'maximum_points 必须在 16–512 之间',
          );
        }
        return null;
      case 'analyze_spectrum':
      case 'place_peak_markers':
        final peakCount = _integer(call.arguments['peak_count'], 5);
        final threshold =
            _number(call.arguments['threshold_above_noise_db']) ?? 6;
        if (peakCount < 1 ||
            peakCount > 8 ||
            threshold < 0 ||
            threshold > 100) {
          return const InstrumentActionOutcome(
            success: false,
            message: '峰值数量或噪声阈值超出允许范围',
          );
        }
        return null;
      case 'get_realtime_spectrum_snapshot':
        final trace = call.arguments['trace']?.toString() ?? 'latest';
        final maximumPoints = _integer(call.arguments['maximum_points'], 128);
        if (!const <String>{'latest', 'average', 'max_hold'}.contains(trace) ||
            maximumPoints < 16 ||
            maximumPoints > 315) {
          return const InstrumentActionOutcome(
            success: false,
            message: '实时频谱 trace 或 maximum_points 无效（允许 16–315）',
          );
        }
        return null;
      case 'get_realtime_waterfall_history':
        final maximumRows = _integer(call.arguments['maximum_rows'], 20);
        final lookbackSeconds = _number(call.arguments['lookback_seconds']);
        final maximumPoints =
            _integer(call.arguments['maximum_points_per_row'], 64);
        if (maximumRows < 1 ||
            maximumRows > 60 ||
            (lookbackSeconds != null &&
                (lookbackSeconds < 0.1 || lookbackSeconds > 300)) ||
            maximumPoints < 16 ||
            maximumPoints > 128) {
          return const InstrumentActionOutcome(
            success: false,
            message: '瀑布历史参数无效：行数 1–60，时间 0.1–300 秒，每行点数 16–128',
          );
        }
        return null;
      case 'save_realtime_measurement':
        final trace = call.arguments['trace']?.toString() ?? 'average';
        final includeWaterfall = call.arguments['include_waterfall'];
        final waterfallRows = _integer(call.arguments['waterfall_rows'], 20);
        if ((call.arguments['label']?.toString().trim() ?? '').isEmpty ||
            !const <String>{'latest', 'average', 'max_hold'}.contains(trace) ||
            (includeWaterfall != null && includeWaterfall is! bool) ||
            waterfallRows < 1 ||
            waterfallRows > 60) {
          return const InstrumentActionOutcome(
            success: false,
            message: '实时频谱保存参数无效：label、trace 或瀑布行数不正确',
          );
        }
        return null;
      case 'capture_screenshot':
        return null;
      case 'analyze_realtime_spectrum':
      case 'place_realtime_peak_markers':
        final trace = call.arguments['trace']?.toString() ?? 'latest';
        final peakCount = _integer(call.arguments['peak_count'], 5);
        final threshold =
            _number(call.arguments['threshold_above_noise_db']) ?? 6;
        if (!const <String>{'latest', 'average', 'max_hold'}.contains(trace) ||
            peakCount < 1 ||
            peakCount > 8 ||
            threshold < 0 ||
            threshold > 100) {
          return const InstrumentActionOutcome(
            success: false,
            message: '实时频谱 trace、峰值数量或噪声阈值超出允许范围',
          );
        }
        return null;
      case 'save_measurement':
        if ((call.arguments['label']?.toString().trim() ?? '').isEmpty) {
          return const InstrumentActionOutcome(
            success: false,
            message: '保存测试记录必须提供 label',
          );
        }
        return null;
      case 'get_test_session':
        return null;
      case 'start_test_session':
        if ((call.arguments['name']?.toString().trim() ?? '').isEmpty) {
          return const InstrumentActionOutcome(
            success: false,
            message: '开始测试会话必须提供 name',
          );
        }
        return null;
      case 'add_test_note':
        if ((call.arguments['note']?.toString().trim() ?? '').isEmpty) {
          return const InstrumentActionOutcome(
            success: false,
            message: '测试备注不能为空',
          );
        }
        return null;
      case 'end_test_session':
        return null;
      case 'list_test_sessions':
        final limit = _integer(call.arguments['limit'], 20);
        if (limit < 1 || limit > 50) {
          return const InstrumentActionOutcome(
            success: false,
            message: 'limit 必须在 1–50 之间',
          );
        }
        return null;
      case 'list_measurements':
        final limit = _integer(call.arguments['limit'], 20);
        if (limit < 1 || limit > 100) {
          return const InstrumentActionOutcome(
            success: false,
            message: 'limit 必须在 1–100 之间',
          );
        }
        return null;
      case 'load_measurement':
        if ((call.arguments['measurement_id']?.toString().trim() ?? '')
            .isEmpty) {
          return const InstrumentActionOutcome(
            success: false,
            message: '加载历史测量必须提供 measurement_id',
          );
        }
        return null;
      case 'compare_measurements':
        final first = call.arguments['first_measurement_id']?.toString().trim();
        final second =
            call.arguments['second_measurement_id']?.toString().trim();
        if ((first ?? '').isEmpty || (second ?? '').isEmpty) {
          return const InstrumentActionOutcome(
            success: false,
            message: '对比频谱必须提供两个 measurement_id',
          );
        }
        return null;
      case 'evaluate_spectrum_limits':
        final noise = _number(call.arguments['maximum_noise_floor_dbm']);
        final peak = _number(call.arguments['minimum_main_peak_dbm']);
        final spur = _number(call.arguments['minimum_spur_suppression_db']);
        if (noise == null && peak == null && spur == null) {
          return const InstrumentActionOutcome(
            success: false,
            message: '至少需要提供一项频谱限值条件',
          );
        }
        if (spur != null && (spur < 0 || spur > 200)) {
          return const InstrumentActionOutcome(
            success: false,
            message: '杂散抑制度限值必须在 0–200 dB 之间',
          );
        }
        return null;
      case 'clear_analysis_overlays':
      case 'export_test_report':
        return null;
      default:
        return const InstrumentActionOutcome(
          success: false,
          message: '模型请求了未注册的仪器工具',
        );
    }
  }

  InstrumentToolResult _result(
    InstrumentToolCall call,
    InstrumentActionOutcome outcome,
  ) {
    return InstrumentToolResult(
      callId: call.id,
      toolName: call.name,
      success: outcome.success,
      message: outcome.message,
      data: outcome.data,
    );
  }

  static Map<String, dynamic> _functionTool({
    required String name,
    required String description,
    required Map<String, dynamic> properties,
    List<String> required = const <String>[],
  }) {
    return <String, dynamic>{
      'type': 'function',
      'function': <String, dynamic>{
        'name': name,
        'description': description,
        'parameters': <String, dynamic>{
          'type': 'object',
          'properties': properties,
          'required': required,
          'additionalProperties': false,
        },
      },
    };
  }

  static double? _number(dynamic value) {
    if (value is num) return value.toDouble();
    return double.tryParse(value?.toString() ?? '');
  }

  static int _integer(dynamic value, int fallback) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    return int.tryParse(value?.toString() ?? '') ?? fallback;
  }

  static String _formatHz(double? value) {
    if (value == null || !value.isFinite) return '--';
    final absolute = value.abs();
    if (absolute >= 1e9) return '${(value / 1e9).toStringAsFixed(6)} GHz';
    if (absolute >= 1e6) return '${(value / 1e6).toStringAsFixed(3)} MHz';
    if (absolute >= 1e3) return '${(value / 1e3).toStringAsFixed(3)} kHz';
    return '${value.toStringAsFixed(0)} Hz';
  }
}
