abstract final class AgentRequestPolicy {
  static const Set<String> dataAnalysisTools = <String>{
    'get_spectrum_snapshot',
    'analyze_spectrum',
    'place_peak_markers',
    'analyze_phase_noise',
    'get_phase_noise_snapshot',
    'get_sweep_profile',
    'get_realtime_spectrum_snapshot',
    'get_realtime_waterfall_history',
    'analyze_realtime_spectrum',
    'place_realtime_peak_markers',
    'compare_measurements',
    'evaluate_spectrum_limits',
  };
  static const Set<String> measurementStartTools = <String>{
    'start_single_sweep',
    'start_continuous_sweep',
    'start_phase_noise_measurement',
    'start_realtime_spectrum',
  };

  /// Configuration and navigation requests must not silently turn into data
  /// acquisition. Analysis tools are exposed only when the user's current
  /// request clearly asks to inspect or interpret measurement data.
  static bool requestsDataAnalysis(String request) {
    final text = request.trim().toLowerCase();
    if (text.isEmpty) return false;
    const analysisActions = <String>[
      '分析',
      '检测信号',
      '检测基波',
      '检测载波',
      '观察频谱',
      '观测频谱',
      '查看频谱',
      '看看频谱',
      '读取频谱',
      '测量结果',
      '有没有信号',
      '是否有信号',
      '有无信号',
      '发现信号',
      '哪个频段有信号',
      '哪些频段有信号',
      '哪里有信号',
      '瀑布',
      '扫频耗时',
      '扫描耗时',
      '为什么慢',
      '性能分析',
      'profile',
      'waterfall',
      'analysis',
      'analyze',
      'inspect spectrum',
      'signal present',
    ];
    if (analysisActions.any(text.contains)) return true;
    final searchesForSignal =
        RegExp(r'(发现|查找|寻找|搜索|识别|定位).{0,16}(信号|基波|载波)').hasMatch(text) ||
            RegExp(r'(信号|基波|载波).{0,8}(是否存在|是否正常|怎么样|如何)').hasMatch(text);
    if (searchesForSignal) return true;
    if (RegExp(r'(测量|读取|查看).{0,16}(频偏|相位噪声|dbc/hz)').hasMatch(text)) {
      return true;
    }
    const configurationTerms = <String>[
      '配置',
      '设置',
      '调整',
      '修改',
      '切换',
      '进入',
      'configure',
      'set ',
    ];
    if (configurationTerms.any(text.contains)) return false;
    const resultTerms = <String>[
      '频谱数据',
      '噪声底',
      '峰值',
      '找峰',
      '杂散',
      '谐波',
      '信噪比',
      'spectrum data',
      'noise floor',
      'peak',
      'spur',
      'harmonic',
    ];
    return resultTerms.any(text.contains);
  }

  static bool requestsMeasurementStart(String request) {
    if (requestsDataAnalysis(request)) return true;
    final text = request.trim().toLowerCase();
    const terms = <String>[
      '启动测量',
      '开始测量',
      '进行测量',
      '执行测量',
      '测量一下',
      '测一下',
      '启动扫频',
      '开始扫频',
      '单次扫频',
      '连续扫频',
      '扫频',
      '扫描整个频段',
      '扫描全频段',
      '全频段扫描',
      '全频扫描',
      '扫完整个频段',
      '采集',
      '启动实时频谱',
      '开启实时频谱',
      '运行实时频谱',
      'start measurement',
      'start sweep',
      'run measurement',
      'acquire',
    ];
    return terms.any(text.contains) ||
        RegExp(r'(启动|开始|进行|执行).{0,10}(测量|扫频|扫描|采集)').hasMatch(text) ||
        RegExp(r'(扫描|扫查).{0,8}(整个|全部|全).{0,4}(频段|频率范围)').hasMatch(text);
  }

  static List<Map<String, dynamic>> filterToolDefinitions(
    List<Map<String, dynamic>> definitions, {
    required bool allowDataAnalysis,
    bool allowMeasurementStart = true,
  }) {
    return definitions.where((definition) {
      final function = definition['function'];
      if (function is! Map) return true;
      final name = function['name'];
      if (!allowDataAnalysis && dataAnalysisTools.contains(name)) return false;
      if (!allowMeasurementStart && measurementStartTools.contains(name)) {
        return false;
      }
      return true;
    }).toList(growable: false);
  }
}
