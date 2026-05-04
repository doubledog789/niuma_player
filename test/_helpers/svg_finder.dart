// Test-only finder helpers for SVG-based niuma controls.
//
// 控件从 Material Icon 迁到 NiumaSdkIcon 后，旧 `find.byIcon(Icons.X)` 不
// 再适用。提供 [findNiumaIcon] 替代——按 [NiumaSdkIcon.asset] 路径查找。

import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/src/presentation/controls/niuma_sdk_icon.dart';

/// 找到第一个 [NiumaSdkIcon]，其 `asset` 字段等于 [assetPath]。
///
/// ```dart
/// expect(findNiumaIcon(NiumaSdkAssets.icPlay), findsOneWidget);
/// ```
Finder findNiumaIcon(String assetPath) {
  return find.byWidgetPredicate(
    (w) => w is NiumaSdkIcon && w.asset == assetPath,
    description: 'NiumaSdkIcon(asset: $assetPath)',
  );
}
