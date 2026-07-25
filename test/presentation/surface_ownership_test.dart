import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:niuma_player/src/player/surface_ownership.dart';

Widget _gate(Object owner, String label) {
  return ExclusiveSurfaceGate(
    key: ValueKey<String>(label),
    owner: owner,
    builder: (_) => Text(label, textDirection: TextDirection.ltr),
    placeholder: const SizedBox.shrink(),
  );
}

Widget _host(List<Widget> children) {
  return Directionality(
    textDirection: TextDirection.ltr,
    child: Column(children: children),
  );
}

void main() {
  testWidgets('后 mount 的 gate 抢占，先 mount 的让出', (tester) async {
    final owner = Object();

    await tester.pumpWidget(_host([_gate(owner, 'inline')]));
    expect(find.text('inline'), findsOneWidget);

    await tester.pumpWidget(_host([
      _gate(owner, 'inline'),
      _gate(owner, 'fullscreen'),
    ]));
    await tester.pump();

    expect(find.text('fullscreen'), findsOneWidget);
    expect(find.text('inline'), findsNothing);
  });

  testWidgets('活跃 gate unmount 后，仍存活的上一个重新抢回', (tester) async {
    final owner = Object();

    await tester.pumpWidget(_host([_gate(owner, 'inline')]));
    await tester.pumpWidget(_host([
      _gate(owner, 'inline'),
      _gate(owner, 'fullscreen'),
    ]));
    await tester.pump();
    expect(find.text('inline'), findsNothing);

    await tester.pumpWidget(_host([_gate(owner, 'inline')]));
    await tester.pump();

    expect(find.text('inline'), findsOneWidget);
  });

  testWidgets('反复进出全屏，inline 每次都能拿回所有权', (tester) async {
    final owner = Object();
    await tester.pumpWidget(_host([_gate(owner, 'inline')]));

    for (var i = 0; i < 5; i++) {
      await tester.pumpWidget(_host([
        _gate(owner, 'inline'),
        _gate(owner, 'fullscreen'),
      ]));
      await tester.pump();
      expect(find.text('fullscreen'), findsOneWidget);
      expect(find.text('inline'), findsNothing);

      await tester.pumpWidget(_host([_gate(owner, 'inline')]));
      await tester.pump();
      expect(find.text('inline'), findsOneWidget);
    }
  });

  testWidgets('不同 owner 各自独立，互不抢占', (tester) async {
    final a = Object();
    final b = Object();

    await tester.pumpWidget(_host([_gate(a, 'a'), _gate(b, 'b')]));
    await tester.pump();

    expect(find.text('a'), findsOneWidget);
    expect(find.text('b'), findsOneWidget);
  });

  testWidgets('owner 换绑：旧 owner 归还给上一个，新 owner 立即抢占', (tester) async {
    final a = Object();
    final b = Object();

    await tester.pumpWidget(_host([
      _gate(a, 'a-inline'),
      ExclusiveSurfaceGate(
        key: const ValueKey<String>('mover'),
        owner: a,
        builder: (_) => const Text('mover', textDirection: TextDirection.ltr),
        placeholder: const SizedBox.shrink(),
      ),
    ]));
    await tester.pump();
    expect(find.text('a-inline'), findsNothing);

    await tester.pumpWidget(_host([
      _gate(a, 'a-inline'),
      ExclusiveSurfaceGate(
        key: const ValueKey<String>('mover'),
        owner: b,
        builder: (_) => const Text('mover', textDirection: TextDirection.ltr),
        placeholder: const SizedBox.shrink(),
      ),
    ]));
    await tester.pump();

    expect(find.text('a-inline'), findsOneWidget);
    expect(find.text('mover'), findsOneWidget);
  });
}
