import 'package:flutter_pusu/agent/instrument_agent.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  InstrumentAgentSnapshot snapshot({
    bool connected = true,
    bool responsive = true,
    String mode = 'spectrum',
  }) {
    return InstrumentAgentSnapshot(
      connected: connected,
      deviceResponsive: responsive,
      measurementMode: mode,
      startHz: 50e6,
      stopHz: 1.5e9,
      rbwHz: 1e6,
      vbwMode: 'VBW=RBW',
      vbwHz: 1e6,
      detector: '平均',
      referenceDbm: 0,
      pointCount: 128,
      sweepRunning: false,
      continuousSweep: false,
      minimumFrequencyHz: 50e6,
      maximumFrequencyHz: 1.5e9,
    );
  }

  InstrumentAgentGateway gateway(
    InstrumentAgentSnapshot state, {
    SetFrequencyAction? setFrequency,
    ConfigureRealtimeSpectrumAction? configureRealtimeSpectrum,
    RealtimeSpectrumWaterfallHistoryAction? getRealtimeWaterfallHistory,
    SaveRealtimeMeasurementAction? saveRealtimeMeasurement,
    CaptureScreenshotAction? captureScreenshot,
    StartPhaseNoiseMeasurementAction? startPhaseNoiseMeasurement,
    ConfigurePhaseNoiseAction? configurePhaseNoise,
    AnalyzePhaseNoiseAction? analyzePhaseNoise,
  }) {
    const success = InstrumentActionOutcome(
      success: true,
      message: 'ok',
    );
    return InstrumentAgentGateway(
      snapshotProvider: () => state,
      setFrequency: setFrequency ?? ((_, __) async => success),
      setBandwidth: (_, __, ___) async => success,
      setDetector: (_) async => success,
      setMeasurementMode: (_) async => success,
      startSingleSweep: () async => success,
      startContinuousSweep: () async => success,
      stopMeasurement: () async => success,
      startPhaseNoiseMeasurement:
          startPhaseNoiseMeasurement ?? ((_, __) async => success),
      stopPhaseNoiseMeasurement: () async => success,
      getPhaseNoiseState: () async => success,
      configurePhaseNoise: configurePhaseNoise ?? ((_) async => success),
      analyzePhaseNoise: analyzePhaseNoise ?? ((_, __, ___) async => success),
      startRealtimeSpectrum: (_) async => success,
      stopRealtimeSpectrum: () async => success,
      getSpectrumSnapshot: (_) async => success,
      analyzeSpectrum: (_, __) async => success,
      placePeakMarkers: (_, __) async => success,
      getRealtimeSpectrumState: () async => success,
      configureRealtimeSpectrum:
          configureRealtimeSpectrum ?? ((_) async => success),
      getRealtimeSpectrumSnapshot: (_, __) async => success,
      getRealtimeWaterfallHistory:
          getRealtimeWaterfallHistory ?? ((_, __, ___) async => success),
      analyzeRealtimeSpectrum: (_, __, ___) async => success,
      placeRealtimePeakMarkers: (_, __, ___) async => success,
      saveMeasurement: (_, __) async => success,
      saveRealtimeMeasurement: saveRealtimeMeasurement ??
          ((_, __, ___, ____, _____) async => success),
      captureScreenshot: captureScreenshot ?? (() async => success),
      getTestSession: () async => success,
      startTestSession: (_, __) async => success,
      addTestNote: (_) async => success,
      endTestSession: (_) async => success,
      listTestSessions: (_) async => success,
      listMeasurements: (_) async => success,
      loadMeasurement: (_) async => success,
      compareMeasurements: (_, __) async => success,
      evaluateSpectrumLimits: (_, __, ___) async => success,
      clearAnalysisOverlays: () async => success,
      exportTestReport: (_) async => success,
    );
  }

  test('state query is read-only and works while disconnected', () async {
    final agent = gateway(snapshot(connected: false, responsive: false));
    const call = InstrumentToolCall(
      id: 'state-1',
      name: 'get_instrument_state',
      arguments: <String, dynamic>{},
    );

    final result = await agent.execute(call);

    expect(agent.isReadOnly(call.name), isTrue);
    expect(result.success, isTrue);
    expect(result.data['connected'], isFalse);
  });

  test('mutating tool is rejected while disconnected', () async {
    var invoked = false;
    final agent = gateway(
      snapshot(connected: false),
      setFrequency: (center, span) async {
        invoked = true;
        return const InstrumentActionOutcome(success: true, message: 'ok');
      },
    );

    final result = await agent.execute(const InstrumentToolCall(
      id: 'frequency-1',
      name: 'set_frequency',
      arguments: <String, dynamic>{
        'center_hz': 775e6,
        'span_hz': 100e6,
      },
    ));

    expect(result.success, isFalse);
    expect(result.message, contains('串口未连接'));
    expect(invoked, isFalse);
  });

  test('frequency tool validates hardware range before callback', () async {
    var invoked = false;
    final agent = gateway(
      snapshot(),
      setFrequency: (center, span) async {
        invoked = true;
        return const InstrumentActionOutcome(success: true, message: 'ok');
      },
    );

    final result = await agent.execute(const InstrumentToolCall(
      id: 'frequency-2',
      name: 'set_frequency',
      arguments: <String, dynamic>{
        'center_hz': 1.49e9,
        'span_hz': 100e6,
      },
    ));

    expect(result.success, isFalse);
    expect(result.message, contains('超出仪器范围'));
    expect(invoked, isFalse);
  });

  test('valid frequency request invokes typed callback', () async {
    double? receivedCenter;
    double? receivedSpan;
    final agent = gateway(
      snapshot(),
      setFrequency: (center, span) async {
        receivedCenter = center;
        receivedSpan = span;
        return const InstrumentActionOutcome(
          success: true,
          message: 'ACK',
          data: <String, dynamic>{'device_ack': true},
        );
      },
    );

    final result = await agent.execute(const InstrumentToolCall(
      id: 'frequency-3',
      name: 'set_frequency',
      arguments: <String, dynamic>{
        'center_hz': 775e6,
        'span_hz': 100e6,
      },
    ));

    expect(result.success, isTrue);
    expect(receivedCenter, 775e6);
    expect(receivedSpan, 100e6);
    expect(result.data['device_ack'], isTrue);
  });

  test('tool registry exposes instrument and spectrum tools', () {
    final names = gateway(snapshot())
        .toolDefinitions
        .map((tool) => (tool['function'] as Map)['name']);

    expect(
      names,
      containsAll(<String>[
        'get_instrument_state',
        'set_measurement_mode',
        'set_frequency',
        'set_bandwidth',
        'set_detector',
        'start_single_sweep',
        'start_continuous_sweep',
        'stop_measurement',
        'start_phase_noise_measurement',
        'stop_phase_noise_measurement',
        'get_phase_noise_state',
        'configure_phase_noise',
        'analyze_phase_noise',
        'start_realtime_spectrum',
        'stop_realtime_spectrum',
        'get_realtime_spectrum_state',
        'configure_realtime_spectrum',
        'get_realtime_spectrum_snapshot',
        'get_realtime_waterfall_history',
        'analyze_realtime_spectrum',
        'place_realtime_peak_markers',
        'get_spectrum_snapshot',
        'analyze_spectrum',
        'place_peak_markers',
        'save_measurement',
        'capture_screenshot',
        'get_test_session',
        'start_test_session',
        'add_test_note',
        'end_test_session',
        'list_test_sessions',
        'list_measurements',
        'load_measurement',
        'compare_measurements',
        'evaluate_spectrum_limits',
        'clear_analysis_overlays',
        'export_test_report',
      ]),
    );
  });

  test('save tools are exposed only for their matching measurement mode', () {
    final spectrumNames = gateway(snapshot(mode: 'spectrum'))
        .toolDefinitions
        .map((tool) => (tool['function'] as Map)['name']);
    final realtimeNames = gateway(snapshot(mode: 'realtime_spectrum'))
        .toolDefinitions
        .map((tool) => (tool['function'] as Map)['name']);
    final phaseNoiseNames = gateway(snapshot(mode: 'phase_noise'))
        .toolDefinitions
        .map((tool) => (tool['function'] as Map)['name']);

    expect(spectrumNames, contains('save_measurement'));
    expect(spectrumNames, isNot(contains('save_realtime_measurement')));
    expect(realtimeNames, contains('save_realtime_measurement'));
    expect(realtimeNames, isNot(contains('save_measurement')));
    expect(phaseNoiseNames, isNot(contains('save_measurement')));
    expect(phaseNoiseNames, isNot(contains('save_realtime_measurement')));
    expect(phaseNoiseNames, contains('capture_screenshot'));
  });

  test('realtime save forwards dBFS trace and waterfall options', () async {
    String? receivedLabel;
    String? receivedTrace;
    bool? receivedWaterfall;
    int? receivedRows;
    final agent = gateway(
      snapshot(mode: 'realtime_spectrum'),
      saveRealtimeMeasurement:
          (label, note, trace, includeWaterfall, rows) async {
        receivedLabel = label;
        receivedTrace = trace;
        receivedWaterfall = includeWaterfall;
        receivedRows = rows;
        return const InstrumentActionOutcome(success: true, message: 'ok');
      },
    );

    final result = await agent.execute(const InstrumentToolCall(
      id: 'save-rt',
      name: 'save_realtime_measurement',
      arguments: <String, dynamic>{
        'label': '1 GHz 实时频谱',
        'trace': 'average',
        'include_waterfall': true,
        'waterfall_rows': 30,
      },
    ));

    expect(result.success, isTrue);
    expect(receivedLabel, '1 GHz 实时频谱');
    expect(receivedTrace, 'average');
    expect(receivedWaterfall, isTrue);
    expect(receivedRows, 30);
  });

  test('screenshot tool works in phase noise mode while disconnected',
      () async {
    var invoked = false;
    final agent = gateway(
      snapshot(mode: 'phase_noise', connected: false, responsive: false),
      captureScreenshot: () async {
        invoked = true;
        return const InstrumentActionOutcome(success: true, message: 'ok');
      },
    );

    final result = await agent.execute(const InstrumentToolCall(
      id: 'capture-phase-noise',
      name: 'capture_screenshot',
      arguments: <String, dynamic>{},
    ));

    expect(result.success, isTrue);
    expect(invoked, isTrue);
  });

  test('realtime start is rejected outside realtime mode', () async {
    final agent = gateway(snapshot(mode: 'spectrum'));

    final result = await agent.execute(const InstrumentToolCall(
      id: 'rt-1',
      name: 'start_realtime_spectrum',
      arguments: <String, dynamic>{'center_hz': 775e6},
    ));

    expect(result.success, isFalse);
    expect(result.message, contains('realtime_spectrum'));
  });

  test('phase noise start is accepted only in phase noise mode', () async {
    bool? receivedWaitForCarrier;
    final agent = gateway(
      snapshot(mode: 'phase_noise'),
      startPhaseNoiseMeasurement: (_, waitForCarrier) async {
        receivedWaitForCarrier = waitForCarrier;
        return const InstrumentActionOutcome(success: true, message: 'ok');
      },
    );

    final result = await agent.execute(const InstrumentToolCall(
      id: 'pn-1',
      name: 'start_phase_noise_measurement',
      arguments: <String, dynamic>{
        'continuous': true,
        'wait_for_carrier': true,
      },
    ));

    expect(result.success, isTrue);
    expect(receivedWaitForCarrier, isTrue);
  });

  test('phase noise configuration and offset analysis use dedicated tools',
      () async {
    Map<String, dynamic>? receivedConfiguration;
    double? receivedOffset;
    final agent = gateway(
      snapshot(mode: 'phase_noise'),
      configurePhaseNoise: (arguments) async {
        receivedConfiguration = arguments;
        return const InstrumentActionOutcome(success: true, message: 'ok');
      },
      analyzePhaseNoise: (trace, offset, timeout) async {
        receivedOffset = offset;
        return const InstrumentActionOutcome(success: true, message: 'ok');
      },
    );

    final configured = await agent.execute(const InstrumentToolCall(
      id: 'pn-config',
      name: 'configure_phase_noise',
      arguments: <String, dynamic>{
        'carrier_mode': 'manual',
        'carrier_hz': 438e6,
        'start_offset_hz': 1e3,
        'stop_offset_hz': 100e3,
      },
    ));
    expect(configured.success, isTrue);
    expect(receivedConfiguration?['carrier_hz'], 438e6);

    final analyzed = await agent.execute(const InstrumentToolCall(
      id: 'pn-analyze',
      name: 'analyze_phase_noise',
      arguments: <String, dynamic>{
        'offset_hz': 10e3,
        'trace': 'average',
        'wait_timeout_ms': 10000,
      },
    ));
    expect(analyzed.success, isTrue);
    expect(receivedOffset, 10e3);
    expect(agent.isReadOnly('analyze_phase_noise'), isTrue);
    expect(agent.isReadOnly('configure_phase_noise'), isFalse);
  });

  test('phase noise tools reject offsets below 1 kHz', () async {
    var configureInvoked = false;
    var analyzeInvoked = false;
    final agent = gateway(
      snapshot(mode: 'phase_noise'),
      configurePhaseNoise: (_) async {
        configureInvoked = true;
        return const InstrumentActionOutcome(success: true, message: 'ok');
      },
      analyzePhaseNoise: (_, __, ___) async {
        analyzeInvoked = true;
        return const InstrumentActionOutcome(success: true, message: 'ok');
      },
    );

    final configured = await agent.execute(const InstrumentToolCall(
      id: 'pn-config-below-minimum',
      name: 'configure_phase_noise',
      arguments: <String, dynamic>{
        'start_offset_hz': 999,
        'stop_offset_hz': 100e3,
      },
    ));
    final analyzed = await agent.execute(const InstrumentToolCall(
      id: 'pn-analyze-below-minimum',
      name: 'analyze_phase_noise',
      arguments: <String, dynamic>{'offset_hz': 999},
    ));

    expect(configured.success, isFalse);
    expect(configured.message, contains('1 kHz'));
    expect(configureInvoked, isFalse);
    expect(analyzed.success, isFalse);
    expect(analyzed.message, contains('1 kHz'));
    expect(analyzeInvoked, isFalse);
  });

  test('phase noise analysis does not wait by default', () async {
    int? receivedTimeout;
    final agent = gateway(
      snapshot(mode: 'phase_noise'),
      analyzePhaseNoise: (_, __, timeout) async {
        receivedTimeout = timeout;
        return const InstrumentActionOutcome(success: true, message: 'ok');
      },
    );

    final result = await agent.execute(const InstrumentToolCall(
      id: 'pn-analyze-no-wait',
      name: 'analyze_phase_noise',
      arguments: <String, dynamic>{'offset_hz': 10e3},
    ));

    expect(result.success, isTrue);
    expect(receivedTimeout, 0);
  });

  test('realtime analysis tools are isolated from standard spectrum mode',
      () async {
    final spectrumAgent = gateway(snapshot(mode: 'spectrum'));
    final rejected = await spectrumAgent.execute(const InstrumentToolCall(
      id: 'rt-analysis-wrong-mode',
      name: 'analyze_realtime_spectrum',
      arguments: <String, dynamic>{'trace': 'latest'},
    ));
    expect(rejected.success, isFalse);
    expect(rejected.message, contains('realtime_spectrum'));

    final realtimeAgent = gateway(snapshot(mode: 'realtime_spectrum'));
    final accepted = await realtimeAgent.execute(const InstrumentToolCall(
      id: 'rt-analysis-correct-mode',
      name: 'analyze_realtime_spectrum',
      arguments: <String, dynamic>{
        'trace': 'average',
        'peak_count': 4,
        'threshold_above_noise_db': 8,
      },
    ));
    expect(accepted.success, isTrue);
    expect(realtimeAgent.isReadOnly('analyze_realtime_spectrum'), isTrue);
    expect(realtimeAgent.isReadOnly('get_realtime_waterfall_history'), isTrue);
    expect(realtimeAgent.isReadOnly('configure_realtime_spectrum'), isFalse);
  });

  test('realtime waterfall history forwards bounded read parameters', () async {
    int? receivedRows;
    double? receivedLookback;
    int? receivedPoints;
    final agent = gateway(
      snapshot(mode: 'realtime_spectrum'),
      getRealtimeWaterfallHistory: (rows, lookback, points) async {
        receivedRows = rows;
        receivedLookback = lookback;
        receivedPoints = points;
        return const InstrumentActionOutcome(success: true, message: 'ok');
      },
    );

    final result = await agent.execute(const InstrumentToolCall(
      id: 'rt-waterfall-history',
      name: 'get_realtime_waterfall_history',
      arguments: <String, dynamic>{
        'maximum_rows': 12,
        'lookback_seconds': 4.5,
        'maximum_points_per_row': 48,
      },
    ));

    expect(result.success, isTrue);
    expect(receivedRows, 12);
    expect(receivedLookback, 4.5);
    expect(receivedPoints, 48);
  });

  test('realtime configuration validates DSA step and trace parameters',
      () async {
    final agent = gateway(snapshot(mode: 'realtime_spectrum'));

    final badDsa = await agent.execute(const InstrumentToolCall(
      id: 'rt-bad-dsa',
      name: 'configure_realtime_spectrum',
      arguments: <String, dynamic>{'attenuation_db': 1.1},
    ));
    expect(badDsa.success, isFalse);
    expect(badDsa.message, contains('0.25'));

    final badTrace = await agent.execute(const InstrumentToolCall(
      id: 'rt-bad-trace',
      name: 'get_realtime_spectrum_snapshot',
      arguments: <String, dynamic>{
        'trace': 'unknown',
        'maximum_points': 128,
      },
    ));
    expect(badTrace.success, isFalse);
    expect(badTrace.message, contains('trace'));

    final badWaterfall = await agent.execute(const InstrumentToolCall(
      id: 'rt-bad-waterfall',
      name: 'get_realtime_waterfall_history',
      arguments: <String, dynamic>{
        'maximum_rows': 61,
        'maximum_points_per_row': 64,
      },
    ));
    expect(badWaterfall.success, isFalse);
    expect(badWaterfall.message, contains('瀑布历史'));
  });

  test('realtime RF configuration requires a responsive device', () async {
    var invoked = false;
    final agent = gateway(
      snapshot(
        mode: 'realtime_spectrum',
        connected: false,
        responsive: false,
      ),
      configureRealtimeSpectrum: (_) async {
        invoked = true;
        return const InstrumentActionOutcome(success: true, message: 'ok');
      },
    );

    final result = await agent.execute(const InstrumentToolCall(
      id: 'rt-rf-offline',
      name: 'configure_realtime_spectrum',
      arguments: <String, dynamic>{'lna_enabled': true},
    ));
    expect(result.success, isFalse);
    expect(result.message, contains('串口未连接'));
    expect(invoked, isFalse);
  });
}
