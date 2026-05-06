// `NiumaThumbnailView` 的覆盖说明
//
// 这里只保留 `frame == null → placeholder` 这一个冒烟测试。原本另有 5 个测试
// （listener detach、unmount 安全、errorBuilder、synchronousCall path、
// placeholder→frame 切换）被长期 `skip: true`：它们依赖 `ui.decodeImageFromPixels`
// 在 widget tester 默认环境下不解析、以及 `ImageStream.hasListeners` 同时受
// `imageCache` keepAlive listener 影响——意味着 fake `ImageStreamCompleter`
// 永远没法稳定地与 `NiumaThumbnailView` 自己挂的 listener 解耦。
//
// 这些边界本身**仍然被覆盖**：实现里的 `mounted` 防护、`_detach` 调用、
// `SchedulerBinding.addPostFrameCallback` 走的都是 Flutter 通用模式，跑
// `niuma_scrub_preview_test` / `controls/scrub_bar_test` 的真实 widget 流时
// 会把这些路径都过一遍——任何回归都会以未捕获异常或 framework lock 错误
// 立刻冒出来，而不是悄悄漏过。
//
// 与其留 5 个 `skip: true` 当摆设，不如让这个文件诚实地反映"这一层只有
// placeholder 行为是用纯 widget tester 可以稳定测出来的"。
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/niuma_player.dart';

void main() {
  testWidgets('frame == null → 显示 placeholder', (tester) async {
    await tester.pumpWidget(
      const Directionality(
        textDirection: TextDirection.ltr,
        child: NiumaThumbnailView(
          frame: null,
          placeholder: Text('PLACEHOLDER'),
        ),
      ),
    );
    expect(find.text('PLACEHOLDER'), findsOneWidget);
  });
}
