import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/niuma_player.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('protocolId 是 airplay', () {
    expect(AirPlayCastService().protocolId, 'airplay');
  });

  testWidgets('discover 在测试环境（非 iOS）yield 空列表', (tester) async {
    final svc = AirPlayCastService();
    final batches = await svc.discover().toList();
    expect(batches.length, 1);
    expect(batches.first, isEmpty);
  });
}
