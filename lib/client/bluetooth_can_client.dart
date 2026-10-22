import 'dart:typed_data';
import 'package:flutter_bluetooth_serial_ble/flutter_bluetooth_serial_ble.dart';

import 'can_client.dart';
import 'can_protocol_client.dart';
import '../model/can_frame.dart';

/// [CanClient] 및 [CanTransport] 인터페이스를 구현하는 블루투스 기반 CAN 클라이언트
class BluetoothCanClient implements CanClient, CanTransport {
  // ===========================================================================
  // Private Variables
  // ===========================================================================
  /// 블루투스 시리얼 연결 객체
  BluetoothConnection? _connection;

  /// CAN 프로토콜 파싱 및 제어를 담당하는 클라이언트
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
  /// CAN 클라이언트의 현재 연결 상태
  @override
  bool get isConnected => _connection != null;

  /// 파싱 완료된 CAN 데이터 프레임 스트림
  @override
  Stream<CanDataPackType> get frames => _canClient.frames;

  /// 블루투스 수신 Raw 바이트 데이터 스트림
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
  /// 지정된 MAC 주소(또는 포트 정보)로 블루투스 연결을 시도하고 수신 리스닝을 시작합니다.
  @override
  Future<bool> connect([String? address]) async {
    if (isConnected) {
      return false;
    }

    if (address == null || address.isEmpty) {
      return false; // 블루투스는 연결 주소가 필수적입니다.
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

  /// 블루투스 및 CAN 클라이언트 연결을 해제합니다.
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
  /// 블루투스 시리얼을 통해 Raw 바이트 데이터를 전송합니다.
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
  /// 모든 리소스 및 연결을 해제합니다.
  @override
  Future<void> dispose() async {
    await disconnect();
    await _canClient.dispose();
  }

  /// CAN 전송 프레임 객체를 통해 데이터를 전송합니다.
  @override
  Future<bool> sendFrame(CanSendFrameType frame) {
    return _canClient.sendFrame(frame);
  }

  /// CAN 통신 연결 및 설정(채널, 보레이트, 동작 모드)을 수행합니다.
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

  /// 지정 채널의 CAN 통신을 중단합니다.
  @override
  Future<bool> disconnectCan({
    int channel = 0,
  }) {
    return _canClient.disconnectCan(
      channel: channel,
    );
  }

  /// CAN ID와 데이터 배열을 지정하여 CAN 메시지를 전송합니다.
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

  /// 수신 필터링할 CAN ID 목록을 등록합니다.
  @override
  void setCanIdFilter(int channel, Set<int> ids) {
    _canClient.setCanIdFilter(channel, ids);
  }
}