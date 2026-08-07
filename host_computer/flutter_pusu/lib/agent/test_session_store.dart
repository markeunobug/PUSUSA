import 'dart:convert';
import 'dart:io';

class AgentTestSession {
  AgentTestSession({
    required this.id,
    required this.name,
    required this.objective,
    required this.startedAt,
    this.endedAt,
    this.status = 'active',
    List<Map<String, dynamic>>? notes,
    List<Map<String, dynamic>>? measurements,
  })  : notes = notes ?? <Map<String, dynamic>>[],
        measurements = measurements ?? <Map<String, dynamic>>[];

  final String id;
  final String name;
  final String objective;
  final DateTime startedAt;
  DateTime? endedAt;
  String status;
  final List<Map<String, dynamic>> notes;
  final List<Map<String, dynamic>> measurements;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'file_version': 1,
        'id': id,
        'name': name,
        'objective': objective,
        'status': status,
        'started_at': startedAt.toIso8601String(),
        'ended_at': endedAt?.toIso8601String(),
        'notes': notes,
        'measurements': measurements,
      };

  factory AgentTestSession.fromJson(Map<String, dynamic> json) {
    List<Map<String, dynamic>> maps(dynamic value) {
      if (value is! List) return <Map<String, dynamic>>[];
      return value
          .whereType<Map>()
          .map((item) => Map<String, dynamic>.from(item))
          .toList();
    }

    return AgentTestSession(
      id: json['id']?.toString() ?? '',
      name: json['name']?.toString() ?? '未命名测试',
      objective: json['objective']?.toString() ?? '',
      status: json['status']?.toString() ?? 'active',
      startedAt: DateTime.tryParse(json['started_at']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
      endedAt: DateTime.tryParse(json['ended_at']?.toString() ?? ''),
      notes: maps(json['notes']),
      measurements: maps(json['measurements']),
    );
  }
}

class AgentTestSessionStore {
  AgentTestSessionStore(this.rootDirectory);

  final Directory rootDirectory;
  AgentTestSession? _activeSession;

  AgentTestSession? get activeSession => _activeSession;

  Directory? get activeSessionDirectory {
    final session = _activeSession;
    if (session == null) return null;
    return Directory(
      '${rootDirectory.path}${Platform.pathSeparator}${session.id}',
    );
  }

  Future<AgentTestSession?> restoreActiveSession() async {
    final sessions = await _readAllSessions();
    final active = sessions.where((session) => session.status == 'active');
    _activeSession = active.isEmpty ? null : active.first;
    return _activeSession;
  }

  Future<AgentTestSession> start({
    required String name,
    required String objective,
  }) async {
    if (_activeSession != null) {
      throw StateError('已有进行中的测试会话，请先结束当前会话');
    }
    final now = DateTime.now();
    final session = AgentTestSession(
      id: '${_fileTimestamp(now)}_'
          '${now.millisecond.toString().padLeft(3, '0')}_${_slug(name)}',
      name: name.trim(),
      objective: objective.trim(),
      startedAt: now,
    );
    _activeSession = session;
    await _write(session);
    return session;
  }

  Future<AgentTestSession> addNote(String content) async {
    final session = _requireActive();
    session.notes.add(<String, dynamic>{
      'created_at': DateTime.now().toIso8601String(),
      'content': content.trim(),
    });
    await _write(session);
    return session;
  }

  Future<AgentTestSession> registerMeasurement({
    required String label,
    required DateTime savedAt,
    required String jsonPath,
    required String csvPath,
    required Map<String, dynamic> analysis,
    String measurementMode = 'spectrum',
    String amplitudeUnit = 'dBm',
    Map<String, dynamic>? limitEvaluation,
  }) async {
    final session = _requireActive();
    session.measurements.add(<String, dynamic>{
      'id': _baseNameWithoutExtension(jsonPath),
      'label': label,
      'saved_at': savedAt.toIso8601String(),
      'json_path': jsonPath,
      'csv_path': csvPath,
      'measurement_mode': measurementMode,
      'amplitude_unit': amplitudeUnit,
      'analysis': analysis,
      if (limitEvaluation != null) 'limit_evaluation': limitEvaluation,
    });
    await _write(session);
    return session;
  }

  Future<AgentTestSession> end({String summary = ''}) async {
    final session = _requireActive();
    if (summary.trim().isNotEmpty) {
      session.notes.add(<String, dynamic>{
        'created_at': DateTime.now().toIso8601String(),
        'content': summary.trim(),
        'kind': 'closing_summary',
      });
    }
    session
      ..status = 'completed'
      ..endedAt = DateTime.now();
    await _write(session);
    _activeSession = null;
    return session;
  }

  Future<List<AgentTestSession>> list({int limit = 20}) async {
    final sessions = await _readAllSessions();
    return sessions.take(limit.clamp(1, 100)).toList();
  }

  Future<List<Map<String, dynamic>>> listMeasurements({int limit = 50}) async {
    final records = await _readAllMeasurementRecords();
    return records.take(limit.clamp(1, 200)).map(_measurementSummary).toList();
  }

  Future<Map<String, dynamic>> loadMeasurement(String id) async {
    final records = await _readAllMeasurementRecords();
    for (final record in records) {
      if (record['id'] == id) return record;
    }
    throw StateError('未找到测量记录：$id');
  }

  Future<AgentTestSession> loadSession(String id) async {
    final sessions = await _readAllSessions();
    for (final session in sessions) {
      if (session.id == id) return session;
    }
    throw StateError('未找到测试会话：$id');
  }

  Future<String> exportHtmlReport(String sessionId) async {
    final session = await loadSession(sessionId);
    final directory = Directory(
      '${rootDirectory.path}${Platform.pathSeparator}${session.id}',
    );
    await directory.create(recursive: true);
    final generatedAt = DateTime.now();
    final report = File(
      '${directory.path}${Platform.pathSeparator}'
      'report_${_fileTimestamp(generatedAt)}.html',
    );
    await report.writeAsString(
      _buildHtmlReport(session, generatedAt),
      flush: true,
    );
    return report.path;
  }

  AgentTestSession _requireActive() {
    final session = _activeSession;
    if (session == null) {
      throw StateError('当前没有进行中的测试会话');
    }
    return session;
  }

  Future<void> _write(AgentTestSession session) async {
    final directory = Directory(
      '${rootDirectory.path}${Platform.pathSeparator}${session.id}',
    );
    await directory.create(recursive: true);
    final file = File(
      '${directory.path}${Platform.pathSeparator}session.json',
    );
    const encoder = JsonEncoder.withIndent('  ');
    await file.writeAsString(encoder.convert(session.toJson()), flush: true);
  }

  Future<List<AgentTestSession>> _readAllSessions() async {
    if (!await rootDirectory.exists()) return <AgentTestSession>[];
    final sessions = <AgentTestSession>[];
    await for (final entity in rootDirectory.list(followLinks: false)) {
      if (entity is! Directory) continue;
      final file = File(
        '${entity.path}${Platform.pathSeparator}session.json',
      );
      if (!await file.exists()) continue;
      try {
        final decoded = jsonDecode(await file.readAsString());
        if (decoded is Map) {
          final session = AgentTestSession.fromJson(
            Map<String, dynamic>.from(decoded),
          );
          if (session.id.isNotEmpty) sessions.add(session);
        }
      } catch (_) {
        // 单个损坏的会话文件不应阻止读取其余历史记录。
      }
    }
    sessions.sort((a, b) => b.startedAt.compareTo(a.startedAt));
    return sessions;
  }

  Future<List<Map<String, dynamic>>> _readAllMeasurementRecords() async {
    if (!await rootDirectory.exists()) return <Map<String, dynamic>>[];
    final records = <Map<String, dynamic>>[];
    await for (final entity
        in rootDirectory.list(recursive: true, followLinks: false)) {
      if (entity is! File ||
          !entity.path.toLowerCase().endsWith('.json') ||
          _baseNameWithoutExtension(entity.path) == 'session') {
        continue;
      }
      try {
        final decoded = jsonDecode(await entity.readAsString());
        if (decoded is! Map ||
            (decoded['spectrum_points'] is! List &&
                decoded['realtime_spectrum_points'] is! List)) {
          continue;
        }
        final record = Map<String, dynamic>.from(decoded)
          ..['id'] = _baseNameWithoutExtension(entity.path)
          ..['json_path'] = entity.path;
        records.add(record);
      } catch (_) {
        // 忽略损坏或不属于 AI 测量记录的 JSON 文件。
      }
    }
    records.sort((a, b) => _recordTime(b).compareTo(_recordTime(a)));
    return records;
  }

  static Map<String, dynamic> _measurementSummary(
    Map<String, dynamic> record,
  ) {
    final points =
        record['spectrum_points'] ?? record['realtime_spectrum_points'];
    return <String, dynamic>{
      'id': record['id'],
      'label': record['label'],
      'note': record['note'],
      'saved_at': record['saved_at'],
      'point_count': points is List ? points.length : 0,
      'measurement_mode': record['measurement_mode'] ?? 'spectrum',
      'amplitude_unit': record['amplitude_unit'] ?? 'dBm',
      'analysis': record['analysis'],
      'json_path': record['json_path'],
    };
  }

  static DateTime _recordTime(Map<String, dynamic> record) =>
      DateTime.tryParse(record['saved_at']?.toString() ?? '') ??
      DateTime.fromMillisecondsSinceEpoch(0);

  static String _buildHtmlReport(
    AgentTestSession session,
    DateTime generatedAt,
  ) {
    String escape(Object? value) => const HtmlEscape().convert(
          value?.toString() ?? '',
        );
    String number(dynamic value, [int digits = 2]) {
      if (value is num) return value.toStringAsFixed(digits);
      return '--';
    }

    final noteRows = session.notes.map((note) {
      return '<tr><td>${escape(note['created_at'])}</td>'
          '<td>${escape(note['content'])}</td></tr>';
    }).join();
    final measurementRows = session.measurements.map((measurement) {
      final analysis = measurement['analysis'] is Map
          ? Map<String, dynamic>.from(measurement['analysis'] as Map)
          : const <String, dynamic>{};
      final peaks = analysis['peaks'];
      final mainPeak = peaks is List && peaks.isNotEmpty && peaks.first is Map
          ? Map<String, dynamic>.from(peaks.first as Map)
          : const <String, dynamic>{};
      final limitEvaluation = measurement['limit_evaluation'] is Map
          ? Map<String, dynamic>.from(measurement['limit_evaluation'] as Map)
          : const <String, dynamic>{};
      final verdict = limitEvaluation['passed'] is bool
          ? (limitEvaluation['passed'] == true ? 'PASS' : 'FAIL')
          : '--';
      final amplitudeUnit =
          measurement['amplitude_unit'] ?? analysis['amplitude_unit'] ?? 'dBm';
      final noiseFloor =
          analysis['noise_floor_dbfs'] ?? analysis['noise_floor_dbm'];
      final mainPeakLevel = mainPeak['level_dbfs'] ?? mainPeak['power_dbm'];
      return '<tr><td>${escape(measurement['saved_at'])}</td>'
          '<td>${escape(measurement['label'])}</td>'
          '<td>${escape(measurement['measurement_mode'] ?? 'spectrum')}</td>'
          '<td>${escape(amplitudeUnit)}</td>'
          '<td>${number(noiseFloor)}</td>'
          '<td>${number(mainPeak['frequency_hz'], 0)}</td>'
          '<td>${number(mainPeakLevel)}</td>'
          '<td>${escape(verdict)}</td>'
          '<td>${escape(measurement['json_path'])}</td></tr>';
    }).join();
    return '''<!doctype html>
<html lang="zh-CN"><head><meta charset="utf-8">
<title>${escape(session.name)} - PuSuSA 测试报告</title>
<style>
body{font-family:"Microsoft YaHei",sans-serif;margin:40px;color:#20242a}
h1{margin-bottom:4px} .meta{color:#606872;margin-bottom:24px}
table{border-collapse:collapse;width:100%;margin:12px 0 28px}
th,td{border:1px solid #ccd2da;padding:8px;text-align:left;font-size:13px}
th{background:#eef2f6} .status{font-weight:700}
</style></head><body>
<h1>PuSuSA 频谱仪测试报告</h1>
<div class="meta">生成时间：${escape(generatedAt.toIso8601String())}</div>
<h2>${escape(session.name)}</h2>
<p><span class="status">状态：</span>${escape(session.status)}</p>
<p><b>测试目标：</b>${escape(session.objective)}</p>
<p><b>开始：</b>${escape(session.startedAt.toIso8601String())}<br>
<b>结束：</b>${escape(session.endedAt?.toIso8601String() ?? '--')}</p>
<h2>测试备注</h2>
<table><thead><tr><th>时间</th><th>内容</th></tr></thead>
<tbody>$noteRows</tbody></table>
<h2>测量记录</h2>
<table><thead><tr><th>时间</th><th>名称</th><th>模式</th><th>单位</th><th>噪声底</th>
<th>主峰频率 (Hz)</th><th>主峰电平</th><th>判定</th><th>数据文件</th></tr></thead>
<tbody>$measurementRows</tbody></table>
</body></html>''';
  }

  static String _baseNameWithoutExtension(String path) {
    final name = path.split(RegExp(r'[/\\]')).last;
    final dot = name.lastIndexOf('.');
    return dot <= 0 ? name : name.substring(0, dot);
  }

  static String _slug(String value) {
    final slug = value
        .trim()
        .replaceAll(RegExp(r'[<>:"/\\|?*\x00-\x1F]'), '_')
        .replaceAll(RegExp(r'[. ]+$'), '')
        .replaceAll(RegExp(r'\s+'), '_');
    if (slug.isEmpty) return 'test';
    return slug.length <= 40 ? slug : slug.substring(0, 40);
  }

  static String _fileTimestamp(DateTime value) {
    return '${value.year.toString().padLeft(4, '0')}'
        '${value.month.toString().padLeft(2, '0')}'
        '${value.day.toString().padLeft(2, '0')}_'
        '${value.hour.toString().padLeft(2, '0')}'
        '${value.minute.toString().padLeft(2, '0')}'
        '${value.second.toString().padLeft(2, '0')}';
  }
}
