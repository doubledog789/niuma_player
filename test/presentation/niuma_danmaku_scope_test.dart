import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/src/presentation/danmaku/niuma_danmaku_controller.dart';
import 'package:niuma_player/src/presentation/danmaku/niuma_danmaku_scope.dart';

var _notifyCount = 0;

Widget _buildWithNotification(BuildContext ctx) {
  NiumaDanmakuScope.maybeOf(ctx);
  _notifyCount++;
  return const SizedBox();
}

void main() {
  testWidgets('maybeOf 找到注入的 controller', (tester) async {
    final ctl = NiumaDanmakuController();
    NiumaDanmakuController? found;
    await tester.pumpWidget(NiumaDanmakuScope(
      controller: ctl,
      child: Builder(builder: (ctx) {
        found = NiumaDanmakuScope.maybeOf(ctx);
        return const SizedBox();
      }),
    ));
    expect(found, same(ctl));
    ctl.dispose();
  });

  testWidgets('无 scope 时 maybeOf 返回 null', (tester) async {
    NiumaDanmakuController? found;
    await tester.pumpWidget(Builder(builder: (ctx) {
      found = NiumaDanmakuScope.maybeOf(ctx);
      return const SizedBox();
    }));
    expect(found, isNull);
  });

  testWidgets('updateShouldNotify 仅在 controller 实例变化时为真',
      (tester) async {
    final c1 = NiumaDanmakuController();
    final c2 = NiumaDanmakuController();
    _notifyCount = 0;
    const child = Builder(builder: _buildWithNotification);

    await tester.pumpWidget(NiumaDanmakuScope(
      controller: c1,
      child: child,
    ));
    expect(_notifyCount, 1);

    await tester.pumpWidget(NiumaDanmakuScope(
      controller: c1,
      child: child,
    ));
    expect(_notifyCount, 1, reason: '同 controller 不应重建依赖');

    await tester.pumpWidget(NiumaDanmakuScope(
      controller: c2,
      child: child,
    ));
    expect(_notifyCount, 2);

    c1.dispose();
    c2.dispose();
  });
}
