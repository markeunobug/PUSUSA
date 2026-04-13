// 串口配置UI组件，使用SerialPortManager

import 'package:fluent_ui/fluent_ui.dart';
import 'package:flutter/material.dart' as material;
// 新增：支持 AnimatedBuilder
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

  @override
  Widget build(BuildContext context) {
    return FlyoutContent(
      child: SizedBox(
        width: 300,
        child: AnimatedBuilder(
          // 使用 AnimatedBuilder 监听整个 manager（ChangeNotifier）
          // 这样选中端口、刷新列表、设备拔出等任何 notifyListeners() 都会立即重建 UI
          animation: manager,
          builder: (context, child) {
            final bool hasPorts = manager.availablePorts.isNotEmpty;
            final bool connected = manager.isConnected;

            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Row(
                  children: [
                    const SizedBox(
                      width: 100,
                      child: Text('端口：', style: TextStyle(color: material.Colors.white)),
                    ),
                    Expanded(
                      child: connected
                          // 已连接时显示禁用文本框（真正显示端口名）
                          ? TextBox(
                              enabled: false,
                              controller: TextEditingController(
                                text: manager.selectedPort ?? '无',
                              ),
                            )
                          // 未连接时显示 ComboBox
                          : ComboBox<String>(
                              value: manager.selectedPort,
                              placeholder: const Text('选择端口'),
                              items: manager.availablePorts
                                  .map((port) => ComboBoxItem<String>(value: port, child: Text(port)))
                                  .toList(),
                              onChanged: (value) {
                                manager.setSelectedPort(value);
                                // 选中后立即重建（AnimatedBuilder 已处理）
                              },
                            ),
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
                      child: Text('状态：', style: TextStyle(color: material.Colors.white)),
                    ),
                    Text(
                      connected ? '已连接' : (hasPorts ? '未连接' : '无可用串口'),
                      style: TextStyle(
                        color: connected
                            ? material.Colors.green
                            : (hasPorts ? material.Colors.red : material.Colors.grey),
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
                              manager.connect();
                            }
                          } catch (e) {
                            _showError(context, '$e');
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