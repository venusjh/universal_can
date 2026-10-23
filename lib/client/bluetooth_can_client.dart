import 'dart:typed_data';
import 'package:flutter_bluetooth_serial_ble/flutter_bluetooth_serial_ble.dart';

import 'can_client.dart';
import 'can_protocol_client.dart';
import '../model/can_frame.dart';

/// Bluetooth-based CAN client implementing the [CanClient] and [CanTransport] interfaces
class BluetoothCanClient implements CanClient, CanTransport {
  // ===========================================================================
  // Private Variables
  // ===========================================================================
/// Bluetooth Serial Connection Object
  BluetoothConnection? _connection;

 /// Client responsible for CAN protocol parsing and control
  late final CanProtocolClient _canClient;

  // ===========================================================================
  // Constructors
  // ===========================================================================
  BluetoothCanClient() {
    _canClient = CanProtocolClient(this);
  }

  // ===========================================================================
  // CanClient / CanTransport Getters
  // ===========================================================================
  /// Current connection status of the CAN client
  @override
  bool get isConnected => _connection != null;

/// Parsed CAN data frame stream
  @override
  Stream<CanDataPackType> get frames => _canClient.frames;

  /// Bluetooth Received Raw Byte Data Stream
  @override
  Stream<Uint8List> get dataStream {
    final input = _connection?.input;

    if (input == null) {
      return const Stream.empty();
    }

    return input;
  }

  // ===========================================================================
  // Bluetooth Connection Methods
  // ===========================================================================
  // Attempts to connect via Bluetooth to the specified MAC address (or port information) and starts listening.
  @override
  Future<bool> connect([String? address]) async {
    if (isConnected) {
      return false;
    }

    if (address == null || address.isEmpty) {
      return false; // Bluetooth requires a connection address.
    }

    try {
      _connection = await BluetoothConnection.toAddress(address)
          .timeout(const Duration(seconds: 15));

      if (_connection!.input == null) {
        await disconnect();
        return false;
      }

      await _canClient.startListening();

      return true;
    } catch (_) {
      await disconnect();
      return false;
    }
  }

  /// Disconnects Bluetooth and CAN client connections.
  @override
  Future<void> disconnect() async {
    await _canClient.disconnect();

    try {
      await _connection?.close();
    } catch (_) {}

    _connection = null;
  }

  // ===========================================================================
  // CanTransport Interface Implementations
  // ===========================================================================
  /// Transmits raw byte data via Bluetooth serial.
  @override
  Future<bool> send(Uint8List data) async {
    if (!isConnected) {
      return false;
    }

    try {
      _connection!.output.add(data);
      await _connection!.output.allSent;
      return true;
    } catch (_) {
      await disconnect();
      return false;
    }
  }

  // ===========================================================================
  // CanClient Interface Implementations
  // ===========================================================================
  /// Releases all resources and connections.
  @override
  Future<void> dispose() async {
    await disconnect();
    await _canClient.dispose();
  }

 /// Transmits data through the CAN transmission frame object.
  @override
  Future<bool> sendFrame(CanSendFrameType frame) {
    return _canClient.sendFrame(frame);
  }

/// Performs CAN communication connection and settings (channel, baud rate, operating mode).
  @override
  Future<bool> connectCan({
    int channel = 0,
    CanBaudRate baudRate = CanBaudRate.cb125k,
    CanBusMode busMode = CanBusMode.cbmNormal,
  }) {
    return _canClient.connectCan(
      channel: channel,
      baudRate: baudRate,
      busMode: busMode,
    );
  }

  /// Stops CAN communication on the designated channel.
  @override
  Future<bool> disconnectCan({
    int channel = 0,
  }) {
    return _canClient.disconnectCan(
      channel: channel,
    );
  }

  /// Sends a CAN message by specifying the CAN ID and data array.
  @override
  Future<bool> sendCanFrame(
      int id,
      Uint8List data, {
        int channel = 0,
        bool isExtended = true,
      }) {
    return _canClient.sendCanFrame(
      id,
      data,
      channel: channel,
      isExtended: isExtended,
    );
  }

 /// Register a list of CAN IDs to filter incoming calls.
  @override
  void setCanIdFilter(int channel, Set<int> ids) {
    _canClient.setCanIdFilter(channel, ids);
  }
}