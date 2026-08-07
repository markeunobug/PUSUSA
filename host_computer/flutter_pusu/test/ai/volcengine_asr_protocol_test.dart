import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_pusu/asr/volcengine_asr_protocol.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('full request uses JSON and gzip protocol header', () {
    final frame = VolcengineAsrProtocol.buildFullClientRequest();

    expect(frame.sublist(0, 4), <int>[0x11, 0x10, 0x11, 0x00]);
    final payloadSize = ByteData.sublistView(frame, 4, 8).getUint32(0);
    expect(payloadSize, frame.length - 8);

    final json = jsonDecode(utf8.decode(gzip.decode(frame.sublist(8))))
        as Map<String, dynamic>;
    expect((json['audio'] as Map)['rate'], 16000);
    expect((json['request'] as Map)['model_name'], 'bigmodel');
  });

  test('last audio request sets final packet flag', () {
    final frame = VolcengineAsrProtocol.buildAudioRequest(
      Uint8List.fromList(<int>[1, 2, 3, 4]),
      isLast: true,
    );

    expect(frame.sublist(0, 4), <int>[0x11, 0x22, 0x01, 0x00]);
    expect(gzip.decode(frame.sublist(8)), <int>[1, 2, 3, 4]);
  });

  test('server parser reads sequence and final text', () {
    final payload = gzip.encode(
      utf8.encode(
        jsonEncode(<String, dynamic>{
          'result': <String, dynamic>{'text': '中心频率二点四五G'},
        }),
      ),
    );
    final bytes = BytesBuilder()
      ..add(<int>[0x11, 0x93, 0x11, 0x00])
      ..add(_int32Bytes(-2))
      ..add(_uint32Bytes(payload.length))
      ..add(payload);

    final message = VolcengineAsrProtocol.parseServerMessage(bytes.takeBytes());

    expect(message.text, '中心频率二点四五G');
    expect(message.sequence, -2);
    expect(message.isFinal, isTrue);
  });
}

Uint8List _uint32Bytes(int value) {
  final bytes = ByteData(4)..setUint32(0, value, Endian.big);
  return bytes.buffer.asUint8List();
}

Uint8List _int32Bytes(int value) {
  final bytes = ByteData(4)..setInt32(0, value, Endian.big);
  return bytes.buffer.asUint8List();
}
