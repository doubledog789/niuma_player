import 'package:flutter_test/flutter_test.dart';

import 'package:niuma_player_example/main.dart';

void main() {
  testWidgets('example app boots', (WidgetTester tester) async {
    await tester.pumpWidget(const NiumaPlayerExampleApp());
    // 启动先走 NiumaSplashScreen（1200ms 后 push 进首页）；pump 过这段动画
    // 后应落到 _Home，AppBar 标题 'niuma_player' 可见——参考皮迁出后首页
    // 依旧正常启动的 smoke 断言。
    await tester.pump(const Duration(milliseconds: 1500));
    await tester.pumpAndSettle();
    expect(find.text('niuma_player'), findsOneWidget);
  });
}
