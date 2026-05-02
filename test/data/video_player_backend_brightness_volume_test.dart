import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('niuma_player/system channel 协议', () {
    late List<MethodCall> calls;
    const channel = MethodChannel('niuma_player/system');

    setUp(() {
      calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        switch (call.method) {
          case 'getBrightness':
            return 0.6;
          case 'setBrightness':
            return true;
          case 'getSystemVolume':
            return 0.4;
          case 'setSystemVolume':
            return true;
        }
        return null;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('getBrightness 返当前值', () async {
      final r = await channel.invokeMethod<double>('getBrightness');
      expect(r, 0.6);
      expect(calls.first.method, 'getBrightness');
    });

    test('setBrightness 传 value 参数', () async {
      final r = await channel.invokeMethod<bool>('setBrightness', {'value': 0.8});
      expect(r, isTrue);
      expect(calls.first.arguments['value'], 0.8);
    });

    test('getSystemVolume / setSystemVolume 同协议', () async {
      await channel.invokeMethod<double>('getSystemVolume');
      await channel.invokeMethod<bool>('setSystemVolume', {'value': 0.3});
      expect(calls, hasLength(2));
      expect(calls[1].arguments['value'], 0.3);
    });
  });
}
