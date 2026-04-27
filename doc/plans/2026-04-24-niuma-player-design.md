# niuma_player Design

> 版本：v0.1（brainstorming 定稿）
> 日期：2026-04-24
> 维护者：主 agent + 并行子 agent（B1/B2/B3/B4）
> 本文档是所有实现子 agent 的**唯一事实源**。任何与本文档冲突的想法，以本文档为准，除非通过 PR 修改本文档。

---

## 1. Overview

`niuma_player` 是一个 Flutter plugin package，解决"华为/老设备 `video_player` 无法播放视频"的兼容性问题。

- **iOS**：委托给官方 `video_player`，零额外体积
- **Android**：默认使用 `video_player`；运行时检测到失败 → 无缝切换到内置 IJKPlayer；失败结果持久化，下次同设备直接走 IJK

## 2. User Stories

- 作为普通用户（90%+ 设备正常），我打开 App 看视频，感觉和以前一样流畅（走系统原生）
- 作为华为/老设备用户，我第一次看视频时感觉"缓冲了一下"，但最终能看到画面（video_player 失败 → IJK 接管）
- 作为第二次打开 App 的华为/老设备用户，我秒开视频（记忆命中，直接走 IJK）
- 作为开发者，我用 `NiumaPlayerController` 替换 `VideoPlayerController`，API 几乎一致，改动最小

## 3. 架构分层（Clean Architecture）

```
niuma_player/
├── lib/
│   ├── niuma_player.dart                 ← export
│   └── src/
│       ├── domain/
│       │   ├── player_backend.dart       ← abstract PlayerBackend
│       │   ├── player_state.dart         ← freezed NiumaPlayerValue + NiumaPlayerEvent
│       │   └── data_source.dart          ← NiumaDataSource
│       ├── data/
│       │   ├── video_player_backend.dart ← wrap package:video_player
│       │   ├── ijk_backend.dart          ← MethodChannel → Android IJK
│       │   └── device_memory.dart        ← SharedPreferences 持久化失败记忆
│       └── presentation/
│           ├── niuma_player_controller.dart ← Try-Fail-Remember 状态机
│           └── niuma_player_view.dart       ← Widget（Texture / video_player widget）
├── android/
│   ├── build.gradle                      ← minSdk 21, compileSdk 35
│   ├── libs/                             ← .aar 放这里（不进 git，通过 download 脚本从 Release 拉）
│   ├── src/main/kotlin/cn/niuma/niuma_player/
│   │   ├── NiumaPlayerPlugin.kt          ← FlutterPlugin 入口，注册 MethodChannel
│   │   ├── NiumaPlayer.kt                ← 单个播放实例，绑定 TextureEntry + Surface + IjkMediaPlayer
│   │   └── EventSink.kt                  ← 事件上抛工具（统一 main looper）
│   └── scripts/compile/                  ← IJK + FFmpeg 编译脚本
│       ├── README.md
│       ├── VERSIONS.lock
│       ├── build.sh
│       ├── Dockerfile（可选）
│       └── modules/module-lite-hevc.sh
├── ios/                                  ← 空实现（委托给 video_player）
├── example/                              ← 最小验证 app
├── test/                                 ← Dart 单测
└── docs/plans/                           ← 本文档
```

## 4. 核心 API

### 4.1 NiumaDataSource

```dart
class NiumaDataSource {
  final NiumaSourceType type;
  final String uri;
  final Map<String, String>? headers;

  factory NiumaDataSource.network(String url, {Map<String, String>? headers});
  factory NiumaDataSource.asset(String assetPath);
  factory NiumaDataSource.file(String filePath);
}

enum NiumaSourceType { network, asset, file }
```

### 4.2 NiumaPlayerValue（与 VideoPlayerValue 字段对齐）

```dart
@freezed
class NiumaPlayerValue with _$NiumaPlayerValue {
  const factory NiumaPlayerValue({
    required bool initialized,
    required Duration position,
    required Duration duration,
    required Size size,
    required bool isPlaying,
    required bool isBuffering,
    String? errorMessage,
  }) = _NiumaPlayerValue;

  factory NiumaPlayerValue.uninitialized() => const NiumaPlayerValue(
    initialized: false,
    position: Duration.zero,
    duration: Duration.zero,
    size: Size.zero,
    isPlaying: false,
    isBuffering: false,
  );
}
```

### 4.3 NiumaPlayerController

```dart
class NiumaPlayerController extends ValueNotifier<NiumaPlayerValue> {
  NiumaPlayerController(this.dataSource, {NiumaPlayerOptions? options});

  final NiumaDataSource dataSource;

  Future<void> initialize();
  Future<void> play();
  Future<void> pause();
  Future<void> seekTo(Duration position);
  Future<void> setPlaybackSpeed(double speed);
  Future<void> setVolume(double volume);
  @override
  Future<void> dispose();

  Stream<NiumaPlayerEvent> get events;
  PlayerBackendKind get activeBackend;
  int? get textureId; // null if backend doesn't use texture (video_player case)
}

enum PlayerBackendKind { videoPlayer, ijk }

class NiumaPlayerOptions {
  final Duration initTimeout;           // 默认 5s，video_player 起播超时即判失败
  final Duration memoryTtl;             // 默认 Duration.zero（永久）；>0 则过期重试
  final bool forceIjkOnAndroid;         // 测试或应急用
  const NiumaPlayerOptions({
    this.initTimeout = const Duration(seconds: 5),
    this.memoryTtl = Duration.zero,
    this.forceIjkOnAndroid = false,
  });
}
```

### 4.4 NiumaPlayerEvent

```dart
sealed class NiumaPlayerEvent {}

class BackendSelected extends NiumaPlayerEvent {
  final PlayerBackendKind kind;
  final bool fromMemory;
  BackendSelected(this.kind, {required this.fromMemory});
}

class FallbackTriggered extends NiumaPlayerEvent {
  final FallbackReason reason;
  final String? errorCode;
  FallbackTriggered(this.reason, {this.errorCode});
}

enum FallbackReason { error, timeout }
```

### 4.5 NiumaPlayerView

```dart
class NiumaPlayerView extends StatelessWidget {
  const NiumaPlayerView(this.controller, {super.key, this.aspectRatio});
  final NiumaPlayerController controller;
  final double? aspectRatio;
  // 内部：
  //   - activeBackend == videoPlayer: 委托 package:video_player 的 VideoPlayer widget
  //   - activeBackend == ijk: 使用 Texture(textureId)
}
```

## 5. Try-Fail-Remember 状态机

```
initialize()
  │
  ▼
[iOS?] ── yes ─────────────────────► VideoPlayerBackend
  │ no (Android)
  ▼
[options.forceIjkOnAndroid?] ── yes ► IjkBackend
  │ no
  ▼
[DeviceMemory.shouldUseIjk()?] ── yes ► IjkBackend (emit BackendSelected(ijk, fromMemory: true))
  │ no
  ▼
尝试 VideoPlayerBackend.initialize()
  │
  ├── onError 事件 ────────► 记忆失败 → dispose vp → new IjkBackend
  ├── initTimeout 到期      ─► 记忆失败 → dispose vp → new IjkBackend
  └── 成功 initialized      ─► use VideoPlayerBackend (emit BackendSelected(vp, fromMemory: false))
```

**设备指纹 key**：
```
sha1("${Build.MANUFACTURER}|${Build.MODEL}|${Build.VERSION.SDK_INT}")
```
由 Android 原生侧通过 MethodChannel 提供给 Dart 层；Dart 层存 `SharedPreferences`，key = `niuma_player.ijk_needed.<fingerprint>`。

## 6. Android Native 实现

### 6.1 依赖

```gradle
// niuma_player/android/build.gradle
android {
    namespace 'cn.niuma.niuma_player'
    compileSdk 35

    defaultConfig {
        minSdk 21
        ndk {
            abiFilters 'arm64-v8a', 'armeabi-v7a'
        }
    }

    packagingOptions {
        pickFirst 'lib/*/libc++_shared.so'
    }
}

dependencies {
    implementation fileTree(dir: 'libs', include: ['*.aar'])
}
```

### 6.2 MethodChannel 协议

**Method channel name**：`cn.niuma/player/<textureId>`
**Global channel name**：`cn.niuma/player`（用于 `create` / `deviceFingerprint`）

#### 调用方向（Dart → Android）

| method | args | returns |
|---|---|---|
| `create` | `{uri, type, headers}` | `{textureId, fingerprint}` |
| `dispose` | `{textureId}` | `null` |
| `play` | `{textureId}` | `null` |
| `pause` | `{textureId}` | `null` |
| `seekTo` | `{textureId, positionMs}` | `null` |
| `setSpeed` | `{textureId, speed}` | `null` |
| `setVolume` | `{textureId, volume}` | `null` |
| `deviceFingerprint` | `{}` | `{fingerprint}` |

#### 事件方向（Android → Dart，通过 EventChannel `cn.niuma/player/events/<textureId>`）

| event | payload |
|---|---|
| `initialized` | `{durationMs, width, height}` |
| `bufferingStart` | `{}` |
| `bufferingEnd` | `{}` |
| `positionChanged` | `{positionMs}` （250ms 心跳） |
| `completed` | `{}` |
| `error` | `{code, message}` |
| `videoSizeChanged` | `{width, height}` |

### 6.3 Texture 绑定

```kotlin
val entry = flutterPluginBinding.textureRegistry.createSurfaceTexture()
val surface = Surface(entry.surfaceTexture())
ijkMediaPlayer.setSurface(surface)
// entry.id() 即 textureId 返回给 Dart
```

### 6.4 IjkMediaPlayer 推荐配置

```kotlin
player.setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, "mediacodec", 1) // 尝试硬解，失败自动回退软解
player.setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, "mediacodec-auto-rotate", 1)
player.setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, "mediacodec-handle-resolution-change", 1)
player.setOption(IjkMediaPlayer.OPT_CATEGORY_PLAYER, "start-on-prepared", 0) // 手动 start
player.setOption(IjkMediaPlayer.OPT_CATEGORY_FORMAT, "protocol_whitelist", "async,cache,crypto,file,http,https,ijkhttphook,ijkinject,ijklivehook,ijklongurl,ijksegment,ijktcphook,pipe,rtp,tcp,tls,udp,ijkurlhook,data")
```

## 7. IJK / FFmpeg 编译策略

### 7.1 版本锁定（`VERSIONS.lock`）

| 组件 | 版本 |
|---|---|
| Fork | `debugly/ijkplayer` @ tag `k0.8.9-beta-260402150035` |
| FFmpeg | bilibili fork `ff4.0--ijk0.8.8--20210426--001` |
| OpenSSL | 1.1.1w |
| NDK | r26b (`26.1.10909125`) |
| compileSdk / targetSdk | 35 |
| minSdk | 21 |
| ABI | arm64-v8a, armeabi-v7a |
| FFmpeg 配置 | `module-lite-hevc.sh` |
| License | LGPL-2.1, `--disable-gpl --disable-nonfree` |

### 7.2 首版策略

- **v0.1**：`android/libs/` 放 debugly 官方 Release 的 `.aar`（通过 `scripts/compile/download-prebuilt.sh` 拉）
- **v0.2**：替换为自编产物，字节级 diff 验证后发布

### 7.3 脚本产物

```
niuma_player/android/scripts/compile/
├── README.md               ← 5 行编译步骤
├── VERSIONS.lock
├── download-prebuilt.sh    ← 拉 debugly 官方 .aar，v0.1 用
├── build.sh                ← 自编入口，v0.2 用
├── Dockerfile              ← 可选复现环境
└── modules/
    └── module-lite-hevc.sh
```

## 8. 体积预算

| 组件 | 体积 |
|---|---|
| `libijkplayer.so` (armv7-a) | ~3.0 MB |
| `libijkplayer.so` (arm64-v8a) | ~3.5 MB |
| Java class + AndroidX deps | <0.5 MB |
| **APK 净增（双 ABI）** | **≈ 6.5 MB** |

对比：完整 VLC 约 25+ MB，媒体扩展完整版 40+ MB。

## 9. 测试

### 9.1 优先级

| P | 测试内容 | 工具 |
|---|---|---|
| 1 | `DeviceMemory` SharedPreferences 存取 | `flutter_test` + `shared_preferences` mock |
| 1 | `NiumaPlayerController` 状态机（error / timeout / success / memory-hit 四路径）| `flutter_test` + mock Backend |
| 2 | Backend 契约测试（同一 operation sequence 在 VP 和 IJK 上行为一致） | `integration_test` |
| 3 | `NiumaPlayerView` widget 测试 | `flutter_test` |
| 3 | 真机：iPhone × 1 + Android（小米/华为/老设备）× 3 | 手动 |

### 9.2 example app 场景

- 播放 h264 mp4 远程 url
- 播放 h265 mp4 远程 url
- 播放 HLS m3u8
- 强制 `forceIjkOnAndroid: true` 检查 IJK 通路
- 清除 DeviceMemory 按钮（调试用）

## 10. 风险与缓解

| 风险 | 缓解 |
|---|---|
| MethodChannel 事件非 main 线程发出 → Dart race | Native 强制 `Handler(Looper.getMainLooper()).post` |
| TextureRegistry 后台失效 | 监听 `WidgetsBindingObserver`，onResume 重绑 Surface |
| `libc++_shared.so` 符号冲突 | `packagingOptions { pickFirst 'lib/*/libc++_shared.so' }` |
| HLS AES-128 加密流 | FFmpeg `--enable-openssl` 静链 1.1.1w |
| 华为设备仍失败 | 抛 `NiumaPlayerEvent.error`，业务方决定 UI |
| Flutter 3.27 / 3.38 双版本兼容 | `pubspec.yaml` 的 `sdk` 约束保持宽松 |

## 11. 交付清单

- [ ] Dart public API 实现
- [ ] 状态机 + DeviceMemory 单测 100% pass
- [ ] Android Plugin 源码 + MethodChannel 实现
- [ ] `android/libs/` 下挂 debugly prebuilt `.aar`（v0.1）
- [ ] `scripts/compile/build.sh` 可本地跑通（v0.2，可后续补）
- [ ] example app 四个场景都能放
- [ ] README.md 展示 5 行接入示例
- [ ] 一次成功的真机录屏（iPhone + 一台华为）

## 12. 并行实施分工（Phase B）

| Agent | 范围 | 不得碰 |
|---|---|---|
| B1（worktree）| `android/libs/`, `android/scripts/compile/` | `lib/`, `android/src/` |
| B2 | `lib/`, `pubspec.yaml` | `android/`, `ios/`, `example/` |
| B3 | `android/src/`, `android/build.gradle` | `lib/`, `ios/`, `example/` |
| B4 | `example/`, `test/` | `lib/`（只读引用）, `android/`（只读） |

B2 / B3 / B4 共享本文档作为接口约定，B1 独立跑编译。
