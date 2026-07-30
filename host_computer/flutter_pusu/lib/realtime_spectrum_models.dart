import 'dart:typed_data';

/// Raw V1 payload: amplitudeUnit=1 means dBFS, not calibrated dBm.
class RealtimeSpectrumFrame {
  static const int version = 1;
  static const int binCount = 315;
  static const int headerLength = 36;
  static const int payloadLength = headerLength + binCount * 4;
  const RealtimeSpectrumFrame(
      {required this.windowId,
      required this.amplitudeUnit,
      required this.errorCode,
      required this.sequence,
      required this.centerHz,
      required this.sampleRateHz,
      required this.fftSize,
      required this.firstBin,
      required this.droppedFrames,
      required this.framesEmitted,
      required this.rawDbfs});
  final int windowId, amplitudeUnit, errorCode;
  final int sequence;
  final double centerHz;
  final int sampleRateHz;
  final int fftSize;
  final int firstBin;
  final int droppedFrames;
  final int framesEmitted;
  final List<double> rawDbfs;
  double frequencyHz(int index) =>
      centerHz + (firstBin + index) * sampleRateHz / fftSize - 40e6;
}

class RealtimeSpectrumStatus {
  static const int errorNone = 0;
  static const int errorStopped = 10;
  const RealtimeSpectrumStatus(
      {required this.state,
      required this.flags,
      required this.errorCode,
      required this.errorDetail,
      required this.framesEmitted,
      required this.droppedFrames,
      required this.dmaErrorCount,
      required this.centerHz});
  final int state,
      flags,
      errorCode,
      errorDetail,
      framesEmitted,
      droppedFrames,
      dmaErrorCount;
  final double centerHz;
  bool get isIdle => state == 0;

  /// Firmware reports STOPPED (10) with the normal terminal IDLE status.
  bool get isNormalTerminalIdle =>
      isIdle && (errorCode == errorNone || errorCode == errorStopped);

  /// Pure terminal gate used by the host before it may configure/start again.
  bool get permitsReconfiguration => isNormalTerminalIdle;
}

class RealtimeSpectrumCodec {
  const RealtimeSpectrumCodec._();
  static Uint8List configPayload(double centerHz) {
    final bytes = Uint8List(12);
    final b = bytes.buffer.asByteData();
    bytes[0] = RealtimeSpectrumFrame.version;
    bytes[1] = 0;
    b.setUint16(2, 0, Endian.little);
    b.setFloat64(4, centerHz, Endian.little);
    return bytes;
  }

  static RealtimeSpectrumFrame? parseData(Uint8List data) {
    if (data.length != RealtimeSpectrumFrame.payloadLength ||
        data[0] != RealtimeSpectrumFrame.version) {
      return null;
    }
    final b = data.buffer.asByteData(data.offsetInBytes, data.length);
    // Header bytes 0..3: version, window_id, amplitude_unit, error.
    // first_bin and bin_count at 24/26 are protocol_writer_write_u16 (big endian).
    if (data[2] != 1 ||
        b.getUint16(26, Endian.big) != RealtimeSpectrumFrame.binCount) {
      return null;
    }
    final fft = b.getUint32(20, Endian.little);
    final rate = b.getUint32(16, Endian.little);
    final firstBin = b.getUint16(24, Endian.big);
    if (fft != 4096 ||
        rate == 0 ||
        firstBin + RealtimeSpectrumFrame.binCount > fft) {
      return null;
    }
    final bins = List<double>.generate(
        RealtimeSpectrumFrame.binCount,
        (i) => b.getFloat32(
            RealtimeSpectrumFrame.headerLength + i * 4, Endian.little),
        growable: false);
    if (bins.any((v) => !v.isFinite)) {
      return null;
    }
    final centerHz = b.getFloat64(8, Endian.little);
    if (!centerHz.isFinite) {
      return null;
    }
    return RealtimeSpectrumFrame(
        windowId: data[1],
        amplitudeUnit: data[2],
        errorCode: data[3],
        sequence: b.getUint32(4, Endian.little),
        centerHz: centerHz,
        sampleRateHz: rate,
        fftSize: fft,
        firstBin: firstBin,
        droppedFrames: b.getUint32(28, Endian.little),
        framesEmitted: b.getUint32(32, Endian.little),
        rawDbfs: bins);
  }

  static RealtimeSpectrumStatus? parseStatus(Uint8List data) {
    if (data.length != 28 || data[0] != RealtimeSpectrumFrame.version) {
      return null;
    }
    final b = data.buffer.asByteData(data.offsetInBytes, data.length);
    return RealtimeSpectrumStatus(
        state: data[1],
        flags: data[2],
        errorCode: data[3],
        errorDetail: b.getUint32(4, Endian.little),
        framesEmitted: b.getUint32(8, Endian.little),
        droppedFrames: b.getUint32(12, Endian.little),
        dmaErrorCount: b.getUint32(16, Endian.little),
        centerHz: b.getFloat64(20, Endian.little));
  }
}
