// 顶栏 / 底栏控件。两者共用 StandardPlayer 的一个可见性开关，
// 这里只负责渲染 + 把交互回调出去，不持有显隐状态。
import 'package:flutter/material.dart';
import 'package:niuma_player/niuma_player.dart';

/// 顶栏：返回键 + 标题 + 占位「更多」键。
class TopBar extends StatelessWidget {
  /// 构造顶栏。[title] 标题；[onBack] 返回回调（null 时不显示返回键）。
  const TopBar({super.key, required this.title, this.onBack});

  /// 标题文字。
  final String title;

  /// 返回回调；为 null 时隐藏返回键（如最外层无可 pop 时）。
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [Colors.black54, Colors.transparent],
        ),
      ),
      child: Row(
        children: [
          if (onBack != null)
            IconButton(
              icon: const Icon(Icons.arrow_back, color: Colors.white),
              onPressed: onBack,
            )
          else
            const SizedBox(width: 12),
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: const TextStyle(color: Colors.white, fontSize: 16),
            ),
          ),
          // 占位「更多」键——接入方挂菜单 / 投屏 / 设置等。
          IconButton(
            icon: const Icon(Icons.more_vert, color: Colors.white),
            onPressed: () {},
          ),
        ],
      ),
    );
  }
}

/// 底栏：play/pause + 当前时间 + 进度条（带 buffered）+ 总时间 + 全屏键。
class BottomBar extends StatelessWidget {
  /// 构造底栏。
  const BottomBar({
    super.key,
    required this.value,
    required this.onPlayPause,
    required this.onSeek,
    required this.onFullscreen,
    required this.isFullscreen,
  });

  /// 当前播放快照。
  final NiumaPlayerValue value;

  /// play/pause 切换回调。
  final VoidCallback onPlayPause;

  /// 拖动进度回调。
  final ValueChanged<Duration> onSeek;

  /// 全屏键回调（进 / 退由 [isFullscreen] 决定图标）。
  final VoidCallback onFullscreen;

  /// 当前是否在全屏页内（决定全屏键图标）。
  final bool isFullscreen;

  @override
  Widget build(BuildContext context) {
    final position = value.position;
    final duration = value.duration;
    return Container(
      padding: const EdgeInsets.fromLTRB(4, 8, 12, 4),
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.bottomCenter,
          end: Alignment.topCenter,
          colors: [Colors.black54, Colors.transparent],
        ),
      ),
      child: Row(
        children: [
          IconButton(
            icon: Icon(
              value.isPlaying ? Icons.pause : Icons.play_arrow,
              color: Colors.white,
            ),
            onPressed: onPlayPause,
          ),
          Text(
            formatVideoTime(position),
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8),
              child: _ProgressBar(
                position: position,
                duration: duration,
                buffered: value.bufferedPosition,
                onSeek: onSeek,
              ),
            ),
          ),
          Text(
            formatVideoTime(duration),
            style: const TextStyle(color: Colors.white, fontSize: 12),
          ),
          IconButton(
            icon: Icon(
              isFullscreen ? Icons.fullscreen_exit : Icons.fullscreen,
              color: Colors.white,
            ),
            onPressed: onFullscreen,
          ),
        ],
      ),
    );
  }
}

/// 进度条：底层一条 buffered 灰条，上面叠可拖动的 Slider。
class _ProgressBar extends StatelessWidget {
  const _ProgressBar({
    required this.position,
    required this.duration,
    required this.buffered,
    required this.onSeek,
  });

  final Duration position;
  final Duration duration;
  final Duration buffered;
  final ValueChanged<Duration> onSeek;

  @override
  Widget build(BuildContext context) {
    final maxMs = duration.inMilliseconds;
    final hasDuration = maxMs > 0;
    final bufferedFraction =
        hasDuration ? (buffered.inMilliseconds / maxMs).clamp(0.0, 1.0) : 0.0;
    return Stack(
      alignment: Alignment.center,
      children: [
        // buffered 底条。
        FractionallySizedBox(
          alignment: Alignment.centerLeft,
          widthFactor: bufferedFraction,
          child: Container(
            height: 3,
            decoration: BoxDecoration(
              color: Colors.white38,
              borderRadius: BorderRadius.circular(2),
            ),
          ),
        ),
        SliderTheme(
          data: SliderTheme.of(context).copyWith(
            trackHeight: 3,
            thumbShape: const RoundSliderThumbShape(enabledThumbRadius: 6),
            overlayShape: const RoundSliderOverlayShape(overlayRadius: 12),
            activeTrackColor: Colors.white,
            inactiveTrackColor: Colors.transparent,
            thumbColor: Colors.white,
          ),
          child: Slider(
            value: position.inMilliseconds.clamp(0, maxMs).toDouble(),
            max: hasDuration ? maxMs.toDouble() : 1,
            onChanged: hasDuration
                ? (v) => onSeek(Duration(milliseconds: v.round()))
                : null,
          ),
        ),
      ],
    );
  }
}
