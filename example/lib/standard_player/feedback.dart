// 反馈层：封面 / loading / 错误 / 结束。
//
// 这四层都是「按 NiumaPlayerValue 的某个状态盖在画面上」的简单覆盖层，
// 由 StandardPlayer 决定何时挂载。接入方照着这个模式扩自己的样式即可。
import 'package:flutter/material.dart';

/// 封面层：首帧出来之前（`value.size == Size.zero`）盖一张占位封面。
///
/// 模板里用纯色 + 居中大 play 图标占位；接入方通常换成真实 poster：
/// 把这里替换成 `Image.network(posterUrl, fit: BoxFit.cover)` 即可。
class CoverLayer extends StatelessWidget {
  /// 构造封面层。
  const CoverLayer({super.key});

  @override
  Widget build(BuildContext context) {
    return Container(
      color: const Color(0xFF101418),
      alignment: Alignment.center,
      child: const Icon(
        Icons.play_circle_outline,
        size: 72,
        color: Colors.white54,
      ),
    );
  }
}

/// Loading 层：opening / buffering 时居中转圈。
class LoadingLayer extends StatelessWidget {
  /// 构造 loading 层。
  const LoadingLayer({super.key});

  @override
  Widget build(BuildContext context) {
    return const Center(
      child: CircularProgressIndicator(color: Colors.white),
    );
  }
}

/// 错误层：显示错误信息 + 重试按钮。
class ErrorLayer extends StatelessWidget {
  /// 构造错误层。[message] 为错误描述，[onRetry] 触发重试。
  const ErrorLayer({super.key, required this.message, required this.onRetry});

  /// 面向用户的错误描述。
  final String message;

  /// 点「重试」回调（一般是 `controller.initialize()`）。
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black54,
      // 错误信息可能很长（codec 报错带完整原生堆栈），小尺寸播放区里 Column
      // 会竖向溢出——SingleChildScrollView 兜住任意长度。
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, color: Colors.white, size: 40),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Text(
                  message,
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.white),
                ),
              ),
              const SizedBox(height: 12),
              FilledButton.tonal(onPressed: onRetry, child: const Text('重试')),
            ],
          ),
        ),
      ),
    );
  }
}

/// 结束层：播放到结尾时显示重播按钮。
class EndedLayer extends StatelessWidget {
  /// 构造结束层。[onReplay] 触发重播（一般是 `seekTo(0)..play()`）。
  const EndedLayer({super.key, required this.onReplay});

  /// 点「重播」回调。
  final VoidCallback onReplay;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: Colors.black54,
      child: Center(
        child: IconButton(
          iconSize: 56,
          icon: const Icon(Icons.replay, color: Colors.white),
          onPressed: onReplay,
        ),
      ),
    );
  }
}
