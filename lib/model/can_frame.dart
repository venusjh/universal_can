import 'dart:typed_data';

// =============================================================================
// Enums
// =============================================================================

/// CAN Frame Receive/Send and Status Types
enum CanFrameType {
  rxData,
  boardStatus,
  txData,
  reserve,
}

/// Types of CAN module control commands
enum CanSendCommand {
  scDataTx(0),
  scConnect(1),
  scDisconnect(2),
  scRxFilterSet(3),
  scCanReset(4),
  scVerInfo(5),
  scSetUartBaudRate(6),
  scBoardReset(7);

  final int value;
  const CanSendCommand(this.value);
}

/// CAN communication speed (Baud Rate)
enum CanBaudRate {
  cb100k(0),
  cb125k(1),
  cb250k(2),
  cb500k(3),
  cb1000k(4);

  final int value;
  const CanBaudRate(this.value);
}

/// CAN bus error flag
enum CanBusError {
  errCanBufferOverflow(1),
  errCanTransmitTimeout(2),
  errCanErrorCounterOverflow(4),
  errCanBusOffError(8),
  errUsbRs232SyntaxError(16),
  errUsbRs232FormatError(32),
  errUsbRs232BufferOverflow(64);

  final int value;
  const CanBusError(this.value);
}

/// CAN operation mode
enum CanBusMode {
  cbmNormal(0),
  cbmListenOnly(1);

  final int value;
  const CanBusMode(this.value);
}

// =============================================================================
// Data Models
// =============================================================================

/// Received CAN data packet model
class CanDataPackType {
  // ---------------------------------------------------------------------------
  // Properties
  // ---------------------------------------------------------------------------
  /// CAN ID (29 bits)
  int id;

  /// Error Flag (1 bit)
  bool flagErr;

  /// Remote Transmission Request Flag (1 bit)
  bool flagRtr;

  /// Extended Identifier Flag (1 bit, true: 29bit / false: 11bit)
  bool flagIde;

  /// Calculated timestamp (24 bits)
  int timeStamp;

  /// Data Length Code (4 bits, 0~8)
  int dlc;

  /// CAN channel (2 bits)
  int channel;

  /// Frame type (2 bits)
  int frameType;

  /// Payload data (8 Bytes)
  Uint8List data;

  // ---------------------------------------------------------------------------
  // Constructors
  // ---------------------------------------------------------------------------
  CanDataPackType({
    this.id = 0,
    this.flagErr = false,
    this.flagRtr = false,
    this.flagIde = false,
    this.timeStamp = 0,
    this.dlc = 0,
    this.channel = 0,
    this.frameType = 0,
    Uint8List? data,
  }) : data = data ?? Uint8List(8);

  /// Creates an instance of [CanDataPackType] from a 16-byte Raw byte array.
  factory CanDataPackType.fromRawBytes(
      Uint8List bytes, {
        int timeOffset = 0,
        int timeStampHighByte = 0,
      }) {
    if (bytes.length < 16) {
      throw ArgumentError('CAN frame must be 16 bytes');
    }

    final byteData = ByteData.sublistView(bytes);

    // bytes[0] : crc (For ignoring or verification)
    // bytes[1] : dlc(4), channel(2), frameType(2)
    int byte1 = bytes[1];
    int dlc = byte1 & 0x0F;
    int channel = (byte1 >> 4) & 0x03;
    int frameType = (byte1 >> 6) & 0x03;

    // bytes[2..3] : timeStamp (16bit)
    int rawTimeStamp = byteData.getUint16(2, Endian.little);

    // bytes[4..7] : id(29), flagErr(1), flagRtr(1), flagIde(1)
    int byte4to7 = byteData.getUint32(4, Endian.little);
    int id = byte4to7 & 0x1FFFFFFF;
    bool flagErr = ((byte4to7 >> 29) & 0x01) == 1;
    bool flagRtr = ((byte4to7 >> 30) & 0x01) == 1;
    bool flagIde = ((byte4to7 >> 31) & 0x01) == 1;

    // bytes[8..15] : data
    Uint8List dataPayload = bytes.sublist(8, 16);

    if (!flagIde) id &= 0x7FF;
    if (flagRtr) {
      dlc = 0;
      dataPayload = Uint8List(8); // Initialize to 0
    } else if (dlc > 8) {
      dlc = 8;
    }

    int calculatedTimeStamp = ((timeStampHighByte & 0xFF) << 16) + rawTimeStamp + timeOffset;

    return CanDataPackType(
      id: id,
      flagErr: flagErr,
      flagRtr: flagRtr,
      flagIde: flagIde,
      timeStamp: calculatedTimeStamp,
      dlc: dlc,
      channel: channel,
      frameType: frameType,
      data: dataPayload,
    );
  }
}

/// CAN frame model and serialization class to transmit
class CanSendFrameType {
  // ---------------------------------------------------------------------------
  // Properties
  // ---------------------------------------------------------------------------
  /// CRC Checksum
  int crc = 0;

  /// Data Length Code (Default: 8)
  int dlc = 8;

  /// CAN channel
  int channel = 0;

  /// Frame Type (Default: 2, Tx Data)
  int frameType = 2;

  /// Control Command (Command)
  int cmd = 0;

  /// Control parameters(Parameter)
  int para = 0;

  /// CAN ID
  int id = 0;

  /// Error Flag
  bool flagErr = false;

  /// Remote Transmission Request Flag
  bool flagRtr = false;

  /// Extended Identifier Flag
  bool flagIde = false;

  /// Payload data (8 Bytes)
  Uint8List data = Uint8List(8);

  // ---------------------------------------------------------------------------
  // Public Methods
  // ---------------------------------------------------------------------------
  /// Serializes the set field value into a 16-byte [Uint8List] array.
  Uint8List toBytes() {
    final bytes = Uint8List(16);
    final byteData = ByteData.sublistView(bytes);

    // Bite 1 packing
    bytes[1] = (dlc & 0x0F) | ((channel & 0x03) << 4) | ((frameType & 0x03) << 6);
    bytes[2] = cmd;
    bytes[3] = para;

    // Packing bytes 4~7 (ID and flags)
    int idFlags = (id & 0x1FFFFFFF) |
    ((flagErr ? 1 : 0) << 29) |
    ((flagRtr ? 1 : 0) << 30) |
    ((flagIde ? 1 : 0) << 31);
    byteData.setUint32(4, idFlags, Endian.little);

    // Copy data byte 8~15
    for (int i = 0; i < data.length && i < 8; i++) {
      bytes[8 + i] = data[i];
    }

    // The CRC is calculated in sendFrame() and inserted into the first byte.
    return bytes;
  }
}