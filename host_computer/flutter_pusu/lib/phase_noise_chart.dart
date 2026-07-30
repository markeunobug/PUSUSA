import 'dart:math' as math;

import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart' as material;

import 'phase_noise_models.dart';

enum PhaseNoiseTraceDisplay {
  raw,
  average,
  both,
}

class PhaseNoiseMarker {
  final double offsetHz;
  final double dbcHz;
  final double rbwHz;
  final bool fromAverageTrace;

  const PhaseNoiseMarker({
    required this.offsetHz,
    required this.dbcHz,
    required this.rbwHz,
    required this.fromAverageTrace,
  });
}

typedef PhaseNoiseMarkerChanged = void Function(PhaseNoiseMarker? marker);

class PhaseNoiseYAxisRange {
  static const double defaultMinDbcHz = -140.0;
  static const double defaultMaxDbcHz = -80.0;
  static const double lowerClampDbcHz = -180.0;
  static const double upperClampDbcHz = 20.0;
  static const double paddingDb = 8.0;
  static const double gridStepDb = 10.0;
  static const double minSpanDb = 20.0;

  final double minDbcHz;
  final double maxDbcHz;

  const PhaseNoiseYAxisRange({
    required this.minDbcHz,
    required this.maxDbcHz,
  });

  const PhaseNoiseYAxisRange.defaults()
      : minDbcHz = defaultMinDbcHz,
        maxDbcHz = defaultMaxDbcHz;

  factory PhaseNoiseYAxisRange.fromPoints(
    Iterable<PhaseNoisePoint> points, {
    double fallbackMinDbcHz = defaultMinDbcHz,
    double fallbackMaxDbcHz = defaultMaxDbcHz,
  }) {
    final values = points
        .map((point) => point.dbcHz)
        .where((value) => value.isFinite)
        .toList(growable: false);
    if (values.isEmpty) {
      return PhaseNoiseYAxisRange(
        minDbcHz: fallbackMinDbcHz,
        maxDbcHz: fallbackMaxDbcHz,
      );
    }

    var minValue = values.first;
    var maxValue = values.first;
    for (final value in values.skip(1)) {
      minValue = math.min(minValue, value);
      maxValue = math.max(maxValue, value);
    }

    var axisMin =
        ((minValue - paddingDb) / gridStepDb).floorToDouble() * gridStepDb;
    var axisMax =
        ((maxValue + paddingDb) / gridStepDb).ceilToDouble() * gridStepDb;
    axisMin = axisMin.clamp(lowerClampDbcHz, upperClampDbcHz).toDouble();
    axisMax = axisMax.clamp(lowerClampDbcHz, upperClampDbcHz).toDouble();

    if (axisMax - axisMin < minSpanDb) {
      final center = ((axisMin + axisMax) / 2)
          .clamp(
            lowerClampDbcHz + minSpanDb / 2,
            upperClampDbcHz - minSpanDb / 2,
          )
          .toDouble();
      axisMin =
          ((center - minSpanDb / 2) / gridStepDb).floorToDouble() * gridStepDb;
      axisMax =
          ((center + minSpanDb / 2) / gridStepDb).ceilToDouble() * gridStepDb;
      axisMin = axisMin
          .clamp(lowerClampDbcHz, upperClampDbcHz - minSpanDb)
          .toDouble();
      axisMax = axisMax.clamp(axisMin + minSpanDb, upperClampDbcHz).toDouble();
    }

    if (axisMax <= axisMin) {
      return PhaseNoiseYAxisRange(
        minDbcHz: fallbackMinDbcHz,
        maxDbcHz: fallbackMaxDbcHz,
      );
    }
    return PhaseNoiseYAxisRange(minDbcHz: axisMin, maxDbcHz: axisMax);
  }

  bool contains(double value) => value >= minDbcHz && value <= maxDbcHz;
}

class PhaseNoiseChart extends material.StatefulWidget {
  final PhaseNoiseTrace trace;
  final PhaseNoiseConfig config;
  final PhaseNoiseTraceDisplay traceDisplay;
  final double minOffsetHz;
  final double maxOffsetHz;
  final double minDbcHz;
  final double maxDbcHz;
  final bool markerEnabled;
  final PhaseNoiseMarkerChanged? onMarkerChanged;

  const PhaseNoiseChart({
    super.key,
    required this.trace,
    required this.config,
    this.traceDisplay = PhaseNoiseTraceDisplay.both,
    this.minOffsetHz = 1000.0,
    this.maxOffsetHz = 1000000.0,
    this.minDbcHz = -140.0,
    this.maxDbcHz = -80.0,
    this.markerEnabled = true,
    this.onMarkerChanged,
  });

  @override
  material.State<PhaseNoiseChart> createState() => _PhaseNoiseChartState();
}

class _PhaseNoiseChartState extends material.State<PhaseNoiseChart> {
  static const double _leftAxisReservedSize = 72;
  static const double _bottomAxisReservedSize = 34;

  double? _markerOffsetHz;

  List<PhaseNoisePoint> get _rawPoints =>
      _visiblePoints(widget.trace.rawPoints);

  List<PhaseNoisePoint> get _averagePoints =>
      _visiblePoints(widget.trace.averagePoints);

  PhaseNoiseYAxisRange get _effectiveYAxisRange =>
      PhaseNoiseYAxisRange.fromPoints(
        _visibleYAxisPoints,
        fallbackMinDbcHz: widget.minDbcHz,
        fallbackMaxDbcHz: widget.maxDbcHz,
      );

  Iterable<PhaseNoisePoint> get _visibleYAxisPoints sync* {
    if (widget.traceDisplay != PhaseNoiseTraceDisplay.average) {
      yield* _rawPoints;
    }
    if (widget.traceDisplay != PhaseNoiseTraceDisplay.raw) {
      yield* _averagePoints;
    }
  }

  List<PhaseNoisePoint> get _preferredMarkerPoints {
    if (widget.traceDisplay == PhaseNoiseTraceDisplay.raw) {
      return _rawPoints;
    }
    if (_averagePoints.isNotEmpty) {
      return _averagePoints;
    }
    return _rawPoints;
  }

  @override
  void didUpdateWidget(covariant PhaseNoiseChart oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (_preferredMarkerPoints.isEmpty) {
      _setMarkerOffset(null, notify: true);
      return;
    }

    if (_markerOffsetHz != null) {
      _setMarkerOffset(
          _nearestPoint(_preferredMarkerPoints, _markerOffsetHz!).offsetHz);
    }
  }

  List<PhaseNoisePoint> _visiblePoints(List<PhaseNoisePoint> points) {
    return points
        .where(
          (point) =>
              point.offsetHz > 0 &&
              point.offsetHz >= widget.minOffsetHz &&
              point.offsetHz <= widget.maxOffsetHz &&
              point.dbcHz.isFinite &&
              point.valid,
        )
        .toList(growable: false);
  }

  void _setMarkerOffset(double? offsetHz, {bool notify = false}) {
    if (_markerOffsetHz == offsetHz) return;
    setState(() {
      _markerOffsetHz = offsetHz;
    });
    if (notify) {
      widget.onMarkerChanged?.call(_buildMarker());
    }
  }

  PhaseNoiseMarker? _buildMarker() {
    if (_markerOffsetHz == null || _preferredMarkerPoints.isEmpty) return null;
    final point = _nearestPoint(_preferredMarkerPoints, _markerOffsetHz!);
    final fromAverage = widget.traceDisplay != PhaseNoiseTraceDisplay.raw &&
        _averagePoints.isNotEmpty;
    return PhaseNoiseMarker(
      offsetHz: point.offsetHz,
      dbcHz: point.dbcHz,
      rbwHz: point.rbwHz,
      fromAverageTrace: fromAverage,
    );
  }

  PhaseNoisePoint _nearestPoint(List<PhaseNoisePoint> points, double offsetHz) {
    return points.reduce(
      (best, point) =>
          (point.offsetHz - offsetHz).abs() < (best.offsetHz - offsetHz).abs()
              ? point
              : best,
    );
  }

  double _logOffset(double offsetHz) {
    return math.log(offsetHz) / math.ln10;
  }

  double _offsetFromLog(double logOffset) {
    return math.pow(10.0, logOffset).toDouble();
  }

  String _formatOffset(double offsetHz, [int decimalPlaces = 2]) {
    if (offsetHz >= 1e6) {
      return '${(offsetHz / 1e6).toStringAsFixed(decimalPlaces)} MHz';
    }
    if (offsetHz >= 1e3) {
      return '${(offsetHz / 1e3).toStringAsFixed(decimalPlaces)} kHz';
    }
    return '${offsetHz.toStringAsFixed(decimalPlaces)} Hz';
  }

  String _formatAxisOffset(double offsetHz) {
    if (offsetHz >= 1e6) {
      return '${(offsetHz / 1e6).toStringAsFixed(0)} MHz';
    }
    if (offsetHz >= 1e3) {
      return '${(offsetHz / 1e3).toStringAsFixed(0)} kHz';
    }
    return offsetHz.toStringAsFixed(0);
  }

  List<FlSpot> _toLogSpots(List<PhaseNoisePoint> points) {
    return points
        .map((point) => FlSpot(_logOffset(point.offsetHz), point.dbcHz))
        .toList(growable: false);
  }

  List<double> _majorLogTicks() {
    final ticks = <double>[];
    final startDecade = _logOffset(widget.minOffsetHz).ceil();
    final stopDecade = _logOffset(widget.maxOffsetHz).floor();
    for (var decade = startDecade; decade <= stopDecade; decade++) {
      ticks.add(decade.toDouble());
    }
    return ticks;
  }

  List<VerticalLine> _minorGridLines() {
    final lines = <VerticalLine>[];
    final startDecade = _logOffset(widget.minOffsetHz).floor();
    final stopDecade = _logOffset(widget.maxOffsetHz).ceil();
    for (var decade = startDecade; decade <= stopDecade; decade++) {
      final base = math.pow(10.0, decade).toDouble();
      for (final multiplier in const [2.0, 3.0, 5.0]) {
        final offset = base * multiplier;
        if (offset <= widget.minOffsetHz || offset >= widget.maxOffsetHz) {
          continue;
        }
        lines.add(
          VerticalLine(
            x: _logOffset(offset),
            color: material.Colors.white.withValues(alpha: 0.08),
            strokeWidth: 1,
            dashArray: [2, 4],
          ),
        );
      }
    }
    return lines;
  }

  List<VerticalLine> _markerLines() {
    final marker = _buildMarker();
    if (marker == null) return const [];
    return [
      VerticalLine(
        x: _logOffset(marker.offsetHz),
        color: material.Colors.redAccent.withValues(alpha: 0.70),
        strokeWidth: 1,
      ),
    ];
  }

  List<HorizontalLine> _markerHorizontalLines(PhaseNoiseYAxisRange yAxisRange) {
    final marker = _buildMarker();
    if (marker == null || !yAxisRange.contains(marker.dbcHz)) return const [];
    return [
      HorizontalLine(
        y: marker.dbcHz,
        color: material.Colors.white.withValues(alpha: 0.20),
        strokeWidth: 1,
        dashArray: [4, 4],
      ),
    ];
  }

  void _updateMarkerFromPosition(material.Offset position, material.Size size) {
    if (!widget.markerEnabled || _preferredMarkerPoints.isEmpty) return;

    final plotRect = _plotRect(size);
    if (plotRect.width <= 0 || !plotRect.contains(position)) return;

    final minLog = _logOffset(widget.minOffsetHz);
    final maxLog = _logOffset(widget.maxOffsetHz);
    final ratio =
        ((position.dx - plotRect.left) / plotRect.width).clamp(0.0, 1.0);
    final offset = _offsetFromLog(minLog + ratio * (maxLog - minLog));
    final snapped = _nearestPoint(_preferredMarkerPoints, offset);
    _setMarkerOffset(snapped.offsetHz, notify: true);
  }

  material.Rect _plotRect(material.Size size) {
    return material.Rect.fromLTRB(
      _leftAxisReservedSize,
      0,
      size.width,
      size.height - _bottomAxisReservedSize,
    );
  }

  material.Widget _buildMarkerInfoRow() {
    final marker = _buildMarker();
    final warningText = widget.trace.warnings.map((w) => w.message).join(' | ');
    return material.Padding(
      padding: const material.EdgeInsets.only(bottom: 10),
      child: material.Wrap(
        spacing: 24,
        runSpacing: 6,
        crossAxisAlignment: material.WrapCrossAlignment.center,
        children: [
          material.Text(
            marker == null
                ? 'M1 --'
                : 'M1 ${_formatOffset(marker.offsetHz)}  ${marker.dbcHz.toStringAsFixed(2)} dBc/Hz  ${marker.fromAverageTrace ? 'AVG' : 'RAW'}',
            style: const material.TextStyle(
              color: material.Colors.white,
              fontSize: 13,
              fontWeight: material.FontWeight.w600,
            ),
          ),
          material.Text(
            marker == null
                ? 'RBW ${_formatOffset(widget.config.rbwHz)}  ENBW ${_formatOffset(widget.config.effectiveEnbwHz)}'
                : 'Marker RBW ${_formatOffset(marker.rbwHz)}  ENBW ${_formatOffset(widget.config.effectiveEnbwForRbw(marker.rbwHz))}',
            style: const material.TextStyle(
              color: material.Colors.white70,
              fontSize: 12,
            ),
          ),
          if (warningText.isNotEmpty)
            material.Text(
              warningText,
              style: const material.TextStyle(
                color: material.Color(0xFFFFD166),
                fontSize: 12,
              ),
            ),
        ],
      ),
    );
  }

  material.Widget _buildChart() {
    final rawSpots = _toLogSpots(_rawPoints);
    final averageSpots = _toLogSpots(_averagePoints);
    final minLog = _logOffset(widget.minOffsetHz);
    final maxLog = _logOffset(widget.maxOffsetHz);
    final majorTicks = _majorLogTicks();
    final yAxisRange = _effectiveYAxisRange;

    return material.LayoutBuilder(
      builder: (context, constraints) {
        final chartSize = constraints.biggest;
        return material.Stack(
          fit: material.StackFit.expand,
          children: [
            LineChart(
              LineChartData(
                minX: minLog,
                maxX: maxLog,
                minY: yAxisRange.minDbcHz,
                maxY: yAxisRange.maxDbcHz,
                borderData: FlBorderData(show: false),
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: true,
                  drawHorizontalLine: true,
                  verticalInterval: 1.0,
                  horizontalInterval: 10.0,
                  checkToShowVerticalLine: (value) =>
                      majorTicks.any((tick) => (tick - value).abs() < 1e-6),
                  getDrawingVerticalLine: (value) => FlLine(
                    color: material.Colors.white.withValues(alpha: 0.18),
                    strokeWidth: 1,
                  ),
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: material.Colors.white.withValues(alpha: 0.10),
                    strokeWidth: 1,
                    dashArray: [2, 3],
                  ),
                ),
                titlesData: FlTitlesData(
                  show: true,
                  topTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  rightTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
                  ),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: _leftAxisReservedSize,
                      interval: 10,
                      getTitlesWidget: (value, meta) => material.Text(
                        '${value.toInt()}',
                        style: const material.TextStyle(
                          color: material.Colors.white,
                          fontSize: 11,
                        ),
                      ),
                    ),
                    axisNameWidget: const material.Text(
                      'dBc/Hz',
                      style: material.TextStyle(
                        color: material.Colors.white70,
                        fontSize: 11,
                      ),
                    ),
                    axisNameSize: 16,
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: _bottomAxisReservedSize,
                      interval: 1.0,
                      getTitlesWidget: (value, meta) {
                        if (!majorTicks
                            .any((tick) => (tick - value).abs() < 1e-6)) {
                          return const material.SizedBox.shrink();
                        }
                        return material.Padding(
                          padding: const material.EdgeInsets.only(top: 6),
                          child: material.Text(
                            _formatAxisOffset(_offsetFromLog(value)),
                            style: const material.TextStyle(
                              color: material.Colors.white,
                              fontSize: 11,
                            ),
                          ),
                        );
                      },
                    ),
                    axisNameWidget: const material.Text(
                      '频率偏移',
                      style: material.TextStyle(
                        color: material.Colors.white70,
                        fontSize: 11,
                      ),
                    ),
                    axisNameSize: 16,
                  ),
                ),
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipItems: (touchedSpots) {
                      return touchedSpots.map((spot) {
                        return LineTooltipItem(
                          '${_formatOffset(_offsetFromLog(spot.x))}\n'
                          '${spot.y.toStringAsFixed(2)} dBc/Hz',
                          const material.TextStyle(
                            color: material.Colors.white,
                            fontSize: 12,
                          ),
                        );
                      }).toList();
                    },
                  ),
                ),
                lineBarsData: [
                  if (widget.traceDisplay != PhaseNoiseTraceDisplay.average)
                    LineChartBarData(
                      spots: rawSpots,
                      isCurved: false,
                      color: const material.Color(0xFF51C7F5),
                      barWidth: 1.4,
                      dotData: const FlDotData(show: false),
                    ),
                  if (widget.traceDisplay != PhaseNoiseTraceDisplay.raw)
                    LineChartBarData(
                      spots: averageSpots,
                      isCurved: false,
                      color: const material.Color(0xFFFFD166),
                      barWidth: 2.2,
                      dotData: const FlDotData(show: false),
                    ),
                ],
                extraLinesData: ExtraLinesData(
                  verticalLines: [
                    ..._minorGridLines(),
                    ..._markerLines(),
                  ],
                  horizontalLines: _markerHorizontalLines(yAxisRange),
                ),
              ),
              duration: Duration.zero,
            ),
            material.Positioned.fill(
              child: material.MouseRegion(
                cursor: widget.markerEnabled
                    ? material.SystemMouseCursors.click
                    : material.SystemMouseCursors.basic,
                child: material.GestureDetector(
                  behavior: material.HitTestBehavior.translucent,
                  onTapDown: (details) => _updateMarkerFromPosition(
                      details.localPosition, chartSize),
                  onHorizontalDragUpdate: (details) =>
                      _updateMarkerFromPosition(
                          details.localPosition, chartSize),
                ),
              ),
            ),
            material.IgnorePointer(
              child: material.CustomPaint(
                painter: _PhaseNoiseMarkerPainter(
                  marker: _buildMarker(),
                  minLogOffset: minLog,
                  maxLogOffset: maxLog,
                  minDbcHz: yAxisRange.minDbcHz,
                  maxDbcHz: yAxisRange.maxDbcHz,
                  leftReservedSize: _leftAxisReservedSize,
                  bottomReservedSize: _bottomAxisReservedSize,
                  logOffset: _logOffset,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  @override
  material.Widget build(material.BuildContext context) {
    final hasData = _rawPoints.isNotEmpty || _averagePoints.isNotEmpty;
    if (!hasData) {
      return material.Container(
        height: double.infinity,
        width: double.infinity,
        alignment: material.Alignment.center,
        color: const material.Color(0xFF1D2330),
        child: const material.Text(
          '暂无相位噪声数据',
          style: material.TextStyle(color: material.Colors.white70),
        ),
      );
    }

    return material.Container(
      height: double.infinity,
      width: double.infinity,
      padding: const material.EdgeInsets.all(16),
      decoration: material.BoxDecoration(
        color: const material.Color(0xFF1D2330),
        borderRadius: material.BorderRadius.circular(8),
      ),
      child: material.Column(
        children: [
          _buildMarkerInfoRow(),
          material.Expanded(child: _buildChart()),
          const material.SizedBox(height: 8),
          material.Row(
            mainAxisAlignment: material.MainAxisAlignment.spaceBetween,
            children: [
              material.Text(
                '起始 ${_formatOffset(widget.minOffsetHz)}',
                style: const material.TextStyle(
                  color: material.Color(0xFF77DD77),
                  fontSize: 12,
                ),
              ),
              const material.Text(
                '对数频偏',
                style: material.TextStyle(
                  color: material.Color(0xFF77DD77),
                  fontSize: 12,
                ),
              ),
              material.Text(
                '终止 ${_formatOffset(widget.maxOffsetHz)}',
                style: const material.TextStyle(
                  color: material.Color(0xFF77DD77),
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }
}

class PhaseNoiseCsvExporter {
  const PhaseNoiseCsvExporter._();

  static String buildCsv({
    required PhaseNoiseTrace trace,
    required PhaseNoiseConfig config,
  }) {
    final buffer = StringBuffer();
    final carrier = trace.carrier;
    final rawByOffset = {
      for (final point in trace.rawPoints) point.offsetHz: point,
    };
    final avgByOffset = {
      for (final point in trace.averagePoints) point.offsetHz: point,
    };
    final offsets = <double>{...rawByOffset.keys, ...avgByOffset.keys}.toList()
      ..sort();

    buffer.writeln('metadata_key,metadata_value');
    buffer.writeln('carrier_hz,${_csvNumber(carrier?.measuredHz)}');
    buffer.writeln('carrier_dbm,${_csvNumber(carrier?.levelDbm)}');
    buffer.writeln('start_offset_hz,${_csvNumber(config.startOffsetHz)}');
    buffer.writeln('stop_offset_hz,${_csvNumber(config.stopOffsetHz)}');
    buffer.writeln('average_count,${trace.completedAverages}');
    buffer.writeln(
        'enbw_mode,${config.enbwHz == null ? 'calculated' : 'calibrated'}');
    buffer.writeln('calibration_state,FILTER_ENBW');
    buffer.writeln('rbw_hz,${_csvNumber(config.rbwHz)}');
    buffer.writeln('enbw_hz,${_csvNumber(config.effectiveEnbwHz)}');
    buffer.writeln('points_per_decade,${config.pointsPerDecade}');
    buffer.writeln('planned_points,${config.estimatedPointCount}');
    buffer.writeln('received_points,${offsets.length}');
    buffer.writeln();
    buffer.writeln(
        'offset_hz,raw_dbc_hz,avg_dbc_hz,noise_power_dbm,rbw_hz,enbw_hz,valid,warning');

    for (final offset in offsets) {
      final raw = rawByOffset[offset];
      final avg = avgByOffset[offset];
      final rbwHz = raw?.rbwHz ?? avg?.rbwHz ?? config.rbwHz;
      final valid = (raw?.valid ?? true) && (avg?.valid ?? true);
      final warning = offset < rbwHz ? 'Offset < RBW' : '';
      buffer.writeln(
        [
          _csvNumber(offset),
          _csvNumber(raw?.dbcHz),
          _csvNumber(avg?.dbcHz ?? raw?.dbcHz),
          _csvNumber(raw?.noisePowerDbm ?? avg?.noisePowerDbm),
          _csvNumber(rbwHz),
          _csvNumber(config.effectiveEnbwForRbw(rbwHz)),
          valid ? '1' : '0',
          warning,
        ].join(','),
      );
    }

    return buffer.toString();
  }

  static String _csvNumber(double? value) {
    if (value == null || value.isNaN || !value.isFinite) return '';
    return value.toStringAsPrecision(12);
  }
}

class _PhaseNoiseMarkerPainter extends material.CustomPainter {
  final PhaseNoiseMarker? marker;
  final double minLogOffset;
  final double maxLogOffset;
  final double minDbcHz;
  final double maxDbcHz;
  final double leftReservedSize;
  final double bottomReservedSize;
  final double Function(double offsetHz) logOffset;

  const _PhaseNoiseMarkerPainter({
    required this.marker,
    required this.minLogOffset,
    required this.maxLogOffset,
    required this.minDbcHz,
    required this.maxDbcHz,
    required this.leftReservedSize,
    required this.bottomReservedSize,
    required this.logOffset,
  });

  @override
  void paint(material.Canvas canvas, material.Size size) {
    if (marker == null) return;
    final logRange = maxLogOffset - minLogOffset;
    final dbRange = maxDbcHz - minDbcHz;
    if (logRange <= 0 || dbRange <= 0 || size.isEmpty) return;

    final plotRect = material.Rect.fromLTRB(
      leftReservedSize,
      0,
      size.width,
      size.height - bottomReservedSize,
    );
    if (plotRect.width <= 0 || plotRect.height <= 0) return;

    final markerLog = logOffset(marker!.offsetHz);
    final x = plotRect.left +
        ((markerLog - minLogOffset) / logRange).clamp(0.0, 1.0) *
            plotRect.width;
    final y = plotRect.bottom -
        (((marker!.dbcHz.clamp(minDbcHz, maxDbcHz) - minDbcHz) / dbRange) *
            plotRect.height);

    const labelStyle = material.TextStyle(
      color: material.Colors.white,
      fontSize: 14,
      fontWeight: material.FontWeight.bold,
      height: 1,
    );
    final textPainter = material.TextPainter(
      text: const material.TextSpan(text: 'M1\nv', style: labelStyle),
      textAlign: material.TextAlign.center,
      textDirection: material.TextDirection.ltr,
    )..layout();

    final dx = (x - textPainter.width / 2).clamp(
      0.0,
      (size.width - textPainter.width).clamp(0.0, size.width),
    );
    final dy = (y - textPainter.height - 6).clamp(
      0.0,
      (size.height - textPainter.height).clamp(0.0, size.height),
    );
    textPainter.paint(canvas, material.Offset(dx, dy));
  }

  @override
  bool shouldRepaint(covariant _PhaseNoiseMarkerPainter oldDelegate) {
    return oldDelegate.marker != marker ||
        oldDelegate.minLogOffset != minLogOffset ||
        oldDelegate.maxLogOffset != maxLogOffset ||
        oldDelegate.minDbcHz != minDbcHz ||
        oldDelegate.maxDbcHz != maxDbcHz ||
        oldDelegate.leftReservedSize != leftReservedSize ||
        oldDelegate.bottomReservedSize != bottomReservedSize;
  }
}
