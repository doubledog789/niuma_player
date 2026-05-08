import 'dart:async';

import 'package:flutter/foundation.dart' show defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:niuma_player/niuma_player.dart';

/// 演示 SDK 投屏（DLNA / AirPlay）+ PiP（画中画）的接入：
///
/// ## 投屏
/// SDK 0.9 起 [NiumaCastRegistry] 在首次使用时**自动 register**
/// `DlnaCastService` + `AirPlayCastService`——业务方零配置就能用，控件层默认
/// 带 cast 按钮。如果业务自家有 Chromecast / 自研协议，仍可在 main() 里
/// 显式 `NiumaCastRegistry.register(...)` 注入。
///
/// 监听 [CastStarted] / [CastEnded] 事件做埋点 / 业务侧 UI 反馈。
///
/// ## PiP
/// **iOS**：SDK 内部反射拿 video_player 的 AVPlayer，业务侧零配置；
/// 但 PiP 必须由 user gesture 直接 trigger（点 PiP 按钮）。
///
/// **Android**：业务侧 [MainActivity] 必须重写 `onPictureInPictureModeChanged`
/// 调 `NiumaPlayerPlugin.reportPipModeChanged(...)` —— 否则 SDK 收不到 PiP
/// 状态变化。AndroidManifest 里 `<activity>` 加 `android:supportsPictureInPicture="true"`。
///
/// **Web**：浏览器原生 PiP 需 user gesture 直 trigger 不能跨 frame，控件层
/// 在 web 上隐藏 cast / PiP 按钮（[_showMoreMenu] 跳过）避免误导。
class CastPipDemoPage extends StatefulWidget {
  const CastPipDemoPage({super.key});

  @override
  State<CastPipDemoPage> createState() => _CastPipDemoPageState();
}

class _CastPipDemoPageState extends State<CastPipDemoPage> {
  late final NiumaPlayerController _controller;
  StreamSubscription<NiumaPlayerEvent>? _eventSub;
  final List<String> _eventLog = <String>[];

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
    // 监听 cast / PiP 事件——业务侧用来做埋点 / toast / UI 反馈。
    _eventSub = _controller.events.listen((e) {
      if (!mounted) return;
      if (e is CastStarted || e is CastEnded || e is PipModeChanged) {
        setState(() {
          _eventLog.insert(
            0,
            '${DateTime.now().toIso8601String().substring(11, 19)}  $e',
          );
          if (_eventLog.length > 20) _eventLog.removeLast();
        });
      }
    });
    unawaited(_controller.initialize());
  }

  @override
  void dispose() {
    _eventSub?.cancel();
    unawaited(_controller.dispose());
    super.dispose();
  }

  /// 程序触发进入 PiP——iOS Safari 上必须由 user gesture 直接调用，跨
  /// frame 异步会被浏览器 reject。本 demo 在按钮 onPressed 里同步调即可。
  Future<void> _enterPip() async {
    final ok = await _controller.enterPictureInPicture();
    if (!mounted) return;
    if (!ok) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('PiP 启动失败——可能设备不支持或权限被拒')),
      );
    }
  }

  /// 程序触发退出 PiP（业务侧很少用——通常用户在 PiP 小窗自己点关闭，
  /// 或 SDK 监听到 PipModeChanged(false) 自动同步）。
  Future<void> _exitPip() async {
    await _controller.exitPictureInPicture();
  }

  @override
  Widget build(BuildContext context) {
    final platform = kIsWeb
        ? 'Web'
        : defaultTargetPlatform == TargetPlatform.iOS
            ? 'iOS'
            : defaultTargetPlatform == TargetPlatform.android
                ? 'Android'
                : '其它';

    return Scaffold(
      appBar: AppBar(title: const Text('投屏 + 画中画')),
      body: Column(
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: NiumaPlayer(controller: _controller),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    onPressed: _enterPip,
                    icon: const Icon(Icons.picture_in_picture_alt),
                    label: const Text('进入 PiP'),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _exitPip,
                    icon: const Icon(Icons.cancel_outlined),
                    label: const Text('退出 PiP'),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: ValueListenableBuilder<NiumaPlayerValue>(
              valueListenable: _controller,
              builder: (ctx, v, _) => _StatusRow(
                platform: platform,
                isInPip: v.isInPictureInPicture,
                pipSupported: v.isPictureInPictureSupported,
              ),
            ),
          ),
          const Divider(color: Colors.white12, height: 24),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _DocBlock(
                  title: '投屏（Cast）',
                  body: kIsWeb
                      ? 'Web 上浏览器无可靠程序化 cast API（DLNA/AirPlay 不可控、'
                          'Chromecast 需 cast SDK + user gesture）——SDK 在 web '
                          '隐藏 cast 按钮避免误导用户。'
                      : 'SDK 0.9 起 NiumaCastRegistry 自动 register DLNA + AirPlay。'
                          '控件层默认带 cast 按钮——点击 → 设备扫描 panel → 选设备 → '
                          'controller.connectCast(session)。本地播放器自动暂停 + '
                          '视频区显示"投屏中"覆盖层。监听 controller.events → '
                          'CastStarted / CastEnded 做业务侧反馈。',
                ),
                const SizedBox(height: 8),
                _DocBlock(
                  title: '画中画（PiP）',
                  body: kIsWeb
                      ? 'Web PiP 需 user gesture 直 trigger 不能跨 frame——SDK 在 '
                          'web 隐藏 PiP 按钮避免误导。'
                      : defaultTargetPlatform == TargetPlatform.iOS
                          ? 'iOS：SDK 内部反射拿 video_player 的 AVPlayer 接 '
                              'AVPictureInPictureController，业务零配置。**必须由 '
                              'user gesture 直接调用** controller.enterPictureInPicture()。'
                          : 'Android：业务侧 MainActivity 必须重写 '
                              'onPictureInPictureModeChanged 调 '
                              'NiumaPlayerPlugin.reportPipModeChanged(...)；'
                              'AndroidManifest <activity> 加 '
                              'android:supportsPictureInPicture="true"。',
                ),
                const SizedBox(height: 8),
                const _DocBlock(
                  title: 'controller.events 监听',
                  body:
                      'CastStarted / CastEnded / PipModeChanged 是业务侧最关心的 '
                      '3 个事件——埋点、toast、跳转、recover state 都靠它们。'
                      '这页面把这 3 个事件实时打到下方日志。',
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 12),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                '事件日志：',
                style: TextStyle(color: Colors.white70, fontSize: 12),
              ),
            ),
          ),
          const SizedBox(height: 4),
          Expanded(
            child: ListView.builder(
              padding: const EdgeInsets.symmetric(horizontal: 12),
              itemCount: _eventLog.length,
              itemBuilder: (ctx, i) => Text(
                _eventLog[i],
                style: const TextStyle(
                  color: Colors.white60,
                  fontSize: 11,
                  fontFamily: 'monospace',
                  height: 1.4,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _StatusRow extends StatelessWidget {
  const _StatusRow({
    required this.platform,
    required this.isInPip,
    required this.pipSupported,
  });
  final String platform;
  final bool isInPip;
  final bool pipSupported;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        _Chip(label: '平台', value: platform),
        const SizedBox(width: 8),
        _Chip(
          label: 'PiP 支持',
          value: pipSupported ? 'YES' : 'NO',
          ok: pipSupported,
        ),
        const SizedBox(width: 8),
        _Chip(
          label: '当前 PiP',
          value: isInPip ? 'YES' : 'NO',
          ok: !isInPip,
        ),
      ],
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip({required this.label, required this.value, this.ok});
  final String label;
  final String value;
  final bool? ok;

  @override
  Widget build(BuildContext context) {
    final color = ok == true
        ? const Color(0xFF6BCB77)
        : ok == false
            ? const Color(0xFFFF6B6B)
            : Colors.white60;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: const Color(0xFF252526),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: color.withValues(alpha: 0.4), width: 0.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '$label: ',
            style: const TextStyle(color: Colors.white60, fontSize: 11),
          ),
          Text(
            value,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
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
