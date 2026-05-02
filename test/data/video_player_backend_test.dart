import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('VideoPlayerBackend PiP channel 协议', () {
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

    test('enterPictureInPicture 调 channel 带 textureId / aspectNum / aspectDen', () async {
      final r = await channel.invokeMethod<bool>('enterPictureInPicture', {
        'textureId': 7,
        'aspectNum': 16,
        'aspectDen': 9,
      });
      expect(r, isTrue);
      expect(calls, hasLength(1));
      expect(calls.first.method, 'enterPictureInPicture');
      expect(calls.first.arguments['textureId'], 7);
      expect(calls.first.arguments['aspectNum'], 16);
      expect(calls.first.arguments['aspectDen'], 9);
    });

    test('exitPictureInPicture 不传参数', () async {
      final r = await channel.invokeMethod<bool>('exitPictureInPicture');
      expect(r, isTrue);
      expect(calls, hasLength(1));
      expect(calls.first.method, 'exitPictureInPicture');
    });

    test('queryPictureInPictureSupport 不传参数', () async {
      final r = await channel.invokeMethod<bool>('queryPictureInPictureSupport');
      expect(r, isTrue);
      expect(calls.first.method, 'queryPictureInPictureSupport');
    });
  });
}
