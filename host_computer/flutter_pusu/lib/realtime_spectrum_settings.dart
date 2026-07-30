import 'package:shared_preferences/shared_preferences.dart';

class RealtimeSpectrumSettings {
  const RealtimeSpectrumSettings({
    required this.centerMhz,
    required this.averageEnabled,
    required this.maxHoldEnabled,
    required this.markerEnabled,
    required this.lnaEnabled,
    required this.attenCode,
    required this.vgaLabel,
    required this.referenceDbfs,
    required this.waterfallFloorDbfs,
    required this.waterfallReferenceDbfs,
  });

  static const defaults = RealtimeSpectrumSettings(
    centerMhz: '775',
    averageEnabled: true,
    maxHoldEnabled: true,
    markerEnabled: true,
    lnaEnabled: false,
    attenCode: 127,
    vgaLabel: '0 dB',
    referenceDbfs: -20,
    waterfallFloorDbfs: -140,
    waterfallReferenceDbfs: -30,
  );

  final String centerMhz;
  final bool averageEnabled;
  final bool maxHoldEnabled;
  final bool markerEnabled;
  final bool lnaEnabled;
  final int attenCode;
  final String vgaLabel;
  final double referenceDbfs;
  final double waterfallFloorDbfs;
  final double waterfallReferenceDbfs;
}

class RealtimeSpectrumSettingsStore {
  RealtimeSpectrumSettingsStore._();

  static const _prefix = 'realtime_spectrum.';
  static RealtimeSpectrumSettings _cached = RealtimeSpectrumSettings.defaults;
  static SharedPreferences? _preferences;
  static bool _loaded = false;
  static int _revision = 0;

  static RealtimeSpectrumSettings get cached => _cached;

  static Future<RealtimeSpectrumSettings> load() async {
    if (_loaded) return _cached;

    final revisionAtStart = _revision;
    final preferences = await SharedPreferences.getInstance();
    _preferences = preferences;
    const defaults = RealtimeSpectrumSettings.defaults;
    final loaded = RealtimeSpectrumSettings(
      centerMhz:
          preferences.getString('${_prefix}center_mhz') ?? defaults.centerMhz,
      averageEnabled: preferences.getBool('${_prefix}average_enabled') ??
          defaults.averageEnabled,
      maxHoldEnabled: preferences.getBool('${_prefix}max_hold_enabled') ??
          defaults.maxHoldEnabled,
      markerEnabled: preferences.getBool('${_prefix}marker_enabled') ??
          defaults.markerEnabled,
      lnaEnabled:
          preferences.getBool('${_prefix}lna_enabled') ?? defaults.lnaEnabled,
      attenCode:
          (preferences.getInt('${_prefix}atten_code') ?? defaults.attenCode)
              .clamp(0, 127),
      vgaLabel:
          preferences.getString('${_prefix}vga_label') ?? defaults.vgaLabel,
      referenceDbfs: (preferences.getDouble('${_prefix}reference_dbfs') ??
              defaults.referenceDbfs)
          .clamp(-140.0, 0.0),
      waterfallFloorDbfs:
          (preferences.getDouble('${_prefix}waterfall_floor_dbfs') ??
                  defaults.waterfallFloorDbfs)
              .clamp(-160.0, -10.0),
      waterfallReferenceDbfs:
          (preferences.getDouble('${_prefix}waterfall_reference_dbfs') ??
                  defaults.waterfallReferenceDbfs)
              .clamp(-150.0, 0.0),
    );
    if (_revision == revisionAtStart) {
      _cached = loaded;
    }
    _loaded = true;
    return _cached;
  }

  static void remember(RealtimeSpectrumSettings settings) {
    _cached = settings;
    _revision++;
  }

  static Future<void> persist() async {
    final preferences = _preferences ?? await SharedPreferences.getInstance();
    _preferences = preferences;
    final settings = _cached;
    await Future.wait([
      preferences.setString('${_prefix}center_mhz', settings.centerMhz),
      preferences.setBool('${_prefix}average_enabled', settings.averageEnabled),
      preferences.setBool(
          '${_prefix}max_hold_enabled', settings.maxHoldEnabled),
      preferences.setBool('${_prefix}marker_enabled', settings.markerEnabled),
      preferences.setBool('${_prefix}lna_enabled', settings.lnaEnabled),
      preferences.setInt('${_prefix}atten_code', settings.attenCode),
      preferences.setString('${_prefix}vga_label', settings.vgaLabel),
      preferences.setDouble('${_prefix}reference_dbfs', settings.referenceDbfs),
      preferences.setDouble(
          '${_prefix}waterfall_floor_dbfs', settings.waterfallFloorDbfs),
      preferences.setDouble('${_prefix}waterfall_reference_dbfs',
          settings.waterfallReferenceDbfs),
    ]);
    _loaded = true;
  }
}
