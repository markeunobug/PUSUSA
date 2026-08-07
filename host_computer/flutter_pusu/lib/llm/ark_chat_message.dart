import 'dart:convert';

enum ArkChatRole { user, assistant, tool }

class ArkToolCallData {
  const ArkToolCallData({
    required this.id,
    required this.name,
    required this.arguments,
  });

  final String id;
  final String name;
  final Map<String, dynamic> arguments;

  Map<String, dynamic> toJson() => <String, dynamic>{
        'id': id,
        'type': 'function',
        'function': <String, dynamic>{
          'name': name,
          'arguments': jsonEncode(arguments),
        },
      };
}

class ArkChatMessage {
  const ArkChatMessage({
    required this.role,
    required this.content,
    this.toolCalls = const <ArkToolCallData>[],
    this.toolCallId,
  });

  final ArkChatRole role;
  final String content;
  final List<ArkToolCallData> toolCalls;
  final String? toolCallId;

  ArkChatMessage copyWith({
    String? content,
    List<ArkToolCallData>? toolCalls,
  }) {
    return ArkChatMessage(
      role: role,
      content: content ?? this.content,
      toolCalls: toolCalls ?? this.toolCalls,
      toolCallId: toolCallId,
    );
  }

  Map<String, dynamic> toJson() {
    final json = <String, dynamic>{
      'role': role.name,
      'content': content,
    };
    if (role == ArkChatRole.assistant && toolCalls.isNotEmpty) {
      json['tool_calls'] = toolCalls.map((call) => call.toJson()).toList();
    }
    if (role == ArkChatRole.tool && toolCallId != null) {
      json['tool_call_id'] = toolCallId;
    }
    return json;
  }
}
