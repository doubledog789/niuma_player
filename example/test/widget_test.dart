import 'package:flutter_test/flutter_test.dart';

import 'package:niuma_player_example/main.dart';

void main() {
  testWidgets('example app boots', (WidgetTester tester) async {
    await tester.pumpWidget(const NiumaPlayerExampleApp());
    expect(find.text('niuma_player example'), findsOneWidget);
  });
}
