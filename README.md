# Universal CAN Communication Package

[![Flutter CI](https://github.com/venusjh/universal_can/actions/workflows/main.yml/badge.svg)](https://github.com/venusjh/universal_can/actions/workflows/main.yml)
[![Pub Version](https://img.shields.io/pub/v/universal_can.svg)](https://pub.dev/packages/universal_can)

A Flutter package with CAN communication clients for two specific transport protocols: SLCAN over Android USB serial, and this package's fixed-length binary protocol over Bluetooth Classic Serial.

---

## Requirements
- **Flutter:** >= 3.3.0
- **Dart:** >= 3.11.4
- **USB Serial:** Android only. The native USB implementation is provided for Android.
- **Bluetooth:** Requires a Bluetooth Classic device that exposes a serial connection and speaks the binary protocol described below. The package does not implement BLE GATT.

## Device and Protocol Compatibility

This package does **not** support every CAN adapter or automatically detect arbitrary CAN hardware. The CAN adapter must expose one of the protocols implemented by the selected client:

- **`SerialCanClient`:** Android USB host connection to an adapter exposing USB CDC bulk IN/OUT endpoints and accepting SLCAN commands and frames. The client uses SLCAN commands (`C`, `S3`–`S8`, `O`) and parses standard/extended SLCAN data frames (`t`/`T`). The native code checks for USB IDs `0483:5740` and `1D50:606F` first, then searches for a CDC-class device. These checks are device discovery heuristics, not a guarantee that every matching device or firmware is compatible. The USB setup also sends CP210x-specific control transfers, so generic CDC compatibility is not guaranteed.
- **`BluetoothCanClient`:** Bluetooth Classic Serial (RFCOMM) connection to a device whose firmware implements this package's 16-byte binary command/frame format, including CRC-8. A generic Bluetooth serial CAN adapter that uses a different protocol will not work without a matching adapter implementation.

The two clients use different CAN-side protocols: USB serial uses SLCAN text, while Bluetooth serial uses the package's binary protocol. A device supporting one path is not necessarily compatible with the other. BLE GATT, SocketCAN, and vendor-specific USB protocols are not implemented in this release.

No specific adapter model is claimed as verified by this package documentation. Confirm compatibility with the adapter firmware and target platform before relying on it in a deployment.

## Package Architecture & Structure

This package is cleanly separated into distinct layers by responsibility:

1. **Client (`/client`)**
   - `CanClient` / `CanTransport`: Common interfaces for upper clients and lower communication channels.
   - `CanProtocolClient`: Core controller managing CAN connection commands, filter settings, data transmission/reception, and parser integration.
   - `SerialCanClient` / `BluetoothCanClient`: Clients for SLCAN over Android USB serial and the package binary protocol over Bluetooth Classic Serial, respectively.
2. **Model (`/model`)**
   - `CanDataPackType`: Parsing model converting incoming 16-byte raw data into objects.
   - `CanSendFrameType`: Serialization model converting outgoing CAN data into 16-byte binary arrays.
   - Various enums (`CanSendCommand`, `CanBaudRate`, `CanBusMode`, etc.)
3. **Parser (`/parser`)**
   - `CanParser`: Parser that buffers incoming byte streams, slices them into 16-byte units, performs CRC-8 verification, and calculates timestamps.
   - `Crc8`: Lookup table-based integrity check checksum utility.

---

## Main Features & Usage

### 1. Initialize Client & Connect (Android USB SLCAN Example)
```dart
// Create a client for a compatible SLCAN USB adapter on Android
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
  isExtended: false, // Standard 11-bit ID flag for 0x123
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
