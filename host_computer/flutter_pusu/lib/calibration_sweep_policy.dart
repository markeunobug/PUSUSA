class CalibrationSweepPolicy {
  const CalibrationSweepPolicy._();

  static const double powerDropRetryDb = 6.0;

  static const Map<String, double> _fastSpanHzByRbwMode = {
    '300 kHz': 2e6,
    '100 kHz': 600e3,
    '30 kHz': 200e3,
    '10 kHz': 40e3,
    '1 kHz': 5e3,
  };

  static double? spanHzForMode(String rbwMode) {
    return _fastSpanHzByRbwMode[rbwMode];
  }

  static bool shouldRetryForPowerDrop({
    required double previousPeakDbm,
    required double currentPeakDbm,
  }) {
    return currentPeakDbm < previousPeakDbm - powerDropRetryDb;
  }

  static double retrySpanHz(double initialSpanHz) {
    return initialSpanHz * 2.0;
  }
}
