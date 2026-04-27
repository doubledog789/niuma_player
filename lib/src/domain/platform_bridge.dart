/// Thin indirection over `dart:io` Platform / `kIsWeb` and the native device
/// fingerprint lookup. Exists so tests can inject fakes without dragging in
/// dart:io.
abstract class PlatformBridge {
  /// True on iOS. Drives "use video_player → AVPlayer" routing.
  bool get isIOS;

  /// True when running in a browser. Drives "use video_player → <video>"
  /// routing (with hls.js dropped in by `video_player_web_hls` for HLS).
  bool get isWeb;

  /// SHA-1 fingerprint of the current device. Identical hardware/software
  /// shape returns the same fingerprint, so it can be used as a key in
  /// `DeviceMemoryStore`.
  Future<String> deviceFingerprint();
}
