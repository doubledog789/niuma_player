import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;

import '../domain/platform_bridge.dart';
import 'native_backend.dart';

/// Production [PlatformBridge].
///
/// On iOS / Web we synthesize a fingerprint from the SDK side instead of
/// hitting the Android plugin (which doesn't exist on those platforms).
/// On Android we forward to [NativeBackend.fetchDeviceFingerprint].
class DefaultPlatformBridge implements PlatformBridge {
  const DefaultPlatformBridge();

  @override
  bool get isIOS {
    // On Web, dart:io's Platform getters throw; gate behind kIsWeb first.
    if (kIsWeb) return false;
    return Platform.isIOS;
  }

  @override
  bool get isWeb => kIsWeb;

  @override
  Future<String> deviceFingerprint() async {
    if (kIsWeb) return 'web';
    if (Platform.isIOS) {
      return 'ios-${Platform.operatingSystemVersion}';
    }
    final fp = await NativeBackend.fetchDeviceFingerprint();
    return fp ?? 'unknown';
  }
}
