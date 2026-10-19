export 'client/can_client.dart';
export 'client/can_protocol_client.dart';
export 'client/serial_can_client.dart';
export 'client/bluetooth_can_client.dart';
export 'parser/can_parser.dart';
export 'parser/crc8.dart';
export 'model/can_frame.dart';

import 'universal_can_platform_interface.dart';

class UniversalCan {
  Future<String?> getPlatformVersion() {
    return UniversalCanPlatform.instance.getPlatformVersion();
  }
}
