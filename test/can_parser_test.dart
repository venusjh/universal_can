import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter_test/flutter_test.dart';
import 'package:universal_can/universal_can.dart';

void main() {
  group('CanParser SLCAN Tests', () {
    late CanParser parser;

    setUp(() {
      parser = CanParser();
    });

    test('Standard frame parsing with \\r delimiter', () {
      final raw = Uint8List.fromList(ascii.encode('t123411223344\r'));
      final frames = parser.add(raw);

      expect(frames.length, 1);
      expect(frames[0].id, 0x123);
      expect(frames[0].dlc, 4);
      expect(frames[0].flagIde, false);
      expect(frames[0].data, [0x11, 0x22, 0x33, 0x44]);
    });

    test('Extended frame parsing with \\n delimiter', () {
      final raw = Uint8List.fromList(ascii.encode('T0000012381122334455667788\n'));
      final frames = parser.add(raw);

      expect(frames.length, 1);
      expect(frames[0].id, 0x123);
      expect(frames[0].dlc, 8);
      expect(frames[0].flagIde, true);
      expect(frames[0].data, [0x11, 0x22, 0x33, 0x44, 0x55, 0x66, 0x77, 0x88]);
    });

    test('Mixed delimiters and split chunks', () {
      final chunk1 = Uint8List.fromList(ascii.encode('t1002AABB\r\nT20'));
      final frames1 = parser.add(chunk1);
      expect(frames1.length, 1);
      expect(frames1[0].id, 0x100);

      final chunk2 = Uint8List.fromList(ascii.encode('0000001FF\r'));
      final frames2 = parser.add(chunk2);
      expect(frames2.length, 1);
      expect(frames2[0].id, 0x20000000);
      expect(frames2[0].dlc, 1);
      expect(frames2[0].data, [0xFF]);
    });

    test('Binary 16-byte frame parsing with CRC8', () {
      final frame = CanSendFrameType()
        ..id = 0x18DAF110
        ..flagIde = true
        ..dlc = 8
        ..channel = 0
        ..data = Uint8List.fromList([1, 2, 3, 4, 5, 6, 7, 8]);

      final bytes = frame.toBytes();
      bytes[0] = Crc8.calculate(bytes);

      final parsed = parser.add(bytes);
      expect(parsed.length, 1);
      expect(parsed[0].id, 0x18DAF110);
      expect(parsed[0].dlc, 8);
      expect(parsed[0].flagIde, true);
      expect(parsed[0].data, [1, 2, 3, 4, 5, 6, 7, 8]);
    });
  });
}
