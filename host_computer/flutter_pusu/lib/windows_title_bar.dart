import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:window_manager/window_manager.dart';

/// Keeps the existing application toolbar while adding Windows caption
/// behavior to its right-hand side.
class WindowsTitleBar extends StatelessWidget {
  const WindowsTitleBar({
    super.key,
    required this.child,
  });

  final Widget child;

  static const double _height = 64;
  static const double _minimumDragWidth = 64;
  static const double controlsWidth = 46 * 3 + 32;

  @override
  Widget build(BuildContext context) {
    if (!Platform.isWindows) return child;

    return SizedBox(
      width: double.infinity,
      height: _height,
      child: ColoredBox(
        color: const Color(0xFF242424),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final toolbarMaxWidth =
                (constraints.maxWidth - controlsWidth - _minimumDragWidth)
                    .clamp(0.0, double.infinity)
                    .toDouble();

            return Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                ConstrainedBox(
                  constraints: BoxConstraints(maxWidth: toolbarMaxWidth),
                  child: ClipRect(
                    child: SingleChildScrollView(
                      scrollDirection: Axis.horizontal,
                      child: child,
                    ),
                  ),
                ),
                const Expanded(
                  child: DragToMoveArea(
                    key: ValueKey('title-bar-main-drag-area'),
                    child: SizedBox.expand(),
                  ),
                ),
                const SizedBox(width: controlsWidth),
              ],
            );
          },
        ),
      ),
    );
  }
}

class WindowsWindowControls extends StatelessWidget {
  const WindowsWindowControls({super.key});

  @override
  Widget build(BuildContext context) {
    if (!Platform.isWindows) return const SizedBox.shrink();

    return const ColoredBox(
      color: Color(0xFF242424),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DragToMoveArea(child: SizedBox(width: 32)),
          _WindowsCaptionButtons(),
        ],
      ),
    );
  }
}

class _WindowsCaptionButtons extends StatefulWidget {
  const _WindowsCaptionButtons();

  @override
  State<_WindowsCaptionButtons> createState() => _WindowsCaptionButtonsState();
}

class _WindowsCaptionButtonsState extends State<_WindowsCaptionButtons>
    with WindowListener {
  bool _isMaximized = false;

  @override
  void initState() {
    super.initState();
    windowManager.addListener(this);
    unawaited(_refreshMaximizedState());
  }

  @override
  void dispose() {
    windowManager.removeListener(this);
    super.dispose();
  }

  Future<void> _refreshMaximizedState() async {
    try {
      final isMaximized = await windowManager.isMaximized();
      if (!mounted || _isMaximized == isMaximized) return;
      setState(() => _isMaximized = isMaximized);
    } catch (_) {
      // Widget tests do not register the native desktop plugin.
    }
  }

  void _setMaximized(bool value) {
    if (!mounted || _isMaximized == value) return;
    setState(() => _isMaximized = value);
  }

  @override
  void onWindowMaximize() => _setMaximized(true);

  @override
  void onWindowUnmaximize() => _setMaximized(false);

  Widget _fullHeightButton({
    required String label,
    required Widget child,
  }) {
    return Semantics(
      button: true,
      label: label,
      child: SizedBox(
        width: 46,
        height: double.infinity,
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    const brightness = Brightness.dark;

    return SizedBox(
      height: double.infinity,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _fullHeightButton(
            label: '最小化',
            child: WindowCaptionButton.minimize(
              brightness: brightness,
              onPressed: () => unawaited(windowManager.minimize()),
            ),
          ),
          _fullHeightButton(
            label: _isMaximized ? '还原' : '最大化',
            child: _isMaximized
                ? WindowCaptionButton.unmaximize(
                    brightness: brightness,
                    onPressed: () => unawaited(windowManager.unmaximize()),
                  )
                : WindowCaptionButton.maximize(
                    brightness: brightness,
                    onPressed: () => unawaited(windowManager.maximize()),
                  ),
          ),
          _fullHeightButton(
            label: '关闭',
            child: WindowCaptionButton.close(
              brightness: brightness,
              onPressed: () => unawaited(windowManager.close()),
            ),
          ),
        ],
      ),
    );
  }
}
