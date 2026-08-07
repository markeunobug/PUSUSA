import 'dart:async';
import 'dart:math' as math;

import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';

import 'agent/realtime_spectrum_analysis.dart';
import 'device_models.dart';
import 'realtime_spectrum_controls.dart';
import 'realtime_spectrum_models.dart';
import 'realtime_spectrum_processor.dart';
import 'realtime_spectrum_settings.dart';
import 'resizable_panel_divider.dart';
import 'serial_protocol.dart';

class RealtimeSpectrumPage extends StatefulWidget {
  const RealtimeSpectrumPage({
    super.key,
    required this.protocol,
    required this.connected,
    this.initialRfConfig,
    this.initialVgaLabel,
    this.sidebarWidth = 300,
    this.onSidebarDragDelta,
  });

  final SerialProtocol protocol;
  final bool connected;
  final RfFrontendConfig? initialRfConfig;
  final String? initialVgaLabel;
  final double sidebarWidth;
  final ValueChanged<double>? onSidebarDragDelta;

  @override
  State<RealtimeSpectrumPage> createState() => RealtimeSpectrumPageState();
}

class _RtTransactionCancelled implements Exception {
  const _RtTransactionCancelled();
}

class RealtimeSpectrumPageState extends State<RealtimeSpectrumPage> {
  static const _vgaLabels = <String>[
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
  static const _vgaCodes = <String, int>{
    '-11 dB': 0x05,
    '-10 dB': 0x06,
    '-6 dB': 0x09,
    '-3 dB': 0x0D,
    '0 dB': 0x12,
    '3 dB': 0x19,
    '6 dB': 0x24,
    '10 dB': 0x39,
    '20 dB': 0x99,
    '30 dB': 0xD0,
    '34 dB': 0xFF,
  };

  final _processor = RealtimeSpectrumProcessor();
  final _center = TextEditingController(
      text: RealtimeSpectrumSettingsStore.cached.centerMhz);
  final _attenuation = TextEditingController();
  late final StreamSubscription<RealtimeSpectrumFrame> _dataSub;
  late final StreamSubscription<RealtimeSpectrumStatus> _statusSub;
  Timer? _uiTimer;
  Timer? _settingsSaveTimer;
  RealtimeSpectrumStatus? _status;
  RealtimeSpectrumFrame? _latestFrame;
  int _session = 0;
  int _operationToken = 0;
  int? _lastSequence;
  bool _acceptFrames = false;
  bool _running = false;
  bool _busy = false;
  bool _settingsChanged = false;
  bool _average = RealtimeSpectrumSettingsStore.cached.averageEnabled;
  bool _maxHold = RealtimeSpectrumSettingsStore.cached.maxHoldEnabled;
  bool _markerEnabled = RealtimeSpectrumSettingsStore.cached.markerEnabled;
  List<double> _agentMarkerFrequenciesHz = <double>[];
  List<double> _agentMarkerLevelsDbfs = <double>[];
  RfFrontendConfig _rf = RfFrontendConfig(
      lnaMode: RealtimeSpectrumSettingsStore.cached.lnaEnabled
          ? RfLnaMode.enable
          : RfLnaMode.bypass,
      pathMode: RfPathMode.mixerChain,
      attenCode: RealtimeSpectrumSettingsStore.cached.attenCode);
  String _vga = RealtimeSpectrumSettingsStore.cached.vgaLabel;
  String _vgaStatus = 'Not sent';
  double _referenceDbfs = RealtimeSpectrumSettingsStore.cached.referenceDbfs;
  double _waterfallFloorDbfs =
      RealtimeSpectrumSettingsStore.cached.waterfallFloorDbfs;
  double _waterfallReferenceDbfs =
      RealtimeSpectrumSettingsStore.cached.waterfallReferenceDbfs;
  String _state = 'Idle';

  double get _attenuationDb => _rf.attenDb;

  @override
  void initState() {
    super.initState();
    final initialRf = widget.initialRfConfig;
    final initialVga = widget.initialVgaLabel;
    if (initialRf != null) {
      _rf = initialRf.copyWith(pathMode: RfPathMode.mixerChain);
      _settingsChanged = true;
    }
    if (initialVga != null && _vgaLabels.contains(initialVga)) {
      _vga = initialVga;
      _settingsChanged = true;
    }
    // Keep the session cache in sync even when tests, Agent actions, or other
    // code update the controller directly instead of going through TextBox's
    // onChanged callback.
    _center.addListener(_rememberSettings);
    _restoreSettings();
    _attenuation.text = _attenuationDb.toStringAsFixed(2);
    _dataSub = widget.protocol.realtimeSpectrumStream.listen((frame) {
      if (!_acceptFrames ||
          frame.errorCode != 0 ||
          frame.amplitudeUnit != 1 ||
          (_lastSequence != null && frame.sequence <= _lastSequence!)) {
        return;
      }
      _lastSequence = frame.sequence;
      _latestFrame = frame;
      _processor.add(frame, averageEnabled: _average, maxHoldEnabled: _maxHold);
      _uiTimer ??= Timer(const Duration(milliseconds: 100), () {
        _uiTimer = null;
        if (mounted) setState(() {});
      });
    });
    _statusSub = widget.protocol.realtimeSpectrumStatusStream.listen((status) {
      if (!mounted) return;
      setState(() {
        _status = status;
        if (status.isNormalTerminalIdle) {
          _running = false;
          _acceptFrames = false;
          _state = status.errorCode == RealtimeSpectrumStatus.errorStopped
              ? 'Idle (stopped)'
              : 'Idle';
        } else if (status.errorCode != RealtimeSpectrumStatus.errorNone) {
          _running = false;
          _acceptFrames = false;
          _state =
              'Device error ${status.errorCode} detail ${status.errorDetail}';
        } else {
          _state = 'Running';
        }
      });
    });
  }

  @override
  void dispose() {
    _operationToken++;
    _uiTimer?.cancel();
    _settingsSaveTimer?.cancel();
    _rememberSettings(scheduleSave: false);
    unawaited(RealtimeSpectrumSettingsStore.persist());
    _dataSub.cancel();
    _statusSub.cancel();
    _center.dispose();
    _attenuation.dispose();
    super.dispose();
  }

  Future<void> _restoreSettings() async {
    final settings = await RealtimeSpectrumSettingsStore.load();
    if (!mounted || _settingsChanged) return;

    final vgaLabel = _vgaLabels.contains(settings.vgaLabel)
        ? settings.vgaLabel
        : RealtimeSpectrumSettings.defaults.vgaLabel;
    final waterfallReference =
        settings.waterfallReferenceDbfs.clamp(-150.0, 0.0);
    final waterfallFloor =
        settings.waterfallFloorDbfs.clamp(-160.0, waterfallReference - 10.0);
    setState(() {
      _center.text = settings.centerMhz;
      _average = settings.averageEnabled;
      _maxHold = settings.maxHoldEnabled;
      _markerEnabled = settings.markerEnabled;
      _rf = RfFrontendConfig(
        lnaMode: settings.lnaEnabled ? RfLnaMode.enable : RfLnaMode.bypass,
        pathMode: RfPathMode.mixerChain,
        attenCode: settings.attenCode,
      );
      _attenuation.text = _rf.attenDb.toStringAsFixed(2);
      _vga = vgaLabel;
      _referenceDbfs = settings.referenceDbfs;
      _waterfallFloorDbfs = waterfallFloor;
      _waterfallReferenceDbfs = waterfallReference;
    });
  }

  RealtimeSpectrumSettings get _currentSettings => RealtimeSpectrumSettings(
        centerMhz: _center.text,
        averageEnabled: _average,
        maxHoldEnabled: _maxHold,
        markerEnabled: _markerEnabled,
        lnaEnabled: _rf.lnaMode == RfLnaMode.enable,
        attenCode: _rf.attenCode,
        vgaLabel: _vga,
        referenceDbfs: _referenceDbfs,
        waterfallFloorDbfs: _waterfallFloorDbfs,
        waterfallReferenceDbfs: _waterfallReferenceDbfs,
      );

  void _rememberSettings({bool scheduleSave = true}) {
    _settingsChanged = true;
    RealtimeSpectrumSettingsStore.remember(_currentSettings);
    if (!scheduleSave) return;

    _settingsSaveTimer?.cancel();
    _settingsSaveTimer = Timer(const Duration(milliseconds: 250), () {
      unawaited(RealtimeSpectrumSettingsStore.persist());
    });
  }

  void _setRememberedState(VoidCallback update) {
    setState(update);
    _rememberSettings();
  }

  double? get _centerHz {
    final value = double.tryParse(_center.text.trim());
    return value == null ? null : value * 1e6;
  }

  bool get isRunning => _running;
  String get agentStatus => _state;
  double? get agentCenterHz => _centerHz;

  Map<String, dynamic> get agentConfiguration => <String, dynamic>{
        'measurement_mode': 'realtime_spectrum',
        'connected': widget.connected,
        'running': _running,
        'busy': _busy,
        'state': _state,
        'center_hz': _centerHz,
        'span_hz': 10e6,
        'fft_size': 4096,
        'bin_count': RealtimeSpectrumFrame.binCount,
        'amplitude_unit': 'dBFS',
        'average_enabled': _average,
        'average_count': _processor.averageCount,
        'max_hold_enabled': _maxHold,
        'marker_enabled': _markerEnabled,
        'lna_enabled': _rf.lnaMode == RfLnaMode.enable,
        'attenuation_db': _rf.attenDb,
        'vga_db': double.tryParse(_vga.split(' ').first),
        'vga_status': _vgaStatus,
        'reference_dbfs': _referenceDbfs,
        'waterfall_floor_dbfs': _waterfallFloorDbfs,
        'waterfall_reference_dbfs': _waterfallReferenceDbfs,
        'waterfall_rows': _processor.waterfall.length,
        'latest_frame': _latestFrame == null
            ? null
            : <String, dynamic>{
                'sequence': _latestFrame!.sequence,
                'center_hz': _latestFrame!.centerHz,
                'sample_rate_hz': _latestFrame!.sampleRateHz,
                'fft_size': _latestFrame!.fftSize,
                'first_bin': _latestFrame!.firstBin,
                'frames_emitted': _latestFrame!.framesEmitted,
                'dropped_frames': _latestFrame!.droppedFrames,
              },
        'device_status': _status == null
            ? null
            : <String, dynamic>{
                'state': _status!.state,
                'error_code': _status!.errorCode,
                'error_detail': _status!.errorDetail,
                'frames_emitted': _status!.framesEmitted,
                'dropped_frames': _status!.droppedFrames,
                'dma_error_count': _status!.dmaErrorCount,
              },
      };

  Future<Map<String, dynamic>> configureFromAgent({
    double? centerHz,
    bool? averageEnabled,
    bool? maxHoldEnabled,
    bool? markerEnabled,
    bool? lnaEnabled,
    double? attenuationDb,
    double? vgaDb,
    double? referenceDbfs,
    double? waterfallFloorDbfs,
    double? waterfallReferenceDbfs,
    bool resetAverage = false,
    bool resetMaxHold = false,
  }) async {
    if (_busy) {
      throw StateError('实时频谱正在执行其他配置事务');
    }
    if (centerHz != null && (centerHz < 50e6 || centerHz > 1.5e9)) {
      throw ArgumentError('实时频谱中心频率必须在 50 MHz–1.5 GHz 之间');
    }
    if (attenuationDb != null && (attenuationDb < 0 || attenuationDb > 31.75)) {
      throw ArgumentError('实时频谱 DSA 必须在 0–31.75 dB 之间');
    }
    final vgaLabel = vgaDb == null ? _vga : _vgaLabel(vgaDb);
    if (vgaLabel == null) {
      throw ArgumentError('实时频谱 VGA 不在支持列表中');
    }
    if (referenceDbfs != null && (referenceDbfs < -140 || referenceDbfs > 0)) {
      throw ArgumentError('参考电平必须在 -140–0 dBFS 之间');
    }
    final targetWaterfallFloor = waterfallFloorDbfs ?? _waterfallFloorDbfs;
    final targetWaterfallReference =
        waterfallReferenceDbfs ?? _waterfallReferenceDbfs;
    if (targetWaterfallFloor < -160 ||
        targetWaterfallReference > 0 ||
        targetWaterfallFloor > targetWaterfallReference - 10) {
      throw ArgumentError('瀑布底部必须至少比瀑布参考低 10 dB，范围为 -160–0 dBFS');
    }

    final targetRf = _rf.copyWith(
      lnaMode: lnaEnabled == null
          ? _rf.lnaMode
          : lnaEnabled
              ? RfLnaMode.enable
              : RfLnaMode.bypass,
      pathMode: RfPathMode.mixerChain,
      attenCode: attenuationDb == null
          ? _rf.attenCode
          : (attenuationDb / 0.25).round().clamp(0, 127),
    );
    final rfChanged = targetRf.lnaMode != _rf.lnaMode ||
        targetRf.attenCode != _rf.attenCode ||
        vgaLabel != _vga;
    if (rfChanged && !widget.connected) {
      throw StateError('串口未连接，不能应用实时频谱射频前端配置');
    }
    final wasRunning = _running;
    final centerChanged = centerHz != null && centerHz != _centerHz;

    setState(() {
      if (centerHz != null) {
        _center.text = (centerHz / 1e6).toStringAsFixed(6);
      }
      if (averageEnabled != null) _average = averageEnabled;
      if (maxHoldEnabled != null) _maxHold = maxHoldEnabled;
      if (markerEnabled != null) {
        _markerEnabled = markerEnabled;
        if (!markerEnabled) _agentMarkerFrequenciesHz = <double>[];
        if (!markerEnabled) _agentMarkerLevelsDbfs = <double>[];
      }
      if (referenceDbfs != null) _referenceDbfs = referenceDbfs;
      _waterfallFloorDbfs = targetWaterfallFloor;
      _waterfallReferenceDbfs = targetWaterfallReference;
      if (resetAverage) _processor.resetAverage();
      if (resetMaxHold) _processor.resetMaxHold();
    });
    _rememberSettings();

    var hardwareApplied = false;
    if (rfChanged) {
      await _applyFrontend(rf: targetRf, vga: vgaLabel);
      hardwareApplied = targetRf.lnaMode == _rf.lnaMode &&
          targetRf.attenCode == _rf.attenCode &&
          vgaLabel == _vga &&
          (!wasRunning || _running);
      if (!hardwareApplied) {
        throw StateError('实时频谱射频前端配置失败：$_state');
      }
    } else if (centerChanged && wasRunning) {
      await _start();
      hardwareApplied = _running;
      if (!hardwareApplied) {
        throw StateError('实时频谱中心频率配置失败：$_state');
      }
    }
    await RealtimeSpectrumSettingsStore.persist();
    return <String, dynamic>{
      ...agentConfiguration,
      'hardware_applied': hardwareApplied,
      'center_applied_to_device': !centerChanged || wasRunning,
      'vga_has_device_readback': false,
    };
  }

  Map<String, dynamic> snapshotForAgent({
    required String trace,
    required int maximumPoints,
  }) {
    final samples = _samplesForTrace(trace);
    final sampled = RealtimeSpectrumAnalyzer.downsample(
      samples,
      maximumPoints,
    );
    return <String, dynamic>{
      ...agentConfiguration,
      'trace': trace,
      'original_point_count': samples.length,
      'returned_point_count': sampled.length,
      'points': sampled.map((sample) => sample.toJson()).toList(),
    };
  }

  List<RealtimeSpectrumSample> samplesForAgent(String trace) =>
      List<RealtimeSpectrumSample>.unmodifiable(_samplesForTrace(trace));

  Map<String, dynamic> waterfallHistoryForAgent({
    required int maximumRows,
    required double? lookbackSeconds,
    required int maximumPointsPerRow,
  }) {
    if (maximumRows < 1 || maximumRows > 60) {
      throw ArgumentError('maximumRows 必须在 1–60 之间');
    }
    if (lookbackSeconds != null &&
        (lookbackSeconds < 0.1 || lookbackSeconds > 300)) {
      throw ArgumentError('lookbackSeconds 必须在 0.1–300 秒之间');
    }
    if (maximumPointsPerRow < 16 || maximumPointsPerRow > 128) {
      throw ArgumentError('maximumPointsPerRow 必须在 16–128 之间');
    }

    final history = _processor.waterfallHistory;
    if (history.isEmpty) {
      throw StateError('尚未收到可读取的实时频谱瀑布数据');
    }
    final now = DateTime.now().toUtc();
    final cutoff = lookbackSeconds == null
        ? null
        : now.subtract(
            Duration(microseconds: (lookbackSeconds * 1000000).round()),
          );
    final rowsInWindow = cutoff == null
        ? history
        : history
            .where((row) => !row.capturedAtUtc.isBefore(cutoff))
            .toList(growable: false);
    if (rowsInWindow.isEmpty) {
      throw StateError('指定的最近时间段内没有瀑布数据');
    }

    final selectedRows = rowsInWindow.take(maximumRows).toList(growable: false);
    final newest = selectedRows.first;
    final indices = _waterfallSampleIndices(
      newest.levelsDbfs.length,
      maximumPointsPerRow,
    );
    return <String, dynamic>{
      ...agentConfiguration,
      'amplitude_unit': 'dBFS',
      'row_order': 'newest_first',
      'available_rows': history.length,
      'rows_in_time_window': rowsInWindow.length,
      'returned_row_count': selectedRows.length,
      'rows_truncated': rowsInWindow.length > selectedRows.length,
      'lookback_seconds': lookbackSeconds,
      'original_points_per_row': newest.levelsDbfs.length,
      'returned_points_per_row': indices.length,
      'frequencies_hz':
          indices.map((index) => newest.frequencyHz(index)).toList(),
      'rows': selectedRows
          .map(
            (row) => <String, dynamic>{
              'captured_at_utc': row.capturedAtUtc.toIso8601String(),
              'age_ms': math.max(
                0,
                now.difference(row.capturedAtUtc).inMilliseconds,
              ),
              'sequence': row.sequence,
              'frames_emitted': row.framesEmitted,
              'center_hz': row.centerHz,
              'sample_rate_hz': row.sampleRateHz,
              'fft_size': row.fftSize,
              'first_bin': row.firstBin,
              'levels_dbfs':
                  indices.map((index) => row.levelsDbfs[index]).toList(),
            },
          )
          .toList(),
    };
  }

  List<int> _waterfallSampleIndices(int pointCount, int maximumPoints) {
    if (pointCount <= maximumPoints) {
      return List<int>.generate(pointCount, (index) => index, growable: false);
    }
    return List<int>.generate(
      maximumPoints,
      (index) => (index * (pointCount - 1) / (maximumPoints - 1)).round(),
      growable: false,
    );
  }

  RealtimeSpectrumAnalysis analyzeForAgent({
    required String trace,
    required int peakCount,
    required double thresholdAboveNoiseDb,
  }) {
    return RealtimeSpectrumAnalyzer.analyze(
      _samplesForTrace(trace),
      trace: trace,
      peakCount: peakCount,
      thresholdAboveNoiseDb: thresholdAboveNoiseDb,
    );
  }

  RealtimeSpectrumAnalysis placePeakMarkersFromAgent({
    required String trace,
    required int peakCount,
    required double thresholdAboveNoiseDb,
  }) {
    final analysis = analyzeForAgent(
      trace: trace,
      peakCount: peakCount,
      thresholdAboveNoiseDb: thresholdAboveNoiseDb,
    );
    if (analysis.peaks.isEmpty) {
      throw StateError('实时频谱中没有满足阈值的峰值');
    }
    setState(() {
      _markerEnabled = true;
      _agentMarkerFrequenciesHz =
          analysis.peaks.map((peak) => peak.frequencyHz).toList();
      _agentMarkerLevelsDbfs =
          analysis.peaks.map((peak) => peak.levelDbfs).toList();
    });
    _rememberSettings();
    return analysis;
  }

  List<RealtimeSpectrumSample> _samplesForTrace(String trace) {
    final frame = _latestFrame;
    if (frame == null) throw StateError('尚未收到实时频谱 FFT 数据帧');
    final values = switch (trace) {
      'latest' => _processor.latest,
      'average' => _processor.average,
      'max_hold' => _processor.maxHold,
      _ => throw ArgumentError('不支持的实时频谱 trace：$trace'),
    };
    if (values == null || values.isEmpty) {
      throw StateError('实时频谱 $trace trace 尚无数据');
    }
    return List<RealtimeSpectrumSample>.generate(
      values.length,
      (index) => RealtimeSpectrumSample(
        frequencyHz: frame.frequencyHz(index),
        levelDbfs: values[index],
      ),
    );
  }

  String? _vgaLabel(double value) {
    for (final label in _vgaLabels) {
      if ((double.parse(label.split(' ').first) - value).abs() < 1e-9) {
        return label;
      }
    }
    return null;
  }

  Future<bool> startFromAgent(double centerHz) async {
    if (!widget.connected || _busy || centerHz < 50e6 || centerHz > 1.5e9) {
      return false;
    }
    _center.text = (centerHz / 1e6).toStringAsFixed(6);
    _rememberSettings();
    await _start();
    return _running;
  }

  Future<bool> stopFromAgent() async {
    if (!widget.connected || _busy) return false;
    await _stop();
    return !_running && (_status?.permitsReconfiguration ?? true);
  }

  void _checkOperation(int token) {
    if (!mounted || token != _operationToken) {
      throw const _RtTransactionCancelled();
    }
  }

  Future<String?> _waitForIdle(int token) async {
    _checkOperation(token);
    final current = _status;
    if (current != null && current.isIdle) {
      return current.permitsReconfiguration
          ? null
          : 'idle terminal error ${current.errorCode} detail ${current.errorDetail}';
    }
    final done = Completer<String?>();
    late final StreamSubscription<RealtimeSpectrumStatus> sub;
    sub = widget.protocol.realtimeSpectrumStatusStream.listen((status) {
      if (done.isCompleted) return;
      if (status.permitsReconfiguration) {
        done.complete(null);
      } else if (status.errorCode != RealtimeSpectrumStatus.errorNone) {
        done.complete(
            'terminal error ${status.errorCode} detail ${status.errorDetail}');
      }
    });
    try {
      _checkOperation(token);
      widget.protocol.getRealtimeSpectrumStatus();
      final result = await done.future.timeout(const Duration(seconds: 2),
          onTimeout: () => 'idle status timeout');
      _checkOperation(token);
      return result;
    } finally {
      await sub.cancel();
    }
  }

  void _clearDisplays() {
    _processor.reset();
    _latestFrame = null;
    _lastSequence = null;
    _agentMarkerFrequenciesHz = <double>[];
    _agentMarkerLevelsDbfs = <double>[];
  }

  Future<void> _configureAndStart(double hz, int token) async {
    _checkOperation(token);
    _clearDisplays();
    _session++;
    if (!await widget.protocol.configureRealtimeSpectrumConfirmed(hz)) {
      throw StateError('CONFIG ACK timeout');
    }
    _checkOperation(token);
    if (!await widget.protocol.startRealtimeSpectrumConfirmed()) {
      throw StateError('START ACK timeout');
    }
    _checkOperation(token);
    _running = true;
    _acceptFrames = true;
  }

  Future<void> _applyRememberedFrontendForStart(int token) async {
    _checkOperation(token);
    setState(() => _state = 'Applying remembered RF frontend...');
    if (!await widget.protocol.setRfFrontendConfirmed(_rf)) {
      throw StateError('RF frontend 0x0C ACK timeout');
    }
    _checkOperation(token);
    await _awaitRfConfirmation(_rf, token);
    _checkOperation(token);
    widget.protocol.setVgaGainCode(_vgaCodes[_vga]!);
    _vgaStatus = 'Restored for this session';
  }

  Future<void> _start() async {
    final hz = _centerHz;
    if (hz == null || hz < 50e6 || hz > 1.5e9) {
      setState(() => _state = 'Center must be 50 MHz - 1.5 GHz');
      return;
    }
    final token = ++_operationToken;
    setState(() {
      _busy = true;
      _acceptFrames = false;
      _state = 'Stopping RT...';
    });
    try {
      if (!await widget.protocol.stopRealtimeSpectrumConfirmed()) {
        throw StateError('STOP ACK timeout');
      }
      _checkOperation(token);
      final idleError = await _waitForIdle(token);
      if (idleError != null) throw StateError(idleError);
      await widget.protocol.drainAndResetReceiveBuffer();
      _checkOperation(token);
      await _applyRememberedFrontendForStart(token);
      _checkOperation(token);
      await _configureAndStart(hz, token);
      _checkOperation(token);
      setState(() => _state = 'Running (session $_session)');
    } on _RtTransactionCancelled {
      // Navigation, stop, or another transaction invalidated this operation.
    } catch (error) {
      if (mounted && token == _operationToken) {
        setState(() => _state = '$error');
      }
    } finally {
      if (mounted && token == _operationToken) setState(() => _busy = false);
    }
  }

  Future<void> _stop() async {
    final token = ++_operationToken;
    setState(() {
      _busy = true;
      _acceptFrames = false;
      _state = 'Stopping RT...';
    });
    try {
      final ack = await widget.protocol.stopRealtimeSpectrumConfirmed();
      _checkOperation(token);
      final idleError = ack ? await _waitForIdle(token) : 'STOP ACK timeout';
      _checkOperation(token);
      setState(() {
        _running = false;
        _state = idleError ?? 'Idle';
      });
    } on _RtTransactionCancelled {
      // A newer operation owns the device lifecycle now.
    } finally {
      if (mounted && token == _operationToken) setState(() => _busy = false);
    }
  }

  Future<RfFrontendStatus> _awaitRfConfirmation(
      RfFrontendConfig expected, int token) async {
    final done = Completer<RfFrontendStatus>();
    late final StreamSubscription<RfFrontendStatus> sub;
    sub = widget.protocol.rfFrontendStatusStream.listen((status) {
      if (!done.isCompleted) done.complete(status);
    });
    try {
      _checkOperation(token);
      widget.protocol.getRfFrontendStatus();
      final status = await done.future.timeout(const Duration(seconds: 2),
          onTimeout: () =>
              throw StateError('RF frontend 0x84 confirmation timeout'));
      _checkOperation(token);
      if (status.error != 0 ||
          status.config.lnaMode != expected.lnaMode ||
          status.config.pathMode != expected.pathMode ||
          status.config.attenCode != expected.attenCode) {
        throw StateError(
            'RF frontend confirmation rejected (error ${status.error})');
      }
      return status;
    } finally {
      await sub.cancel();
    }
  }

  /// Serializes active RT front-end changes; firmware rejects 0x0C while active.
  Future<void> _applyFrontend({RfFrontendConfig? rf, String? vga}) async {
    if (_busy || !widget.connected) return;
    final targetRf = rf ?? _rf;
    final targetVga = vga ?? _vga;
    final wasRunning = _running;
    final hz = _centerHz;
    if (wasRunning && (hz == null || hz < 50e6 || hz > 1.5e9)) {
      setState(
          () => _state = 'Cannot restart: center must be 50 MHz - 1.5 GHz');
      return;
    }
    final token = ++_operationToken;
    setState(() {
      _busy = true;
      _acceptFrames = false;
      _state = 'RT transition: STOP -> idle...';
    });
    try {
      if (!await widget.protocol.stopRealtimeSpectrumConfirmed()) {
        throw StateError('STOP ACK timeout');
      }
      _checkOperation(token);
      final idleError = await _waitForIdle(token);
      if (idleError != null) throw StateError(idleError);
      _checkOperation(token);
      setState(() => _state = 'Applying mixer-chain RF frontend...');
      if (!await widget.protocol.setRfFrontendConfirmed(targetRf)) {
        throw StateError('RF frontend 0x0C ACK timeout');
      }
      _checkOperation(token);
      await _awaitRfConfirmation(targetRf, token);
      _checkOperation(token);
      widget.protocol.setVgaGainCode(_vgaCodes[targetVga]!);
      // 0x0B has no device readback; this is only a successful local send.
      _rf = targetRf;
      _vga = targetVga;
      _vgaStatus = 'Sent locally (no device readback)';
      _rememberSettings();
      _clearDisplays();
      if (wasRunning) {
        _checkOperation(token);
        setState(() => _state = 'Restarting RT CONFIG/START...');
        await widget.protocol.drainAndResetReceiveBuffer();
        _checkOperation(token);
        await _configureAndStart(hz!, token);
      }
      _checkOperation(token);
      setState(() => _state = wasRunning
          ? 'Running (session $_session)'
          : 'Idle; RF frontend applied');
    } on _RtTransactionCancelled {
      // Do not issue another command after this page loses ownership.
    } catch (error) {
      if (mounted && token == _operationToken) {
        setState(() => _state = 'RF transition failed: $error');
      }
    } finally {
      if (mounted && token == _operationToken) setState(() => _busy = false);
    }
  }

  void _submitAttenuation() {
    final value = double.tryParse(_attenuation.text.trim());
    if (value == null || value < 0 || value > 31.75) {
      _attenuation.text = _attenuationDb.toStringAsFixed(2);
      return;
    }
    final code = (value / 0.25).round().clamp(0, 127);
    _attenuation.text = (code * 0.25).toStringAsFixed(2);
    unawaited(_applyFrontend(
      rf: _rf.copyWith(
        attenCode: code,
        pathMode: RfPathMode.mixerChain,
      ),
    ));
  }

  void _stepAttenuation(int deltaCode) {
    final code = (_rf.attenCode + deltaCode).clamp(0, 127);
    _attenuation.text = (code * 0.25).toStringAsFixed(2);
    unawaited(_applyFrontend(
      rf: _rf.copyWith(
        attenCode: code,
        pathMode: RfPathMode.mixerChain,
      ),
    ));
  }

  void _setReference(double value) {
    final range = realtimeDisplayRange(value);
    _setRememberedState(() {
      _referenceDbfs = range.referenceDbfs;
      _waterfallReferenceDbfs = range.waterfallReferenceDbfs;
      _waterfallFloorDbfs = range.waterfallFloorDbfs;
    });
  }

  @override
  Widget build(BuildContext context) {
    final latest = _processor.latest;
    final frame = _latestFrame;
    final displayRange = realtimeDisplayRange(_referenceDbfs);
    return Material(
      color: const Color(0xff101419),
      child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Expanded(
            child: Padding(
          padding: const EdgeInsets.all(12),
          child:
              Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Expanded(
                flex: 3,
                child: CustomPaint(
                    painter: _TracePainter(
                        frame: frame,
                        latest: latest,
                        average: _average ? _processor.average : null,
                        maxHold: _maxHold ? _processor.maxHold : null,
                        markerEnabled: _markerEnabled,
                        agentMarkerFrequenciesHz: _agentMarkerFrequenciesHz,
                        agentMarkerLevelsDbfs: _agentMarkerLevelsDbfs,
                        minDbfs: displayRange.minDbfs,
                        maxDbfs: displayRange.referenceDbfs),
                    child: const SizedBox.expand())),
            const SizedBox(height: 8),
            Expanded(
                flex: 2,
                child: CustomPaint(
                    painter: _WaterfallPainter(_processor.waterfall,
                        floorDbfs: _waterfallFloorDbfs,
                        referenceDbfs: _waterfallReferenceDbfs),
                    child: const SizedBox.expand())),
          ]),
        )),
        if (widget.onSidebarDragDelta != null)
          ResizablePanelDivider(
            onDragDelta: widget.onSidebarDragDelta!,
            tooltip: '拖动调整仪器工具栏宽度',
          ),
        _buildSidebar(),
      ]),
    );
  }

  Widget _buildSidebar() => Container(
        width: widget.sidebarWidth,
        color: const Color.fromARGB(255, 66, 66, 66),
        padding: const EdgeInsets.all(8),
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              fluent.Expander(
                initiallyExpanded: true,
                header: const Text('采集'),
                content: Column(
                  children: [
                    _controlRow(
                      '中心频率：',
                      fluent.TextBox(
                        controller: _center,
                        enabled: !_busy && !_running,
                        placeholder: '775',
                      ),
                      const Text('MHz'),
                    ),
                    const SizedBox(height: 8),
                    SizedBox(
                      width: double.infinity,
                      child: fluent.FilledButton(
                        onPressed: !widget.connected || _busy
                            ? null
                            : (_running ? _stop : _start),
                        child: Text(_running ? '停止实时频谱' : '启动实时频谱'),
                      ),
                    ),
                    const SizedBox(height: 6),
                    Tooltip(
                      message: _state,
                      child: Text(
                        _state,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 11, color: Colors.white70),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text('固定 10 MHz Span · Hann · FFT 4096',
                        style: TextStyle(fontSize: 12, color: Colors.white70)),
                  ],
                ),
              ),
              fluent.Expander(
                initiallyExpanded: true,
                header: const Text('射频前端'),
                content: Column(
                  children: [
                    _modeButtons<RfLnaMode>(
                      'LNA：',
                      _rf.lnaMode,
                      const [RfLnaMode.bypass, RfLnaMode.enable],
                      (mode) => unawaited(_applyFrontend(
                        rf: _rf.copyWith(
                          lnaMode: mode,
                          pathMode: RfPathMode.mixerChain,
                        ),
                      )),
                      (mode) => mode == RfLnaMode.enable ? 'LNA' : '直通',
                    ),
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        const SizedBox(width: 100, child: Text('衰减：')),
                        Expanded(
                          child: fluent.TextBox(
                            controller: _attenuation,
                            enabled: !_busy,
                            textAlign: TextAlign.right,
                            onSubmitted: (_) => _submitAttenuation(),
                          ),
                        ),
                        const SizedBox(width: 6),
                        const Text('dB'),
                        const SizedBox(width: 8),
                        SizedBox(
                          width: 32,
                          child: fluent.Button(
                            onPressed:
                                _busy ? null : () => _stepAttenuation(-1),
                            child: const Text('-'),
                          ),
                        ),
                        const SizedBox(width: 4),
                        SizedBox(
                          width: 32,
                          child: fluent.Button(
                            onPressed: _busy ? null : () => _stepAttenuation(1),
                            child: const Text('+'),
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),
                    _controlRow(
                      'VGA：',
                      fluent.ComboBox<String>(
                        value: _vga,
                        isExpanded: true,
                        items: _vgaLabels
                            .map((value) => fluent.ComboBoxItem(
                                value: value, child: Text(value)))
                            .toList(),
                        onChanged: _busy
                            ? null
                            : (value) => value == null
                                ? null
                                : _applyFrontend(vga: value),
                      ),
                      const SizedBox.shrink(),
                    ),
                    const SizedBox(height: 6),
                    Tooltip(
                      message: '射频参数变更会安全停止实时频谱，等待空闲并确认设置后再恢复运行。',
                      child: Text(
                        _busy ? '正在应用射频设置…' : 'VGA：$_vgaStatus',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 11, color: Colors.white70),
                      ),
                    ),
                  ],
                ),
              ),
              fluent.Expander(
                initiallyExpanded: true,
                header: const Text('显示'),
                content: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    _controlRow(
                      '参考电平：',
                      fluent.Slider(
                        value: _referenceDbfs,
                        min: -140,
                        max: 0,
                        divisions: 140,
                        label: '${_referenceDbfs.toStringAsFixed(0)} dBFS',
                        onChanged: _busy ? null : _setReference,
                      ),
                      Text('${_referenceDbfs.toStringAsFixed(0)} dBFS',
                          style: const TextStyle(fontWeight: FontWeight.bold)),
                    ),
                    const SizedBox(height: 4),
                    const Text('仅调整显示范围；当前为原始 dBFS，并非 dBm。',
                        style: TextStyle(fontSize: 11, color: Colors.amber)),
                    const SizedBox(height: 10),
                    _traceToggle(
                        '平均：',
                        _average,
                        (value) => _setRememberedState(() => _average = value),
                        () => setState(_processor.resetAverage)),
                    const SizedBox(height: 6),
                    _traceToggle(
                        '最大保持：',
                        _maxHold,
                        (value) => _setRememberedState(() => _maxHold = value),
                        () => setState(_processor.resetMaxHold)),
                    const SizedBox(height: 6),
                    _controlRow(
                      '峰值游标：',
                      fluent.ToggleSwitch(
                        checked: _markerEnabled,
                        onChanged: _busy
                            ? null
                            : (value) => _setRememberedState(
                                () => _markerEnabled = value),
                      ),
                      const SizedBox.shrink(),
                    ),
                    const SizedBox(height: 10),
                    _waterfallScale(),
                    const SizedBox(height: 8),
                    _controlRow(
                      '瀑布底部：',
                      fluent.Slider(
                        value: _waterfallFloorDbfs,
                        min: -160,
                        max: _waterfallReferenceDbfs - 10,
                        divisions: (_waterfallReferenceDbfs - 10 + 160).round(),
                        label: '${_waterfallFloorDbfs.toStringAsFixed(0)} dBFS',
                        onChanged: _busy
                            ? null
                            : (value) => _setRememberedState(() =>
                                _waterfallFloorDbfs = value.roundToDouble()),
                      ),
                      Text('${_waterfallFloorDbfs.toStringAsFixed(0)} dBFS'),
                    ),
                    const SizedBox(height: 6),
                    _controlRow(
                      '瀑布参考：',
                      fluent.Slider(
                        value: _waterfallReferenceDbfs,
                        min: _waterfallFloorDbfs + 10,
                        max: 0,
                        divisions: (0 - (_waterfallFloorDbfs + 10)).round(),
                        label:
                            '${_waterfallReferenceDbfs.toStringAsFixed(0)} dBFS',
                        onChanged: _busy
                            ? null
                            : (value) => _setRememberedState(() =>
                                _waterfallReferenceDbfs =
                                    value.roundToDouble()),
                      ),
                      Text(
                          '${_waterfallReferenceDbfs.toStringAsFixed(0)} dBFS'),
                    ),
                    const SizedBox(height: 4),
                    const Text('最新数据位于瀑布图顶部。',
                        style: TextStyle(fontSize: 11, color: Colors.white70)),
                  ],
                ),
              ),
            ],
          ),
        ),
      );

  Widget _controlRow(String label, Widget control, Widget value) => Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(width: 100, child: Text(label)),
          Expanded(child: control),
          const SizedBox(width: 6),
          SizedBox(
              width: 60,
              child: DefaultTextStyle.merge(
                  style: const TextStyle(fontSize: 12), child: value)),
        ],
      );

  Widget _modeButtons<T>(
    String label,
    T selected,
    List<T> values,
    ValueChanged<T> onChanged,
    String Function(T) text,
  ) =>
      Row(
        children: [
          SizedBox(width: 100, child: Text(label)),
          Expanded(
            child: Row(
              children: values
                  .map((value) => Expanded(
                        child: Padding(
                          padding: const EdgeInsets.only(right: 6),
                          child: fluent.ToggleButton(
                            checked: value == selected,
                            onChanged: _busy ? null : (_) => onChanged(value),
                            child: Center(child: Text(text(value))),
                          ),
                        ),
                      ))
                  .toList(),
            ),
          ),
        ],
      );

  Widget _traceToggle(String label, bool enabled, ValueChanged<bool> onChanged,
          VoidCallback onReset) =>
      Row(children: [
        SizedBox(width: 100, child: Text(label)),
        fluent.ToggleSwitch(
          checked: enabled,
          onChanged: _busy ? null : onChanged,
        ),
        const Spacer(),
        Tooltip(
          message: 'Reset $label',
          child: fluent.IconButton(
            icon: const Icon(fluent.FluentIcons.refresh),
            onPressed: _busy ? null : onReset,
          ),
        ),
      ]);

  Widget _waterfallScale() => Container(
        height: 12,
        decoration: const BoxDecoration(
          borderRadius: BorderRadius.all(Radius.circular(2)),
          gradient: LinearGradient(colors: [
            Color(0xff071017),
            Color(0xff1456a0),
            Color(0xff00c8d7),
            Color(0xffffd166),
            Color(0xffef476f),
          ]),
        ),
      );
}

class _PlotLayout {
  static const double left = 66;
  static const double right = 12;
  static const double traceTop = 10;
  static const double traceBottom = 42;

  static Rect traceRect(Size size) => Rect.fromLTRB(
        left,
        traceTop,
        math.max(left + 1, size.width - right),
        math.max(traceTop + 1, size.height - traceBottom),
      );

  static Rect waterfallRect(Size size) => Rect.fromLTRB(
        left,
        0,
        math.max(left + 1, size.width - right),
        size.height,
      );
}

class _TracePainter extends CustomPainter {
  const _TracePainter({
    required this.frame,
    required this.latest,
    required this.average,
    required this.maxHold,
    required this.markerEnabled,
    required this.agentMarkerFrequenciesHz,
    required this.agentMarkerLevelsDbfs,
    required this.minDbfs,
    required this.maxDbfs,
  });
  final RealtimeSpectrumFrame? frame;
  final List<double>? latest;
  final List<double>? average;
  final List<double>? maxHold;
  final bool markerEnabled;
  final List<double> agentMarkerFrequenciesHz;
  final List<double> agentMarkerLevelsDbfs;
  final double minDbfs;
  final double maxDbfs;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
        Offset.zero & size, Paint()..color = const Color(0xff071017));
    if (size.width <= _PlotLayout.left + _PlotLayout.right ||
        size.height <= _PlotLayout.traceTop + _PlotLayout.traceBottom) {
      return;
    }
    final plot = _PlotLayout.traceRect(size);
    final gridPaint = Paint()
      ..color = const Color(0x554b7188)
      ..strokeWidth = 1;
    final axisPaint = Paint()
      ..color = const Color(0xff9eb4c2)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawRect(plot, axisPaint);

    // Derive ticks from the active display range. The old fixed 20 dB
    // sequence could extend beyond maxDbfs and stack labels at the top.
    final tickCount = math.min(5, math.max(2, (plot.height / 28).floor()));
    for (var i = 0; i <= tickCount; i++) {
      final value = minDbfs + (maxDbfs - minDbfs) * i / tickCount;
      final y = _yFor(value, plot);
      canvas.drawLine(Offset(plot.left, y), Offset(plot.right, y), gridPaint);
      _drawText(
        canvas,
        value.toStringAsFixed(0),
        Offset(plot.left - 8, y),
        align: TextAlign.right,
        anchorRight: true,
      );
    }

    final activeFrame = frame;
    if (activeFrame != null) {
      final firstHz = activeFrame.frequencyHz(0);
      final lastHz =
          activeFrame.frequencyHz(RealtimeSpectrumFrame.binCount - 1);
      final useGhz = math.max(firstHz.abs(), lastHz.abs()) >= 1e9;
      final xDivisions = plot.width < 220
          ? 1
          : plot.width < 440
              ? 2
              : 4;
      for (var i = 0; i <= xDivisions; i++) {
        final fraction = i / xDivisions;
        final x = plot.left + plot.width * fraction;
        canvas.drawLine(Offset(x, plot.top), Offset(x, plot.bottom), gridPaint);
        final hz = firstHz + (lastHz - firstHz) * fraction;
        final label = useGhz
            ? (hz / 1e9).toStringAsFixed(4)
            : (hz / 1e6).toStringAsFixed(3);
        _drawText(canvas, label, Offset(x, plot.bottom + 5), center: true);
      }
      _drawText(
        canvas,
        'RF Frequency (${useGhz ? 'GHz' : 'MHz'})',
        Offset(plot.center.dx, size.height - 17),
        center: true,
        bold: true,
      );
    } else {
      _drawText(
        canvas,
        'RF Frequency',
        Offset(plot.center.dx, size.height - 17),
        center: true,
        bold: true,
      );
    }

    canvas.save();
    canvas.translate(13, plot.center.dy);
    canvas.rotate(-math.pi / 2);
    _drawText(canvas, 'Power (dBFS)', Offset.zero, center: true, bold: true);
    canvas.restore();

    canvas.save();
    canvas.clipRect(plot);
    _drawLine(canvas, plot, maxHold, Colors.redAccent);
    _drawLine(canvas, plot, average, Colors.amber);
    _drawLine(canvas, plot, latest, Colors.cyanAccent);
    if (markerEnabled && latest != null && latest!.isNotEmpty) {
      final markerBins = <int>[];
      if (agentMarkerFrequenciesHz.isNotEmpty && activeFrame != null) {
        for (final frequency in agentMarkerFrequenciesHz) {
          var closest = 0;
          var distance = (activeFrame.frequencyHz(0) - frequency).abs();
          for (var index = 1; index < latest!.length; index++) {
            final candidate =
                (activeFrame.frequencyHz(index) - frequency).abs();
            if (candidate < distance) {
              closest = index;
              distance = candidate;
            }
          }
          markerBins.add(closest);
        }
      } else {
        var peak = 0;
        for (var i = 1; i < latest!.length; i++) {
          if (latest![i] > latest![peak]) peak = i;
        }
        markerBins.add(peak);
      }
      final markerPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;
      for (var markerIndex = 0;
          markerIndex < markerBins.length;
          markerIndex++) {
        final bin = markerBins[markerIndex];
        final x = plot.left + plot.width * bin / (latest!.length - 1);
        final markerLevel = markerIndex < agentMarkerLevelsDbfs.length
            ? agentMarkerLevelsDbfs[markerIndex]
            : latest![bin];
        final y = _yFor(markerLevel, plot);
        canvas.drawLine(
          Offset(x, plot.top),
          Offset(x, plot.bottom),
          markerPaint,
        );
        canvas.drawCircle(Offset(x, y), 4, markerPaint);
        _drawText(
          canvas,
          'M${markerIndex + 1}',
          Offset(x, math.max(plot.top + 8, y - 10)),
          center: true,
          bold: true,
        );
      }
    }
    canvas.restore();
  }

  double _yFor(double value, Rect plot) {
    final normalized = (value.clamp(minDbfs, maxDbfs).toDouble() - minDbfs) /
        (maxDbfs - minDbfs);
    return plot.bottom - plot.height * normalized;
  }

  void _drawLine(
    Canvas canvas,
    Rect plot,
    List<double>? values,
    Color color,
  ) {
    if (values == null || values.isEmpty) return;
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = plot.left + plot.width * i / (values.length - 1);
      final y = _yFor(values[i], plot);
      if (i == 0) {
        path.moveTo(x, y);
      } else {
        path.lineTo(x, y);
      }
    }
    canvas.drawPath(
      path,
      Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.2,
    );
  }

  void _drawText(
    Canvas canvas,
    String text,
    Offset offset, {
    bool center = false,
    bool anchorRight = false,
    bool bold = false,
    TextAlign align = TextAlign.left,
  }) {
    final painter = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
          color: const Color(0xffb8c9d4),
          fontSize: 10,
          fontWeight: bold ? FontWeight.bold : FontWeight.normal,
        ),
      ),
      textDirection: TextDirection.ltr,
      textAlign: align,
    )..layout();
    final dx = center
        ? offset.dx - painter.width / 2
        : anchorRight
            ? offset.dx - painter.width
            : offset.dx;
    painter.paint(canvas, Offset(dx, offset.dy - painter.height / 2));
  }

  @override
  bool shouldRepaint(covariant _TracePainter oldDelegate) =>
      oldDelegate.frame != frame ||
      oldDelegate.latest != latest ||
      oldDelegate.average != average ||
      oldDelegate.maxHold != maxHold ||
      oldDelegate.markerEnabled != markerEnabled ||
      oldDelegate.agentMarkerFrequenciesHz != agentMarkerFrequenciesHz ||
      oldDelegate.minDbfs != minDbfs ||
      oldDelegate.maxDbfs != maxDbfs;
}

class _WaterfallPainter extends CustomPainter {
  const _WaterfallPainter(
    this.rows, {
    required this.floorDbfs,
    required this.referenceDbfs,
  });

  final List<List<double>> rows;
  final double floorDbfs;
  final double referenceDbfs;

  static final List<Color> colorLut = List<Color>.generate(256, (index) {
    final t = index / 255;
    const stops = <Color>[
      Color(0xff02030d),
      Color(0xff142b74),
      Color(0xff007f9b),
      Color(0xff16c784),
      Color(0xffffd24a),
      Color(0xffff5722),
      Color(0xffffffff),
    ];
    final scaled = t * (stops.length - 1);
    final segment = math.min(stops.length - 2, scaled.floor());
    return Color.lerp(stops[segment], stops[segment + 1], scaled - segment)!;
  }, growable: false);

  @override
  void paint(Canvas canvas, Size size) {
    canvas.drawRect(
        Offset.zero & size, Paint()..color = const Color(0xff071017));
    final plot = _PlotLayout.waterfallRect(size);
    canvas.drawRect(plot, Paint()..color = Colors.black);
    if (rows.isEmpty || plot.width <= 0 || plot.height <= 0) return;
    final rowHeight = plot.height / rows.length;
    final cellPaint = Paint()..isAntiAlias = false;
    final colorScale = 255 / (referenceDbfs - floorDbfs);
    for (var y = 0; y < rows.length; y++) {
      final row = rows[y];
      if (row.isEmpty) continue;
      final cellWidth = plot.width / row.length;
      for (var x = 0; x < row.length; x++) {
        final lutIndex =
            ((row[x] - floorDbfs) * colorScale).clamp(0.0, 255.0).round();
        cellPaint.color = colorLut[lutIndex];
        canvas.drawRect(
          Rect.fromLTWH(
            plot.left + x * cellWidth,
            plot.top + y * rowHeight,
            cellWidth + .5,
            rowHeight + .5,
          ),
          cellPaint,
        );
      }
    }
    final borderPaint = Paint()
      ..color = const Color(0xff9eb4c2)
      ..style = PaintingStyle.stroke;
    canvas.drawRect(plot, borderPaint);
  }

  @override
  bool shouldRepaint(covariant _WaterfallPainter oldDelegate) =>
      oldDelegate.rows != rows ||
      oldDelegate.floorDbfs != floorDbfs ||
      oldDelegate.referenceDbfs != referenceDbfs;
}
