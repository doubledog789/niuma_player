// kernel
export 'src/data/default_backend_factory.dart' show DefaultBackendFactory;
export 'src/data/default_platform_bridge.dart' show DefaultPlatformBridge;
export 'src/data/device_memory.dart';
export 'src/domain/backend_factory.dart' show BackendFactory;
export 'src/domain/data_source.dart';
export 'src/domain/platform_bridge.dart' show PlatformBridge;
export 'src/domain/player_backend.dart' show PlayerBackend, PlayerBackendKind;
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
        LineSwitchFailed;
export 'src/presentation/niuma_player_controller.dart';
export 'src/presentation/niuma_player_view.dart';
export 'src/presentation/niuma_thumbnail_view.dart' show NiumaThumbnailView;

// orchestration
export 'src/orchestration/multi_source.dart'
    show MediaQuality, MediaLine, NiumaMediaSource, MultiSourcePolicy;
export 'src/orchestration/thumbnail_track.dart'
    show ThumbnailFrame, WebVttCue, ThumbnailLoadState;
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
export 'src/orchestration/retry_policy.dart' show RetryPolicy;
export 'src/orchestration/ad_schedule.dart'
    show
        AdCue,
        AdController,
        NiumaAdSchedule,
        MidRollAd,
        MidRollSkipPolicy,
        PauseAdShowPolicy;
export 'src/orchestration/ad_scheduler.dart' show AdSchedulerOrchestrator;
export 'src/orchestration/auto_failover.dart' show AutoFailoverOrchestrator;

// observability
export 'src/observability/analytics_event.dart'
    show
        AnalyticsEvent,
        AdScheduled,
        AdImpression,
        AdClick,
        AdDismissed,
        AdCueType,
        AdDismissReason;
export 'src/observability/analytics_emitter.dart' show AnalyticsEmitter;
