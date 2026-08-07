import 'dart:convert';

import 'package:flutter_pusu/tts/volcengine_tts_client.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('parses a base64 audio response chunk', () {
    final line = jsonEncode(<String, dynamic>{
      'code': 0,
      'message': 'OK',
      'data': base64Encode(<int>[0x49, 0x44, 0x33]),
    });

    final chunk = VolcengineTtsClient.parseResponseLine(line);

    expect(chunk.code, 0);
    expect(chunk.audioBytes, <int>[0x49, 0x44, 0x33]);
    expect(chunk.isFinished, isFalse);
  });

  test('recognizes the terminal TTS response code', () {
    final chunk = VolcengineTtsClient.parseResponseLine(
      '{"code":20000000,"message":"OK"}',
    );

    expect(chunk.isFinished, isTrue);
    expect(chunk.audioBytes, isNull);
  });
}
