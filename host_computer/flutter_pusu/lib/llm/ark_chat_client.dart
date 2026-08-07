import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'ark_chat_message.dart';
import 'ark_config.dart';
import 'ark_model.dart';

class ArkApiException implements Exception {
  const ArkApiException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

class ArkRequestCancelledException implements Exception {
  const ArkRequestCancelledException();

  @override
  String toString() => '模型请求已取消';
}

class ArkToolCallDelta {
  const ArkToolCallDelta({
    required this.index,
    this.id,
    this.name,
    this.argumentsFragment = '',
  });

  final int index;
  final String? id;
  final String? name;
  final String argumentsFragment;
}

class ArkChatStreamEvent {
  const ArkChatStreamEvent({
    required this.content,
    this.responseModelId,
    this.toolCallDeltas = const <ArkToolCallDelta>[],
    this.finishReason,
  });

  final String content;
  final String? responseModelId;
  final List<ArkToolCallDelta> toolCallDeltas;
  final String? finishReason;
}

class ArkChatClient {
  ArkChatClient({HttpClient? httpClient})
      : _httpClient = httpClient ?? HttpClient() {
    _httpClient.connectionTimeout = const Duration(seconds: 15);
  }

  final HttpClient _httpClient;
  HttpClientRequest? _activeRequest;

  Stream<ArkChatStreamEvent> streamReply({
    required ArkModel model,
    required List<ArkChatMessage> messages,
    List<Map<String, dynamic>> tools = const <Map<String, dynamic>>[],
  }) async* {
    if (!ArkConfig.isConfigured) {
      throw StateError('请先在 ark_config.dart 中填写火山方舟 API Key');
    }

    final request = await _httpClient
        .postUrl(Uri.parse(ArkConfig.endpoint))
        .timeout(const Duration(seconds: 15));
    _activeRequest = request;
    request.headers
      ..set(HttpHeaders.authorizationHeader, 'Bearer ${ArkConfig.apiKey}')
      ..set(HttpHeaders.contentTypeHeader, 'application/json; charset=utf-8')
      ..set(HttpHeaders.acceptHeader, 'text/event-stream');

    final body = <String, dynamic>{
      'model': model.modelId,
      'messages': <Map<String, dynamic>>[
        <String, dynamic>{
          'role': 'system',
          'content': ArkConfig.systemPrompt,
        },
        ...messages.map((message) => message.toJson()),
      ],
      'stream': true,
    };
    if (tools.isNotEmpty) {
      body['tools'] = tools;
      body['tool_choice'] = 'auto';
    }
    request.add(utf8.encode(jsonEncode(body)));

    try {
      final response =
          await request.close().timeout(const Duration(seconds: 30));
      if (response.statusCode < 200 || response.statusCode >= 300) {
        final responseBody = await utf8.decoder.bind(response).join();
        throw ArkApiException(
          _extractErrorMessage(responseBody) ??
              '方舟请求失败（HTTP ${response.statusCode}）',
          statusCode: response.statusCode,
        );
      }

      await for (final line in response
          .transform(utf8.decoder)
          .transform(const LineSplitter())
          .timeout(const Duration(seconds: 90))) {
        final event = parseSseEvent(line);
        if (event != null) yield event;
      }
    } finally {
      if (identical(_activeRequest, request)) {
        _activeRequest = null;
      }
    }
  }

  void cancelActiveRequest() {
    final request = _activeRequest;
    _activeRequest = null;
    request?.abort(const ArkRequestCancelledException());
  }

  static ArkChatStreamEvent? parseSseEvent(String line) {
    if (!line.startsWith('data:')) return null;
    final payload = line.substring(5).trim();
    if (payload.isEmpty || payload == '[DONE]') return null;

    final decoded = jsonDecode(payload);
    if (decoded is! Map) return null;
    final json = Map<String, dynamic>.from(decoded);
    final error = json['error'];
    if (error is Map) {
      throw ArkApiException(error['message']?.toString() ?? '方舟返回了未知错误');
    }

    final responseModelId = json['model']?.toString();
    final choices = json['choices'];
    if (choices is! List || choices.isEmpty || choices.first is! Map) {
      return responseModelId == null
          ? null
          : ArkChatStreamEvent(content: '', responseModelId: responseModelId);
    }

    final choice = Map<String, dynamic>.from(choices.first as Map);
    final finishReason = choice['finish_reason']?.toString();
    final delta = choice['delta'];
    if (delta is! Map) {
      return ArkChatStreamEvent(
        content: '',
        responseModelId: responseModelId,
        finishReason: finishReason,
      );
    }

    final deltaMap = Map<String, dynamic>.from(delta);
    final content = _extractContent(deltaMap['content']);
    final toolCallDeltas = <ArkToolCallDelta>[];
    final rawToolCalls = deltaMap['tool_calls'];
    if (rawToolCalls is List) {
      for (final rawCall in rawToolCalls.whereType<Map>()) {
        final call = Map<String, dynamic>.from(rawCall);
        final function = call['function'];
        final functionMap = function is Map
            ? Map<String, dynamic>.from(function)
            : const <String, dynamic>{};
        toolCallDeltas.add(
          ArkToolCallDelta(
            index: call['index'] is int
                ? call['index'] as int
                : int.tryParse(call['index']?.toString() ?? '') ?? 0,
            id: call['id']?.toString(),
            name: functionMap['name']?.toString(),
            argumentsFragment: functionMap['arguments']?.toString() ?? '',
          ),
        );
      }
    }

    return ArkChatStreamEvent(
      content: content,
      responseModelId: responseModelId,
      toolCallDeltas: toolCallDeltas,
      finishReason: finishReason,
    );
  }

  static String _extractContent(dynamic content) {
    if (content is String) return content;
    if (content is List) {
      return content
          .whereType<Map>()
          .map((part) => part['text'])
          .whereType<String>()
          .join();
    }
    return '';
  }

  static String? parseSseContent(String line) => parseSseEvent(line)?.content;

  static Map<String, dynamic> parseToolArguments(String rawArguments) {
    final raw = rawArguments.trim();
    if (raw.isEmpty) return const <String, dynamic>{};
    dynamic decoded;
    try {
      decoded = jsonDecode(raw);
    } on FormatException {
      final repaired = _repairTruncatedJson(raw);
      if (repaired == null) {
        throw const FormatException(
          '模型返回的工具参数 JSON 不完整，本轮工具未执行',
        );
      }
      try {
        decoded = jsonDecode(repaired);
      } on FormatException {
        throw const FormatException(
          '模型返回的工具参数 JSON 无法安全补全，本轮工具未执行',
        );
      }
    }
    if (decoded is! Map) {
      throw const FormatException('工具参数不是 JSON 对象，本轮工具未执行');
    }
    return Map<String, dynamic>.from(decoded);
  }

  static String? _repairTruncatedJson(String raw) {
    if (!raw.startsWith('{')) return null;
    final closing = <String>[];
    var insideString = false;
    var escaped = false;
    for (var index = 0; index < raw.length; index++) {
      final character = raw[index];
      if (insideString) {
        if (escaped) {
          escaped = false;
        } else if (character == r'\') {
          escaped = true;
        } else if (character == '"') {
          insideString = false;
        }
        continue;
      }
      if (character == '"') {
        insideString = true;
      } else if (character == '{') {
        closing.add('}');
      } else if (character == '[') {
        closing.add(']');
      } else if (character == '}' || character == ']') {
        if (closing.isEmpty || closing.last != character) return null;
        closing.removeLast();
      }
    }
    if (insideString || escaped || closing.isEmpty) return null;
    final trimmedRight = raw.trimRight();
    final last = trimmedRight[trimmedRight.length - 1];
    if (last == ':' || last == ',') return null;
    return '$raw${closing.reversed.join()}';
  }

  static String? _extractErrorMessage(String body) {
    try {
      final decoded = jsonDecode(body);
      if (decoded is Map) {
        final error = decoded['error'];
        if (error is Map && error['message'] != null) {
          return error['message'].toString();
        }
        if (decoded['message'] != null) return decoded['message'].toString();
      }
    } on FormatException {
      // 非 JSON 错误页由 HTTP 状态码说明。
    }
    return null;
  }

  void dispose() {
    cancelActiveRequest();
    _httpClient.close(force: true);
  }
}
