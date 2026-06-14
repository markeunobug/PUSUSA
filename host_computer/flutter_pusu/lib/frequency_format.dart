String formatFreqAutoUnit(double freqHz, {int decimalPlaces = 2}) {
  if (freqHz >= 1e9) {
    return '${(freqHz / 1e9).toStringAsFixed(decimalPlaces)} GHz';
  }
  if (freqHz >= 1e6) {
    return '${(freqHz / 1e6).toStringAsFixed(decimalPlaces)} MHz';
  }
  if (freqHz >= 1e3) {
    return '${(freqHz / 1e3).toStringAsFixed(decimalPlaces)} kHz';
  }
  return '${freqHz.toStringAsFixed(decimalPlaces)} Hz';
}

String formatMarkerFreqAutoUnit(double freqHz) {
  return formatFreqAutoUnit(freqHz, decimalPlaces: freqHz >= 1e9 ? 6 : 3);
}

String formatFreqInput(double freqHz, double unitFactor) {
  final text = (freqHz / unitFactor).toStringAsFixed(6);
  return text.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
}
