import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'universal_can_platform_interface.dart';

/// An implementation of [UniversalCanPlatform] that uses method channels.
class MethodChannelUniversalCan extends UniversalCanPlatform {
  /// The method channel used to interact with the native platform.
  @visibleForTesting
  final methodChannel = const MethodChannel('universal_can');

  @override
  Future<String?> getPlatformVersion() async {
    final version = await methodChannel.invokeMethod<String>(
      'getPlatformVersion',
    );
    return version;
  }
}
