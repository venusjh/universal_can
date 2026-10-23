[![Flutter CI](https://github.com/venusjh/universal_can/actions/workflows/main.yml/badge.svg)](https://github.com/venusjh/universal_can/actions/workflows/main.yml)

# Universal CAN Communication Package

[![Flutter CI](https://github.com/venusjh/universal_can/actions/workflows/flutter.yml/badge.svg)](https://github.com/venusjh/universal_can/actions/workflows/flutter.yml)
[![Pub Version](https://img.shields.io/pub/v/universal_can)](https://pub.dev/packages/universal_can)

A Flutter package that enables custom 16-byte binary protocol-based CAN communication via USB Serial and Bluetooth.

---

## Requirements
- **Flutter:** >= 3.3.0
- **Dart:** >= 3.11.4
- **Platform:** Android (Supports hardware communication such as Bluetooth)

## Package Architecture & Structure

This package is cleanly separated into distinct layers by responsibility:

1. **Client (`/client`)**
   - `CanClient` / `CanTransport`: Common interfaces for upper clients and lower communication channels.
   - `CanProtocolClient`: Core controller managing CAN connection commands, filter settings, data transmission/reception, and parser integration.
   - `SerialCanClient` / `BluetoothCanClient`: Practical clients implementing USB Serial and Bluetooth hardware pathways.
2. **Model (`/model`)**
   - `CanDataPackType`: Parsing model converting incoming 16-byte raw data into objects.
   - `CanSendFrameType`: Serialization model converting outgoing CAN data into 16-byte binary arrays.
   - Various enums (`CanSendCommand`, `CanBaudRate`, `CanBusMode`, etc.)
3. **Parser (`/parser`)**
   - `CanParser`: Parser that buffers incoming byte streams, slices them into 16-byte units, performs CRC-8 verification, and calculates timestamps.
   - `Crc8`: Lookup table-based integrity check checksum utility.

---

## Main Features & Usage

### 1. Initialize Client & Connect (USB Serial Example)
```dart
// Create a USB Serial-based client
final canClient = SerialCanClient();

// 1. Physical hardware connection (e.g., open USB port)
bool isConnected = await canClient.connect();
if (isConnected) {
  print('Device connected successfully!');
}

// 2. Start CAN bus communication (Channel 0, 125kbps, Normal mode)
await canClient.connectCan(
  channel: 0,
  baudRate: CanBaudRate.cb125k,
  busMode: CanBusMode.cbmNormal,
);
```

### 2. Subscribe to Incoming Data Stream
Process parsed `CanDataPackType` frames in real time.
```dart
canClient.frames.listen((packet) {
  print('Received CAN ID: 0x${packet.id.toRadixString(16)}');
  print('Channel: ${packet.channel}, DLC: ${packet.dlc}');
  print('Payload Data: ${packet.data}');
});
```

### 3. Send CAN Messages
```dart
// Prepare 8-byte payload data
final payload = Uint8List.fromList([0x01, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08]);

// Send message with specified CAN ID
await canClient.sendCanFrame(
  0x123, // CAN ID
  payload,
  channel: 0,
  isExtended: true, // Extended 29-bit ID flag
);
```

### 4. Configure CAN ID Filtering
Filter messages to receive only specific IDs.
```dart
// Allow receiving only IDs 0x123 and 0x456 on channel 0
canClient.setCanIdFilter(0, {0x123, 0x456});
```

### 5. Disconnect & Cleanup Resources
```dart
// Stop CAN communication
await canClient.disconnectCan(channel: 0);

// Disconnect hardware and release resources
await canClient.disconnect();
await canClient.dispose();
```

---

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details.
