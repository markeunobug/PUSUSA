import 'package:flutter_pusu/llm/ark_config.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('long phase-noise measurements use asynchronous assistant rules', () {
    const prompt = ArkConfig.systemPrompt;

    expect(prompt, contains('后台异步任务'));
    expect(prompt, contains('不得在同一回合继续调用 analyze_phase_noise'));
    expect(prompt, contains('每个用户回合最多调用一次 get_phase_noise_state'));
    expect(prompt, contains('wait_timeout_ms=0'));
    expect(prompt, contains('不得为了等待完成而反复轮询'));
  });
}
