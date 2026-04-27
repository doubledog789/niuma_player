import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// In-memory fake of the native `cn.niuma/player` channel's `deviceMemory.*`
/// surface. Tests use [install] in setUp and [uninstall] in tearDown to
/// stand in for the real Android plugin without touching SharedPreferences.
///
/// Storage shape mirrors the wire protocol:
///   - absent key  ↔  fingerprint never marked
///   - value `null` ↔  marked, no expiry
///   - value `int`  ↔  expiresAt epoch-ms
class FakeDeviceMemoryChannel {
  FakeDeviceMemoryChannel._();

  /// Underlying store. Exposed only for assertions in tests that need to
  /// inspect persistence side-effects directly; most tests should drive
  /// state through [DeviceMemory] instead.
  final Map<String, int?> store = <String, int?>{};

  /// `true` once an entry was present and we let it through; tests can read
  /// this to assert "the channel was actually called".
  bool get isInstalled => _installed;
  bool _installed = false;

  static FakeDeviceMemoryChannel install() {
    final fake = FakeDeviceMemoryChannel._();
    TestWidgetsFlutterBinding.ensureInitialized();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('cn.niuma/player'),
      fake._handle,
    );
    fake._installed = true;
    return fake;
  }

  void uninstall() {
    if (!_installed) return;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('cn.niuma/player'),
      null,
    );
    _installed = false;
  }

  Future<Object?> _handle(MethodCall call) async {
    switch (call.method) {
      case 'deviceMemory.get':
        final fp = (call.arguments as Map)['fingerprint'] as String;
        if (!store.containsKey(fp)) return null;
        return <String, dynamic>{'expiresAt': store[fp]};
      case 'deviceMemory.set':
        final args = call.arguments as Map;
        final fp = args['fingerprint'] as String;
        store[fp] = (args['expiresAt'] as num?)?.toInt();
        return null;
      case 'deviceMemory.unset':
        final fp = (call.arguments as Map)['fingerprint'] as String;
        store.remove(fp);
        return null;
      case 'deviceMemory.clear':
        store.clear();
        return null;
    }
    return null;
  }
}
