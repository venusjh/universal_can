import 'dart:async';
import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:flutter/services.dart';

import 'can_client.dart';
import 'can_protocol_client.dart';
import '../model/can_frame.dart';

class SerialCanClient implements CanClient, CanTransport {
  // ===========================================================================
  // Private Variables
  // ===========================================================================
  String _rxBuffer = '';
  bool _connected = false;

  static const MethodChannel _channel = MethodChannel('universal_can');
  static const EventChannel _dataChannel = EventChannel('universal_can/data');

  final _dataController = StreamController<Uint8List>.broadcast();

  /// SLCAN 파싱된 CAN 프레임을 상위로 전달하기 위한 자체 프레임 스트림 컨트롤러
  final _frameController = StreamController<CanDataPackType>.broadcast();

  late final CanProtocolClient _canClient;

  StreamSubscription<dynamic>? _dataSubscription;

  // ===========================================================================
  // Constructors
  // ===========================================================================
  SerialCanClient() {
    _canClient = CanProtocolClient(this);
    _setupDataListener();
  }

  // ===========================================================================
  // CanClient / CanTransport Getters
  // ===========================================================================
  @override
  bool get isConnected => _connected;

  @override
  Stream<Uint8List> get dataStream => _dataController.stream;

  @override
  Stream<CanDataPackType> get frames => _frameController.stream;

  // ===========================================================================
  // Serial Connection Methods
  // ===========================================================================
  @override
  Future<bool> connect([String? portName]) async {
    _connected = false;

    try {
      final result = await _channel.invokeMethod('openSerial');
      // debugPrint('USB Serial 연결 결과: $result');

      if (result == 'USB_DEVICE_READY') {
        _connected = true;
        // 연결 성공 시 리스너가 정상 동작하도록 보장
        _setupDataListener();
        return true;
      }

      debugPrint('[USB 오류] 연결 실패: $result');
      return false;
    } on PlatformException catch (e) {
      debugPrint('USB Serial 연결 실패: ${e.code} ${e.message}');
      return false;
    } catch (e) {
      debugPrint('USB Serial 연결 예외: $e');
      return false;
    }
  }

  @override
  Future<void> disconnect() async {
    if (!_connected) return;

    try {
      await sendCommand('C\r');
    } catch (e) {
      debugPrint('[SLCAN 종료 오류] $e');
    } finally {
      _connected = false;
      _rxBuffer = '';
      // 연결 해제 시 리스너 정리
      await _dataSubscription?.cancel();
      _dataSubscription = null;
    }
  }

  // ===========================================================================
  // CanTransport Interface Implementations
  // ===========================================================================
  @override
  Future<bool> send(Uint8List data) async {
    if (!_connected) {
      return false;
    }

    try {
      final result = await _channel.invokeMethod<int>(
        'writeSerial',
        {
          'data': data,
        },
      );

      return result == data.length;
    } on PlatformException catch (e) {
      debugPrint('USB Serial 전송 실패: ${e.code} ${e.message}');
      return false;
    } catch (e) {
      debugPrint('USB Serial 전송 예외: $e');
      return false;
    }
  }

  // ===========================================================================
  // CanClient Interface Implementations
  // ===========================================================================
  @override
  Future<void> dispose() async {
    await disconnect();

    await _dataSubscription?.cancel();
    _dataSubscription = null;

    await _dataController.close();
    await _frameController.close();
  }

  @override
  Future<bool> sendFrame(CanSendFrameType frame) {
    return _canClient.sendFrame(frame);
  }

  @override
  Future<bool> connectCan({
    int channel = 0,
    CanBaudRate baudRate = CanBaudRate.cb125k,
    CanBusMode busMode = CanBusMode.cbmNormal,
  }) async {
    if (!_connected) return false;

    // CAN 연결 시도 전 리스너가 살아있도록 확실히 보장
    _setupDataListener();

    // 기존 채널 닫기
    final closed = await sendCommand('C\r');
    if (!closed) return false;

    // 동적 보레이트 명령어 전송
    final baudSet = await sendCommand(baudRate.slcanCommand);
    if (!baudSet) return false;

    // 채널 오픈
    return await sendCommand('O\r');
  }

  @override
  Future<bool> disconnectCan({int channel = 0}) async {
    try {
      // CAN 정지 명령어 전송
      final success = await sendCommand('C\r');
      if (success) {
        debugPrint('[SLCAN] CAN 채널 닫힘');
      }

      _rxBuffer = '';

      return success;
    } catch (e) {
      debugPrint('[SLCAN] CAN 채널 닫기 중 예외 발생: $e');
      _rxBuffer = '';
      return false;
    }
  }

  @override
  Future<bool> sendCanFrame(
      int id,
      Uint8List data, {
        int channel = 0,
        bool isExtended = true,
      }) async {
    if (!_connected) {
      debugPrint('[SLCAN TX 오류] USB 미연결');
      return false;
    }

    if (data.length > 8) {
      debugPrint('[SLCAN TX 오류] CAN 데이터는 최대 8바이트');
      return false;
    }

    final maxId = isExtended ? 0x1FFFFFFF : 0x7FF;

    if (id < 0 || id > maxId) {
      debugPrint('[SLCAN TX 오류] 잘못된 CAN ID: $id');
      return false;
    }

    final frameType = isExtended ? 'T' : 't';
    final idLength = isExtended ? 8 : 3;

    final idHex = id.toRadixString(16).toUpperCase().padLeft(
      idLength,
      '0',
    );

    final dlc = data.length.toRadixString(16).toUpperCase();

    final dataHex = data
        .map((byte) => byte.toRadixString(16).toUpperCase().padLeft(2, '0'))
        .join();

    final command = '$frameType$idHex$dlc$dataHex\r';

    return sendCommand(command);
  }

  @override
  void setCanIdFilter(int channel, Set<int> ids) {
    _canClient.setCanIdFilter(channel, ids);
  }

  Future<bool> sendCommand(String command) async {
    final data = Uint8List.fromList(ascii.encode(command));
    return await send(data);
  }

  // ===========================================================================
  // Internal Data Listener & SLCAN ASCII Parsing
  // ===========================================================================
  void _setupDataListener() {
    // 이미 구독 중인 리스너가 있다면 안전하게 해제 (중복 방지)
    _dataSubscription?.cancel();
    _dataSubscription = null;

    // 수신 버퍼 초기화
    _rxBuffer = '';

    _dataSubscription =
        _dataChannel.receiveBroadcastStream().listen(
              (data) {
            final Uint8List bytes;
            if (data is Uint8List) {
              bytes = data;
            } else if (data is List<int>) {
              bytes = Uint8List.fromList(data);
            } else {
              return;
            }

            _dataController.add(bytes);

            _rxBuffer += ascii.decode(bytes, allowInvalid: true);

            while (_rxBuffer.contains('\r')) {
              final crIndex = _rxBuffer.indexOf('\r');
              final packet = _rxBuffer.substring(0, crIndex).trim();
              _rxBuffer = _rxBuffer.substring(crIndex + 1);

              if (packet.isNotEmpty) {
                _parseSlcanPacket(packet);
              }
            }
          },
          onError: (Object error) {
            debugPrint('[SLCAN RX 오류] $error');
          },
        );
  }

  void _parseSlcanPacket(String packet) {
    if (packet.isEmpty) return;

    final type = packet[0];

    if (type != 't' && type != 'T') {
      return;
    }

    final isExtended = type == 'T';
    final idLength = isExtended ? 8 : 3;

    if (packet.length < 1 + idLength + 1) {
      debugPrint('[SLCAN 오류] 헤더 길이 부족: $packet');
      return;
    }

    try {
      final idStr = packet.substring(1, 1 + idLength);
      final dlcStr = packet.substring(1 + idLength, 2 + idLength);

      final id = int.parse(idStr, radix: 16);
      final dlc = int.parse(dlcStr, radix: 16);

      if (dlc < 0 || dlc > 8) {
        debugPrint('[SLCAN 오류] 잘못된 DLC: $packet');
        return;
      }

      final expectedLength = 1 + idLength + 1 + (dlc * 2);

      if (packet.length != expectedLength) {
        debugPrint('[SLCAN 오류] 데이터 길이 불일치: $packet');
        return;
      }

      final dataStr = packet.substring(1 + idLength + 1);
      final dataBytes = Uint8List(dlc);

      for (var i = 0; i < dlc; i++) {
        dataBytes[i] = int.parse(
          dataStr.substring(i * 2, (i * 2) + 2),
          radix: 16,
        );
      }

      final frame = CanDataPackType(
        id: id,
        flagErr: false,
        flagRtr: false,
        flagIde: isExtended,
        timeStamp: 0,
        dlc: dlc,
        channel: 0,
        frameType: 0,
        data: dataBytes,
      );

      _frameController.add(frame);
    } catch (e) {
      debugPrint('[SLCAN 파싱 오류] $packet / $e');
    }
  }
}

// ===========================================================================
// Extensions
// ===========================================================================
extension CanBaudRateExt on CanBaudRate {
  String get slcanCommand {
    switch (this) {
      case CanBaudRate.cb100k: return 'S3\r';
      case CanBaudRate.cb125k: return 'S4\r';
      case CanBaudRate.cb250k: return 'S5\r';
      case CanBaudRate.cb500k: return 'S6\r';
      case CanBaudRate.cb1000k: return 'S8\r';
    }
  }
}