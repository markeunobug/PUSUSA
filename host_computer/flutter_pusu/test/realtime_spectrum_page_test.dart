import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_pusu/device_models.dart';
import 'package:flutter_pusu/realtime_spectrum_page.dart';
import 'package:flutter_pusu/realtime_spectrum_settings.dart';
import 'package:flutter_pusu/serial_port_manager.dart';
import 'package:flutter_pusu/serial_protocol.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('sweep RF settings initialize realtime spectrum controls',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    final manager = SerialPortManager();
    final protocol = SerialProtocol(manager);
    final key = GlobalKey<RealtimeSpectrumPageState>();
    addTearDown(() {
      protocol.dispose();
      manager.dispose();
    });

    await tester.pumpWidget(fluent.FluentApp(
      home: RealtimeSpectrumPage(
        key: key,
        protocol: protocol,
        connected: false,
        initialRfConfig: const RfFrontendConfig(
          lnaMode: RfLnaMode.enable,
          pathMode: RfPathMode.directIf,
          attenCode: 40,
        ),
        initialVgaLabel: '20 dB',
      ),
    ));
    await tester.pumpAndSettle();

    final state = key.currentState!.agentConfiguration;
    expect(state['lna_enabled'], isTrue);
    expect(state['attenuation_db'], 10.0);
    expect(state['vga_db'], 20.0);
  });

  testWidgets('sidebar is top-aligned and session settings survive recreation',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await tester.binding.setSurfaceSize(const Size(1400, 800));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final manager = SerialPortManager();
    final protocol = SerialProtocol(manager);
    addTearDown(() {
      protocol.dispose();
      manager.dispose();
    });

    Widget page() => fluent.FluentApp(
          home: RealtimeSpectrumPage(
            protocol: protocol,
            connected: false,
          ),
        );

    await tester.pumpWidget(page());
    await tester.pumpAndSettle();

    expect(tester.getTopLeft(find.text('采集')).dy, lessThan(50));
    expect(tester.getTopLeft(find.text('采集')).dx, greaterThan(1100));

    await tester.tap(find.text('采集'));
    await tester.pumpAndSettle();
    final centerBox = tester.widget<fluent.TextBox>(find.byWidgetPredicate(
      (widget) =>
          widget is fluent.TextBox && widget.controller?.text == '775',
    ));
    expect(centerBox.controller!.text, '775');
    centerBox.controller!.text = '915';
    await tester.pump();
    expect(
      centerBox.controller!.text,
      '915',
    );
    expect(RealtimeSpectrumSettingsStore.cached.centerMhz, '915');

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    await tester.tap(find.text('采集'));
    await tester.pumpAndSettle();

    final restoredBox = tester.widget<fluent.TextBox>(find.byWidgetPredicate(
      (widget) =>
          widget is fluent.TextBox && widget.controller?.text == '915',
    ));
    expect(restoredBox.controller!.text, '915');
    expect(tester.takeException(), isNull);
  });
}
