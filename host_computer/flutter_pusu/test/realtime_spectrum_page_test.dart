import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_pusu/realtime_spectrum_page.dart';
import 'package:flutter_pusu/serial_port_manager.dart';
import 'package:flutter_pusu/serial_protocol.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

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
    final centerBox =
        tester.widget<fluent.TextBox>(find.byType(fluent.TextBox));
    expect(centerBox.controller!.text, '775');
    await tester.enterText(find.byType(fluent.TextBox), '915');
    await tester.pump();

    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump();
    await tester.pumpWidget(page());
    await tester.pumpAndSettle();
    await tester.tap(find.text('采集'));
    await tester.pumpAndSettle();

    final restoredBox =
        tester.widget<fluent.TextBox>(find.byType(fluent.TextBox));
    expect(restoredBox.controller!.text, '915');
    expect(tester.takeException(), isNull);
  });
}
