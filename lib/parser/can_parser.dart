import 'dart:typed_data';

import '../model/can_frame.dart';
import 'crc8.dart';

/// Parser class for parsing and filtering received CAN bus packets
class CanParser {
  // ===========================================================================
  // Constants
  // ===========================================================================
  /// Fixed size (Byte) of one CAN frame
  static const int frameSize = 16;

  /// Maximum buffer size allowed (clean up old data if exceeded)
  static const int maxBufferSize = 2048;

  /// Size of data to retain when cleaning up buffer overflow
  static const int keepBufferSize = 512;

  // ===========================================================================
  // State Variables
  // ===========================================================================
  /// Byte buffer for parsing received packets
  final List<int> _buffer = [];

  /// Channel-specific CAN ID Filter Map (Key: Channel, Value: ID Set)
  final Map<int, Set<int>> _canIdFilters = {};

  /// Reference time (stores the time of the first frame reception)
  DateTime? _currentTime;

  /// Timestamp offset value of the first frame
  int _timeOffset = 0;

  /// 16-bit timestamp overflow counter
  int _timeStampHighByte = 0;

  /// Raw timestamp value of the previous frame (for overflow detection)
  int _bTimeStamp = 0;

  // ===========================================================================
  // Public Methods
  // ===========================================================================
  /// Sets the CAN ID filter for the specified channel.
  void setCanIdFilter(int channel, Set<int> ids) {
    _canIdFilters[channel] = Set<int>.from(ids);
  }

  /// Initializes the parser's internal buffer and timestamp-related state.
  void reset() {
    _buffer.clear();
    _currentTime = null;
    _timeOffset = 0;
    _timeStampHighByte = 0;
    _bTimeStamp = 0;
  }

  /// Adds received byte data to a buffer, parses a valid CAN frame, and returns it.
  List<CanDataPackType> add(Uint8List data) {
    final frames = <CanDataPackType>[];

    // Accumulate received data buffer
    _buffer.addAll(data);

    // Prevent buffer overflow (delete old data when maximum size is exceeded)
    if (_buffer.length > maxBufferSize) {
      _buffer.removeRange(
        0,
        _buffer.length - keepBufferSize,
      );
    }

    // Repeated parsing while the buffer is filled to the minimum frame size
    while (_buffer.length >= frameSize) {
      final frameBytes = Uint8List.fromList(
        _buffer.sublist(0, frameSize),
      );

      // CRC8 verification
      final checkSum = Crc8.calculate(frameBytes);

      // Retry synchronization by 1 byte on CRC mismatch
      if (checkSum != frameBytes[0]) {
        _buffer.removeAt(0);
        continue;
      }

      // Initial reference time setting
      if (_currentTime == null) {
        _currentTime = DateTime.now();

        _timeOffset = ByteData.sublistView(
          frameBytes,
        ).getUint16(2, Endian.little);

        _timeStampHighByte = 0;
        _bTimeStamp = _timeOffset;
      }

      // Timestamp calculation and overflow detection
      final rawTimeStamp = ByteData.sublistView(
        frameBytes,
      ).getUint16(2, Endian.little);

      if (_bTimeStamp > rawTimeStamp) {
        _timeStampHighByte++;
      }

      _bTimeStamp = rawTimeStamp;

      // Creation of parsed data objects and buffer consumption
      final frame = CanDataPackType.fromRawBytes(
        frameBytes,
        timeOffset: _timeOffset,
        timeStampHighByte: _timeStampHighByte,
      );
      _buffer.removeRange(0, frameSize);

      // After filtering by CAN ID, add only frames that meet the criteria to the result
      final filter = _canIdFilters[frame.channel] ?? <int>{};

      if (filter.isEmpty || filter.contains(frame.id)) {
        frames.add(frame);
      }
    }

    return frames;
  }
}