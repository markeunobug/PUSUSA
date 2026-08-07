// spectrum_chart.dart
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart' as material;
import 'frequency_format.dart';

class Marker {
  final int id;
  double freqHz;
  bool enabled = false;

  Marker(this.id, this.freqHz, {this.enabled = false});
}

class SpectrumLimitLine {
  const SpectrumLimitLine({
    required this.label,
    required this.powerDbm,
    required this.color,
  });

  final String label;
  final double powerDbm;
  final material.Color color;
}

typedef MarkerDragUpdate = void Function(Marker marker, double freqHz);

class SpectrumChart extends material.StatelessWidget {
  final List<FlSpot> data;
  final double minFreq;
  final double maxFreq;
  final double minDbm;
  final double maxDbm;
  final double scalePerGrid;
  final String startFreqStr;
  final String stopFreqStr;
  final String centerFreqStr;
  final String spanStr;
  final String sweepSpeedStr;
  final List<Marker> markers;
  final bool markersDraggable;
  final MarkerDragUpdate? onMarkerDragUpdate;
  final bool isZeroSpan;
  final bool traceSmoothingEnabled;
  final String zeroSpanFreqStr;
  final String zeroSpanElapsedStr;
  final List<FlSpot> referenceData;
  final String referenceLabel;
  final List<SpectrumLimitLine> limitLines;

  const SpectrumChart({
    super.key,
    required this.data,
    required this.minFreq,
    required this.maxFreq,
    required this.minDbm,
    required this.maxDbm,
    required this.scalePerGrid,
    required this.startFreqStr,
    required this.stopFreqStr,
    required this.centerFreqStr,
    required this.spanStr,
    required this.sweepSpeedStr,
    this.markers = const [],
    this.markersDraggable = false,
    this.onMarkerDragUpdate,
    this.isZeroSpan = false,
    this.traceSmoothingEnabled = false,
    this.zeroSpanFreqStr = '',
    this.zeroSpanElapsedStr = '',
    this.referenceData = const <FlSpot>[],
    this.referenceLabel = '',
    this.limitLines = const <SpectrumLimitLine>[],
  });

  static const double _leftAxisReservedSize = 60;
  static const double _bottomAxisReservedSize = 28;
  static const double _markerDragHitSlop = 10;

  /// 根据频点 x 值，获取最接近的幅度值（dBm）。
  double _getYAt(double x) {
    if (data.isEmpty) return minDbm;
    FlSpot closest = data[0];
    double minDiff = (data[0].x - x).abs();
    for (var spot in data) {
      double diff = (spot.x - x).abs();
      if (diff < minDiff) {
        minDiff = diff;
        closest = spot;
      }
    }
    return closest.y;
  }

  material.Widget _buildMarkerInfoRow() {
    if (isZeroSpan) return const material.SizedBox.shrink();
    final enabledMarkers = markers.where((m) => m.enabled).toList();
    final items = <material.Widget>[
      ...enabledMarkers.map((m) {
        final freqStr = formatMarkerFreqAutoUnit(m.freqHz);
        final y = _getYAt(m.freqHz);
        return material.Text(
          'M${m.id}  $freqStr  ${y.toStringAsFixed(2)} dBm',
          style: const material.TextStyle(
            color: material.Colors.white,
            fontSize: 13,
            fontWeight: material.FontWeight.w600,
          ),
        );
      }),
      if (referenceData.isNotEmpty)
        material.Text(
          '参考：${referenceLabel.isEmpty ? '历史测量' : referenceLabel}',
          style: const material.TextStyle(
            color: material.Colors.cyanAccent,
            fontSize: 12,
            fontWeight: material.FontWeight.w600,
          ),
        ),
      ...limitLines.map(
        (line) => material.Text(
          '${line.label}  ${line.powerDbm.toStringAsFixed(2)} dBm',
          style: material.TextStyle(
            color: line.color,
            fontSize: 12,
            fontWeight: material.FontWeight.w600,
          ),
        ),
      ),
    ];

    return material.Container(
      width: double.infinity,
      padding: const material.EdgeInsets.only(top: 0, bottom: 15),
      child: material.Wrap(
        alignment: material.WrapAlignment.start,
        crossAxisAlignment: material.WrapCrossAlignment.start,
        spacing: 32,
        runSpacing: 8,
        children: items,
      ),
    );
  }

  List<VerticalLine> _buildMarkerVerticalLines() {
    if (isZeroSpan) return [];
    final enabledMarkers = markers.where((m) => m.enabled).toList();
    return enabledMarkers
        .where((m) => m.freqHz >= minFreq && m.freqHz <= maxFreq)
        .map((m) {
      return VerticalLine(
        x: m.freqHz,
        color: material.Colors.red.withValues(alpha: 0.5),
        strokeWidth: 1,
        dashArray: null,
      );
    }).toList();
  }

  material.Widget _buildChartArea() {
    return material.LayoutBuilder(
      builder: (context, constraints) {
        final chartSize = constraints.biggest;
        return material.Stack(
          fit: material.StackFit.expand,
          children: [
            LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: true,
                  drawHorizontalLine: true,
                  verticalInterval:
                      (maxFreq - minFreq) > 0 ? (maxFreq - minFreq) / 10 : 1.0,
                  horizontalInterval: scalePerGrid,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: material.Colors.white.withValues(alpha: 0.1),
                    strokeWidth: 1,
                    dashArray: [2, 2],
                  ),
                  getDrawingVerticalLine: (value) => FlLine(
                    color: material.Colors.white.withValues(alpha: 0.1),
                    strokeWidth: 1,
                    dashArray: [2, 2],
                  ),
                ),
                titlesData: FlTitlesData(
                  show: true,
                  topTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(
                      sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: _leftAxisReservedSize,
                      interval: scalePerGrid,
                      getTitlesWidget: (value, meta) => material.Text(
                        '${value.toInt()} dBm',
                        style: const material.TextStyle(
                            color: material.Colors.white, fontSize: 12),
                      ),
                    ),
                  ),
                  bottomTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: isZeroSpan,
                      reservedSize: _bottomAxisReservedSize,
                      interval: (maxFreq - minFreq) > 0
                          ? (maxFreq - minFreq) / 10
                          : 1.0,
                      getTitlesWidget: (value, meta) => material.Text(
                        '${value.toInt()} s',
                        style: const material.TextStyle(
                            color: material.Colors.white, fontSize: 11),
                      ),
                    ),
                  ),
                ),
                lineTouchData: LineTouchData(
                  touchTooltipData: LineTouchTooltipData(
                    getTooltipItems: (touchedSpots) {
                      return touchedSpots.map((spot) {
                        if (isZeroSpan) {
                          return LineTooltipItem(
                            '${spot.x.toStringAsFixed(1)} s\n'
                            '${spot.y.toStringAsFixed(2)} dBm',
                            const material.TextStyle(
                              color: material.Colors.white,
                              fontSize: 12,
                            ),
                          );
                        }
                        return LineTooltipItem(
                          '${formatFreqAutoUnit(spot.x, decimalPlaces: 3)}\n'
                          '${spot.y.toStringAsFixed(2)} dBm',
                          const material.TextStyle(
                            color: material.Colors.white,
                            fontSize: 12,
                          ),
                        );
                      }).toList();
                    },
                  ),
                ),
                borderData: FlBorderData(show: false),
                minX: minFreq,
                maxX: maxFreq,
                minY: minDbm,
                maxY: maxDbm,
                lineBarsData: [
                  LineChartBarData(
                    spots: data,
                    isCurved: traceSmoothingEnabled && !isZeroSpan,
                    preventCurveOverShooting: true,
                    curveSmoothness: 0.18,
                    color: material.Colors.yellow,
                    barWidth: 2,
                    dotData: const FlDotData(show: false),
                  ),
                  if (referenceData.isNotEmpty && !isZeroSpan)
                    LineChartBarData(
                      spots: referenceData,
                      isCurved: false,
                      color: material.Colors.cyanAccent.withValues(alpha: 0.8),
                      barWidth: 1.5,
                      dashArray: const <int>[7, 5],
                      dotData: const FlDotData(show: false),
                    ),
                ],
                extraLinesData: ExtraLinesData(
                  verticalLines: _buildMarkerVerticalLines(),
                  horizontalLines: <HorizontalLine>[
                    ..._buildMarkerHorizontalLines(),
                    ..._buildLimitHorizontalLines(),
                  ],
                ),
              ),
              duration: Duration.zero,
            ),
            if (markersDraggable && !isZeroSpan)
              ..._buildMarkerDragHandles(chartSize),
            if (!isZeroSpan)
              material.IgnorePointer(
                child: material.CustomPaint(
                  painter: _MarkerLabelPainter(
                    markers: markers,
                    minFreq: minFreq,
                    maxFreq: maxFreq,
                    minDbm: minDbm,
                    maxDbm: maxDbm,
                    leftReservedSize: _leftAxisReservedSize,
                    bottomReservedSize:
                        isZeroSpan ? _bottomAxisReservedSize : 0,
                    getYAt: _getYAt,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }

  double? _freqFromLocalPosition(material.Offset position, material.Size size) {
    final freqRange = maxFreq - minFreq;
    if (freqRange <= 0 || size.isEmpty) return null;

    final plotRect = material.Rect.fromLTRB(
      _leftAxisReservedSize,
      0,
      size.width,
      size.height - (isZeroSpan ? _bottomAxisReservedSize : 0),
    );
    if (plotRect.width <= 0 || plotRect.height <= 0) return null;

    final ratio =
        ((position.dx - plotRect.left) / plotRect.width).clamp(0.0, 1.0);
    return minFreq + ratio * freqRange;
  }

  void _updateDraggedMarker(
    Marker marker,
    material.Offset position,
    material.Size chartSize,
  ) {
    final freq = _freqFromLocalPosition(position, chartSize);
    if (freq == null) return;
    onMarkerDragUpdate?.call(marker, freq);
  }

  void _updateDraggedMarkerByDelta(
    Marker marker,
    double deltaX,
    material.Size chartSize,
  ) {
    final plotRect = _plotRect(chartSize);
    final freqRange = maxFreq - minFreq;
    if (plotRect.width <= 0 || freqRange <= 0) return;

    final freqDelta = (deltaX / plotRect.width) * freqRange;
    onMarkerDragUpdate?.call(marker, marker.freqHz + freqDelta);
  }

  List<material.Widget> _buildMarkerDragHandles(material.Size chartSize) {
    final handleWidth = (_markerDragHitSlop * 2).clamp(0.0, chartSize.width);
    return markers
        .where((marker) =>
            marker.enabled &&
            marker.freqHz >= minFreq &&
            marker.freqHz <= maxFreq)
        .map((marker) {
          final markerX = _xForFreq(marker.freqHz, chartSize);
          if (markerX == null) return null;

          final left = (markerX - handleWidth / 2)
              .clamp(0.0, chartSize.width - handleWidth);
          return material.Positioned(
            left: left,
            top: 0,
            width: handleWidth,
            height: chartSize.height,
            child: material.MouseRegion(
              cursor: material.SystemMouseCursors.resizeColumn,
              child: material.GestureDetector(
                behavior: material.HitTestBehavior.opaque,
                onHorizontalDragUpdate: (details) =>
                    _updateDraggedMarkerByDelta(
                        marker, details.delta.dx, chartSize),
                onTapDown: (details) => _updateDraggedMarker(
                  marker,
                  material.Offset(
                    left + details.localPosition.dx,
                    details.localPosition.dy,
                  ),
                  chartSize,
                ),
              ),
            ),
          );
        })
        .whereType<material.Widget>()
        .toList();
  }

  double? _xForFreq(double freqHz, material.Size size) {
    final freqRange = maxFreq - minFreq;
    if (freqRange <= 0 || size.isEmpty) return null;

    final plotRect = _plotRect(size);
    if (plotRect.width <= 0 || plotRect.height <= 0) return null;

    final ratio = ((freqHz - minFreq) / freqRange).clamp(0.0, 1.0);
    return plotRect.left + ratio * plotRect.width;
  }

  material.Rect _plotRect(material.Size size) {
    return material.Rect.fromLTRB(
      _leftAxisReservedSize,
      0,
      size.width,
      size.height - (isZeroSpan ? _bottomAxisReservedSize : 0),
    );
  }

  List<HorizontalLine> _buildMarkerHorizontalLines() {
    if (isZeroSpan) return [];
    final enabledMarkers = markers.where((m) => m.enabled).toList();
    return enabledMarkers
        .where((m) =>
            m.freqHz >= minFreq &&
            m.freqHz <= maxFreq &&
            _getYAt(m.freqHz) >= minDbm &&
            _getYAt(m.freqHz) <= maxDbm)
        .map((m) {
      final yValue = _getYAt(m.freqHz);
      return HorizontalLine(
        y: yValue,
        color: material.Colors.white.withValues(alpha: 0.3),
        strokeWidth: 0,
        dashArray: null,
        label: HorizontalLineLabel(
          show: false,
          alignment: material.Alignment.centerRight,
          padding: const material.EdgeInsets.only(right: 8),
          labelResolver: (line) => '◀${yValue.toStringAsFixed(2)}',
          style: const material.TextStyle(
            color: material.Colors.white,
            fontSize: 12,
            fontWeight: material.FontWeight.bold,
          ),
        ),
      );
    }).toList();
  }

  List<HorizontalLine> _buildLimitHorizontalLines() {
    if (isZeroSpan) return const <HorizontalLine>[];
    return limitLines
        .where((line) => line.powerDbm >= minDbm && line.powerDbm <= maxDbm)
        .map(
          (line) => HorizontalLine(
            y: line.powerDbm,
            color: line.color.withValues(alpha: 0.9),
            strokeWidth: 1.5,
            dashArray: const <int>[6, 4],
            label: HorizontalLineLabel(
              show: true,
              alignment: material.Alignment.topRight,
              padding: const material.EdgeInsets.only(right: 6, bottom: 2),
              labelResolver: (_) => line.label,
              style: material.TextStyle(
                color: line.color,
                fontSize: 10,
                fontWeight: material.FontWeight.w600,
              ),
            ),
          ),
        )
        .toList();
  }

  @override
  material.Widget build(material.BuildContext context) {
    if (data.isEmpty) {
      return const material.Center(
        child: material.Text('无数据',
            style: material.TextStyle(color: material.Colors.white)),
      );
    }

    return material.Container(
      height: double.infinity,
      width: double.infinity,
      padding: const material.EdgeInsets.all(16),
      decoration: material.BoxDecoration(
        color: const material.Color(0xFF1E1E2E),
        borderRadius: material.BorderRadius.circular(8),
      ),
      child: material.Column(
        children: [
          _buildMarkerInfoRow(),
          material.Expanded(
            child: _buildChartArea(),
          ),
          const material.SizedBox(height: 8),
          material.Row(
            mainAxisAlignment: material.MainAxisAlignment.spaceBetween,
            children: isZeroSpan
                ? [
                    material.Text('监测频率: $zeroSpanFreqStr',
                        style: const material.TextStyle(
                            color: material.Colors.green, fontSize: 12)),
                    material.Text('已用时间: $zeroSpanElapsedStr',
                        style: const material.TextStyle(
                            color: material.Colors.green, fontSize: 12)),
                    material.Text('扫描速度: $sweepSpeedStr',
                        style: const material.TextStyle(
                            color: material.Colors.green, fontSize: 12)),
                  ]
                : [
                    material.Text('起始: $startFreqStr',
                        style: const material.TextStyle(
                            color: material.Colors.green, fontSize: 12)),
                    material.Text('扫宽: $spanStr',
                        style: const material.TextStyle(
                            color: material.Colors.green, fontSize: 12)),
                    material.Text('中心: $centerFreqStr',
                        style: const material.TextStyle(
                            color: material.Colors.green, fontSize: 12)),
                    material.Text('扫描速度: $sweepSpeedStr',
                        style: const material.TextStyle(
                            color: material.Colors.green, fontSize: 12)),
                    material.Text('终止: $stopFreqStr',
                        style: const material.TextStyle(
                            color: material.Colors.green, fontSize: 12)),
                  ],
          )
        ],
      ),
    );
  }
}

class _MarkerLabelPainter extends material.CustomPainter {
  final List<Marker> markers;
  final double minFreq;
  final double maxFreq;
  final double minDbm;
  final double maxDbm;
  final double leftReservedSize;
  final double bottomReservedSize;
  final double Function(double x) getYAt;

  _MarkerLabelPainter({
    required this.markers,
    required this.minFreq,
    required this.maxFreq,
    required this.minDbm,
    required this.maxDbm,
    required this.leftReservedSize,
    required this.bottomReservedSize,
    required this.getYAt,
  });

  @override
  void paint(material.Canvas canvas, material.Size size) {
    final freqRange = maxFreq - minFreq;
    final dbmRange = maxDbm - minDbm;
    if (freqRange <= 0 || dbmRange <= 0 || size.isEmpty) return;
    final plotRect = material.Rect.fromLTRB(
      leftReservedSize,
      0,
      size.width,
      size.height - bottomReservedSize,
    );
    if (plotRect.width <= 0 || plotRect.height <= 0) return;

    const labelStyle = material.TextStyle(
      color: material.Colors.white,
      fontSize: 15,
      fontWeight: material.FontWeight.bold,
      height: 1,
    );
    const labelEdgePadding = 4.0;
    const labelMarkerGap = 6.0;

    material.TextPainter buildLabelPainter(String text) {
      return material.TextPainter(
        text: material.TextSpan(text: text, style: labelStyle),
        textAlign: material.TextAlign.center,
        textDirection: material.TextDirection.ltr,
      )..layout();
    }

    for (final marker in markers) {
      if (!marker.enabled ||
          marker.freqHz < minFreq ||
          marker.freqHz > maxFreq) {
        continue;
      }

      final yValue = getYAt(marker.freqHz).clamp(minDbm, maxDbm);
      final x = plotRect.left +
          ((marker.freqHz - minFreq) / freqRange) * plotRect.width;
      final y =
          plotRect.bottom - (((yValue - minDbm) / dbmRange) * plotRect.height);

      final abovePainter = buildLabelPainter('M${marker.id}\n\u25BC');
      final paintAbove =
          y - abovePainter.height - labelMarkerGap >= plotRect.top;
      final textPainter = paintAbove
          ? abovePainter
          : buildLabelPainter('\u25B2\nM${marker.id}');

      final minDx = plotRect.left + labelEdgePadding;
      final maxDx = plotRect.right - labelEdgePadding - textPainter.width;
      final preferredDx = x - textPainter.width / 2;
      final dx =
          maxDx < minDx ? minDx : preferredDx.clamp(minDx, maxDx).toDouble();

      final minDy = plotRect.top + labelEdgePadding;
      final maxDy = plotRect.bottom - labelEdgePadding - textPainter.height;
      final preferredDy = paintAbove
          ? y - textPainter.height - labelMarkerGap
          : y + labelMarkerGap;
      final dy =
          maxDy < minDy ? minDy : preferredDy.clamp(minDy, maxDy).toDouble();

      textPainter.paint(canvas, material.Offset(dx, dy));
    }
  }

  @override
  bool shouldRepaint(covariant _MarkerLabelPainter oldDelegate) {
    return oldDelegate.markers != markers ||
        oldDelegate.minFreq != minFreq ||
        oldDelegate.maxFreq != maxFreq ||
        oldDelegate.minDbm != minDbm ||
        oldDelegate.maxDbm != maxDbm ||
        oldDelegate.leftReservedSize != leftReservedSize ||
        oldDelegate.bottomReservedSize != bottomReservedSize;
  }
}
