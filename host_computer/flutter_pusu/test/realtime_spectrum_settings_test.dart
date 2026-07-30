import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_pusu/realtime_spectrum_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('realtime spectrum settings load, remember, and persist', () async {
    SharedPreferences.setMockInitialValues({
      'realtime_spectrum.center_mhz': '915',
      'realtime_spectrum.average_enabled': false,
      'realtime_spectrum.atten_code': 40,
      'realtime_spectrum.reference_dbfs': -35.0,
    });

    final loaded = await RealtimeSpectrumSettingsStore.load();
    expect(loaded.centerMhz, '915');
    expect(loaded.averageEnabled, isFalse);
    expect(loaded.attenCode, 40);
    expect(loaded.referenceDbfs, -35);
    expect(loaded.maxHoldEnabled, isTrue);

    const updated = RealtimeSpectrumSettings(
      centerMhz: '433.92',
      averageEnabled: true,
      maxHoldEnabled: false,
      markerEnabled: false,
      lnaEnabled: true,
      attenCode: 12,
      vgaLabel: '10 dB',
      referenceDbfs: -25,
      waterfallFloorDbfs: -130,
      waterfallReferenceDbfs: -40,
    );
    RealtimeSpectrumSettingsStore.remember(updated);
    await RealtimeSpectrumSettingsStore.persist();

    final preferences = await SharedPreferences.getInstance();
    expect(preferences.getString('realtime_spectrum.center_mhz'), '433.92');
    expect(preferences.getBool('realtime_spectrum.max_hold_enabled'), isFalse);
    expect(preferences.getBool('realtime_spectrum.lna_enabled'), isTrue);
    expect(preferences.getInt('realtime_spectrum.atten_code'), 12);
    expect(preferences.getString('realtime_spectrum.vga_label'), '10 dB');
    expect(
        preferences.getDouble('realtime_spectrum.waterfall_floor_dbfs'), -130);
  });
}
