abstract final class VolcengineAsrConfig {
  // 获取 Key 后直接替换此字符串。新版豆包语音控制台只需要 API Key。
  static const String apiKey = 'REDACTED_API_KEY';

  // 豆包流式语音识别模型 2.0 小时版。
  static const String resourceId = 'volc.seedasr.sauc.duration';

  // 官方推荐的双向流式优化接口，只在识别结果发生变化时返回数据。
  static const String endpoint =
      'wss://openspeech.bytedance.com/api/v3/sauc/bigmodel_async';

  static bool get isConfigured =>
      apiKey.isNotEmpty && apiKey != 'PASTE_YOUR_API_KEY_HERE';
}
