// spectrum_chart.dart
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart' as material;

class Marker {
  final int id;
  double freqHz;
  bool enabled = false;

  Marker(this.id, this.freqHz, {this.enabled = false});
}

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
  });

  /// 核心：根据频点x值，精准获取对应的幅值y值（dBm）
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

  String _formatFreqAutoUnit(double freqHz, [int decimalPlaces = 3]) {
    if (freqHz >= 1e9) return '${(freqHz / 1e9).toStringAsFixed(decimalPlaces)} GHz';
    if (freqHz >= 1e6) return '${(freqHz / 1e6).toStringAsFixed(decimalPlaces)} MHz';
    if (freqHz >= 1e3) return '${(freqHz / 1e3).toStringAsFixed(decimalPlaces)} kHz';
    return '${freqHz.toStringAsFixed(decimalPlaces)} Hz';
  }

  // 顶部Marker信息栏（强制左对齐 + 自动换行）
  material.Widget _buildMarkerInfoRow() {
    final enabledMarkers = markers.where((m) => m.enabled).toList();

    return material.Container(
      width: double.infinity, // 强制容器充满父宽度，避免宽度不足导致对齐异常
      padding: const material.EdgeInsets.only(top: 0, bottom: 15),
      // 移除固定高度！固定高度会挤压Wrap布局，导致视觉上"居中"
      // height: 32, 
      child: material.Wrap(
        alignment: material.WrapAlignment.start, // 水平方向左对齐（核心）
        crossAxisAlignment: material.WrapCrossAlignment.start, // 垂直方向左对齐（解决居中关键）
        spacing: 32, // 子元素水平间距
        runSpacing: 8, // 换行后垂直间距
        children: enabledMarkers.map((m) {
          final freqStr = _formatFreqAutoUnit(m.freqHz);
          final y = _getYAt(m.freqHz);
          return material.Text(
            'M${m.id}  $freqStr  ${y.toStringAsFixed(2)} dBm',
            style: const material.TextStyle(
              color: material.Colors.white,
              fontSize: 13,
              fontWeight: material.FontWeight.w600,
            ),
          );
        }).toList(),
      ),
    );
  }

  // 【横轴标记：VerticalLine 精确频率坐标 + 三角游标（精准对齐幅值）】
  List<VerticalLine> _buildMarkerVerticalLines() {
    final enabledMarkers = markers.where((m) => m.enabled).toList();
    return enabledMarkers
        .where((m) => m.freqHz >= minFreq && m.freqHz <= maxFreq)
        .map((m) {
          final capturedM = m;
          final yValue = _getYAt(m.freqHz); 
          
          final verticalOffsetRatio = (maxDbm - yValue) / (maxDbm - minDbm);
          
          return VerticalLine(
            x: m.freqHz,
            color: material.Colors.red.withOpacity(0.5),
            strokeWidth: 1,
            dashArray: null,
            label: VerticalLineLabel(
              show: true,
              alignment: material.Alignment(0, -1 + (verticalOffsetRatio * 2)),
              padding: const material.EdgeInsets.only(top: -40),
              labelResolver: (line) => 'M${capturedM.id}\n ▼',
              style: const material.TextStyle(
                color: material.Colors.white,
                fontSize: 15,
                fontWeight: material.FontWeight.bold,
                height: 1,
              ),
            ),
          );
        })
        .toList();
  }

  // 【纵轴标记：HorizontalLine 精确幅值坐标 + '◀数值' 文本】
  List<HorizontalLine> _buildMarkerHorizontalLines() {
    final enabledMarkers = markers.where((m) => m.enabled).toList();
    return enabledMarkers
        .where((m) => 
          m.freqHz >= minFreq && m.freqHz <= maxFreq && 
          _getYAt(m.freqHz) >= minDbm && _getYAt(m.freqHz) <= maxDbm
        )
        .map((m) {
          final capturedM = m;
          final yValue = _getYAt(m.freqHz);
          return HorizontalLine(
            y: yValue,
            color: material.Colors.white.withOpacity(0.3),
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
        })
        .toList();
  }

  @override
  material.Widget build(material.BuildContext context) {
    if (data.isEmpty) {
      return const material.Center(
        child: material.Text('无数据', style: material.TextStyle(color: material.Colors.white)),
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
          // 顶部Marker信息栏
          _buildMarkerInfoRow(),

          // 图表 + 游标标记（横轴+纵轴）
          material.Expanded(
            child: LineChart(
              LineChartData(
                gridData: FlGridData(
                  show: true,
                  drawVerticalLine: true,
                  drawHorizontalLine: true,
                  verticalInterval: (maxFreq - minFreq) / 10,
                  horizontalInterval: scalePerGrid,
                  getDrawingHorizontalLine: (value) => FlLine(
                    color: material.Colors.white.withOpacity(0.1),
                    strokeWidth: 1,
                    dashArray: [2, 2],
                  ),
                  getDrawingVerticalLine: (value) => FlLine(
                    color: material.Colors.white.withOpacity(0.1),
                    strokeWidth: 1,
                    dashArray: [2, 2],
                  ),
                ),
                titlesData: FlTitlesData(
                  show: true,
                  topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
                  leftTitles: AxisTitles(
                    sideTitles: SideTitles(
                      showTitles: true,
                      reservedSize: 60,
                      interval: scalePerGrid,
                      getTitlesWidget: (value, meta) => material.Text(
                        '${value.toInt()} dBm',
                        style: const material.TextStyle(color: material.Colors.white, fontSize: 12),
                      ),
                    ),
                  ),
                  bottomTitles: const AxisTitles(
                    sideTitles: SideTitles(showTitles: false),
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
                    isCurved: false,
                    color: material.Colors.yellow,
                    barWidth: 2,
                    dotData: const FlDotData(show: false),
                  ),
                ],
                extraLinesData: ExtraLinesData(
                  verticalLines: _buildMarkerVerticalLines(),
                  horizontalLines: _buildMarkerHorizontalLines(),
                ),
              ),
              duration: Duration.zero,
            ),
          ),

          const material.SizedBox(height: 8),
          material.Row(
            mainAxisAlignment: material.MainAxisAlignment.spaceBetween,
            children: [
              material.Text('起始: $startFreqStr', style: const material.TextStyle(color: material.Colors.green, fontSize: 12)),
              material.Text('中心: $centerFreqStr', style: const material.TextStyle(color: material.Colors.green, fontSize: 12)),
              material.Text('扫宽: $spanStr', style: const material.TextStyle(color: material.Colors.green, fontSize: 12)),
              material.Text('扫描速度: $sweepSpeedStr', style: const material.TextStyle(color: material.Colors.green, fontSize: 12)),
              material.Text('终止: $stopFreqStr', style: const material.TextStyle(color: material.Colors.green, fontSize: 12)),
            ],
          )
        ],
      ),
    );
  }
}