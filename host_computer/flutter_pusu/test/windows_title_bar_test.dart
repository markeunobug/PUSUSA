import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_pusu/windows_title_bar.dart';
import 'package:window_manager/window_manager.dart';

void main() {
  testWidgets('Windows caption buttons stay inside a 1280 px window',
      (tester) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(
      const FluentApp(
        home: Stack(
          children: [
            Positioned.fill(
              child: ScaffoldPage(
                header: WindowsTitleBar(
                  child: CommandBar(
                    overflowBehavior: CommandBarOverflowBehavior.noWrap,
                    primaryItems: [
                      CommandBarButton(
                        icon: Icon(FluentIcons.settings),
                        label: Text('模式'),
                        onPressed: null,
                      ),
                    ],
                  ),
                ),
                content: SizedBox.expand(),
              ),
            ),
            Positioned(
              top: 0,
              right: 0,
              width: WindowsTitleBar.controlsWidth,
              height: 64,
              child: WindowsWindowControls(),
            ),
          ],
        ),
      ),
    );
    await tester.pump();

    final titleBarRect = tester.getRect(find.byType(WindowsTitleBar));
    final mainDragRect = tester.getRect(
      find.byKey(const ValueKey('title-bar-main-drag-area')),
    );
    final buttons = find.byType(WindowCaptionButton);

    expect(titleBarRect.width, 1280);
    expect(titleBarRect.height, 64);
    expect(mainDragRect.width, greaterThan(32));
    expect(buttons, findsNWidgets(3));
    for (var index = 0; index < 3; index++) {
      final buttonRect = tester.getRect(buttons.at(index));
      expect(buttonRect.left, greaterThanOrEqualTo(titleBarRect.left));
      expect(buttonRect.right, lessThanOrEqualTo(titleBarRect.right));
    }
  });
}
