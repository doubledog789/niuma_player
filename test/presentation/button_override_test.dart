import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/src/presentation/control_bar/button_override.dart';

void main() {
  test('ButtonOverride.builder 是 BuilderOverride', () {
    final o = ButtonOverride.builder((ctx) => const SizedBox());
    expect(o, isA<BuilderOverride>());
  });

  test('ButtonOverride.fields 是 FieldsOverride 并保留传入字段', () {
    final o = ButtonOverride.fields(
      icon: const Icon(Icons.cast),
      label: '投屏',
      onTap: () {},
    );
    expect(o, isA<FieldsOverride>());
    expect((o as FieldsOverride).label, '投屏');
    expect(o.icon, isA<Icon>());
    expect(o.onTap, isNotNull);
  });
}
