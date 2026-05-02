import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('NativeBackend PiP channel 协议', () {
    late List<MethodCall> calls;
    const channel = MethodChannel('niuma_player/pip');

    setUp(() {
      calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        switch (call.method) {
          case 'enterPictureInPicture':
            return true;
          case 'exitPictureInPicture':
            return true;
          case 'queryPictureInPictureSupport':
            return true;
        }
        return false;
      });
    });

    tearDown(() {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null);
    });

    test('enterPictureInPicture 不传 textureId（Android Activity 级别）', () async {
      final r = await channel.invokeMethod<bool>('enterPictureInPicture', {
        'aspectNum': 16,
        'aspectDen': 9,
      });
      expect(r, isTrue);
      expect(calls.first.method, 'enterPictureInPicture');
      expect(calls.first.arguments['aspectNum'], 16);
      expect(calls.first.arguments['aspectDen'], 9);
      expect(calls.first.arguments.containsKey('textureId'), isFalse,
          reason: 'Android PiP 是 Activity 级别，不需要 textureId');
    });

    test('exitPictureInPicture 不传参数', () async {
      final r = await channel.invokeMethod<bool>('exitPictureInPicture');
      expect(r, isTrue);
      expect(calls.first.method, 'exitPictureInPicture');
    });

    test('queryPictureInPictureSupport 不传参数', () async {
      final r = await channel.invokeMethod<bool>('queryPictureInPictureSupport');
      expect(r, isTrue);
      expect(calls.first.method, 'queryPictureInPictureSupport');
    });
  });
}
