# niuma_player Headless 化迁移计划

> **For Claude:** 执行时用 flutter-craft:flutter-executing(批量)或 flutter-craft:flutter-subagent-dev(逐任务子代理)。这是**架构迁移**,不是新 feature——按"先建 headless 核 → 瘦 barrel → 搬 chrome → 接 example → 发版"的阶段推进,每阶段 `flutter analyze && flutter test` 双绿 + `cd example && flutter analyze` 通过才算完成。

**目标:** 把 `niuma_player` 从"开箱即用的播放器 + UI"重定位为 **headless 播放能力底座**;唯一稳定 API 是 controller + 纯逻辑;`example/` 成为一套可拷贝、可丢弃、不进 semver 契约的官方参考皮。

**定位决策(已与刀盾大哥确认):**
- 路线 = 核 + 可拷贝参考 UI(非分包、非全 headless 裸核、非 mason)
- 逻辑进核(import、保 semver),chrome 进模板(随便改、不保契约)
- **留核**:controller / backends / platform_bridge / 全部 orchestration / 手势→意图映射 + 自动隐藏计时(headless)/ 全屏编排(headless controller)/ 弹幕引擎(轨道/bucket/调度)
- **进 example 模板**:NiumaPlayer 一体化 widget / 22 原子控件 / control_bar / fullscreen 页面 / feedback / short_video / shared / 主题系统 / gesture HUD widget / 弹幕渲染 widget+面板 / **cast 整块(含 DLNA/AirPlay 协议)** / **广告整块** / **缩略图整块**
- 交付 = 接入方从 `example/lib/` 拷文件,README 指明拷哪些
- 代价已认账:接入方要 cast 就得拷 DLNA SSDP/SOAP 9 文件自己维护;cast/广告/缩略图视为可选附加、非核心播放能力
- 版本:`0.0.4 → 0.1.0`,大 BREAKING;orphaned 的 airplay/dlna sibling 包维持死亡

**Architecture:** Clean Architecture 边界不变(domain/data/orchestration 纯 Dart 可测),只是把 presentation/ 的 chrome 整体移出 `lib/`。

---

## 边界清单(核 vs 模板)— 迁移的事实依据

### 留在 `lib/src/`(headless 核,继续 export)

| 目录 | 文件 | 说明 |
|---|---|---|
| data/ | 全部(backends / platform_bridge / device_memory / hls_detect / native_backend / web_video_backend / _pip_event_bus) | 无 chrome |
| domain/ | backend_factory / data_source / platform_bridge / player_backend / player_state / gesture_kind / gesture_feedback_state | 接口 + 值对象 |
| orchestration/ | **全部 11 个**(multi_source / resume_position / retry_policy / source_middleware / thumbnail_track / webvtt_parser / auto_failover / danmaku_models / danmaku_bucket_loader / danmaku_track_allocator) | 已纯 Dart |
| observability/ | analytics_event / analytics_emitter | 纯逻辑 |
| testing/ | fake_analytics_emitter / fake_resume_storage | 测试 fake |
| presentation/core/ | **niuma_player_controller.dart**(已无 material)/ niuma_player_view.dart(裸 render 面)/ pip_lifecycle_observer.dart(生命周期逻辑) | 验证过不依赖 material |
| presentation/danmaku/ | **niuma_danmaku_controller.dart**(已无 material) | 弹幕引擎入口 |
| 根 | niuma_sdk_assets.dart | 资源常量 |
| **新增** | gesture/niuma_gesture_controller.dart(Task 1)/ fullscreen/niuma_fullscreen_controller.dart(Task 2) | 从 widget 剥出的 headless 逻辑 |

### 搬到 `example/lib/niuma_ui/`(可拷贝模板,移出 lib/、移出 barrel)

`presentation/` 下其余全部 + cast/(协议+UI 整块)。逐文件清单见 Phase 3 / Phase 4。

> **判定规则**:文件 import `package:flutter/material.dart` 或是 `CustomPainter` / `InheritedWidget` / `StatefulWidget` 纯 UI = chrome,搬走。已确认 **44 个文件 import material**(`grep` 结果),它们全是搬迁候选。

---

## Phase 0:基线与落脚点

### Task 0.1:确认基线双绿 + 锁定起点
**Files:** 无改动

**Implementation:** 记录迁移前状态,后续每步对比。
```bash
flutter analyze
flutter test
git status   # 注意:工作区已有 assets/hls/ design/ hls_detect 等未提交改动,迁移前先处理干净或单独 stash
```
**Verification:** `flutter analyze` = No issues;`flutter test` 全绿(注意 `test/presentation/niuma_thumbnail_view_test.dart` 历史挂起问题,卡住时 `--exclude-tags` 定位,勿砍测试)。

**Commit:** 无(只读基线)。

### Task 0.2:建 example 模板目录骨架
**Files:**
- Create: `example/lib/niuma_ui/.gitkeep`

**Implementation:** 参考皮的家。按场景再分子目录(后续 Phase 填充):
```
example/lib/niuma_ui/
├── core/        # niuma_player 一体化 + theme + popup_menu
├── controls/    # 22 原子控件
├── control_bar/
├── fullscreen/  # 全屏 page 视图(消费 NiumaFullscreenController)
├── feedback/
├── gesture/     # HUD widget + gesture layer 适配 widget(消费 NiumaGestureController)
├── danmaku/     # overlay / painter / scope / settings panel
├── thumbnail/   # 整块
├── ad/          # 整块
├── cast/        # 整块(协议 + UI)
├── short_video/
└── shared/      # glass_card / video_time_format
```
**Verification:** `ls example/lib/niuma_ui`。
**Commit:** `chore(example): 新增 niuma_ui 参考皮目录骨架`

---

## Phase 1:剥出 headless 逻辑(唯一的新代码,走 TDD)

> 这是整个方案的技术支点。先红后绿:每个 controller 先写纯 Dart 测试(注入 fake backend/bridge,复用 `test/state_machine_test.dart` 的注入风格),再实现。

### Task 1.1:NiumaGestureController(手势→意图,headless)
**Layer:** Presentation-logic(headless)

**Files:**
- Create: `lib/src/presentation/gesture/niuma_gesture_controller.dart`
- Test: `test/presentation/gesture/niuma_gesture_controller_test.dart`

**设计:** 把 `niuma_gesture_layer.dart` 里 `_NiumaGestureLayerState` 的**纯逻辑**搬进来,widget 只剩 `GestureDetector` 透传几何量。controller 持有 `_lockedKind / _panStart / _seekStart / _origValue / _lastChannelSet / _dragThreshold` 等状态,暴露:

```dart
class NiumaGestureController {
  NiumaGestureController(this.player, {this.disabledGestures = const {}});
  final NiumaPlayerController player;
  final Set<GestureKind> disabledGestures;

  // 几何量由 widget 传入,controller 不碰 BuildContext
  void onDoubleTap();
  void onLongPressStart();
  void onLongPressEnd();
  void onPanStart(Offset localPosition);
  Future<void> onPanUpdate(Offset localPosition, Size size);
  void onPanEnd();
  void initBrightness();   // 异步读初始亮度
  void restoreBrightness(); // dispose 时恢复
}
```

**关键拆分:** HUD 反馈走 `player.setGestureFeedbackInternal(...)`(已存在),controller 产出 `GestureFeedbackState` 时**只用 `iconAsset`(SDK 资源字符串),不再引 material `Icons`**——material 的 `IconData icon` 字段由 HUD widget 在 example 侧按 iconAsset 映射。`GestureFeedbackState.icon`(IconData)如无核内用处则在 Task 1.4 收尾移除。文案("已暂停"/"+10s")属逻辑产物,保留在 controller。

**Verification:**
```bash
flutter test test/presentation/gesture/niuma_gesture_controller_test.dart
# 覆盖:阈值锁定方向、左右半屏判定、seek 提交、亮度/音量节流
flutter analyze lib/src/presentation/gesture/niuma_gesture_controller.dart
```
**Commit:** `refactor(gesture): 剥离 NiumaGestureController(手势→意图 headless)`

### Task 1.2:NiumaFullscreenController(全屏编排,headless)
**Layer:** Presentation-logic(headless)

**Files:**
- Create: `lib/src/presentation/fullscreen/niuma_fullscreen_controller.dart`
- Test: `test/presentation/fullscreen/niuma_fullscreen_controller_test.dart`

**设计:** 把 `niuma_fullscreen_page.dart`(670 行)里**朝向 / SystemUI / 进退编排**逻辑剥出,page 只剩视图。复用现有 `PlatformBridge`(朝向/SystemUI 已走它)。web 原生全屏入口 `enterNativeFullscreen/exitNativeFullscreen` 已在 controller(`f036f29`),此处补 io 侧:

```dart
class NiumaFullscreenController {
  NiumaFullscreenController(this.bridge);
  final PlatformBridge bridge;
  final ValueNotifier<bool> isFullscreen = ValueNotifier(false);

  Future<void> enter({Set<DeviceOrientation>? orientations}); // 横屏/竖屏不旋转两种
  Future<void> exit();
  // page widget 监听 isFullscreen + 调 enter/exit;push/pop 路由仍由 example 侧 page 持有
}
```
**关键拆分:** `InheritedWidget` marker"是否已在全屏"的检测属 widget,留 example;controller 只管系统态(朝向/SystemUI/isFullscreen flag)。注入 fake `PlatformBridge` 断言调用序列。

**Verification:**
```bash
flutter test test/presentation/fullscreen/niuma_fullscreen_controller_test.dart
```
**Commit:** `refactor(fullscreen): 剥离 NiumaFullscreenController(朝向/SystemUI headless)`

### Task 1.3:核对弹幕引擎已 headless
**Files:** 无改动(只读核对)

**Implementation:** 确认 `niuma_danmaku_controller.dart` + orchestration 三件(danmaku_models / danmaku_bucket_loader / danmaku_track_allocator)无 material 依赖(grep 已证实 controller 不在 material 列表),渲染态(painter/overlay/scope/settings_panel)归 chrome。
```bash
grep -l "material.dart" lib/src/presentation/danmaku/niuma_danmaku_controller.dart  # 应为空
```
**Verification:** grep 为空。**Commit:** 无。

### Task 1.4:自动隐藏计时归核(若尚未 headless)
**Files:**
- Modify: `lib/src/presentation/core/niuma_player_controller.dart`(或新建 `controls_visibility` notifier)

**Implementation:** 控件自动隐藏的 `ValueNotifier<bool> + Timer` 若当前埋在 `niuma_player.dart` widget 里,上提到 controller 暴露 `ValueListenable<bool> controlsVisible` + `pokeControls()`,让 example 控制条只监听。若已在 controller 则跳过本 task。
**Verification:** `flutter analyze lib/src/presentation/core/`
**Commit:** `refactor(core): 控件自动隐藏计时上提为 headless controlsVisible`

---

## Phase 2:瘦身 barrel(定义新公开 API,BREAKING)

### Task 2.1:重写 `lib/niuma_player.dart` 只 export 核
**Files:**
- Modify: `lib/niuma_player.dart`

**Implementation:** 删除所有 chrome export,保留 headless 核。**删除清单**(原 barrel 里的 UI 行):NiumaPlayer / NiumaPlayerConfigScope / NiumaFullscreenPage / NiumaFullscreenControl / 所有 feedback(loading/error/ended/progress_thumb)/ NiumaScrubPreview / 控件条全套(NiumaControlBar / NiumaControlButton / config / button_override / fullscreen_control_bar)/ NiumaCastPickerPanel / NiumaAdOverlay / 10 个原子裸名 + control_aliases 10 个 Niuma* / ThumbnailFrame / NiumaThumbnailView / 弹幕 overlay+scope+settings_panel / gesture layer+hud / 全部 short_video / cast UI(button/overlay)/ cast 协议(DlnaCastService/AirPlayCastService)/ cast 抽象(按决策 cast 整块出核 → CastService/CastDevice/CastSession/NiumaCastRegistry/CastState 也移除)。

**保留 export**(核):backends/bridge/device_memory/data_source/player_backend/player_state 全枚举/**NiumaPlayerController + NiumaPlayerOptions + ThumbnailFetcher**/niuma_player_view/orchestration 全部/observability/danmaku_models + NiumaDanmakuController/gesture_kind + gesture_feedback_state/**新增 NiumaGestureController + NiumaFullscreenController**/niuma_sdk_assets。

> ad_schedule / ad_scheduler 按"广告整块出核"决策一并移除 export(逻辑也搬 example)。resume/multi_source/source_middleware/retry/auto_failover 保留。

**Verification:**
```bash
flutter analyze   # barrel 自身应 clean;此时 lib/ 内仍有 chrome 文件但不再导出
```
**Commit:** `refactor!: barrel 瘦身为 headless 核 API(BREAKING)`

---

## Phase 3:物理搬迁 chrome → example(逐块)

> 每块:`git mv` 文件到 `example/lib/niuma_ui/<子目录>/` → 把内部 `import 'package:niuma_player/src/...'` 改写为 `import 'package:niuma_player/niuma_player.dart'`(消费公开核)或 example 内相对 import → `cd example && flutter analyze`。缠在一起的文件先在 Phase 1 已剥逻辑,这里只搬 widget 残体。

### Task 3.1:shared + feedback
**Files:** `git mv` `presentation/shared/{glass_card,video_time_format}.dart` → `example/lib/niuma_ui/shared/`;`presentation/feedback/*`(4)→ `niuma_ui/feedback/`。
**Verification:** `cd example && flutter analyze`(预期此时 example 还没接,先确保文件本身改完 import 能 analyze 各文件)。
**Commit:** `refactor(example): 搬迁 shared/feedback 参考皮`

### Task 3.2:原子控件(22)+ control_bar(6)
**Files:** `git mv` `presentation/controls/*`(22)→ `niuma_ui/controls/`;`presentation/control_bar/*`(6)→ `niuma_ui/control_bar/`;`control_aliases.dart` → `niuma_ui/controls/aliases.dart`。
**Commit:** `refactor(example): 搬迁原子控件 + 控件条参考皮`

### Task 3.3:gesture HUD + layer widget
**Files:** `git mv` `presentation/gesture/{niuma_gesture_hud,niuma_gesture_layer}.dart` → `niuma_ui/gesture/`;改写 gesture_layer 消费 Task 1.1 的 `NiumaGestureController`(widget 只剩 GestureDetector 透传几何量 + HUD 渲染)。
**Commit:** `refactor(example): 搬迁手势 widget,消费 NiumaGestureController`

### Task 3.4:fullscreen page + danmaku 渲染
**Files:** `git mv` `presentation/fullscreen/{niuma_fullscreen_page,_root_bg_io,_root_bg_web}.dart` → `niuma_ui/fullscreen/`(page 消费 Task 1.2 controller);`presentation/danmaku/{niuma_danmaku_overlay,niuma_danmaku_painter,niuma_danmaku_scope,danmaku_settings_panel}.dart` → `niuma_ui/danmaku/`(controller 留核)。
**Commit:** `refactor(example): 搬迁全屏页 + 弹幕渲染参考皮`

### Task 3.5:short_video + core 一体化 widget + theme
**Files:** `git mv` `presentation/short_video/*`(5)+ `domain/niuma_short_video_theme.dart` → `niuma_ui/short_video/`;`presentation/core/{niuma_player,niuma_player_theme,niuma_player_popup_menu}.dart` → `niuma_ui/core/`(controller/view/pip_lifecycle 留核)。
**Verification:** `cd example && flutter analyze`
**Commit:** `refactor(example): 搬迁短视频 + 一体化 widget + 主题参考皮`

---

## Phase 4:cast / 广告 / 缩略图 整块出核

### Task 4.1:cast 整块(协议 + UI)
**Files:** `git mv` `lib/src/cast/**`(14 文件,含 dlna/ 9 个)+ `presentation/cast/*`(3)→ `example/lib/niuma_ui/cast/`;改写 import。
**说明:** 接入方拷此目录即获完整 DLNA/AirPlay 能力。README 标注"协议自维护"。
**Commit:** `refactor(example): cast 整块(DLNA/AirPlay 协议+UI)移入参考皮`

### Task 4.2:广告整块
**Files:** `git mv` `presentation/ad/{ad_schedule,ad_scheduler,niuma_ad_overlay}.dart` → `niuma_ui/ad/`。
**Commit:** `refactor(example): 广告调度+overlay 整块移入参考皮`

### Task 4.3:缩略图整块
**Files:** `git mv` `presentation/thumbnail/{thumbnail_cache,thumbnail_frame,thumbnail_resolver,niuma_thumbnail_view,niuma_scrub_preview}.dart` → `niuma_ui/thumbnail/`。
**注意:** orchestration/{thumbnail_track,webvtt_parser} **留核**(纯解析);只搬 resolver/cache/widget。`NiumaPlayerController` 里 `ThumbnailFetcher` typedef 留核。
**Verification:** `flutter analyze`(核);确认 `lib/src/presentation/` 只剩 core/{controller,view,pip_lifecycle} + danmaku/controller + gesture/controller + fullscreen/controller。
**Commit:** `refactor(example): 缩略图 resolver/cache/widget 移入参考皮`

### Task 4.4:核 pubspec 依赖收敛
**Files:** Modify `pubspec.yaml`
**Implementation:** 评估 chrome 搬走后核还需不需要 `flutter_svg`(渲染 SVG 图标——属 chrome,应移到 example/pubspec)。把仅 chrome 用的依赖从核 pubspec 删除、加到 `example/pubspec.yaml`。`material` 是 flutter SDK 一部分无法单独移除,但核代码不再 import 它即达成"核零 material 依赖"目标。
```bash
grep -rl "flutter_svg" lib/src   # 应为空 → 可从核 pubspec 移除
```
**Verification:** `flutter pub get && flutter analyze`(核);`cd example && flutter pub get && flutter analyze`
**Commit:** `refactor: 核 pubspec 移除仅 chrome 用依赖(flutter_svg 等)迁至 example`

---

## Phase 5:example 接线成参考皮 + 跑通

### Task 5.1:example barrel + demo 页接新皮
**Files:**
- Create: `example/lib/niuma_ui/niuma_ui.dart`(example 内的皮 barrel,方便 demo import)
- Modify: `example/lib/*_demo*.dart`(现有 demo 页改 import 自 `niuma_ui/`)

**Implementation:** 现有 demo(long_video / short_video / custom_controls / custom_feedback_ui / danmaku / cast_pip / gesture_lock / rollback_failover)从"import SDK 的 UI"改为"import 本地 niuma_ui 参考皮 + import SDK 核 controller"。demo 即活的拷贝示范。
**Verification:**
```bash
cd example && flutter analyze   # No issues
cd example && flutter build apk --debug   # 冒烟,确保参考皮在真实 app 编译过
```
**Commit:** `refactor(example): demo 页改用本地 niuma_ui 参考皮`

### Task 5.2:删除核侧测试中依赖已搬 chrome 的用例 / 迁测试
**Files:** Modify/Move `test/presentation/**`
**Implementation:** 核保留的测试(state_machine / orchestration / 新增两个 controller)留 `test/`;针对已搬 widget 的 widget 测试(如 niuma_thumbnail_view_test)迁到 `example/test/` 或删除。**勿砍可迁移的有效测试**,先迁后删。
**Verification:** `flutter test`(核全绿);`cd example && flutter test`
**Commit:** `test: 核测试聚焦 headless;widget 测试迁至 example`

---

## Phase 6:版本 / 文档 / 定位

### Task 6.1:bump 0.1.0 + CHANGELOG 迁移指南
**Files:** Modify `pubspec.yaml`(version: 0.1.0)、`CHANGELOG.md`
**Implementation:** CHANGELOG 写:
```markdown
## [0.1.0]

### BREAKING CHANGE: 重定位为 headless 播放内核
- `niuma_player` 现在只导出播放内核(NiumaPlayerController + 编排逻辑 +
  手势/全屏/弹幕 headless controller)。所有 UI widget(NiumaPlayer 一体化、
  原子控件、控件条、全屏页、反馈态、弹幕/广告/缩略图/cast/短视频 UI、主题)
  已移出包,作为可拷贝参考皮存放于 example/lib/niuma_ui/。
- **迁移**:从 example/lib/niuma_ui/ 拷贝所需 widget 到你的项目,改 import
  为本地路径;controller 与编排 API 保持兼容。
- cast(DLNA/AirPlay 协议+UI)、广告、缩略图整块移入参考皮,接入方自维护。
```
**Verification:** `flutter pub publish --dry-run`(0 warning;注意先把 example 的私有调试源 stash)。
**Commit:** `chore: 发布 0.1.0(headless 重定位)`

### Task 6.2:README + CLAUDE.md 同步新定位
**Files:** Modify `README.md`、`CLAUDE.md`
**Implementation:**
- README 顶部重写:"headless 播放内核 + 可拷贝参考皮",给"如何拷皮"小节(拷 `example/lib/niuma_ui/<子目录>`)。
- `CLAUDE.md` 更新"项目定位""presentation 目录组织""公开 API 边界"段:presentation/ 现只剩 4 个 headless(controller/view/pip_lifecycle + 三 controller);UI 在 example。
**Verification:** 人工读一遍;`flutter analyze` 不受影响。
**Commit:** `docs: README/CLAUDE.md 同步 headless 重定位`

---

## 风险与回滚

- **每个 Phase 独立 commit**,出问题 `git revert` 到上一 Phase。Phase 1(剥逻辑)与 Phase 2(瘦 barrel)之间核仍可编译,是安全检查点。
- **example 私有调试源**(long_video_demo 的 m3u8)与本迁移无关,迁移前先 stash,避免污染 `pub publish --dry-run`(参考 obs 2196-2198 踩过的坑)。
- **iOS PiP 反射区**不在搬迁范围(原生 Swift),但 pip_lifecycle_observer.dart 留核——确认它不依赖任何已搬 widget。
- **niuma_thumbnail_view_test 历史挂起**:thumbnail widget 搬 example 后,该测试一并迁 example/test,顺手验证是否仍挂起。
- 工作量级:Phase 1(新代码+TDD)是真正费时项;Phase 3-4 主要是 `git mv` + import 改写,机械但量大(~50 文件)。建议 Phase 1 用子代理逐任务 + code review,Phase 3-5 批量执行。
