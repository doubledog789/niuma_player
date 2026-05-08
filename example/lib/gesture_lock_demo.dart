import 'dart:async';

import 'package:flutter/material.dart';
import 'package:niuma_player/niuma_player.dart';

/// 演示 SDK 手势层的两条配置点：
///
/// 1. **`disabledGestures`**：黑名单——传入 [GestureKind] 集合让 SDK 跳过
///    这些手势的 onPan / onTap 处理。典型用例：禁双击 / 禁亮度调节
///    （比如已经有自家亮度滑条不想冲突）。
/// 2. **`gestureHudBuilder`**：完全自定义手势 HUD——拖动时浮在屏幕中央
///    那块 widget。传 null 用 SDK 默认 [NiumaGestureHud]（M16 抖音风）。
///
/// **锁屏按钮（[LockButton]）** SDK 已内置——全屏页左中浮，点击后整个
/// 控件层 + 手势层 freeze，只剩锁按钮自己可点（再点解锁）。业务方不用
/// 配置，开全屏自带。
class GestureLockDemoPage extends StatefulWidget {
  const GestureLockDemoPage({super.key});

  @override
  State<GestureLockDemoPage> createState() => _GestureLockDemoPageState();
}

class _GestureLockDemoPageState extends State<GestureLockDemoPage> {
  late final NiumaPlayerController _controller;

  // 哪些手势被禁用——dynamic toggle 演示。
  Set<GestureKind> _disabled = const {};
  // 是否换成自定义 HUD（演示业务侧定制视觉）。
  bool _useCustomHud = false;

  @override
  void initState() {
    super.initState();
    _controller = NiumaPlayerController(
      NiumaMediaSource.single(
        NiumaDataSource.network(
          'https://artplayer.org/assets/sample/bbb-video.mp4',
        ),
      ),
    );
    unawaited(_controller.initialize());
  }

  @override
  void dispose() {
    unawaited(_controller.dispose());
    super.dispose();
  }

  void _toggleGesture(GestureKind k) {
    setState(() {
      _disabled = {..._disabled};
      if (_disabled.contains(k)) {
        _disabled.remove(k);
      } else {
        _disabled.add(k);
      }
    });
  }

  /// 自定义 HUD——演示业务侧完全替换 SDK 默认视觉的能力。这里做成
  /// 极简的彩色胶囊（圆角 + brand 色 + label）。
  Widget _customHudBuilder(BuildContext ctx, GestureFeedbackState state) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [Color(0xFFEF9F27), Color(0xFFFAC775)],
        ),
        borderRadius: BorderRadius.circular(999),
        boxShadow: [
          BoxShadow(
            color: const Color(0xFFEF9F27).withValues(alpha: 0.4),
            blurRadius: 12,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            _iconFor(state.kind),
            color: Colors.black87,
            size: 20,
          ),
          const SizedBox(width: 8),
          Text(
            state.label ?? state.kind.name,
            style: const TextStyle(
              color: Colors.black87,
              fontSize: 14,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }

  IconData _iconFor(GestureKind kind) {
    switch (kind) {
      case GestureKind.horizontalSeek:
        return Icons.fast_forward;
      case GestureKind.brightness:
        return Icons.brightness_6;
      case GestureKind.volume:
        return Icons.volume_up;
      case GestureKind.longPressSpeed:
        return Icons.speed;
      case GestureKind.doubleTap:
        return Icons.play_arrow;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('手势层 + 锁屏')),
      body: SingleChildScrollView(
        child: Column(
          children: [
            AspectRatio(
              aspectRatio: 16 / 9,
              child: NiumaPlayer(
                controller: _controller,
                disabledGestures: _disabled,
                gestureHudBuilder: _useCustomHud ? _customHudBuilder : null,
              ),
            ),
            const SizedBox(height: 12),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(
                  '手势黑名单（disabledGestures）',
                  style: TextStyle(color: Colors.white70, fontSize: 13),
                ),
              ),
            ),
            const SizedBox(height: 4),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: GestureKind.values.map((k) {
                  final disabled = _disabled.contains(k);
                  return FilterChip(
                    label: Text(k.name),
                    selected: disabled,
                    onSelected: (_) => _toggleGesture(k),
                    selectedColor:
                        const Color(0xFFEF9F27).withValues(alpha: 0.3),
                    checkmarkColor: const Color(0xFFEF9F27),
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: SwitchListTile(
                contentPadding: EdgeInsets.zero,
                title: const Text(
                  '自定义 HUD (gestureHudBuilder)',
                  style: TextStyle(color: Colors.white, fontSize: 14),
                ),
                subtitle: const Text(
                  '试试拖动屏幕：HUD 变成 brand 色胶囊',
                  style: TextStyle(color: Colors.white60, fontSize: 11),
                ),
                value: _useCustomHud,
                onChanged: (v) => setState(() => _useCustomHud = v),
              ),
            ),
            const Divider(color: Colors.white12, height: 24),
            const Padding(
              padding: EdgeInsets.symmetric(horizontal: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _DocBlock(
                    title: 'disabledGestures',
                    body:
                        '黑名单 [GestureKind] 集合。SDK 默认全开（除了 PiP 期间）。'
                        '业务侧禁某个手势：在上面 chip 切下试试。'
                        '\n\n**注意**：SDK 默认只在全屏页启用全部手势（M13 设计），inline '
                        '场景看 NiumaPlayer.gesturesEnabledInline（默认 false）。',
                  ),
                  SizedBox(height: 8),
                  _DocBlock(
                    title: 'gestureHudBuilder',
                    body:
                        '完全替换默认 HUD 的视觉。签名 (BuildContext, '
                        'GestureFeedbackState) → Widget。state 字段：kind / progress '
                        '/ label / icon / iconAsset，业务自由组合。',
                  ),
                  SizedBox(height: 8),
                  _DocBlock(
                    title: 'LockButton（SDK 内置）',
                    body:
                        '全屏页左中浮的"小锁"按钮——点击后整个 control bar + 手势层 '
                        'freeze，只剩 LockButton 自己可点（再点解锁）。业务方零配置自带。'
                        '业务想自定义锁屏视觉直接 export 用 LockButton widget。',
                  ),
                  SizedBox(height: 8),
                  _DocBlock(
                    title: '5 种手势对应 GestureKind',
                    body:
                        'horizontalSeek (水平拖快进/退)、brightness (左半屏垂直拖亮度)、'
                        'volume (右半屏垂直拖音量)、longPressSpeed (长按 2x 倍速)、'
                        'doubleTap (双击 toggle play/pause)。',
                  ),
                ],
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
  }
}

class _DocBlock extends StatelessWidget {
  const _DocBlock({required this.title, required this.body});
  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: const Color(0xFF252526),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: Color(0xFFEF9F27),
              fontSize: 13,
              fontWeight: FontWeight.w600,
              fontFamily: 'monospace',
            ),
          ),
          const SizedBox(height: 4),
          Text(
            body,
            style: const TextStyle(color: Colors.white70, fontSize: 12),
          ),
        ],
      ),
    );
  }
}
