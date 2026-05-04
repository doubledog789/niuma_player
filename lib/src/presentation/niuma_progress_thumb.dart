import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../niuma_sdk_assets.dart';

/// 进度条上的牛马表情头像（Debug 风格 thumb）。
///
/// 监听拖动方向、速度和暂停时长，自动切换 5 种表情：
///   - idle           → ×× 死机眼
///   - seekForward    → 微笑
///   - seekBackward   → 委屈
///   - seekFast       → 吃惊
///   - paused（5s+） → 睡觉
///
/// 资源在 [NiumaSdkAssets.thumbDefault]…[NiumaSdkAssets.thumbSleep]。
class NiumaProgressThumb extends StatefulWidget {
  const NiumaProgressThumb({
    super.key,
    required this.progress,
    this.isPlaying = true,
    this.isDragging = false,
    this.seekDirection = 0,
    this.seekSpeed = 0,
    this.size = 32,
    this.fastSpeedThreshold = 50,
    this.sleepAfterMs = 5000,
  });

  /// 当前播放进度 0..1。仅用于 [Semantics]，不影响表情切换。
  final double progress;

  /// 是否正在播放。暂停 [sleepAfterMs] ms 后切到 sleep。
  final bool isPlaying;

  /// 是否在拖动 thumb。
  final bool isDragging;

  /// 拖动方向：-1 后退，0 静止，1 前进。
  final int seekDirection;

  /// 拖动速度（像素/100ms）。超过 [fastSpeedThreshold] 切到 shock 表情。
  final double seekSpeed;

  /// thumb 尺寸。
  final double size;

  /// 高速判定阈值。
  final double fastSpeedThreshold;

  /// 暂停多少 ms 后切到 sleep。
  final int sleepAfterMs;

  @override
  State<NiumaProgressThumb> createState() => _NiumaProgressThumbState();
}

class _NiumaProgressThumbState extends State<NiumaProgressThumb> {
  Timer? _sleepTimer;
  NiumaProgressThumbState _state = NiumaProgressThumbState.idle;

  @override
  void initState() {
    super.initState();
    _evaluate();
  }

  @override
  void didUpdateWidget(NiumaProgressThumb oldWidget) {
    super.didUpdateWidget(oldWidget);
    _evaluate();
  }

  void _evaluate() {
    _sleepTimer?.cancel();

    NiumaProgressThumbState next;
    if (widget.isDragging) {
      if (widget.seekSpeed.abs() > widget.fastSpeedThreshold) {
        next = NiumaProgressThumbState.seekFast;
      } else if (widget.seekDirection > 0) {
        next = NiumaProgressThumbState.seekForward;
      } else if (widget.seekDirection < 0) {
        next = NiumaProgressThumbState.seekBackward;
      } else {
        next = NiumaProgressThumbState.idle;
      }
    } else if (!widget.isPlaying) {
      next = NiumaProgressThumbState.idle;
      _sleepTimer = Timer(Duration(milliseconds: widget.sleepAfterMs), () {
        if (mounted && !widget.isPlaying) {
          setState(() => _state = NiumaProgressThumbState.paused);
        }
      });
    } else {
      next = NiumaProgressThumbState.idle;
    }

    if (next != _state) setState(() => _state = next);
  }

  @override
  void dispose() {
    _sleepTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 200),
      transitionBuilder: (child, animation) =>
          ScaleTransition(scale: animation, child: child),
      child: SvgPicture.asset(
        NiumaSdkAssets.thumbForState(_state),
        key: ValueKey(_state),
        width: widget.size,
        height: widget.size,
      ),
    );
  }
}
