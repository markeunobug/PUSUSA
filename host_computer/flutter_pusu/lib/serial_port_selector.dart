import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/material.dart' as material;

import 'serial_port_manager.dart';

class SerialPortSelector extends StatelessWidget {
  final SerialPortManager manager;

  const SerialPortSelector({super.key, required this.manager});

  void _showError(BuildContext context, String message) {
    showDialog(
      context: context,
      builder: (context) => ContentDialog(
        title: const Text('错误'),
        content: Text(message),
        actions: [
          Button(
            child: const Text('确定'),
            onPressed: () => Navigator.pop(context),
          ),
        ],
      ),
    );
  }

  Widget _buildSelectedPortField(bool connected) {
    return Container(
      height: 34,
      padding: const EdgeInsets.symmetric(horizontal: 11),
      alignment: Alignment.centerLeft,
      decoration: BoxDecoration(
        color: material.Colors.white.withValues(alpha: 0.06),
        border: Border.all(color: material.Colors.white24),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        manager.selectedPort ?? '无',
        overflow: TextOverflow.ellipsis,
        style: TextStyle(
          color: connected ? material.Colors.white70 : material.Colors.white,
        ),
      ),
    );
  }

  Widget _buildPortList(BuildContext context, bool connected, bool hasPorts) {
    if (connected || !hasPorts) {
      return _buildSelectedPortField(connected);
    }

    return Container(
      constraints: const BoxConstraints(maxHeight: 156),
      decoration: BoxDecoration(
        color: material.Colors.white.withValues(alpha: 0.04),
        border: Border.all(color: material.Colors.white24),
        borderRadius: BorderRadius.circular(4),
      ),
      child: ListView.builder(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(vertical: 4),
        itemCount: manager.availablePorts.length,
        itemBuilder: (context, index) {
          final port = manager.availablePorts[index];
          final selected = port == manager.selectedPort;

          return Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4),
            child: Button(
              style: ButtonStyle(
                padding: const WidgetStatePropertyAll(
                  EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                ),
                backgroundColor: WidgetStateProperty.resolveWith((states) {
                  if (selected) {
                    final alpha = states.isPressed ? 0.45 : 0.32;
                    return FluentTheme.of(context)
                        .accentColor
                        .withValues(alpha: alpha);
                  }
                  if (states.isHovered) {
                    return material.Colors.white.withValues(alpha: 0.08);
                  }
                  return material.Colors.transparent;
                }),
              ),
              onPressed: () => manager.setSelectedPort(port),
              child: Row(
                children: [
                  Icon(
                    selected
                        ? FluentIcons.radio_btn_on
                        : FluentIcons.radio_btn_off,
                    size: 14,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(port, overflow: TextOverflow.ellipsis),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return FlyoutContent(
      child: SizedBox(
        width: 300,
        child: AnimatedBuilder(
          animation: manager,
          builder: (context, child) {
            final bool hasPorts = manager.availablePorts.isNotEmpty;
            final bool connected = manager.isConnected;

            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(
                      width: 100,
                      child: Padding(
                        padding: EdgeInsets.only(top: 7),
                        child: Text(
                          '端口：',
                          style: TextStyle(color: material.Colors.white),
                        ),
                      ),
                    ),
                    Expanded(
                      child: _buildPortList(context, connected, hasPorts),
                    ),
                    const SizedBox(width: 8),
                    IconButton(
                      icon: const Icon(FluentIcons.refresh),
                      onPressed: manager.refreshPorts,
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    const SizedBox(
                      width: 100,
                      child: Text(
                        '状态：',
                        style: TextStyle(color: material.Colors.white),
                      ),
                    ),
                    Text(
                      connected ? '已连接' : (hasPorts ? '未连接' : '无可用串口'),
                      style: TextStyle(
                        color: connected
                            ? material.Colors.green
                            : (hasPorts
                                ? material.Colors.red
                                : material.Colors.grey),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                FilledButton(
                  onPressed: hasPorts
                      ? () async {
                          try {
                            if (connected) {
                              manager.disconnect();
                            } else {
                              await manager.connect();
                            }
                          } catch (e) {
                            if (context.mounted) {
                              _showError(context, '$e');
                            }
                          }
                        }
                      : null,
                  child: Text(connected ? '断开' : '连接'),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}
