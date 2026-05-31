/// `niuma_player` —— **headless 视频播放内核**。
///
/// 本包只导出播放内核：`NiumaPlayerController` + 全部编排逻辑（多线路 / 续播 /
/// retry / source middleware / auto-failover / 弹幕引擎）+ 手势 / 全屏 / 弹幕的
/// **headless controller**。所有 UI widget（一体化 `NiumaPlayer`、原子控件、
/// 控件条、全屏页、反馈态、弹幕 / 广告 / 缩略图 / cast / 短视频 UI、主题）以及
/// 缩略图取帧逻辑作为**可拷贝参考皮**存放于 `example/lib/niuma_ui/`，不进 semver
/// 契约——接入方按需拷贝、自由改造。
library;

// 内核
export 'package:niuma_player/src/data/default_backend_factory.dart' show DefaultBackendFactory;
export 'package:niuma_player/src/data/default_platform_bridge.dart' show DefaultPlatformBridge;
export 'package:niuma_player/src/data/device_memory.dart';
export 'package:niuma_player/src/domain/backend_factory.dart' show BackendFactory;
export 'package:niuma_player/src/domain/data_source.dart';
export 'package:niuma_player/src/domain/platform_bridge.dart' show PlatformBridge;
export 'package:niuma_player/src/domain/player_backend.dart' show PlayerBackend, PlayerBackendKind;
export 'src/domain/player_state.dart'
    show
        NiumaPlayerValue,
        PlayerPhase,
        PlayerError,
        PlayerErrorCategory,
        NiumaPlayerEvent,
        BackendSelected,
        FallbackTriggered,
        FallbackReason,
        LineSwitching,
        LineSwitched,
        LineSwitchFailed,
        PipModeChanged,
        PipRemoteAction,
        CastStarted,
        CastEnded,
        CastError;
export 'src/player/niuma_player_controller.dart'
    show NiumaPlayerController, NiumaPlayerOptions;
export 'package:niuma_player/src/player/niuma_player_view.dart';

// 运行时资源常量（仅 web 后端 hls.js 路径；UI 资源已移出核）
export 'src/niuma_sdk_assets.dart' show NiumaSdkAssets;

// 编排
export 'src/orchestration/multi_source.dart'
    show MediaQuality, MediaLine, NiumaMediaSource, MultiSourcePolicy;
export 'src/orchestration/source_middleware.dart'
    show
        SourceMiddleware,
        HeaderInjectionMiddleware,
        SignedUrlMiddleware,
        runSourceMiddlewares;
export 'src/orchestration/resume_position.dart'
    show
        ResumeStorage,
        SharedPreferencesResumeStorage,
        ResumePolicy,
        ResumeBehaviour,
        ResumeKeyOf,
        defaultResumeKey,
        ResumeOrchestrator;
export 'package:niuma_player/src/orchestration/retry_policy.dart' show RetryPolicy;
export 'src/orchestration/auto_failover.dart' show AutoFailoverOrchestrator;

// M11 弹幕引擎（headless：模型 + controller + 轨道分配，渲染 widget 在参考皮）
export 'src/orchestration/danmaku_models.dart'
    show DanmakuItem, DanmakuMode, DanmakuSettings, DanmakuLoader;
export 'src/orchestration/danmaku_track_allocator.dart'
    show DanmakuTrackAllocator;
export 'src/player/niuma_danmaku_controller.dart'
    show NiumaDanmakuController;

// 视频时长格式化纯函数——手势 / 短视频参考皮渲染 HUD / 进度 label 复用。
export 'src/player/video_time_format.dart' show formatVideoTime;

// 可观测性
export 'src/observability/analytics_event.dart'
    show
        AnalyticsEvent,
        AdScheduled,
        AdImpression,
        AdClick,
        AdDismissed,
        AdCueType,
        AdDismissReason;
export 'package:niuma_player/src/observability/analytics_emitter.dart' show AnalyticsEmitter;

// M13 手势（headless：意图映射 controller + 值对象，HUD widget 在参考皮）
export 'package:niuma_player/src/domain/gesture_kind.dart' show GestureKind;
export 'package:niuma_player/src/domain/gesture_feedback_state.dart' show GestureFeedbackState;
export 'package:niuma_player/src/domain/gesture_hud_icon.dart' show GestureHudIcon;
export 'package:niuma_player/src/player/niuma_gesture_controller.dart'
    show NiumaGestureController;

// 全屏（headless：朝向 / SystemUI 编排 controller，全屏页 widget 在参考皮）
export 'package:niuma_player/src/player/niuma_fullscreen_controller.dart'
    show NiumaFullscreenController;
export 'package:niuma_player/src/player/web_fullscreen_coordination.dart'
    show NiumaFullscreenScope, webFullscreenRouteCount, webFullscreenRouteCountListenable;

// M15 投屏（Cast）抽象层——controller.connectCast / castSession + 事件模型依赖
// 它，故留核。协议实现（DLNA / AirPlay）+ registry + cast UI 作为可选附加在
// 参考皮里，接入方自维护。
export 'package:niuma_player/src/cast/cast_device.dart' show CastDevice;
export 'package:niuma_player/src/cast/cast_state.dart' show CastConnectionState, CastEndReason;
export 'package:niuma_player/src/cast/cast_session.dart' show CastSession;
