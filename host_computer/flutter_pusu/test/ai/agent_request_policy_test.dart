import 'package:flutter_pusu/agent/agent_request_policy.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('configuration-only requests do not enable spectrum analysis', () {
    expect(
      AgentRequestPolicy.requestsDataAnalysis(
        '切换到实时频谱，把中心频率设为1 GHz并打开平均',
      ),
      isFalse,
    );
    expect(
      AgentRequestPolicy.requestsDataAnalysis('进入相位噪声模式并配置参数'),
      isFalse,
    );
    expect(
      AgentRequestPolicy.requestsMeasurementStart('进入相位噪声模式并配置参数'),
      isFalse,
    );
  });

  test('explicit inspection requests enable spectrum analysis', () {
    expect(
      AgentRequestPolicy.requestsDataAnalysis('分析实时频谱的平均曲线和峰值'),
      isTrue,
    );
    expect(
      AgentRequestPolicy.requestsDataAnalysis('看看有没有信号输入'),
      isTrue,
    );
    expect(
      AgentRequestPolicy.requestsMeasurementStart('启动相位噪声测量'),
      isTrue,
    );
    expect(
      AgentRequestPolicy.requestsDataAnalysis('测量10 kHz频偏处的相位噪声'),
      isTrue,
    );
    expect(
      AgentRequestPolicy.requestsDataAnalysis('读取最近5秒的瀑布历史数据'),
      isTrue,
    );
  });

  test('full-band signal discovery workflow enables acquisition and analysis',
      () {
    const request = '先扫描整个频段，然后发现哪个频段有信号，随后切换实时频谱模式到这个频段进一步观察';
    expect(AgentRequestPolicy.requestsDataAnalysis(request), isTrue);
    expect(AgentRequestPolicy.requestsMeasurementStart(request), isTrue);

    final visible = AgentRequestPolicy.filterToolDefinitions(
      <Map<String, dynamic>>[
        <String, dynamic>{
          'function': <String, dynamic>{'name': 'start_single_sweep'},
        },
        <String, dynamic>{
          'function': <String, dynamic>{'name': 'get_spectrum_snapshot'},
        },
        <String, dynamic>{
          'function': <String, dynamic>{'name': 'analyze_spectrum'},
        },
      ],
      allowDataAnalysis: AgentRequestPolicy.requestsDataAnalysis(request),
      allowMeasurementStart:
          AgentRequestPolicy.requestsMeasurementStart(request),
    );
    expect(
      visible.map((tool) => (tool['function'] as Map)['name']),
      containsAll(<String>[
        'start_single_sweep',
        'get_spectrum_snapshot',
        'analyze_spectrum',
      ]),
    );
  });

  test('analysis tools are hidden for configuration requests', () {
    final filtered = AgentRequestPolicy.filterToolDefinitions(
      <Map<String, dynamic>>[
        <String, dynamic>{
          'function': <String, dynamic>{'name': 'set_frequency'},
        },
        <String, dynamic>{
          'function': <String, dynamic>{'name': 'analyze_spectrum'},
        },
        <String, dynamic>{
          'function': <String, dynamic>{
            'name': 'get_realtime_spectrum_snapshot',
          },
        },
        <String, dynamic>{
          'function': <String, dynamic>{
            'name': 'start_phase_noise_measurement',
          },
        },
      ],
      allowDataAnalysis: false,
      allowMeasurementStart: false,
    );
    final names =
        filtered.map((tool) => (tool['function'] as Map)['name']).toList();
    expect(names, <String>['set_frequency']);
  });
}
