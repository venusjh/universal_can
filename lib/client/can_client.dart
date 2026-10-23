import 'dart:typed_data';
import '../model/can_frame.dart';

/// CAN communication client interface
abstract class CanClient {
  // ===========================================================================
  // Getters
  // ===========================================================================
  /// Current connection status with physical devices (USB Serial, Bluetooth, etc.)
  bool get isConnected;

  /// Parsed CAN received frame stream
  Stream<CanDataPackType> get frames;

  // ===========================================================================
  // Public Methods
  // ===========================================================================
  /// Connect to a physical communication device (USB port or Bluetooth device).
  Future<bool> connect([String? portOrAddress]);

  /// Disconnects the currently connected communication socket/device.
  Future<void> disconnect();

  /// Starts CAN bus communication with the specified channel, baud rate, and operating mode.
  Future<bool> connectCan({
    int channel = 0,
    CanBaudRate baudRate = CanBaudRate.cb125k,
    CanBusMode busMode = CanBusMode.cbmNormal,
  });

/// Stops communication on the specified CAN channel.
  Future<bool> disconnectCan({
    int channel = 0,
  });

  /// Serializes the generated CAN frame object into bytes and transmits it.
  Future<bool> sendFrame(CanSendFrameType frame);

/// Receives the CAN ID and data payload and sends a standard CAN message.
  Future<bool> sendCanFrame(
      int id,
      Uint8List data, {
        int channel = 0,
        bool isExtended = true,
      });

/// Registers the list of CAN IDs to be received as a specified channel filter.
  void setCanIdFilter(
      int channel,
      Set<int> ids,
      );

/// Releases all resources (streams, sockets, etc.) and terminates the client.
  Future<void> dispose();
}