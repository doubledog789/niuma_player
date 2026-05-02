import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/src/domain/gesture_kind.dart';

void main() {
  test('GestureKind 5 值齐全', () {
    expect(GestureKind.values, hasLength(5));
    expect(GestureKind.values, containsAll([
      GestureKind.doubleTap,
      GestureKind.horizontalSeek,
      GestureKind.brightness,
      GestureKind.volume,
      GestureKind.longPressSpeed,
    ]));
  });
}
