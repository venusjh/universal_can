import 'dart:typed_data';

import '../model/can_frame.dart';
import 'crc8.dart';

/// CAN 버스 수신 패킷을 파싱하고 필터링하는 파서 클래스
class CanParser {
  // ===========================================================================
  // Constants
  // ===========================================================================
  /// CAN 프레임 1개의 고정 크기 (Byte)
  static const int frameSize = 16;

  /// 버퍼 최대 허용 크기 (초과 시 오래된 데이터 정리)
  static const int maxBufferSize = 2048;

  /// 버퍼 초과 정리 시 남겨둘 데이터 크기
  static const int keepBufferSize = 512;

  // ===========================================================================
  // State Variables
  // ===========================================================================
  /// 수신 패킷 파싱용 바이트 버퍼
  final List<int> _buffer = [];

  /// 채널별 CAN ID 필터 맵 (Key: Channel, Value: ID Set)
  final Map<int, Set<int>> _canIdFilters = {};

  /// 기준 시간 (최초 프레임 수신 시점 저장)
  DateTime? _currentTime;

  /// 최초 프레임의 타임스탬프 오프셋값
  int _timeOffset = 0;

  /// 16bit 타임스탬프 오버플로우 발생 횟수 카운터
  int _timeStampHighByte = 0;

  /// 이전 프레임의 Raw 타임스탬프값 (오버플로우 감지용)
  int _bTimeStamp = 0;

  // ===========================================================================
  // Public Methods
  // ===========================================================================
  /// 지정된 채널에 대한 CAN ID 필터를 설정합니다.
  void setCanIdFilter(int channel, Set<int> ids) {
    _canIdFilters[channel] = Set<int>.from(ids);
  }

  /// 파서의 내부 버퍼 및 타임스탬프 관련 상태를 초기화합니다.
  void reset() {
    _buffer.clear();
    _currentTime = null;
    _timeOffset = 0;
    _timeStampHighByte = 0;
    _bTimeStamp = 0;
  }

  /// 수신된 바이트 데이터를 버퍼에 추가하고, 유효한 CAN 프레임을 파싱하여 반환합니다.
  List<CanDataPackType> add(Uint8List data) {
    final frames = <CanDataPackType>[];

    // 수신 데이터 버퍼 축적
    _buffer.addAll(data);

    // 버퍼 오버플로우 방지 (최대 크기 초과 시 오래된 데이터 삭제)
    if (_buffer.length > maxBufferSize) {
      _buffer.removeRange(
        0,
        _buffer.length - keepBufferSize,
      );
    }

    // 최소 프레임 크기만큼 버퍼가 채워진 동안 반복 파싱
    while (_buffer.length >= frameSize) {
      final frameBytes = Uint8List.fromList(
        _buffer.sublist(0, frameSize),
      );

      // CRC8 검증
      final checkSum = Crc8.calculate(frameBytes);

      // CRC 불일치 시 1바이트 동기화 재시도
      if (checkSum != frameBytes[0]) {
        _buffer.removeAt(0);
        continue;
      }

      // 최초 기준 시간 설정
      if (_currentTime == null) {
        _currentTime = DateTime.now();

        _timeOffset = ByteData.sublistView(
          frameBytes,
        ).getUint16(2, Endian.little);

        _timeStampHighByte = 0;
        _bTimeStamp = _timeOffset;
      }

      // 타임스탬프 계산 및 오버플로우 감지
      final rawTimeStamp = ByteData.sublistView(
        frameBytes,
      ).getUint16(2, Endian.little);

      if (_bTimeStamp > rawTimeStamp) {
        _timeStampHighByte++;
      }

      _bTimeStamp = rawTimeStamp;

      // 파싱 완료된 데이터 객체 생성 및 버퍼 소모
      final frame = CanDataPackType.fromRawBytes(
        frameBytes,
        timeOffset: _timeOffset,
        timeStampHighByte: _timeStampHighByte,
      );
      _buffer.removeRange(0, frameSize);

      // CAN ID 필터링 후 조건에 맞는 프레임만 결과에 추가
      final filter = _canIdFilters[frame.channel] ?? <int>{};

      if (filter.isEmpty || filter.contains(frame.id)) {
        frames.add(frame);
      }
    }

    return frames;
  }
}