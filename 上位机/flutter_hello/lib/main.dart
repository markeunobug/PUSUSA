// main.dart
import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/material.dart' as material;
import 'dart:math' as math;
import 'dart:async';
import 'package:fl_chart/fl_chart.dart';

// 导入串口相关
import 'serial_port_manager.dart';
import 'serial_port_selector.dart';
import 'serial_protocol.dart';

// 导入自定义频谱图组件
import 'spectrum_chart.dart';

// ==================== 扫描模式枚举（顶层） ====================
enum SweepMode { standard, realTime }

void main() {
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return FluentApp(
      title: 'Spectrum Analyzer',
      theme: FluentThemeData(
        brightness: Brightness.dark,
        accentColor: Colors.blue,
      ),
      home: const MyHomePage(),
    );
  }
}

class MyHomePage extends StatefulWidget {
  const MyHomePage({super.key});

  @override
  State<MyHomePage> createState() => _MyHomePageState();
}

class _MyHomePageState extends State<MyHomePage> {
  final FocusNode startFreqFocus = FocusNode();
  final FocusNode stopFreqFocus = FocusNode();
  final FocusNode centerFreqFocus = FocusNode();
  final FocusNode spanFocus = FocusNode();
  final FocusNode refLevelFocus = FocusNode();
  final FocusNode rbwFocus = FocusNode();
  final FocusNode vbwFocus = FocusNode();
  final FocusNode scaleFocus = FocusNode();

  // 单位选项列表
  final List<String> freqUnits = ['Hz', 'kHz', 'MHz', 'GHz'];

  // Frequency 参数控制器和单位
  final TextEditingController startFreqController = TextEditingController(text: '0');
  final TextEditingController stopFreqController = TextEditingController(text: '10');
  final TextEditingController centerFreqController = TextEditingController(text: '5');
  final TextEditingController spanController = TextEditingController(text: '10');
  final ValueNotifier<String> startFreqUnit = ValueNotifier<String>('GHz');
  final ValueNotifier<String> stopFreqUnit = ValueNotifier<String>('GHz');
  final ValueNotifier<String> centerFreqUnit = ValueNotifier<String>('GHz');
  final ValueNotifier<String> spanUnit = ValueNotifier<String>('GHz');

  // Amplitude 参数
  final TextEditingController refLevelController = TextEditingController(text: '0');
  final ValueNotifier<String> attenuatorValue = ValueNotifier<String>('自动');
  final ValueNotifier<String> preAmpValue = ValueNotifier<String>('自动');

  // BW 参数状态
  final ValueNotifier<String> rbwMode = ValueNotifier<String>('自动');
  final ValueNotifier<String> rbwUnit = ValueNotifier<String>('Hz');
  final TextEditingController rbwController = TextEditingController(text: '0');
  final ValueNotifier<String> vbwMode = ValueNotifier<String>('VBW=RBW');
  final ValueNotifier<String> vbwUnit = ValueNotifier<String>('Hz');
  final TextEditingController vbwController = TextEditingController(text: '0');

  // Detect 参数状态
  final ValueNotifier<String> detectMode = ValueNotifier<String>('平均');

  // Graph 参数
  final TextEditingController scalePerGridController = TextEditingController(text: '10');

  // 扫描速度（设置值）
  final ValueNotifier<double> sweepSpeed = ValueNotifier<double>(30.0);

  // 扫描模式（默认标准模式）
  SweepMode _sweepMode = SweepMode.standard;
  final FlyoutController _modeFlyoutController = FlyoutController();

  // 串口管理
  late SerialPortManager _serialManager;
  late SerialProtocol _protocol;

  final FlyoutController _serialFlyoutController = FlyoutController();

  // 频谱数据
  List<FlSpot> _spectrumData = [];

  // 连续扫描定时器
  Timer? _continuousSweepTimer;

  // Marker 管理
  List<Marker> _markers = [];
  Marker? _currentMarker;
  final TextEditingController _markerFreqController = TextEditingController();
  final ValueNotifier<String> _markerFreqUnit = ValueNotifier<String>('GHz');

  // 自动峰值标注开关
  final ValueNotifier<bool> autoPeakEnabled = ValueNotifier<bool>(true);

  // 最小峰间距系数（专业频谱仪通常1~3倍RBW）
  final double _minPeakSpacingRatio = 1.0;

  // 扫描计数相关（新增）
  int _scanCount = 0; // 扫描次数计数器
  DateTime? _lastScanTime; // 上次统计时间
  double _currentSweepSpeed = 0.0; // 当前实际扫描速度（次/秒）
  Timer? _speedCalculationTimer; // 每秒计算一次扫描速度

  @override
  void initState() {
    super.initState();
    _serialManager = SerialPortManager()..init();
    _protocol = SerialProtocol(_serialManager);

    _protocol.spectrumStream.listen(_handleSpectrumData);
    _protocol.getStatus();

    sweepSpeed.addListener(_sendSweepConfig);
    attenuatorValue.addListener(_sendAmplitudeConfig);
    preAmpValue.addListener(_sendAmplitudeConfig);
    rbwMode.addListener(() {
      _updateRbwField();
      _updateVbwField();
      _sendBwConfig();
    });
    vbwMode.addListener(() {
      _updateVbwField();
      _sendBwConfig();
    });
    detectMode.addListener(_sendDetectConfig);

    // 初始化固定8个Marker，初始禁用，频率为中心频率
    _markers = List.generate(8, (index) => Marker(index + 1, _getCurrentCenterFreq(), enabled: false));

    // 默认开启游标1，并选中
    _markers[0].enabled = true;
    _selectMarker(_markers[0]);

    // 初始化扫描计数相关（新增）
    _lastScanTime = DateTime.now();
    _speedCalculationTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (_lastScanTime != null) {
        final duration = DateTime.now().difference(_lastScanTime!);
        if (duration.inMilliseconds > 0) {
          // 计算每秒扫描次数
          _currentSweepSpeed = _scanCount / (duration.inMilliseconds / 1000);
        } else {
          _currentSweepSpeed = 0.0;
        }
      } else {
        _currentSweepSpeed = 0.0;
      }
      // 重置计数和时间
      _scanCount = 0;
      _lastScanTime = DateTime.now();
      setState(() {}); // 更新UI显示
    });
  }

  @override
  void dispose() {
    //九个 FocusNode
    startFreqFocus.dispose();
    stopFreqFocus.dispose();
    centerFreqFocus.dispose();
    spanFocus.dispose();
    refLevelFocus.dispose();
    rbwFocus.dispose();
    vbwFocus.dispose();
    scaleFocus.dispose();

    startFreqController.dispose();
    stopFreqController.dispose();
    centerFreqController.dispose();
    spanController.dispose();
    refLevelController.dispose();
    rbwController.dispose();
    vbwController.dispose();
    scalePerGridController.dispose();
    _markerFreqController.dispose();
    _markerFreqUnit.dispose();
    _serialManager.dispose();
    _protocol.dispose();
    _serialFlyoutController.dispose();
    _modeFlyoutController.dispose();
    _continuousSweepTimer?.cancel();
    _speedCalculationTimer?.cancel(); // 销毁扫描速度计算定时器
    sweepSpeed.removeListener(_sendSweepConfig);
    attenuatorValue.removeListener(_sendAmplitudeConfig);
    preAmpValue.removeListener(_sendAmplitudeConfig);
    rbwMode.removeListener(() {
      _updateRbwField();
      _updateVbwField();
      _sendBwConfig();
    });
    vbwMode.removeListener(() {
      _updateVbwField();
      _sendBwConfig();
    });
    detectMode.removeListener(_sendDetectConfig);
    super.dispose();
  }

  // 计算最小峰间距（基于RBW，单位：Hz）
  double _getMinPeakSpacing() {
    double rbwHz = _parseFreq(rbwController.text, rbwUnit.value) ?? 1e6; // 默认1MHz兜底
    return rbwHz * _minPeakSpacingRatio;
  }

  // 筛选不重叠的独立峰值（间距≥最小峰间距）
  List<FlSpot> _getNonOverlappingPeaks(List<FlSpot> sortedPeaks) {
    if (sortedPeaks.isEmpty) return [];

    final double minSpacing = _getMinPeakSpacing();
    List<FlSpot> nonOverlappingPeaks = [sortedPeaks.first];

    for (int i = 1; i < sortedPeaks.length; i++) {
      FlSpot currentPeak = sortedPeaks[i];
      // 检查与已选峰值的最小间距
      bool isOverlapping = nonOverlappingPeaks.any((peak) => 
        (currentPeak.x - peak.x).abs() < minSpacing
      );
      if (!isOverlapping) {
        nonOverlappingPeaks.add(currentPeak);
      }
    }
    return nonOverlappingPeaks;
  }

  void _handleSpectrumData(List<FlSpot> segment) {
    if (segment.isEmpty) {
      setState(() {});
      return;
    }

    final sortedSegment = List<FlSpot>.from(segment)..sort((a, b) => a.x.compareTo(b.x));

    // 频率映射表（频率 -> 幅值），用于合并新旧数据点
    final Map<double, double> freqMap = {};

    // 1. 保留所有已有数据点
    for (var spot in _spectrumData) {
      freqMap[spot.x] = spot.y;
    }

    // 2. 新接收到的段数据覆盖对应频率点（更新 Y 值）
    for (var spot in sortedSegment) {
      freqMap[spot.x] = spot.y;
    }

    // 3. 生成排序后的新列表
    setState(() {
      _spectrumData = freqMap.entries
          .map((e) => FlSpot(e.key, e.value))
          .toList()
        ..sort((a, b) => a.x.compareTo(b.x));

      // 扫描计数逻辑（新增核心）
      if (_sweepMode == SweepMode.realTime) {
        // 实时模式：每次刷新计为一次扫描
        _scanCount++;
      } else {
        // 标准模式：完成一整段（频率覆盖完整start~stop）计为一次扫描
        final startFreq = _getCurrentStartFreq();
        final stopFreq = _getCurrentStopFreq();
        final minX = _spectrumData.map((e) => e.x).reduce(math.min);
        final maxX = _spectrumData.map((e) => e.x).reduce(math.max);
        // 频率容差（避免浮点精度问题）
        const frequencyTolerance = 1e-6;
        if (minX <= startFreq + frequencyTolerance && maxX >= stopFreq - frequencyTolerance) {
          _scanCount++;
        }
      }

      if (autoPeakEnabled.value) {
        var enabledMarkers = _markers.where((m) => m.enabled).toList()..sort((a, b) => a.id.compareTo(b.id));
        if (enabledMarkers.isNotEmpty && _spectrumData.isNotEmpty) {
          // 按幅值降序排序所有数据点
          var sortedPeaks = List<FlSpot>.from(_spectrumData)..sort((a, b) => b.y.compareTo(a.y));
          // 筛选不重叠的独立峰值
          var nonOverlappingPeaks = _getNonOverlappingPeaks(sortedPeaks);
          // 分配峰值到启用的游标
          for (int i = 0; i < enabledMarkers.length; i++) {
            if (i < nonOverlappingPeaks.length) {
              enabledMarkers[i].freqHz = nonOverlappingPeaks[i].x;
            } else {
              // 峰值数量不足时，保留最后一个有效峰值
              enabledMarkers[i].freqHz = nonOverlappingPeaks.isNotEmpty 
                  ? nonOverlappingPeaks.last.x 
                  : _getCurrentCenterFreq();
            }
          }
          if (_currentMarker != null && _currentMarker!.enabled) {
            _markerFreqController.text = _formatFreq(_currentMarker!.freqHz, _markerFreqUnit.value);
          }
        }
      }
    });
  }

  double _getCurrentStartFreq() {
    return _parseFreq(startFreqController.text, startFreqUnit.value) ?? 0;
  }

  double _getCurrentStopFreq() {
    return _parseFreq(stopFreqController.text, stopFreqUnit.value) ?? 10e9;
  }

  double _getCurrentCenterFreq() {
    return _parseFreq(centerFreqController.text, centerFreqUnit.value) ?? 5e9;
  }

  double _getUnitFactor(String unit) {
    switch (unit) {
      case 'kHz':
        return 1e3;
      case 'MHz':
        return 1e6;
      case 'GHz':
        return 1e9;
      default:
        return 1.0;
    }
  }

  double? _parseFreq(String text, String unit) {
    final double? value = double.tryParse(text);
    if (value == null || value < 0) return null;
    return value * _getUnitFactor(unit);
  }

  String _formatFreqAutoUnit(double freqHz, [int decimalPlaces = 2]) {
    if (freqHz >= 1e9) return '${(freqHz / 1e9).toStringAsFixed(decimalPlaces)} GHz';
    if (freqHz >= 1e6) return '${(freqHz / 1e6).toStringAsFixed(decimalPlaces)} MHz';
    if (freqHz >= 1e3) return '${(freqHz / 1e3).toStringAsFixed(decimalPlaces)} kHz';
    return '${freqHz.toStringAsFixed(decimalPlaces)} Hz';
  }

  String _formatFreq(double freqHz, String unit, [int decimalPlaces = 2]) {
    final double factor = _getUnitFactor(unit);
    return '${(freqHz / factor).toStringAsFixed(decimalPlaces)}';
  }

  void _setFreqField(TextEditingController controller, ValueNotifier<String> unitNotifier, double freqHz) {
    String bestUnit;
    double value;
    if (freqHz >= 1e9) {
      bestUnit = 'GHz';
      value = freqHz / 1e9;
    } else if (freqHz >= 1e6) {
      bestUnit = 'MHz';
      value = freqHz / 1e6;
    } else if (freqHz >= 1e3) {
      bestUnit = 'kHz';
      value = freqHz / 1e3;
    } else {
      bestUnit = 'Hz';
      value = freqHz;
    }
    unitNotifier.value = bestUnit;
    controller.text = value.toStringAsFixed(2);
  }

  void _updateRbwField() {
    if (rbwMode.value == '手动') return;
    final double? spanHz = _parseFreq(spanController.text, spanUnit.value);
    if (spanHz == null || spanHz <= 0) return;
    double rbwHz = spanHz * 0.01;
    if (rbwMode.value == '0.001*Span') rbwHz = spanHz * 0.001;
    if (rbwMode.value == '0.01*Span') rbwHz = spanHz * 0.01;
    _setFreqField(rbwController, rbwUnit, rbwHz);
  }

  void _updateVbwField() {
    if (vbwMode.value == '手动') return;
    final double? rbwHz = _parseFreq(rbwController.text, rbwUnit.value);
    if (rbwHz == null || rbwHz <= 0) return;
    double vbwHz = rbwHz;
    switch (vbwMode.value) {
      case 'VBW=0.1*RBW':
        vbwHz *= 0.1;
        break;
      case 'VBW=0.01*RBW':
        vbwHz *= 0.01;
        break;
      case 'VBW=10*RBW':
        vbwHz *= 10;
        break;
    }
    _setFreqField(vbwController, vbwUnit, vbwHz);
  }

  void _showErrorDialog(String message) {
    showDialog(
      context: context,
      builder: (context) => ContentDialog(
        title: const Text('参数错误'),
        content: Text(message),
        actions: [Button(child: const Text('确定'), onPressed: () => Navigator.pop(context))],
      ),
    );
  }

  void _updateFreqFromStartStop() {
    final double? startHz = _parseFreq(startFreqController.text, startFreqUnit.value);
    final double? stopHz = _parseFreq(stopFreqController.text, stopFreqUnit.value);
    if (startHz == null || stopHz == null) {
      _showErrorDialog('起始/终止频率输入无效');
      return;
    }
    if (startHz >= stopHz) {
      _showErrorDialog('起始频率不能大于等于终止频率');
      return;
    }

    final double centerHz = (startHz + stopHz) / 2;
    final double spanHz = stopHz - startHz;

    setState(() {
      centerFreqController.text = _formatFreq(centerHz, centerFreqUnit.value);
      spanController.text = _formatFreq(spanHz, spanUnit.value);
    });

    _protocol.setFreq(startHz, stopHz, centerHz, spanHz);
    _updateRbwField();
    _updateVbwField();
    _sendBwConfig();
    _spectrumData.clear();
  }

  void _updateFreqFromCenterSpan() {
    final double? centerHz = _parseFreq(centerFreqController.text, centerFreqUnit.value);
    final double? spanHz = _parseFreq(spanController.text, spanUnit.value);
    if (centerHz == null || spanHz == null) {
      _showErrorDialog('中心频率/扫宽输入无效');
      return;
    }
    if (spanHz <= 0) {
      _showErrorDialog('扫宽必须大于0');
      return;
    }

    final double startHz = centerHz - spanHz / 2;
    final double stopHz = centerHz + spanHz / 2;
    if (startHz < 0) {
      _showErrorDialog('起始频率为负数');
      return;
    }

    setState(() {
      startFreqController.text = _formatFreq(startHz, startFreqUnit.value);
      stopFreqController.text = _formatFreq(stopHz, stopFreqUnit.value);
    });

    _protocol.setFreq(startHz, stopHz, centerHz, spanHz);
    _updateRbwField();
    _updateVbwField();
    _sendBwConfig();
    _spectrumData.clear();
  }

  void _sendAmplitudeConfig() {
    final double refLevel = double.tryParse(refLevelController.text) ?? 0;
    int attenuator = _mapAttenuatorStringToInt(attenuatorValue.value);
    int preamp = _mapPreAmpStringToInt(preAmpValue.value);
    _protocol.setAmplitude(refLevel, attenuator, preamp);
  }

  void _sendBwConfig() {
    int rbwModeInt = _mapRbwModeStringToInt(rbwMode.value);
    double rbwHz = _parseFreq(rbwController.text, rbwUnit.value) ?? 0;
    int vbwModeInt = _mapVbwModeStringToInt(vbwMode.value);
    double vbwHz = _parseFreq(vbwController.text, vbwUnit.value) ?? 0;
    _protocol.setBw(rbwModeInt, rbwHz, vbwModeInt, vbwHz);
  }

  void _sendDetectConfig() {
    _protocol.setDetect(_mapDetectStringToInt(detectMode.value));
  }

  void _sendSweepConfig() {
    _protocol.setSweep(sweepSpeed.value, 0);
  }

  // ====================== 传统 switch 语句（兼容旧 Dart 版本） ======================
  int _mapAttenuatorStringToInt(String value) {
    switch (value) {
      case '自动':
        return 0;
      case '0dB':
        return 1;
      case '0.25dB':
        return 2;
      case '0.5dB':
        return 3;
      case '1dB':
        return 4;
      case '2dB':
        return 5;
      case '4dB':
        return 6;
      case '8dB':
        return 7;
      case '16dB':
        return 8;
      case '31.75dB':
        return 9;
      default:
        return 0;
    }
  }

  int _mapPreAmpStringToInt(String value) {
    switch (value) {
      case '自动':
        return 0;
      case '使能':
        return 1;
      case '关闭':
        return 2;
      default:
        return 0;
    }
  }

  int _mapRbwModeStringToInt(String value) {
    switch (value) {
      case '自动':
        return 0;
      case '手动':
        return 1;
      case '0.001*Span':
        return 2;
      case '0.01*Span':
        return 3;
      default:
        return 0;
    }
  }

  int _mapVbwModeStringToInt(String value) {
    switch (value) {
      case 'VBW=RBW':
        return 0;
      case '手动':
        return 1;
      case 'VBW=0.1*RBW':
        return 2;
      case 'VBW=0.01*RBW':
        return 3;
      case 'VBW=10*RBW':
        return 4;
      default:
        return 0;
    }
  }

  int _mapDetectStringToInt(String value) {
    switch (value) {
      case '平均':
        return 0;
      case '取样':
        return 1;
      case '正峰值':
        return 2;
      case '负峰值':
        return 3;
      case '最大功率':
        return 4;
      case '均方根值':
        return 5;
      default:
        return 0;
    }
  }

  void _startContinuousSweep() {
    _continuousSweepTimer?.cancel();
    _continuousSweepTimer = Timer.periodic(
      Duration(milliseconds: (1000 / sweepSpeed.value).round()),
      (_) => _protocol.getSpectrum(),
    );
  }

  void _stopContinuousSweep() => _continuousSweepTimer?.cancel();

  void _showModeFlyout() {
    _modeFlyoutController.showFlyout(
      builder: (context) => FlyoutContent(
        child: SizedBox(
          width: 280,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                title: const Text('标准模式'),
                subtitle: const Text('分段扫描，显示扫频进度（大扫宽推荐）'),
                trailing: _sweepMode == SweepMode.standard ? const Icon(FluentIcons.check_mark) : const SizedBox.shrink(),
                onPressed: () {
                  setState(() {
                    _sweepMode = SweepMode.standard;
                    _spectrumData.clear();
                  });
                  Navigator.pop(context);
                },
              ),
              ListTile(
                title: const Text('实时模式'),
                subtitle: const Text('全帧实时刷新（小扫宽推荐）'),
                trailing: _sweepMode == SweepMode.realTime ? const Icon(FluentIcons.check_mark) : const SizedBox.shrink(),
                onPressed: () {
                  setState(() => _sweepMode = SweepMode.realTime);
                  Navigator.pop(context);
                },
              ),
            ],
          ),
        ),
      ),
    );
  }

  // 向左寻峰（跳过最小峰间距）
  double _findLeftPeak(double currentFreq) {
    if (_spectrumData.isEmpty) return currentFreq;
    
    final double minSpacing = _getMinPeakSpacing();
    // 筛选当前频率左侧且间距≥最小间距的点
    var leftData = _spectrumData
        .where((spot) => spot.x < currentFreq - minSpacing)
        .toList();
    
    if (leftData.isEmpty) return currentFreq;
    // 找到左侧最大幅值的点
    return leftData.reduce((a, b) => a.y > b.y ? a : b).x;
  }

  // 向右寻峰（跳过最小峰间距）
  double _findRightPeak(double currentFreq) {
    if (_spectrumData.isEmpty) return currentFreq;
    
    final double minSpacing = _getMinPeakSpacing();
    // 筛选当前频率右侧且间距≥最小间距的点
    var rightData = _spectrumData
        .where((spot) => spot.x > currentFreq + minSpacing)
        .toList();
    
    if (rightData.isEmpty) return currentFreq;
    // 找到右侧最大幅值的点
    return rightData.reduce((a, b) => a.y > b.y ? a : b).x;
  }

  void _selectMarker(Marker? marker) {
    setState(() {
      _currentMarker = marker;
    });
    if (marker != null) {
      _markerFreqController.text = _formatFreq(marker.freqHz, _markerFreqUnit.value);
    } else {
      _markerFreqController.clear();
    }
  }

  @override
  Widget build(BuildContext context) {
    final double startFreq = _parseFreq(startFreqController.text, startFreqUnit.value) ?? 0;
    final double stopFreq = _parseFreq(stopFreqController.text, stopFreqUnit.value) ?? 10e9;
    final double centerFreq = _parseFreq(centerFreqController.text, centerFreqUnit.value) ?? 5e9;
    final double span = _parseFreq(spanController.text, spanUnit.value) ?? 10e9;

    final double refLevel = double.tryParse(refLevelController.text) ?? 0;
    final double scalePerGrid = double.tryParse(scalePerGridController.text) ?? 10;

    double actualMinDbm = -110;
    double actualMaxDbm = -90;
    if (_spectrumData.isNotEmpty) {
      actualMinDbm = _spectrumData.map((e) => e.y).reduce(math.min);
      actualMaxDbm = _spectrumData.map((e) => e.y).reduce(math.max);
    }

    var displayScale = scalePerGrid;
    while ((actualMaxDbm - actualMinDbm) > 10 * displayScale) {
      displayScale *= 2;
    }

    final double minDbmDisplay = (actualMinDbm / displayScale).floor() * displayScale;
    final double maxDbmDisplay = minDbmDisplay + 10 * displayScale;

    return ScaffoldPage(
      padding: const EdgeInsets.only(top: 0),
      header: CommandBar(
        overflowBehavior: CommandBarOverflowBehavior.wrap,
        primaryItems: [
          CommandBarButton(
            icon: Image.asset('assets/imgs/logo6.png', width: 127, height: 35),
            onPressed: null,
          ),
          CommandBarButton(icon: const Icon(FluentIcons.document), label: const Text('文件'), onPressed: () {}),

          // 模式按钮（只显示“模式”）
          CommandBarButton(
            icon: FlyoutTarget(
              controller: _modeFlyoutController,
              child: const Icon(FluentIcons.settings),
            ),
            label: const Text('模式'),
            onPressed: _showModeFlyout,
          ),

          CommandBarButton(icon: const Icon(FluentIcons.toolbox), label: const Text('系统'), onPressed: () {}),
          CommandBarButton(icon: const Icon(FluentIcons.refresh), label: const Text('预设'), onPressed: () {
            _protocol.reset();
            _spectrumData.clear();
          }),
          CommandBarButton(icon: const Icon(FluentIcons.play), label: const Text('单次'), onPressed: () => _protocol.getSpectrum()),
          CommandBarButton(icon: const Icon(FluentIcons.play_resume), label: const Text('连续'), onPressed: _startContinuousSweep),
          CommandBarButton(icon: const Icon(FluentIcons.record2), label: const Text('记录'), onPressed: _stopContinuousSweep),
          CommandBarButton(icon: const Icon(FluentIcons.repeat_all), label: const Text('回放'), onPressed: () {}),
          CommandBarButton(icon: const Icon(FluentIcons.camera), label: const Text('截图'), onPressed: () {}),
          const CommandBarSeparator(),
          CommandBarButton(
            icon: FlyoutTarget(
              controller: _serialFlyoutController,
              child: ValueListenableBuilder<ConnectionStatus>(
                valueListenable: _serialManager.connectionStatus,
                builder: (context, status, child) {
                  Color color;
                  switch (status) {                    // 传统 switch
                    case ConnectionStatus.connected:
                      color = material.Colors.green;
                      break;
                    case ConnectionStatus.disconnected:
                      color = material.Colors.red;
                      break;
                    case ConnectionStatus.noPorts:
                      color = material.Colors.grey;
                      break;
                  }
                  return Container(
                    width: 12,
                    height: 12,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: color),
                  );
                },
              ),
            ),
            label: const Text('Serial Port'),
            onPressed: () => _serialFlyoutController.showFlyout(
              builder: (context) => SerialPortSelector(manager: _serialManager),
            ),
          ),
        ],
      ),
      content: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Acrylic(
              tint: material.Colors.black.withOpacity(0.8),
              child: SpectrumChart(
                data: _spectrumData,
                minFreq: startFreq,
                maxFreq: stopFreq,
                minDbm: minDbmDisplay,
                maxDbm: maxDbmDisplay,
                scalePerGrid: displayScale,
                startFreqStr: _formatFreqAutoUnit(startFreq),
                stopFreqStr: _formatFreqAutoUnit(stopFreq),
                centerFreqStr: _formatFreqAutoUnit(centerFreq),
                spanStr: _formatFreqAutoUnit(span),
                sweepSpeedStr: '${_currentSweepSpeed.toStringAsFixed(1)} 次/秒', // 修改单位为次/秒
                markers: _markers,
              ),
            ),
          ),
          Container(
            width: 300,
            color: const Color.fromARGB(255, 66, 66, 66),
            padding: const EdgeInsets.all(8),
            child: SingleChildScrollView(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expander(
                    header: const Text('Frequency'),
                    content: Column(
                      children: [
                        _buildInputRow(label: '起始频率：', controller: startFreqController, unitNotifier: startFreqUnit, units: freqUnits, onSubmitted: _updateFreqFromStartStop),
                        const SizedBox(height: 8),
                        _buildInputRow(label: '终止频率：', controller: stopFreqController, unitNotifier: stopFreqUnit, units: freqUnits, onSubmitted: _updateFreqFromStartStop),
                        const SizedBox(height: 8),
                        _buildInputRow(label: '中心频率：', controller: centerFreqController, unitNotifier: centerFreqUnit, units: freqUnits, onSubmitted: _updateFreqFromCenterSpan),
                        const SizedBox(height: 8),
                        _buildInputRow(label: '扫描宽度：', controller: spanController, unitNotifier: spanUnit, units: freqUnits, onSubmitted: _updateFreqFromCenterSpan),
                      ],
                    ),
                  ),
                  Expander(
                    header: const Text('Amplitude'),
                    content: Column(
                      children: [
                        Row(
                          children: [
                            const SizedBox(width: 100, child: Text('参考电平：', style: TextStyle(color: material.Colors.white))),
                            Expanded(child: TextBox(controller: refLevelController, onSubmitted: (v) => _sendAmplitudeConfig())),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const SizedBox(width: 100, child: Text('衰减器：', style: TextStyle(color: material.Colors.white))),
                            Expanded(
                              child: ValueListenableBuilder<String>(
                                valueListenable: attenuatorValue,
                                builder: (context, value, child) => ComboBox<String>(
                                  value: value,
                                  isExpanded: true,
                                  items: ['自动', '0dB', '0.25dB', '0.5dB', '1dB', '2dB', '4dB', '8dB', '16dB', '31.75dB']
                                      .map((o) => ComboBoxItem<String>(value: o, child: Text(o)))
                                      .toList(),
                                  onChanged: (nv) => nv != null ? attenuatorValue.value = nv : null,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const SizedBox(width: 100, child: Text('预放：', style: TextStyle(color: material.Colors.white))),
                            Expanded(
                              child: ValueListenableBuilder<String>(
                                valueListenable: preAmpValue,
                                builder: (context, value, child) => ComboBox<String>(
                                  value: value,
                                  isExpanded: true,
                                  items: ['使能', '关闭', '自动']
                                      .map((o) => ComboBoxItem<String>(value: o, child: Text(o)))
                                      .toList(),
                                  onChanged: (nv) => nv != null ? preAmpValue.value = nv : null,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Expander(
                    header: const Text('BW'),
                    content: Column(
                      children: [
                        Row(
                          children: [
                            const SizedBox(width: 100, child: Text('RBW模式：', style: TextStyle(color: material.Colors.white))),
                            Expanded(
                              child: ValueListenableBuilder<String>(
                                valueListenable: rbwMode,
                                builder: (context, value, child) => ComboBox<String>(
                                  value: value,
                                  isExpanded: true,
                                  items: ['手动', '自动', '0.001*Span', '0.01*Span']
                                      .map((o) => ComboBoxItem<String>(value: o, child: Text(o)))
                                      .toList(),
                                  onChanged: (nv) => nv != null ? rbwMode.value = nv : null,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ValueListenableBuilder<String>(
                          valueListenable: rbwMode,
                          builder: (context, mode, child) {
                            final bool isEnabled = mode == '手动';
                            return _buildInputRow(
                              label: 'RBW：',
                              controller: rbwController,
                              unitNotifier: rbwUnit,
                              units: freqUnits,
                              enabled: isEnabled,
                              onSubmitted: isEnabled ? _sendBwConfig : null,
                            );
                          },
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const SizedBox(width: 100, child: Text('VBW模式：', style: TextStyle(color: material.Colors.white))),
                            Expanded(
                              child: ValueListenableBuilder<String>(
                                valueListenable: vbwMode,
                                builder: (context, value, child) => ComboBox<String>(
                                  value: value,
                                  isExpanded: true,
                                  items: ['手动', 'VBW=RBW', 'VBW=0.1*RBW', 'VBW=0.01*RBW', 'VBW=10*RBW']
                                      .map((o) => ComboBoxItem<String>(value: o, child: Text(o)))
                                      .toList(),
                                  onChanged: (nv) => nv != null ? vbwMode.value = nv : null,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 8),
                        ValueListenableBuilder<String>(
                          valueListenable: vbwMode,
                          builder: (context, mode, child) {
                            final bool isEnabled = mode == '手动';
                            return _buildInputRow(
                              label: 'VBW：',
                              controller: vbwController,
                              unitNotifier: vbwUnit,
                              units: freqUnits,
                              enabled: isEnabled,
                              onSubmitted: isEnabled ? _sendBwConfig : null,
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  Expander(
                    header: const Text('Detect'),
                    content: Column(
                      children: [
                        Row(
                          children: [
                            const SizedBox(width: 100, child: Text('检波方式：', style: TextStyle(color: material.Colors.white))),
                            Expanded(
                              child: ValueListenableBuilder<String>(
                                valueListenable: detectMode,
                                builder: (context, value, child) => ComboBox<String>(
                                  value: value,
                                  isExpanded: true,
                                  items: ['取样', '平均', '正峰值', '负峰值', '最大功率', '均方根值']
                                      .map((o) => ComboBoxItem<String>(value: o, child: Text(o)))
                                      .toList(),
                                  onChanged: (nv) => nv != null ? detectMode.value = nv : null,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ),
                  Expander(
                    header: const Text('Marker'),
                    content: Column(
                      children: [
                        ValueListenableBuilder<bool>(
                          valueListenable: autoPeakEnabled,
                          builder: (context, value, child) => Row(
                            children: [
                              const SizedBox(width: 100, child: Text('峰值搜索：', style: TextStyle(color: material.Colors.white))),
                              ToggleSwitch(
                                checked: value,
                                onChanged: (v) => autoPeakEnabled.value = v,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 8),
                        Row(
                          children: [
                            const SizedBox(width: 100, child: Text('当前游标：', style: TextStyle(color: material.Colors.white))),
                            Expanded(
                              child: ComboBox<int?>(
                                value: _currentMarker?.id,
                                isExpanded: true,
                                items: _markers.map((m) => ComboBoxItem<int?>(value: m.id, child: Text('Marker ${m.id}'))).toList(),
                                placeholder: const Text('无'),
                                onChanged: (id) {
                                  if (id == null) {
                                    _selectMarker(null);
                                  } else {
                                    _selectMarker(_markers.firstWhere((m) => m.id == id));
                                  }
                                },
                              ),
                            ),
                            const SizedBox(width: 8),
                            if (_currentMarker != null) ...[
                              Row(
                                mainAxisAlignment: MainAxisAlignment.end,
                                children: [
                                  ToggleSwitch(
                                    checked: _currentMarker!.enabled,
                                    onChanged: (v) => setState(() => _currentMarker!.enabled = v),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 8),
                            ],
                          ],
                        ),
                        const SizedBox(height: 8),
                        ValueListenableBuilder<bool>(
                          valueListenable: autoPeakEnabled,
                          builder: (context, autoEnabled, child) {
                            final bool manualEnabled = !autoEnabled;
                            return Row(
                              children: [
                                const SizedBox(width: 100, child: Text('游标操作：', style: TextStyle(color: material.Colors.white))),
                                Expanded(
                                  child: ComboBox<String>(
                                    placeholder: const Text('选择操作'),
                                    isExpanded: true,
                                    items: ['向左寻峰', '向右寻峰', '起始点', '结束点', '中间点']
                                        .map((o) => ComboBoxItem<String>(value: o, child: Text(o)))
                                        .toList(),
                                    onChanged: manualEnabled
                                        ? (action) {
                                            if (action == null || _currentMarker == null) return;
                                            double newFreq = _currentMarker!.freqHz;
                                            switch (action) {
                                              case '起始点':
                                                newFreq = _getCurrentStartFreq();
                                                break;
                                              case '结束点':
                                                newFreq = _getCurrentStopFreq();
                                                break;
                                              case '向左寻峰':
                                                newFreq = _findLeftPeak(_currentMarker!.freqHz);
                                                break;
                                              case '向右寻峰':
                                                newFreq = _findRightPeak(_currentMarker!.freqHz);
                                                break;
                                              case '中间点':
                                                newFreq = _getCurrentCenterFreq();
                                                break;
                                            }
                                            _currentMarker!.freqHz = newFreq;
                                            _markerFreqController.text = _formatFreq(newFreq, _markerFreqUnit.value);
                                            setState(() {});
                                          }
                                        : null,
                                  ),
                                ),
                              ],
                            );
                          },
                        ),
                        const SizedBox(height: 8),
                        ValueListenableBuilder<bool>(
                          valueListenable: autoPeakEnabled,
                          builder: (context, autoEnabled, child) {
                            final bool manualEnabled = !autoEnabled;
                            return _buildInputRow(
                              label: '游标频点：',
                              controller: _markerFreqController,
                              unitNotifier: _markerFreqUnit,
                              units: freqUnits,
                              enabled: manualEnabled,
                              onSubmitted: manualEnabled
                                  ? () {
                                      final double? parsed = _parseFreq(_markerFreqController.text, _markerFreqUnit.value);
                                      if (parsed != null && _currentMarker != null) {
                                        _currentMarker!.freqHz = parsed;
                                        setState(() {});
                                      }
                                    }
                                  : null,
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                  const Expander(header: Text('Measure'), content: Placeholder()),
                  const Expander(header: Text('System'), content: Placeholder()),
                  Expander(
                    header: const Text('Graph'),
                    content: Column(
                      children: [
                        Row(
                          children: [
                            const SizedBox(width: 100, child: Text('刻度/格：', style: TextStyle(color: material.Colors.white))),
                            Expanded(
                              child: TextBox(
                                controller: scalePerGridController,
                                onChanged: (value) => setState(() {}),
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Text('dB', style: TextStyle(color: material.Colors.white)),
                          ],
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
      bottomBar: Container(
        height: 30,
        color: material.Colors.grey[900],
        child: Row(
          children: [
            const SizedBox(width: 16),
            Text(
              '模式：${_sweepMode == SweepMode.standard ? "标准" : "实时"}      扫描速度：${_currentSweepSpeed.toStringAsFixed(1)} 次/秒      当前状态：正在扫描      系统温度：25℃',
              style: const TextStyle(color: material.Colors.white),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputRow({
    required String label,
    required TextEditingController controller,
    required ValueNotifier<String> unitNotifier,
    required List<String> units,
    bool enabled = true,
    VoidCallback? onSubmitted,
    FocusNode? focusNode,
  }) {
    return Row(
      children: [
        SizedBox(width: 100, child: Text(label, style: const TextStyle(color: material.Colors.white))),
        Expanded(
          child: TextBox(
            controller: controller,
            focusNode: focusNode,
            enabled: enabled,
            onSubmitted: enabled && onSubmitted != null
                ? (v) {
                    controller.text = v.trim();
                    onSubmitted();
                  }
                : null,
          ),
        ),
        const SizedBox(width: 8),
        SizedBox(
          width: 80,
          child: ValueListenableBuilder<String>(
            valueListenable: unitNotifier,
            builder: (context, value, child) => ComboBox<String>(
              value: value,
              items: units.map((u) => ComboBoxItem<String>(value: u, child: Text(u))).toList(),
              onChanged: (nv) {
                if (nv != null) {
                  unitNotifier.value = nv;
                  // 单位切换建议也立即生效（专业仪器习惯），如果想严格只回车，可删掉下面这行
                  onSubmitted?.call();
                }
              },
            ),
          ),
        ),
      ],
    );
  }
}