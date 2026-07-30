import 'dart:async';
import 'dart:math' as math;

import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart';

import 'device_models.dart';
import 'realtime_spectrum_controls.dart';
import 'realtime_spectrum_models.dart';
import 'realtime_spectrum_processor.dart';
import 'realtime_spectrum_settings.dart';
import 'serial_protocol.dart';

class RealtimeSpectrumPage extends StatefulWidget {
  const RealtimeSpectrumPage({
    super.key,
    required this.protocol,
    required this.connected,
  });

  final SerialProtocol protocol;
  final bool connected;

  @override
  State<RealtimeSpectrumPage> createState() => _RealtimeSpectrumPageState();
}

class _RtTransactionCancelled implements Exception {
  const _RtTransactionCancelled();
}

class _RealtimeSpectrumPageState extends State<RealtimeSpectrumPage> {
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

  @override
  void initState() {
    super.initState();
    _restoreSettings();
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
                        average: _processor.average,
                        maxHold: _processor.maxHold,
                        markerEnabled: _markerEnabled,
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
        _buildSidebar(),
      ]),
    );
  }

  Widget _buildSidebar() => Container(
        width: 300,
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
                        onChanged: (_) => _rememberSettings(),
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
                    _controlRow(
                      'LNA：',
                      fluent.ToggleSwitch(
                        checked: _rf.lnaMode == RfLnaMode.enable,
                        onChanged: _busy
                            ? null
                            : (value) => _applyFrontend(
                                  rf: _rf.copyWith(
                                    lnaMode: value
                                        ? RfLnaMode.enable
                                        : RfLnaMode.bypass,
                                    pathMode: RfPathMode.mixerChain,
                                  ),
                                ),
                      ),
                      Text(_rf.lnaMode == RfLnaMode.enable ? '启用' : '旁路'),
                    ),
                    const SizedBox(height: 8),
                    _controlRow(
                      'DSA：',
                      fluent.Slider(
                        value: _rf.attenDb,
                        min: 0,
                        max: 31.75,
                        divisions: 127,
                        label: '${_rf.attenDb.toStringAsFixed(2)} dB',
                        onChanged: _busy
                            ? null
                            : (value) {
                                final code =
                                    (value / .25).round().clamp(0, 127);
                                _applyFrontend(
                                  rf: _rf.copyWith(
                                    attenCode: code,
                                    pathMode: RfPathMode.mixerChain,
                                  ),
                                );
                              },
                      ),
                      Text('${_rf.attenDb.toStringAsFixed(2)} dB'),
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
    required this.minDbfs,
    required this.maxDbfs,
  });
  final RealtimeSpectrumFrame? frame;
  final List<double>? latest;
  final List<double>? average;
  final List<double>? maxHold;
  final bool markerEnabled;
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
      var peak = 0;
      for (var i = 1; i < latest!.length; i++) {
        if (latest![i] > latest![peak]) peak = i;
      }
      final x = plot.left + plot.width * peak / (latest!.length - 1);
      final y = _yFor(latest![peak], plot);
      final markerPaint = Paint()
        ..color = Colors.white
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1;
      canvas.drawLine(Offset(x, plot.top), Offset(x, plot.bottom), markerPaint);
      canvas.drawCircle(Offset(x, y), 4, markerPaint);
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
