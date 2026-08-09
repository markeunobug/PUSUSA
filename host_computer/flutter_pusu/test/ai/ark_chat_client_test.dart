import 'package:flutter_pusu/llm/ark_chat_client.dart';
import 'package:flutter_pusu/llm/ark_model.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses text from a Chat Completions SSE delta', () {
    const line = 'data: {"model":"doubao-seed-2-1-turbo-260628",'
        '"choices":[{"delta":{"content":"你好"},"index":0}]}';

    expect(ArkChatClient.parseSseContent(line), '你好');
    final event = ArkChatClient.parseSseEvent(line);
    expect(event?.content, '你好');
    expect(event?.responseModelId, 'doubao-seed-2-1-turbo-260628');
    expect(ArkChatClient.parseSseContent('data: [DONE]'), isNull);
    expect(ArkChatClient.parseSseContent('event: message'), isNull);
  });

  test('model list contains the seven selectable model IDs', () {
    expect(
      ArkModel.values.map((model) => model.modelId),
      containsAll(<String>[
        'doubao-seed-evolving-latest-version',
        'doubao-seed-2-1-pro-260628',
        'doubao-seed-2-1-turbo-260628',
        'doubao-seed-character-260628',
        'glm-5-2-260617',
        'deepseek-v4-pro-260425',
        'deepseek-v4-flash-ga-260731',
      ]),
    );
  });

  test('parses streamed function tool call fragments', () {
    const line = 'data: {"model":"deepseek-v4-pro-260425",'
        '"choices":[{"delta":{"tool_calls":[{"index":0,'
        '"id":"call_1","type":"function","function":{'
        '"name":"set_frequency","arguments":"{\\"center_hz\\":100000000}"'
        '}}]},"finish_reason":null,"index":0}]}';

    final event = ArkChatClient.parseSseEvent(line);
    expect(event?.toolCallDeltas, hasLength(1));
    expect(event?.toolCallDeltas.single.id, 'call_1');
    expect(event?.toolCallDeltas.single.name, 'set_frequency');
    expect(
      event?.toolCallDeltas.single.argumentsFragment,
      '{"center_hz":100000000}',
    );
  });

  test('repairs a tool argument object missing only its closing brace', () {
    expect(
      ArkChatClient.parseToolArguments('{"peak_count": 5'),
      <String, dynamic>{'peak_count': 5},
    );
  });

  test('repairs safely truncated nested tool arguments', () {
    expect(
      ArkChatClient.parseToolArguments('{"values":[1,2'),
      <String, dynamic>{
        'values': <dynamic>[1, 2],
      },
    );
  });

  test('repairs truncated arguments containing an escaped quote', () {
    expect(
      ArkChatClient.parseToolArguments(r'{"note":"a\"b","peak_count":5'),
      <String, dynamic>{'note': 'a"b', 'peak_count': 5},
    );
  });

  test('rejects ambiguous truncated tool argument strings', () {
    expect(
      () => ArkChatClient.parseToolArguments('{"detector":"positive'),
      throwsFormatException,
    );
    expect(
      () => ArkChatClient.parseToolArguments('{"peak_count":'),
      throwsFormatException,
    );
  });
}
