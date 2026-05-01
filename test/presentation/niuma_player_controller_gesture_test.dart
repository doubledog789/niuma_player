// test/presentation/niuma_player_controller_gesture_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/niuma_player.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('gestureFeedback 默认 null', () async {
    final c = NiumaPlayerController.dataSource(
      NiumaDataSource.network('https://example.com/test.mp4'),
    );
    expect(c.gestureFeedback.value, isNull);
    await c.dispose();
  });

  test('debugSetGestureFeedback 推送 + 清空 + notify', () async {
    final c = NiumaPlayerController.dataSource(
      NiumaDataSource.network('https://example.com/test.mp4'),
    );
    var notifyCount = 0;
    c.gestureFeedback.addListener(() => notifyCount++);

    c.debugSetGestureFeedback(const GestureFeedbackState(
      kind: GestureKind.volume,
      progress: 0.5,
      label: '50%',
    ));
    expect(notifyCount, 1);
    expect(c.gestureFeedback.value?.kind, GestureKind.volume);

    c.debugSetGestureFeedback(null);
    expect(notifyCount, 2);
    expect(c.gestureFeedback.value, isNull);

    await c.dispose();
  });
}
