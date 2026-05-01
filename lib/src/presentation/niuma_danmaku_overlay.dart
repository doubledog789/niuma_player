import 'package:flutter/scheduler.dart';
import 'package:flutter/widgets.dart';

import '../domain/player_state.dart';
import 'niuma_danmaku_controller.dart';
import 'niuma_danmaku_painter.dart';
import 'niuma_player_controller.dart';

/// 弹幕渲染层。可作为独立积木件直接 Stack 进自定义布局，也由 [NiumaPlayer]
/// 在传入 `danmakuController` 时自动接管。
///
/// 内部行为：
/// - 监听 [video] + [danmaku] 变化作为 seek/桶切换信号；
/// - **内置 [Ticker]** 在 phase=playing 时每帧推进"内插位置"——video_player
///   原生侧约 250ms 推一次 position，painter 不能直接吃 video.value 否则
///   弹幕会跳跃。本 overlay 在 video tick 时同步 (videoPos, wallTimeMs)，
///   两次 tick 之间用 `videoPos + (now - wallTime)` 内插出 60fps 平滑位置。
/// - 检测 |Δposition| > 1s 视为 seek，painter 自然下一帧从 visibleAt 重算
/// - settings.visible=false 时返回 SizedBox.expand（零绘）
/// - 跨入新桶时 fire-and-forget 触发 [NiumaDanmakuController.ensureLoadedFor]
/// - **整个 overlay 包 [IgnorePointer]**——CustomPaint 默认会吃掉 hit test
///   导致外层 click-catcher 的 onTap 失效，必须显式让 tap 穿透。
class NiumaDanmakuOverlay extends StatefulWidget {
  /// 构造一个 overlay。
  const NiumaDanmakuOverlay({
    super.key,
    required this.video,
    required this.danmaku,
  });

  /// 视频 controller（提供 position 推送 + phase）。
  final NiumaPlayerController video;

  /// 弹幕 controller（数据源 + 配置）。
  final NiumaDanmakuController danmaku;

  @override
  State<NiumaDanmakuOverlay> createState() => _NiumaDanmakuOverlayState();
}

class _NiumaDanmakuOverlayState extends State<NiumaDanmakuOverlay>
    with SingleTickerProviderStateMixin {
  late NiumaDanmakuPainter _painter;
  Listenable? _merged;

  // 内插时钟状态
  Duration _baseVideoPosition = Duration.zero;
  int _baseWallMs = 0;
  bool _isPlaying = false;

  // 帧推进 notifier——Ticker 每帧 notify，painter 通过 merged listen 触发 repaint
  final _FrameNotifier _frameNotifier = _FrameNotifier();
  late final Ticker _ticker;

  Duration _lastObservedVideoPos = Duration.zero;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTick);
    _syncClock();
    _wirePainter();
    widget.video.addListener(_onVideoTick);
    _maybeUpdateTicker();
  }

  void _onTick(Duration _) {
    // 仅 frame notify；painter 在 paint() 内调 positionProvider 拿当前 interpolated 位置
    _frameNotifier.tick();
  }

  /// 把当前 video state 锁进内插基准。每次 video tick 调一次。
  void _syncClock() {
    _baseVideoPosition = widget.video.value.position;
    _baseWallMs = DateTime.now().millisecondsSinceEpoch;
    _isPlaying = widget.video.value.phase == PlayerPhase.playing;
  }

  /// 当前 painter 应使用的"内插位置"。playing 时按 wall clock 推进，
  /// 否则冻结在最近一次 sync 时的 video position。
  Duration _interpolatedPosition() {
    if (!_isPlaying) return _baseVideoPosition;
    final elapsed = DateTime.now().millisecondsSinceEpoch - _baseWallMs;
    return _baseVideoPosition + Duration(milliseconds: elapsed);
  }

  void _maybeUpdateTicker() {
    final shouldRun = _isPlaying;
    if (shouldRun && !_ticker.isActive) {
      _ticker.start();
    } else if (!shouldRun && _ticker.isActive) {
      _ticker.stop();
    }
  }

  void _wirePainter() {
    _merged = Listenable.merge(<Listenable>[
      widget.video,
      widget.danmaku,
      _frameNotifier,
    ]);
    _painter = NiumaDanmakuPainter(
      danmaku: widget.danmaku,
      positionProvider: _interpolatedPosition,
      repaint: _merged,
    );
  }

  void _onVideoTick() {
    final pos = widget.video.value.position;
    final delta = (pos - _lastObservedVideoPos).abs();

    // seek 检测 / 跨桶 lazy load 触发
    if (delta > const Duration(seconds: 1)) {
      widget.danmaku.ensureLoadedFor(pos);
    } else {
      final settings = widget.danmaku.settings;
      final cur = pos.inMilliseconds ~/ settings.bucketSize.inMilliseconds;
      final last =
          _lastObservedVideoPos.inMilliseconds ~/ settings.bucketSize.inMilliseconds;
      if (cur != last) {
        widget.danmaku.ensureLoadedFor(pos);
      }
    }
    _lastObservedVideoPos = pos;

    // 同步内插基准 + 启停 Ticker（phase 切换时必跟）
    _syncClock();
    _maybeUpdateTicker();
  }

  @override
  void didUpdateWidget(covariant NiumaDanmakuOverlay old) {
    super.didUpdateWidget(old);
    if (old.video != widget.video || old.danmaku != widget.danmaku) {
      old.video.removeListener(_onVideoTick);
      _syncClock();
      _wirePainter();
      widget.video.addListener(_onVideoTick);
      _maybeUpdateTicker();
    }
  }

  @override
  void dispose() {
    widget.video.removeListener(_onVideoTick);
    _ticker.dispose();
    _frameNotifier.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: widget.danmaku,
      builder: (ctx, _) {
        if (!widget.danmaku.settings.visible) {
          return const SizedBox.expand();
        }
        // CustomPaint 当 painter != null 时默认 hitTestSelf=true，会吃掉 tap
        // 阻断外层 click-catcher 的 onTap 切换 controls。包一层 IgnorePointer
        // 让 hit test 完全穿透到 Stack 下方。
        return IgnorePointer(
          ignoring: true,
          child: CustomPaint(
            painter: _painter,
            size: Size.infinite,
            child: const SizedBox.expand(),
          ),
        );
      },
    );
  }
}

/// 帧推进 notifier——对外暴露 [tick] 方法，避免直接调用受保护的
/// [ChangeNotifier.notifyListeners]（会触发 invalid_use_of_protected_member）。
class _FrameNotifier extends ChangeNotifier {
  void tick() => notifyListeners();
}
