import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'volcengine_tts_config.dart';

class VolcengineTtsException implements Exception {
  const VolcengineTtsException(this.message, {this.code, this.statusCode});

  final String message;
  final int? code;
  final int? statusCode;

  @override
  String toString() => message;
}

class VolcengineTtsChunk {
  const VolcengineTtsChunk({
    required this.code,
    required this.message,
    this.audioBytes,
  });

  final int code;
  final String message;
  final Uint8List? audioBytes;

  bool get isFinished => code == 20000000;
}

class VolcengineTtsClient {
  VolcengineTtsClient({HttpClient? httpClient})
      : _httpClient = httpClient ?? HttpClient() {
    _httpClient.connectionTimeout = const Duration(seconds: 15);
  }

  final HttpClient _httpClient;

  Future<Uint8List> synthesize(String text) async {
    if (!VolcengineTtsConfig.isConfigured) {
      throw StateError('请先配置豆包语音 API Key');
    }
    final normalizedText = text.trim();
    if (normalizedText.isEmpty) {
      throw ArgumentError.value(text, 'text', '待播报文本不能为空');
    }

    final request = await _httpClient
        .postUrl(Uri.parse(VolcengineTtsConfig.endpoint))
        .timeout(const Duration(seconds: 15));
    request.headers
      ..set(HttpHeaders.contentTypeHeader, 'application/json; charset=utf-8')
      ..set('X-Api-Key', VolcengineTtsConfig.apiKey)
      ..set('X-Api-Resource-Id', VolcengineTtsConfig.resourceId)
      ..set('X-Api-Request-Id', _uuidV4())
      ..set('X-Control-Require-Usage-Tokens-Return', '*');

    final body = utf8.encode(
      jsonEncode(<String, dynamic>{
        'req_params': <String, dynamic>{
          'text': normalizedText,
          'speaker': VolcengineTtsConfig.speaker,
          'additions': jsonEncode(<String, dynamic>{
            'disable_markdown_filter': true,
            'disable_emoji_filter': true,
          }),
          'audio_params': <String, dynamic>{
            'format': 'mp3',
            'sample_rate': 24000,
          },
        },
      }),
    );
    request
      ..contentLength = body.length
      ..add(body);

    final response = await request.close().timeout(const Duration(seconds: 30));
    if (response.statusCode < 200 || response.statusCode >= 300) {
      final errorBody = await utf8.decoder.bind(response).join();
      throw VolcengineTtsException(
        _extractHttpError(errorBody) ?? '语音生成请求失败（HTTP ${response.statusCode}）',
        statusCode: response.statusCode,
      );
    }

    final audio = BytesBuilder(copy: false);
    await for (final line in response
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .timeout(const Duration(seconds: 90))) {
      if (line.trim().isEmpty) continue;
      final chunk = parseResponseLine(line);
      if (chunk.code > 0 && !chunk.isFinished) {
        throw VolcengineTtsException(chunk.message, code: chunk.code);
      }
      final bytes = chunk.audioBytes;
      if (bytes != null && bytes.isNotEmpty) audio.add(bytes);
      if (chunk.isFinished) break;
    }

    final result = audio.takeBytes();
    if (result.isEmpty) {
      throw const VolcengineTtsException('语音生成成功，但没有返回音频数据');
    }
    return result;
  }

  static VolcengineTtsChunk parseResponseLine(String line) {
    final decoded = jsonDecode(line);
    if (decoded is! Map) {
      throw const FormatException('TTS 响应不是 JSON 对象');
    }
    final json = Map<String, dynamic>.from(decoded);
    final rawCode = json['code'];
    final code = rawCode is int
        ? rawCode
        : int.tryParse(rawCode?.toString() ?? '') ?? -1;
    final message = json['message']?.toString() ?? '未知 TTS 响应';
    final data = json['data'];
    Uint8List? audioBytes;
    if (data is String && data.isNotEmpty) {
      audioBytes = base64Decode(data);
    }
    return VolcengineTtsChunk(
      code: code,
      message: message,
      audioBytes: audioBytes,
    );
  }

  static String? _extractHttpError(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        return decoded['message']?.toString() ?? decoded['error']?.toString();
      }
    } on FormatException {
      // 非 JSON 错误页由调用方使用 HTTP 状态码说明。
    }
    return null;
  }

  static String _uuidV4() {
    final random = Random.secure();
    final bytes = List<int>.generate(16, (_) => random.nextInt(256));
    bytes[6] = (bytes[6] & 0x0F) | 0x40;
    bytes[8] = (bytes[8] & 0x3F) | 0x80;
    final value =
        bytes.map((byte) => byte.toRadixString(16).padLeft(2, '0')).join();
    return '${value.substring(0, 8)}-'
        '${value.substring(8, 12)}-'
        '${value.substring(12, 16)}-'
        '${value.substring(16, 20)}-'
        '${value.substring(20)}';
  }

  void dispose() => _httpClient.close(force: true);
}
