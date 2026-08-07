import 'dart:async';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'volcengine_asr_config.dart';
import 'volcengine_asr_protocol.dart';

class VolcengineAsrClient {
  final StreamController<VolcengineAsrServerMessage> _messages =
      StreamController<VolcengineAsrServerMessage>.broadcast();

  WebSocket? _socket;
  StreamSubscription<dynamic>? _socketSubscription;

  Stream<VolcengineAsrServerMessage> get messages => _messages.stream;

  Future<void> connect() async {
    if (!VolcengineAsrConfig.isConfigured) {
      throw StateError('请先在 volcengine_asr_config.dart 中填写 API Key');
    }
    await close();

    final requestId = _uuidV4();
    final socket = await WebSocket.connect(
      VolcengineAsrConfig.endpoint,
      headers: <String, dynamic>{
        'X-Api-Key': VolcengineAsrConfig.apiKey,
        'X-Api-Resource-Id': VolcengineAsrConfig.resourceId,
        'X-Api-Request-Id': requestId,
        'X-Api-Sequence': '-1',
      },
    );
    _socket = socket;
    _socketSubscription = socket.listen(
      _handleSocketData,
      onError: (Object error, StackTrace stackTrace) {
        _messages.addError(error, stackTrace);
      },
      onDone: () => _socket = null,
      cancelOnError: false,
    );
    socket.add(VolcengineAsrProtocol.buildFullClientRequest());
  }

  void sendAudio(Uint8List pcmBytes, {bool isLast = false}) {
    final socket = _socket;
    if (socket == null) {
      throw StateError('ASR WebSocket 尚未连接');
    }
    socket.add(
      VolcengineAsrProtocol.buildAudioRequest(pcmBytes, isLast: isLast),
    );
  }

  Future<void> close() async {
    final subscription = _socketSubscription;
    _socketSubscription = null;
    await subscription?.cancel();

    final socket = _socket;
    _socket = null;
    await socket?.close(WebSocketStatus.normalClosure, 'client closed');
  }

  Future<void> dispose() async {
    await close();
    await _messages.close();
  }

  void _handleSocketData(dynamic data) {
    try {
      final bytes = switch (data) {
        Uint8List value => value,
        List<int> value => Uint8List.fromList(value),
        _ => throw const FormatException('ASR 服务返回了非二进制数据'),
      };
      _messages.add(VolcengineAsrProtocol.parseServerMessage(bytes));
    } catch (error, stackTrace) {
      _messages.addError(error, stackTrace);
    }
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
}
