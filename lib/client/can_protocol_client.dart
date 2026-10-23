import 'dart:async';
import 'dart:typed_data';

import '../model/can_frame.dart';
import '../parser/can_parser.dart';
import '../parser/crc8.dart';


// =============================================================================
// Interfaces
// =============================================================================

/// Abstract interface for communication with lower transport layers (Bluetooth, Serial, etc.)
abstract class CanTransport {
 /// Connection status
  bool get isConnected;

  /// Received Data (Raw Bytes) Stream
  Stream<Uint8List> get dataStream;

  /// Raw byte data transmission
  Future<bool> send(Uint8List data);

  /// Disconnect communication
  Future<void> disconnect();

  /// Release resources
  Future<void> dispose();
}

// =============================================================================
// Protocol Client
// =============================================================================

/// A client class that handles the CAN communication protocol and oversees command transmission and parsing.
class CanProtocolClient {
  // ---------------------------------------------------------------------------
  // Properties & Variables
  // ---------------------------------------------------------------------------
  /// Sub-transmission interface object
  final CanTransport transport;

  /// Data reception stream subscription object
  StreamSubscription<Uint8List>? _subscription;

  /// CAN message parser
  final CanParser _parser = CanParser();

  /// 수Broadcast stream controller delivering newly parsed CAN frames
  final _frameController = StreamController<CanDataPackType>.broadcast();

  // ---------------------------------------------------------------------------
  // Getters
  // ---------------------------------------------------------------------------
  /// Return the connection status of the sub-transport
  bool get isConnected => transport.isConnected;

  /// Parsed CAN data packet stream
  Stream<CanDataPackType> get frames => _frameController.stream;

  // ---------------------------------------------------------------------------
  // Constructors
  // ---------------------------------------------------------------------------
  CanProtocolClient(this.transport);

  // ---------------------------------------------------------------------------
  // Lifecycle & Stream Control
  // ---------------------------------------------------------------------------
  /// Start listening for incoming data stream.
  Future<void> startListening() async {
    await _subscription?.cancel();
    _subscription = transport.dataStream.listen(addData);
  }

  /// Adds the received raw data to the parser and sends the generated CAN frame as a stream.
  void addData(Uint8List data) {
    final parsedFrames = _parser.add(data);

    for (final frame in parsedFrames) {
      _frameController.add(frame);
    }
  }

  /// Cancel the subscription and disconnect the sub-transport connection.
  Future<void> disconnect() async {
    await _subscription?.cancel();
    _subscription = null;
    await transport.disconnect();
  }

  /// Releases the stream controller and all resources.
  Future<void> dispose() async {
    await disconnect();
    await _frameController.close();
  }

  // ---------------------------------------------------------------------------
  // CAN Protocol Commands & Message Transmission
  // ---------------------------------------------------------------------------
  /// Calculate the CRC8 of the CAN transmission frame and send it to the downstream transport.
  Future<bool> sendFrame(CanSendFrameType frame) async {
    final data = frame.toBytes();
    data[0] = Crc8.calculate(data);

    return transport.send(data);
  }

  /// Sends a connection command for the specified CAN channel.
  Future<bool> connectCan({
    int channel = 0,
    CanBaudRate baudRate = CanBaudRate.cb125k,
    CanBusMode busMode = CanBusMode.cbmNormal,
  }) async {
    if (channel < 0 || channel > 3) {
      return false;
    }

    final frame = CanSendFrameType()
      ..cmd = CanSendCommand.scConnect.value
      ..para = (busMode.value << 4) | baudRate.value
      ..channel = channel
      ..dlc = 8
      ..flagIde = true;

    return sendFrame(frame);
  }

  /// Sends a disconnect command for the specified CAN channel.
  Future<bool> disconnectCan({
    int channel = 0,
  }) async {
    if (channel < 0 || channel > 3) {
      return false;
    }

    final frame = CanSendFrameType()
      ..cmd = CanSendCommand.scDisconnect.value
      ..channel = channel
      ..dlc = 8;

    return sendFrame(frame);
  }

  /// Generates and transmits a data transmission frame containing a CAN ID and a data array.
  Future<bool> sendCanFrame(
      int id,
      Uint8List data, {
        int channel = 0,
        bool isExtended = true,
      }) async {
    if (data.length > 8) {
      return false;
    }

    final maxId = isExtended ? 0x1FFFFFFF : 0x7FF;

    if (id < 0 || id > maxId) {
      return false;
    }

    if (channel < 0 || channel > 3) {
      return false;
    }

    final frame = CanSendFrameType()
      ..id = id
      ..data = data
      ..dlc = data.length
      ..channel = channel
      ..flagIde = isExtended
      ..cmd = CanSendCommand.scDataTx.value;

    return sendFrame(frame);
  }

  /// Register a list of CAN IDs to filter reception on a specific channel.
  void setCanIdFilter(int channel, Set<int> ids) {
    _parser.setCanIdFilter(channel, ids);
  }
}