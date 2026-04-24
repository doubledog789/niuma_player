/// Thin indirection over `dart:io` Platform and the native device
/// fingerprint lookup. Exists so state-machine tests can inject fakes.
abstract class PlatformBridge {
  bool get isIOS;
  Future<String> deviceFingerprint();
}
