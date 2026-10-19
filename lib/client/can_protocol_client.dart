import 'dart:async';
import 'dart:typed_data';

import '../model/can_frame.dart';
import '../parser/can_parser.dart';
import '../parser/crc8.dart';


// =============================================================================
// Interfaces
// =============================================================================

/// 하위 전송 레이어(블루투스, 시리얼 등)와의 통신을 위한 추상 인터페이스
abstract class CanTransport {
  /// 연결 상태 여부
  bool get isConnected;

  /// 수신 데이터(Raw Bytes) 스트림
  Stream<Uint8List> get dataStream;

  /// Raw 바이트 데이터 전송
  Future<bool> send(Uint8List data);

  /// 통신 연결 해제
  Future<void> disconnect();

  /// 리소스 해제
  Future<void> dispose();
}

// =============================================================================
// Protocol Client
// =============================================================================

/// CAN 통신 프로토콜을 처리하고 명령어 전송 및 파싱을 총괄하는 클라이언트 클래스
class CanProtocolClient {
  // ---------------------------------------------------------------------------
  // Properties & Variables
  // ---------------------------------------------------------------------------
  /// 하위 전송 인터페이스 객체
  final CanTransport transport;

  /// 데이터 수신 스트림 구독 객체
  StreamSubscription<Uint8List>? _subscription;

  /// CAN 메시지 파서
  final CanParser _parser = CanParser();

  /// 수신 파싱된 CAN 프레임을 전달하는 브로드캐스트 스트림 컨트롤러
  final _frameController = StreamController<CanDataPackType>.broadcast();

  // ---------------------------------------------------------------------------
  // Getters
  // ---------------------------------------------------------------------------
  /// 하위 트랜스포트의 연결 상태 반환
  bool get isConnected => transport.isConnected;

  /// 파싱 완료된 CAN 데이터 패킷 스트림
  Stream<CanDataPackType> get frames => _frameController.stream;

  // ---------------------------------------------------------------------------
  // Constructors
  // ---------------------------------------------------------------------------
  CanProtocolClient(this.transport);

  // ---------------------------------------------------------------------------
  // Lifecycle & Stream Control
  // ---------------------------------------------------------------------------
  /// 수신 데이터 스트림 리스닝을 시작합니다.
  Future<void> startListening() async {
    await _subscription?.cancel();
    _subscription = transport.dataStream.listen(addData);
  }

  /// 수신된 Raw 데이터를 파서에 추가하고 생성된 CAN 프레임을 스트림으로 전송합니다.
  void addData(Uint8List data) {
    final parsedFrames = _parser.add(data);

    for (final frame in parsedFrames) {
      _frameController.add(frame);
    }
  }

  /// 구독을 중단하고 하위 트랜스포트 연결을 해제합니다.
  Future<void> disconnect() async {
    await _subscription?.cancel();
    _subscription = null;
    await transport.disconnect();
  }

  /// 스트림 컨트롤러 및 모든 리소스를 해제합니다.
  Future<void> dispose() async {
    await disconnect();
    await _frameController.close();
  }

  // ---------------------------------------------------------------------------
  // CAN Protocol Commands & Message Transmission
  // ---------------------------------------------------------------------------
  /// CAN 송신 프레임의 CRC8을 계산하여 하위 트랜스포트로 전송합니다.
  Future<bool> sendFrame(CanSendFrameType frame) async {
    final data = frame.toBytes();
    data[0] = Crc8.calculate(data);

    return transport.send(data);
  }

  /// 지정한 CAN 채널에 대한 연결 명령을 전송합니다.
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

  /// 지정한 CAN 채널에 대한 연결 해제 명령을 전송합니다.
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

  /// CAN ID와 데이터 배열을 포함하는 데이터 전송 프레임을 생성하여 전송합니다.
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

  /// 특정 채널에 수신 필터링할 CAN ID 목록을 등록합니다.
  void setCanIdFilter(int channel, Set<int> ids) {
    _parser.setCanIdFilter(channel, ids);
  }
}