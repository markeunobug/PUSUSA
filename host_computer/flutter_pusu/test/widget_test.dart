import 'package:fluent_ui/fluent_ui.dart' as fluent;
import 'package:flutter/material.dart' as material;
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_pusu/main.dart';

void main() {
  testWidgets('spectrum settings open frequency amplitude and BW by default',
      (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const material.Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const MyApp());
    await tester.pump();

    for (final header in <String>['频率', '幅度', 'BW']) {
      final expanderFinder = find.ancestor(
        of: find.text(header),
        matching: find.byType(fluent.Expander),
      );
      expect(expanderFinder, findsOneWidget);
      final expander = tester.widget<fluent.Expander>(expanderFinder);
      expect(expander.initiallyExpanded, isTrue);
    }

    for (final removedLabel in <String>['文件', '系统', '回放']) {
      final commandBarButton = find.ancestor(
        of: find.text(removedLabel),
        matching: find.byType(fluent.CommandBarButton),
      );
      expect(commandBarButton, findsNothing);
    }

    await tester.pumpWidget(const material.SizedBox.shrink());
  });

  testWidgets('AI assistant opens idle in Agent mode',
      (WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const material.Size(1600, 1000));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    await tester.pumpWidget(const MyApp());
    await tester.pump();

    await tester.tap(find.text('AI 助手'));
    await tester.pump();

    expect(find.text('AI 助手'), findsOneWidget);
    expect(find.text('AI 录音'), findsNothing);
    expect(find.textContaining('Agent · 自动执行工具计划'), findsOneWidget);
    expect(find.byIcon(material.Icons.mic_rounded), findsOneWidget);

    await tester.pump(const Duration(milliseconds: 200));
    await tester.pumpWidget(const material.SizedBox.shrink());
  });
}
