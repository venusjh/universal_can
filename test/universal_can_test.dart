import 'package:flutter_test/flutter_test.dart';
import 'package:universal_can/universal_can.dart';
import 'package:universal_can/universal_can_platform_interface.dart';
import 'package:universal_can/universal_can_method_channel.dart';
import 'package:plugin_platform_interface/plugin_platform_interface.dart';

class MockUniversalCanPlatform
    with MockPlatformInterfaceMixin
    implements UniversalCanPlatform {
  @override
  Future<String?> getPlatformVersion() => Future.value('42');
}

void main() {
  final UniversalCanPlatform initialPlatform = UniversalCanPlatform.instance;

  test('$MethodChannelUniversalCan is the default instance', () {
    expect(initialPlatform, isInstanceOf<MethodChannelUniversalCan>());
  });

  test('getPlatformVersion', () async {
    UniversalCan universalCanPlugin = UniversalCan();
    MockUniversalCanPlatform fakePlatform = MockUniversalCanPlatform();
    UniversalCanPlatform.instance = fakePlatform;

    expect(await universalCanPlugin.getPlatformVersion(), '42');
  });
}
