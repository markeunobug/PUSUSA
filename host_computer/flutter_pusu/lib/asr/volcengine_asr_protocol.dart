import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

class VolcengineAsrServerMessage {
  const VolcengineAsrServerMessage({
    this.text,
    this.isFinal = false,
    this.sequence,
    this.errorCode,
    this.errorMessage,
    this.rawJson,
  });

  final String? text;
  final bool isFinal;
  final int? sequence;
  final int? errorCode;
  final String? errorMessage;
  final Map<String, dynamic>? rawJson;

  bool get isError => errorCode != null;
}

abstract final class VolcengineAsrProtocol {
  static const int _fullClientRequest = 0x1;
  static const int _audioOnlyRequest = 0x2;
  static const int _fullServerResponse = 0x9;
  static const int _errorResponse = 0xF;

  static const int _flagSequence = 0x1;
  static const int _flagLastPacket = 0x2;
  static const int _gzipCompression = 0x1;

  static Uint8List buildFullClientRequest({String uid = 'ai-instrument'}) {
    final request = <String, dynamic>{
      'user': <String, dynamic>{'uid': uid},
      'audio': <String, dynamic>{
        'format': 'pcm',
        'codec': 'raw',
        'rate': 16000,
        'bits': 16,
        'channel': 1,
        'language': 'zh-CN',
      },
      'request': <String, dynamic>{
        'model_name': 'bigmodel',
        'enable_itn': true,
        'enable_punc': true,
        'enable_ddc': true,
        'show_utterances': true,
        'result_type': 'full',
      },
    };

    final payload = Uint8List.fromList(
      gzip.encode(utf8.encode(jsonEncode(request))),
    );
    return _buildFrame(
      messageType: _fullClientRequest,
      flags: 0,
      serialization: 1,
      compression: _gzipCompression,
      payload: payload,
    );
  }

  static Uint8List buildAudioRequest(
    Uint8List pcmBytes, {
    bool isLast = false,
  }) {
    final payload = Uint8List.fromList(gzip.encode(pcmBytes));
    return _buildFrame(
      messageType: _audioOnlyRequest,
      flags: isLast ? _flagLastPacket : 0,
      serialization: 0,
      compression: _gzipCompression,
      payload: payload,
    );
  }

  static VolcengineAsrServerMessage parseServerMessage(Uint8List data) {
    if (data.length < 4) {
      throw const FormatException('ASR 响应头不足 4 字节');
    }

    final headerBytes = (data[0] & 0x0F) * 4;
    final messageType = data[1] >> 4;
    final flags = data[1] & 0x0F;
    final compression = data[2] & 0x0F;
    var offset = headerBytes;

    if (headerBytes < 4 || offset > data.length) {
      throw const FormatException('ASR 响应头长度无效');
    }

    int? sequence;
    if ((flags & _flagSequence) != 0) {
      _ensureAvailable(data, offset, 4);
      sequence = _readInt32(data, offset);
      offset += 4;
    }

    if (messageType == _fullServerResponse) {
      _ensureAvailable(data, offset, 4);
      final payloadSize = _readUint32(data, offset);
      offset += 4;
      _ensureAvailable(data, offset, payloadSize);
      var payload = data.sublist(offset, offset + payloadSize);
      if (compression == _gzipCompression) {
        payload = Uint8List.fromList(gzip.decode(payload));
      }

      final decoded = jsonDecode(utf8.decode(payload));
      if (decoded is! Map) {
        throw const FormatException('ASR 响应不是 JSON 对象');
      }
      final json = Map<String, dynamic>.from(decoded);
      return VolcengineAsrServerMessage(
        text: _extractText(json),
        isFinal: (flags & _flagLastPacket) != 0,
        sequence: sequence,
        rawJson: json,
      );
    }

    if (messageType == _errorResponse) {
      _ensureAvailable(data, offset, 8);
      final errorCode = _readUint32(data, offset);
      final payloadSize = _readUint32(data, offset + 4);
      offset += 8;
      _ensureAvailable(data, offset, payloadSize);
      var payload = data.sublist(offset, offset + payloadSize);
      if (compression == _gzipCompression) {
        payload = Uint8List.fromList(gzip.decode(payload));
      }
      return VolcengineAsrServerMessage(
        isFinal: true,
        sequence: sequence,
        errorCode: errorCode,
        errorMessage: utf8.decode(payload, allowMalformed: true),
      );
    }

    return VolcengineAsrServerMessage(
      isFinal: (flags & _flagLastPacket) != 0,
      sequence: sequence,
    );
  }

  static Uint8List _buildFrame({
    required int messageType,
    required int flags,
    required int serialization,
    required int compression,
    required Uint8List payload,
  }) {
    final frame = BytesBuilder(copy: false)
      ..add(<int>[
        0x11,
        (messageType << 4) | flags,
        (serialization << 4) | compression,
        0x00,
      ])
      ..add(_uint32Bytes(payload.length))
      ..add(payload);
    return frame.takeBytes();
  }

  static String? _extractText(Map<String, dynamic> json) {
    final result = json['result'];
    if (result is Map) {
      final text = result['text'];
      return text is String ? text : null;
    }
    if (result is List && result.isNotEmpty && result.first is Map) {
      final text = (result.first as Map)['text'];
      return text is String ? text : null;
    }
    return null;
  }

  static Uint8List _uint32Bytes(int value) {
    final bytes = ByteData(4)..setUint32(0, value, Endian.big);
    return bytes.buffer.asUint8List();
  }

  static int _readUint32(Uint8List data, int offset) =>
      ByteData.sublistView(data, offset, offset + 4).getUint32(0, Endian.big);

  static int _readInt32(Uint8List data, int offset) =>
      ByteData.sublistView(data, offset, offset + 4).getInt32(0, Endian.big);

  static void _ensureAvailable(Uint8List data, int offset, int length) {
    if (offset < 0 || length < 0 || offset + length > data.length) {
      throw const FormatException('ASR 响应数据不完整');
    }
  }
}
