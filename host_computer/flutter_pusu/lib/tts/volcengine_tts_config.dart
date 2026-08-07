import '../asr/volcengine_asr_config.dart';

abstract final class VolcengineTtsConfig {
  // 新版豆包语音控制台中，同一项目的 ASR 与 TTS 可以共用 API Key。
  static const String apiKey = VolcengineAsrConfig.apiKey;

  static const String resourceId = 'seed-tts-2.0';
  static const String speaker = 'zh_female_vv_uranus_bigtts';
  static const String endpoint =
      'https://openspeech.bytedance.com/api/v3/tts/unidirectional';

  static bool get isConfigured => VolcengineAsrConfig.isConfigured;
}
