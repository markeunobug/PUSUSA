import 'package:fluent_ui/fluent_ui.dart';

class ResizablePanelDivider extends StatefulWidget {
  const ResizablePanelDivider({
    super.key,
    required this.onDragDelta,
    this.tooltip = '拖动调整宽度',
  });

  final ValueChanged<double> onDragDelta;
  final String tooltip;

  @override
  State<ResizablePanelDivider> createState() => _ResizablePanelDividerState();
}

class _ResizablePanelDividerState extends State<ResizablePanelDivider> {
  bool _hovered = false;
  bool _dragging = false;

  @override
  Widget build(BuildContext context) {
    final active = _hovered || _dragging;
    return Tooltip(
      message: widget.tooltip,
      child: MouseRegion(
        cursor: SystemMouseCursors.resizeColumn,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          behavior: HitTestBehavior.opaque,
          onHorizontalDragStart: (_) => setState(() => _dragging = true),
          onHorizontalDragUpdate: (details) {
            widget.onDragDelta(details.delta.dx);
          },
          onHorizontalDragEnd: (_) => setState(() => _dragging = false),
          onHorizontalDragCancel: () => setState(() => _dragging = false),
          child: SizedBox(
            width: 7,
            child: Center(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 120),
                width: active ? 3 : 1,
                color:
                    active ? const Color(0xFF65A9FF) : const Color(0xFF50545C),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
