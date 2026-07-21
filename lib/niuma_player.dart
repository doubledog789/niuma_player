/// `niuma_player` —— **headless 视频播放内核**。
///
/// 只导出内核：`NiumaPlayerController` + 编排逻辑 + 手势 / 全屏 headless
/// controller + 无样式渲染面 `NiumaPlayerView`；不含任何控件皮肤，接入方
/// 监听 `controller.value` 自拼 UI。曾经的参考皮在 git 历史
/// （`git log --all -- 'example/lib/niuma_ui/**'`）。
library;

// 内核
export 'package:niuma_player/src/data/default_backend_factory.dart'
    show DefaultBackendFactory;
export 'package:niuma_player/src/data/default_platform_bridge.dart'
    show DefaultPlatformBridge;
export 'package:niuma_player/src/domain/backend_factory.dart'
    show BackendFactory;
export 'package:niuma_player/src/domain/data_source.dart';
export 'package:niuma_player/src/domain/platform_bridge.dart'
    show PlatformBridge;
export 'package:niuma_player/src/domain/player_backend.dart'
    show PlayerBackend, PlayerBackendKind;
export 'src/domain/player_state.dart'
    show
        NiumaPlayerValue,
        PlayerPhase,
        PlayerError,
        EngineFallbackFailure,
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
    show NiumaPlayerController;
export 'src/player/niuma_player_options.dart' show NiumaPlayerOptions;
export 'package:niuma_player/src/player/niuma_player_view.dart';

// 运行时资源常量（仅 web 后端 hls.js 路径；UI 资源已移出核）
export 'src/niuma_sdk_assets.dart' show NiumaSdkAssets;

// 设备媒体能力探测（源协商用，业务据此决定请求何种编码的源）
export 'src/capabilities/niuma_capabilities.dart' show NiumaCapabilities;

// 编排
export 'src/orchestration/multi_source.dart'
    show MediaQuality, MediaLine, NiumaMediaSource, MultiSourcePolicy;
export 'src/orchestration/source_middleware.dart'
    show
        SourceMiddleware,
        HeaderInjectionMiddleware,
        SignedUrlMiddleware,
        runSourceMiddlewares;
export 'package:niuma_player/src/orchestration/retry_policy.dart'
    show RetryPolicy;
export 'src/orchestration/auto_failover.dart' show AutoFailoverOrchestrator;
export 'src/orchestration/player_pool.dart'
    show NiumaPlayerPool, PoolControllerFactory;

// 视频时长格式化纯函数——手势 / 短视频参考皮渲染 HUD / 进度 label 复用。
export 'src/player/video_time_format.dart' show formatVideoTime;

// M13 手势（headless：意图映射 controller + 值对象，HUD widget 在参考皮）
export 'package:niuma_player/src/domain/gesture_kind.dart' show GestureKind;
export 'package:niuma_player/src/domain/gesture_feedback_state.dart'
    show GestureFeedbackState;
export 'package:niuma_player/src/domain/gesture_hud_icon.dart'
    show GestureHudIcon;
export 'package:niuma_player/src/player/niuma_gesture_controller.dart'
    show NiumaGestureController;

// 全屏（headless：朝向 / SystemUI 编排 controller，全屏页 widget 在参考皮）
export 'package:niuma_player/src/player/niuma_fullscreen_controller.dart'
    show NiumaFullscreenController;
export 'package:niuma_player/src/player/web_fullscreen_coordination.dart'
    show
        NiumaFullscreenScope,
        webFullscreenRouteCountListenable,
        enterWebFullscreenRoute,
        exitWebFullscreenRoute,
        NiumaWebFullscreenMode,
        webFullscreenMode,
        requestBrowserFullscreen,
        exitBrowserFullscreen,
        onBrowserFullscreenChange;

// M15 投屏（Cast）值类型——controller.connectCast / 事件模型依赖，故留核；
// 协议实现 + UI 在参考皮。
export 'package:niuma_player/src/cast/cast_device.dart' show CastDevice;
export 'package:niuma_player/src/cast/cast_state.dart'
    show CastConnectionState, CastEndReason;
export 'package:niuma_player/src/cast/cast_session.dart' show CastSession;
