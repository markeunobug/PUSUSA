import 'dart:convert';

class AmplitudeCalibrationSample {
  const AmplitudeCalibrationSample({
    required this.rbwHz,
    required this.measuredPowerDbm,
    required this.correctionDb,
    required this.peakFrequencyHz,
    required this.timestamp,
  });

  final double rbwHz;
  final double measuredPowerDbm;
  final double correctionDb;
  final double peakFrequencyHz;
  final DateTime timestamp;

  Map<String, dynamic> toJson() => {
        'rbw_hz': rbwHz,
        'measured_power_dbm': measuredPowerDbm,
        'correction_db': correctionDb,
        'peak_frequency_hz': peakFrequencyHz,
        'timestamp': timestamp.toIso8601String(),
      };

  static AmplitudeCalibrationSample fromJson(Map<String, dynamic> json) {
    return AmplitudeCalibrationSample(
      rbwHz: _readFirstFiniteDouble(json, const [
        'rbw_hz',
        'rbwHz',
        'rbw',
      ]),
      measuredPowerDbm: _readFirstFiniteDouble(json, const [
        'measured_power_dbm',
        'measuredPowerDbm',
        'measured_dbm',
      ]),
      correctionDb: _readFirstFiniteDouble(json, const [
        'correction_db',
        'correctionDb',
        'calibration_db',
      ]),
      peakFrequencyHz: _readFirstFiniteDouble(json, const [
        'peak_frequency_hz',
        'peakFrequencyHz',
        'frequency_hz',
        'freq_hz',
      ]),
      timestamp: DateTime.tryParse(json['timestamp']?.toString() ?? '') ??
          DateTime.fromMillisecondsSinceEpoch(0),
    );
  }
}

class AmplitudeCalibrationPoint {
  const AmplitudeCalibrationPoint({
    required this.frequencyHz,
    required this.referencePowerDbm,
    required this.samples,
  });

  final double frequencyHz;
  final double referencePowerDbm;
  final List<AmplitudeCalibrationSample> samples;

  Map<String, dynamic> toJson() => {
        'frequency_hz': frequencyHz,
        'reference_power_dbm': referencePowerDbm,
        'samples': samples.map((sample) => sample.toJson()).toList(),
      };

  static AmplitudeCalibrationPoint fromJson(Map<String, dynamic> json) {
    final rawSamples = json['samples'];
    final samples = rawSamples is List
        ? rawSamples
            .whereType<Map>()
            .map(_tryParseSample)
            .whereType<AmplitudeCalibrationSample>()
            .toList()
        : <AmplitudeCalibrationSample>[];
    return AmplitudeCalibrationPoint(
      frequencyHz: _readFirstOptionalFiniteDouble(json, const [
            'frequency_hz',
            'freq_hz',
            'frequencyHz',
          ]) ??
          _derivePointFrequencyHz(samples),
      referencePowerDbm: _readFirstOptionalFiniteDouble(json, const [
            'reference_power_dbm',
            'referencePowerDbm',
            'ref_power_dbm',
          ]) ??
          _deriveReferencePowerDbm(samples),
      samples: samples,
    );
  }
}

class AmplitudeCalibrationFile {
  const AmplitudeCalibrationFile({
    this.createdAt,
    this.sourcePath,
    this.deviceName = 'PuSuSA',
    this.deviceSerial = '',
    this.note = '',
    this.cableLossDb = 0.0,
    this.externalAttenDb = 0.0,
    this.points = const [],
  });

  static const String schema = 'pusu_host_amplitude_calibration';
  static const int version = 1;

  final DateTime? createdAt;
  final String? sourcePath;
  final String deviceName;
  final String deviceSerial;
  final String note;
  final double cableLossDb;
  final double externalAttenDb;
  final List<AmplitudeCalibrationPoint> points;

  bool get isEmpty => points.isEmpty;

  int get sampleCount =>
      points.fold(0, (count, point) => count + point.samples.length);

  List<double> get calibratedRbwHz {
    final values = <double>{};
    for (final point in points) {
      for (final sample in point.samples) {
        values.add(sample.rbwHz);
      }
    }
    return values.toList()..sort();
  }

  AmplitudeCalibrationFile copyWith({
    DateTime? createdAt,
    String? sourcePath,
    String? deviceName,
    String? deviceSerial,
    String? note,
    double? cableLossDb,
    double? externalAttenDb,
    List<AmplitudeCalibrationPoint>? points,
  }) {
    return AmplitudeCalibrationFile(
      createdAt: createdAt ?? this.createdAt,
      sourcePath: sourcePath ?? this.sourcePath,
      deviceName: deviceName ?? this.deviceName,
      deviceSerial: deviceSerial ?? this.deviceSerial,
      note: note ?? this.note,
      cableLossDb: cableLossDb ?? this.cableLossDb,
      externalAttenDb: externalAttenDb ?? this.externalAttenDb,
      points: points ?? this.points,
    );
  }

  AmplitudeCalibrationFile appendPoint(
      AmplitudeCalibrationPoint calibrationPoint) {
    final nextPoints = <AmplitudeCalibrationPoint>[
      ...points,
      calibrationPoint,
    ]..sort((a, b) => a.frequencyHz.compareTo(b.frequencyHz));
    return copyWith(points: nextPoints);
  }

  double? correctionDbFor({
    required double rbwHz,
    required double frequencyHz,
    double toleranceHz = 0.5,
  }) {
    final curve = <_CalibrationCurvePoint>[];
    for (final point in points) {
      AmplitudeCalibrationSample? bestSample;
      double bestDelta = double.infinity;
      for (final sample in point.samples) {
        final delta = (sample.rbwHz - rbwHz).abs();
        if (delta < bestDelta) {
          bestDelta = delta;
          bestSample = sample;
        }
      }
      if (bestSample != null && bestDelta <= toleranceHz) {
        curve.add(_CalibrationCurvePoint(
          bestSample.peakFrequencyHz,
          bestSample.correctionDb,
        ));
      }
    }

    if (curve.isEmpty) return null;
    curve.sort((a, b) => a.frequencyHz.compareTo(b.frequencyHz));
    if (curve.length == 1 || frequencyHz <= curve.first.frequencyHz) {
      return curve.first.correctionDb;
    }
    if (frequencyHz >= curve.last.frequencyHz) {
      return curve.last.correctionDb;
    }

    for (var i = 1; i < curve.length; i++) {
      final right = curve[i];
      if (frequencyHz <= right.frequencyHz) {
        final left = curve[i - 1];
        final span = right.frequencyHz - left.frequencyHz;
        if (span <= 0) return left.correctionDb;
        final t = (frequencyHz - left.frequencyHz) / span;
        return left.correctionDb + (right.correctionDb - left.correctionDb) * t;
      }
    }
    return curve.last.correctionDb;
  }

  bool hasRbw(double rbwHz, {double toleranceHz = 0.5}) {
    return calibratedRbwHz.any((value) => (value - rbwHz).abs() <= toleranceHz);
  }

  Map<String, dynamic> toJson() => {
        'schema': schema,
        'version': version,
        'created_at': (createdAt ?? DateTime.now()).toIso8601String(),
        'device': {
          'name': deviceName,
          'serial': deviceSerial,
          'note': note,
        },
        'reference_plane': 'rf_input',
        'source': {
          'model': '',
          'cable_loss_db': cableLossDb,
          'external_atten_db': externalAttenDb,
        },
        'points': points.map((point) => point.toJson()).toList(),
      };

  String toPrettyJson() {
    return const JsonEncoder.withIndent('  ').convert(toJson());
  }

  static AmplitudeCalibrationFile parse(String text, {String? sourcePath}) {
    final decoded = jsonDecode(text);
    if (decoded is! Map) {
      throw const FormatException(
          'Calibration file must contain a JSON object');
    }
    final json = decoded.cast<String, dynamic>();
    if (json['schema'] != schema) {
      throw const FormatException('Unsupported calibration schema');
    }
    if (json['version'] != version) {
      throw const FormatException('Unsupported calibration version');
    }
    final rawPoints = json['points'];
    if (rawPoints is! List || rawPoints.isEmpty) {
      throw const FormatException('Calibration file has no points');
    }

    final device = json['device'] is Map
        ? (json['device'] as Map).cast<String, dynamic>()
        : <String, dynamic>{};
    final source = json['source'] is Map
        ? (json['source'] as Map).cast<String, dynamic>()
        : <String, dynamic>{};

    final points = rawPoints
        .whereType<Map>()
        .map((entry) =>
            AmplitudeCalibrationPoint.fromJson(entry.cast<String, dynamic>()))
        .where((point) => point.samples.isNotEmpty)
        .toList()
      ..sort((a, b) => a.frequencyHz.compareTo(b.frequencyHz));
    if (points.isEmpty) {
      throw const FormatException('Calibration file has no usable samples');
    }

    return AmplitudeCalibrationFile(
      createdAt: DateTime.tryParse(json['created_at']?.toString() ?? ''),
      sourcePath: sourcePath,
      deviceName: device['name']?.toString() ?? 'PuSuSA',
      deviceSerial: device['serial']?.toString() ?? '',
      note: device['note']?.toString() ?? '',
      cableLossDb: _readOptionalFiniteDouble(source, 'cable_loss_db') ?? 0.0,
      externalAttenDb:
          _readOptionalFiniteDouble(source, 'external_atten_db') ?? 0.0,
      points: points,
    );
  }
}

class _CalibrationCurvePoint {
  const _CalibrationCurvePoint(this.frequencyHz, this.correctionDb);

  final double frequencyHz;
  final double correctionDb;
}

double _readFirstFiniteDouble(Map<String, dynamic> json, List<String> keys) {
  final value = _readFirstOptionalFiniteDouble(json, keys);
  if (value == null) {
    throw FormatException(
        'Missing or invalid numeric value: ${keys.join(' / ')}');
  }
  return value;
}

double? _readFirstOptionalFiniteDouble(
    Map<String, dynamic> json, List<String> keys) {
  for (final key in keys) {
    final value = _readOptionalFiniteDouble(json, key);
    if (value != null) return value;
  }
  return null;
}

double? _readOptionalFiniteDouble(Map<String, dynamic> json, String key) {
  final raw = json[key];
  final double? value;
  if (raw is num) {
    value = raw.toDouble();
  } else if (raw == null) {
    value = null;
  } else {
    value = double.tryParse(raw.toString());
  }
  if (value == null || value.isNaN || !value.isFinite) return null;
  return value;
}

AmplitudeCalibrationSample? _tryParseSample(Map<dynamic, dynamic> entry) {
  try {
    return AmplitudeCalibrationSample.fromJson(entry.cast<String, dynamic>());
  } catch (_) {
    return null;
  }
}

double _derivePointFrequencyHz(List<AmplitudeCalibrationSample> samples) {
  if (samples.isEmpty) {
    throw const FormatException(
        'Missing frequency_hz and no sample peak_frequency_hz is available');
  }
  final values = samples.map((sample) => sample.peakFrequencyHz).toList()
    ..sort();
  final middle = values.length ~/ 2;
  if (values.length.isOdd) {
    return values[middle];
  }
  return (values[middle - 1] + values[middle]) / 2.0;
}

double _deriveReferencePowerDbm(List<AmplitudeCalibrationSample> samples) {
  if (samples.isEmpty) {
    throw const FormatException(
        'Missing reference_power_dbm and no usable samples are available');
  }
  final values = samples
      .map((sample) => sample.measuredPowerDbm + sample.correctionDb)
      .toList()
    ..sort();
  final middle = values.length ~/ 2;
  if (values.length.isOdd) {
    return values[middle];
  }
  return (values[middle - 1] + values[middle]) / 2.0;
}
