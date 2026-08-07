abstract final class AssistantResponseFormatter {
  static String toPlainText(String input) {
    final output = <String>[];
    var inCodeFence = false;
    for (var line in input.replaceAll('\r\n', '\n').split('\n')) {
      final trimmed = line.trim();
      if (trimmed.startsWith('```')) {
        inCodeFence = !inCodeFence;
        continue;
      }
      if (inCodeFence) {
        if (trimmed.isNotEmpty) output.add(trimmed);
        continue;
      }
      if (RegExp(r'^\|?\s*:?-{3,}:?\s*(\|\s*:?-{3,}:?\s*)+\|?$')
          .hasMatch(trimmed)) {
        continue;
      }

      line = line
          .replaceFirst(RegExp(r'^\s*#{1,6}\s*'), '')
          .replaceFirst(RegExp(r'^\s*[-*+]\s+'), '')
          .replaceFirst(RegExp(r'^\s*\d+[.)、]\s*'), '')
          .replaceAll(RegExp(r'[*_`]+'), '')
          .replaceAll(RegExp(r'[✅❌⚠️🔹🔸📌👉]'), '')
          .trim();
      if (line.startsWith('|') || line.endsWith('|')) {
        line = line
            .split('|')
            .map((cell) => cell.trim())
            .where((cell) => cell.isNotEmpty)
            .join('，');
      }
      if (line.isNotEmpty) output.add(line);
    }
    return output.join('\n').replaceAll(RegExp(r'\n{3,}'), '\n\n').trim();
  }
}
