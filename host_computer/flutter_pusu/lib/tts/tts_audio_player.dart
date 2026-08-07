import 'dart:io';
import 'dart:typed_data';

import 'package:audioplayers/audioplayers.dart';

class TtsAudioPlayer {
  final AudioPlayer _player = AudioPlayer();
  File? _currentFile;

  Future<void> play(Uint8List mp3Bytes) async {
    await stop();
    final file = File(
      '${Directory.systemTemp.path}'
      '${Platform.pathSeparator}ai_instrument_tts_'
      '${DateTime.now().microsecondsSinceEpoch}.mp3',
    );
    await file.writeAsBytes(mp3Bytes, flush: true);
    _currentFile = file;
    await _player.play(DeviceFileSource(file.path));
  }

  Future<void> stop() async {
    await _player.stop();
    final file = _currentFile;
    _currentFile = null;
    if (file != null && await file.exists()) {
      try {
        await file.delete();
      } on FileSystemException {
        // Windows 音频后端偶尔会延迟释放文件；下次启动由系统临时目录清理。
      }
    }
  }

  Future<void> dispose() async {
    await stop();
    await _player.dispose();
  }
}
