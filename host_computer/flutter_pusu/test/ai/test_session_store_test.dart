import 'dart:io';
import 'dart:convert';

import 'package:flutter_pusu/agent/test_session_store.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late Directory temporaryDirectory;
  late AgentTestSessionStore store;

  setUp(() async {
    temporaryDirectory = await Directory.systemTemp.createTemp(
      'pusu_agent_session_test_',
    );
    store = AgentTestSessionStore(temporaryDirectory);
  });

  tearDown(() async {
    if (await temporaryDirectory.exists()) {
      await temporaryDirectory.delete(recursive: true);
    }
  });

  test('session persists notes and registered measurements', () async {
    final started = await store.start(
      name: '发射机验收',
      objective: '检查主峰和杂散',
    );
    await store.addNote('室温 25 摄氏度');
    await store.registerMeasurement(
      label: '满功率',
      savedAt: DateTime(2026, 8, 5, 12),
      jsonPath: '${temporaryDirectory.path}${Platform.pathSeparator}m1.json',
      csvPath: '${temporaryDirectory.path}${Platform.pathSeparator}m1.csv',
      analysis: <String, dynamic>{'noise_floor_dbm': -100},
    );

    final restoredStore = AgentTestSessionStore(temporaryDirectory);
    final restored = await restoredStore.restoreActiveSession();

    expect(restored?.id, started.id);
    expect(restored?.notes.single['content'], '室温 25 摄氏度');
    expect(restored?.measurements.single['label'], '满功率');
  });

  test('ending a session clears active state and keeps history', () async {
    await store.start(name: '测试 A', objective: '目标');
    final ended = await store.end(summary: '测试通过');

    expect(store.activeSession, isNull);
    expect(ended.status, 'completed');
    expect(ended.notes.last['kind'], 'closing_summary');

    final history = await store.list();
    expect(history, hasLength(1));
    expect(history.single.status, 'completed');
  });

  test('cannot start two active sessions', () async {
    await store.start(name: '测试 A', objective: '');

    expect(
      () => store.start(name: '测试 B', objective: ''),
      throwsStateError,
    );
  });

  test('measurement index loads saved spectrum records', () async {
    final recordFile = File(
      '${temporaryDirectory.path}${Platform.pathSeparator}measurement_a.json',
    );
    await recordFile.writeAsString(jsonEncode(<String, dynamic>{
      'saved_at': '2026-08-05T12:00:00.000',
      'label': '测量 A',
      'analysis': <String, dynamic>{'noise_floor_dbm': -100},
      'spectrum_points': <Map<String, dynamic>>[
        <String, dynamic>{'frequency_hz': 100e6, 'power_dbm': -80},
      ],
    }));

    final summaries = await store.listMeasurements();
    final loaded = await store.loadMeasurement('measurement_a');

    expect(summaries.single['label'], '测量 A');
    expect(loaded['id'], 'measurement_a');
    expect(loaded['spectrum_points'], hasLength(1));
  });

  test('measurement index includes realtime dBFS records', () async {
    final recordFile = File(
      '${temporaryDirectory.path}${Platform.pathSeparator}measurement_rt.json',
    );
    await recordFile.writeAsString(jsonEncode(<String, dynamic>{
      'saved_at': '2026-08-08T12:00:00.000',
      'label': '实时频谱 A',
      'measurement_mode': 'realtime_spectrum',
      'amplitude_unit': 'dBFS',
      'analysis': <String, dynamic>{'noise_floor_dbfs': -95},
      'realtime_spectrum_points': <Map<String, dynamic>>[
        <String, dynamic>{'frequency_hz': 1e9, 'level_dbfs': -63},
      ],
    }));

    final summaries = await store.listMeasurements();
    final loaded = await store.loadMeasurement('measurement_rt');

    expect(summaries.single['measurement_mode'], 'realtime_spectrum');
    expect(summaries.single['amplitude_unit'], 'dBFS');
    expect(loaded['realtime_spectrum_points'], hasLength(1));
  });

  test('measurement index includes phase-noise dBc per Hz records', () async {
    final recordFile = File(
      '${temporaryDirectory.path}${Platform.pathSeparator}measurement_pn.json',
    );
    await recordFile.writeAsString(jsonEncode(<String, dynamic>{
      'saved_at': '2026-08-08T12:30:00.000',
      'label': '相位噪声 A',
      'measurement_mode': 'phase_noise',
      'amplitude_unit': 'dBc/Hz',
      'analysis': <String, dynamic>{'minimum_dbc_per_hz': -140},
      'phase_noise_points': <Map<String, dynamic>>[
        <String, dynamic>{
          'offset_hz': 1e3,
          'phase_noise_dbc_per_hz': -115,
          'rbw_hz': 1e3,
        },
      ],
    }));

    final summaries = await store.listMeasurements();
    final loaded = await store.loadMeasurement('measurement_pn');

    expect(summaries.single['measurement_mode'], 'phase_noise');
    expect(summaries.single['amplitude_unit'], 'dBc/Hz');
    expect(summaries.single['point_count'], 1);
    expect(loaded['phase_noise_points'], hasLength(1));
  });

  test('HTML report is generated for a persisted session', () async {
    final session = await store.start(name: '报告测试', objective: '验证报告');
    await store.addNote('备注 <需要转义>');
    await store.end(summary: '完成');

    final reportPath = await store.exportHtmlReport(session.id);
    final html = await File(reportPath).readAsString();

    expect(html, contains('PuSuSA 频谱仪测试报告'));
    expect(html, contains('备注 &lt;需要转义&gt;'));
  });
}
