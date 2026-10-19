import 'dart:typed_data';
import '../model/can_frame.dart';

/// CAN 통신 클라이언트 인터페이스
abstract class CanClient {
  // ===========================================================================
  // Getters
  // ===========================================================================
  /// 현재 물리적 기기(USB Serial, 블루투스 등)와의 연결 상태
  bool get isConnected;

  /// 파싱 완료된 CAN 수신 프레임 스트림
  Stream<CanDataPackType> get frames;

  // ===========================================================================
  // Public Methods
  // ===========================================================================
  /// 물리적 통신 장치(USB 포트 또는 블루투스 디바이스)에 연결합니다.
  Future<bool> connect([String? portOrAddress]);

  /// 현재 연결된 통신 소켓/장치 연결을 해제합니다.
  Future<void> disconnect();

  /// 지정된 채널 및 보레이트, 동작 모드로 CAN 버스 통신을 시작합니다.
  Future<bool> connectCan({
    int channel = 0,
    CanBaudRate baudRate = CanBaudRate.cb125k,
    CanBusMode busMode = CanBusMode.cbmNormal,
  });

  /// 지정된 CAN 채널의 통신을 중단합니다.
  Future<bool> disconnectCan({
    int channel = 0,
  });

  /// 생성된 CAN 프레임 객체를 바이트로 직렬화하여 전송합니다.
  Future<bool> sendFrame(CanSendFrameType frame);

  /// CAN ID와 데이터 페이로드를 전달받아 표준 CAN 메시지를 전송합니다.
  Future<bool> sendCanFrame(
      int id,
      Uint8List data, {
        int channel = 0,
        bool isExtended = true,
      });

  /// 수신할 CAN ID 목록을 지정 채널 필터로 등록합니다.
  void setCanIdFilter(
      int channel,
      Set<int> ids,
      );

  /// 모든 리소스(스트림, 소켓 등)를 해제하고 클라이언트를 종료합니다.
  Future<void> dispose();
}