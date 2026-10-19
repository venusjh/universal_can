import 'package:plugin_platform_interface/plugin_platform_interface.dart';

import 'universal_can_method_channel.dart';

abstract class UniversalCanPlatform extends PlatformInterface {
  /// Constructs a UniversalCanPlatform.
  UniversalCanPlatform() : super(token: _token);

  static final Object _token = Object();

  static UniversalCanPlatform _instance = MethodChannelUniversalCan();

  /// The default instance of [UniversalCanPlatform] to use.
  ///
  /// Defaults to [MethodChannelUniversalCan].
  static UniversalCanPlatform get instance => _instance;

  /// Platform-specific implementations should set this with their own
  /// platform-specific class that extends [UniversalCanPlatform] when
  /// they register themselves.
  static set instance(UniversalCanPlatform instance) {
    PlatformInterface.verifyToken(instance, _token);
    _instance = instance;
  }

  Future<String?> getPlatformVersion() {
    throw UnimplementedError('platformVersion() has not been implemented.');
  }
}
