import 'dart:io' show Platform;

import '../domain/platform_bridge.dart';
import 'ijk_backend.dart';

/// Production [PlatformBridge]. On iOS we bypass the Android channel entirely
/// and synthesize a fingerprint from `Platform.operatingSystemVersion`. On
/// Android we forward to [IjkBackend.fetchDeviceFingerprint].
class DefaultPlatformBridge implements PlatformBridge {
  const DefaultPlatformBridge();

  @override
  bool get isIOS => Platform.isIOS;

  @override
  Future<String> deviceFingerprint() async {
    if (Platform.isIOS) {
      return 'ios-${Platform.operatingSystemVersion}';
    }
    final fp = await IjkBackend.fetchDeviceFingerprint();
    return fp ?? 'unknown';
  }
}
