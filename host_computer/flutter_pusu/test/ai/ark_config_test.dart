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

  test('full-band carrier discovery explicitly uses 1 MHz RBW', () {
    const prompt = ArkConfig.systemPrompt;
    expect(prompt, contains('RBW=1 MHz'));
    expect(prompt, contains('全频段载波搜索不得沿用较小的 RBW'));
    expect(prompt, contains('VBW 使用 follow_rbw'));
    expect(prompt, contains('spectrum_direct_if'));
    expect(prompt, contains('path_mode 设为 mixer_chain'));
  });

  test('new high-risk tools have explicit mode and data rules', () {
    const prompt = ArkConfig.systemPrompt;
    expect(prompt, contains('save_phase_noise_measurement'));
    expect(prompt, contains('get_phase_noise_snapshot'));
    expect(prompt, contains('apply_spectrum_preset'));
    expect(prompt, contains('get_sweep_profile'));
  });
}
