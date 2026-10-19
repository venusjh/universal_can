import 'dart:typed_data';

// =============================================================================
// Enums
// =============================================================================

/// CAN 프레임의 수신/발신 및 상태 유형
enum CanFrameType {
  rxData,
  boardStatus,
  txData,
  reserve,
}

/// CAN 모듈 제어 명령 종류
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

/// CAN 통신 속도 (Baud Rate)
enum CanBaudRate {
  cb10k(0),
  cb20k(1),
  cb50k(2),
  cb100k(3),
  cb125k(4),
  cb250k(5),
  cb500k(6),
  cb800k(7),
  cb1m(8); // 혹은 cb1000k(8)

  final int value;
  const CanBaudRate(this.value);
}

/// CAN 버스 에러 플래그
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

/// CAN 동작 모드
enum CanBusMode {
  cbmNormal(0),
  cbmListenOnly(1);

  final int value;
  const CanBusMode(this.value);
}

// =============================================================================
// Data Models
// =============================================================================

/// 수신된 CAN 데이터 패킷 모델
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

  /// 계산된 타임스탬프 (24 bits)
  int timeStamp;

  /// Data Length Code (4 bits, 0~8)
  int dlc;

  /// CAN 채널 (2 bits)
  int channel;

  /// 프레임 타입 (2 bits)
  int frameType;

  /// 페이로드 데이터 (8 Bytes)
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

  /// 16바이트 Raw 바이트 배열로부터 [CanDataPackType] 인스턴스를 생성합니다.
  factory CanDataPackType.fromRawBytes(
      Uint8List bytes, {
        int timeOffset = 0,
        int timeStampHighByte = 0,
      }) {
    if (bytes.length < 16) {
      throw ArgumentError('CAN frame must be 16 bytes');
    }

    final byteData = ByteData.sublistView(bytes);

    // bytes[0] : crc (무시 또는 검증용)
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
      dataPayload = Uint8List(8); // 0으로 초기화
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

/// 전송할 CAN 프레임 모델 및 직렬화 클래스
class CanSendFrameType {
  // ---------------------------------------------------------------------------
  // Properties
  // ---------------------------------------------------------------------------
  /// CRC Checksum
  int crc = 0;

  /// Data Length Code (기본값: 8)
  int dlc = 8;

  /// CAN 채널
  int channel = 0;

  /// 프레임 타입 (기본값: 2, Tx Data)
  int frameType = 2;

  /// 제어 명령 (Command)
  int cmd = 0;

  /// 제어 파라미터 (Parameter)
  int para = 0;

  /// CAN ID
  int id = 0;

  /// Error Flag
  bool flagErr = false;

  /// Remote Transmission Request Flag
  bool flagRtr = false;

  /// Extended Identifier Flag
  bool flagIde = false;

  /// 페이로드 데이터 (8 Bytes)
  Uint8List data = Uint8List(8);

  // ---------------------------------------------------------------------------
  // Public Methods
  // ---------------------------------------------------------------------------
  /// 설정된 필드값을 16바이트 [Uint8List] 배열로 직렬화합니다.
  Uint8List toBytes() {
    final bytes = Uint8List(16);
    final byteData = ByteData.sublistView(bytes);

    // 바이트 1 패킹
    bytes[1] = (dlc & 0x0F) | ((channel & 0x03) << 4) | ((frameType & 0x03) << 6);
    bytes[2] = cmd;
    bytes[3] = para;

    // 바이트 4~7 패킹 (ID 및 플래그)
    int idFlags = (id & 0x1FFFFFFF) |
    ((flagErr ? 1 : 0) << 29) |
    ((flagRtr ? 1 : 0) << 30) |
    ((flagIde ? 1 : 0) << 31);
    byteData.setUint32(4, idFlags, Endian.little);

    // 바이트 8~15 데이터 복사
    for (int i = 0; i < data.length && i < 8; i++) {
      bytes[8 + i] = data[i];
    }

    // CRC는 sendFrame()에서 계산하여 첫 번째 바이트에 삽입
    return bytes;
  }
}