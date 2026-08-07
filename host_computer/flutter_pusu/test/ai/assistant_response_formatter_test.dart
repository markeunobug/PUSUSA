import 'package:flutter_pusu/ai/assistant_response_formatter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('removes markdown decoration and table syntax', () {
    const source = '''
## 分析结果
| 项目 | 数值 |
| --- | --- |
| 峰值 | -32 dBFS |
- **结论**：检测到信号 ✅
''';
    final plain = AssistantResponseFormatter.toPlainText(source);
    expect(plain, contains('分析结果'));
    expect(plain, contains('项目，数值'));
    expect(plain, contains('峰值，-32 dBFS'));
    expect(plain, contains('结论：检测到信号'));
    expect(plain, isNot(contains('|')));
    expect(plain, isNot(contains('**')));
    expect(plain, isNot(contains('✅')));
  });
}
