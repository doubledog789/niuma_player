// NiumaCapabilities.supportsHevc()（io 实现）：Android 走 system channel、
// 结果缓存、channel 缺失/异常时安全返回 false。
//
// 注意：VM 测试跑在宿主 mac 上，Platform.isIOS == false → 走 Android 分支
// （invokeMethod），正好可以用 mock handler 驱动。
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/niuma_player.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('niuma_player/system');
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
  });

  test('Android 分支走 supportsHevcDecoder 且缓存结果', () async {
    var calls = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      expect(call.method, 'supportsHevcDecoder');
      calls++;
      return true;
    });
    expect(await NiumaCapabilities.supportsHevc(), isTrue);
    expect(await NiumaCapabilities.supportsHevc(), isTrue);
    expect(calls, 1, reason: '第二次应命中进程内缓存，不再走 channel');
  });
}
