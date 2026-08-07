import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_pusu/serial_port_manager.dart';

void main() {
  test('filters blocked Bluetooth serial ports', () {
    expect(
      filterAvailableSerialPorts(['COM3', 'COM42', 'com43', 'COM50']),
      ['COM3', 'COM50'],
    );
  });
}
