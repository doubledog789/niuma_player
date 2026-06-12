// 短视频 / 短剧 feed demo —— 单个播放器复用换源 + 跟手滑（yc141 式）。
//
// **为什么单 video 复用**：本 demo 模拟「URL 要滑到当前条才请求详情拿到」的业务，
// 下一条 URL 预先不知道、池的预加载用不上；而 iOS Safari 的「有声播放激活」绑在
// 同一个 `<video>` 元素上，每条新建 video 会丢激活、滑动自动播只能静音。所以全程
// 复用一个 controller（一个 `<video>`），滑到某条就 `controller.load(该条)` 换源。
//
// **怎么做到「视频跟手滑」**：把 `NiumaPlayerView` 放进「当前激活页」的 PageView
// item 内（不是固定一层），video 就跟着 page 一起滑入滑出。同一时刻只有激活页
// 渲染 `NiumaPlayerView`、其余页显示封面占位，所以不会出现同一 `<video>` 两处
// mount 的冲突。
//
// 「已知全部 URL、要预加载多条秒切」的场景另见 `NiumaPlayerPool`。
import 'dart:async';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:niuma_player/niuma_player.dart';

import 'audio_unlock.dart'
    if (dart.library.js_interop) 'audio_unlock_web.dart';

/// 公共测试 mp4，6 条不同 URL。全部**有音轨 + 较长 + 偶数宽 + 有 Content-Length**
/// （选源踩过的坑：纯画面哑视频 / 奇数宽 Android 黑帧 / 超大非 faststart 播不了 /
/// chunked 无长度 seek 不稳）。
const List<String> _videoUrls = [
  'https://media.w3.org/2010/05/video/movie_300.mp4',
  'https://media.w3.org/2010/05/sintel/trailer.mp4',
  'https://media.w3.org/2010/05/sintel/trailer_hd.mp4',
  'https://mdn.github.io/learning-area/html/multimedia-and-embedding/video-and-audio-content/rabbit320.mp4',
  'https://interactive-examples.mdn.mozilla.net/media/cc0-videos/flower.mp4',
  'https://artplayer.org/assets/sample/bbb-video.mp4',
];

class FeedPage extends StatefulWidget {
  const FeedPage({super.key});

  @override
  State<FeedPage> createState() => _FeedPageState();
}

class _FeedPageState extends State<FeedPage> with WidgetsBindingObserver {
  final _pageController = PageController();

  late final List<NiumaMediaSource> _sources = _videoUrls
      .map((u) => NiumaMediaSource.single(NiumaDataSource.network(u)))
      .toList(growable: false);

  /// 全程复用一个 controller（一个 `<video>`）——切视频靠 [NiumaPlayerController.load]
  /// 换源，不重建。这是 iOS Safari 能持续有声的关键。
  /// feed 维持默认 Texture 渲染：PlatformView（SurfaceView）虽然画质上限更高，
  /// 但 feed 每滑一条都重建 AndroidView/SurfaceView，换页有黑闪。详情页 /
  /// 单播放器场景才建议开 useAndroidPlatformView（见 standard_player）。
  late final NiumaPlayerController _controller =
      NiumaPlayerController(_sources[0]);

  /// 换源序号——快滑时 await load 期间用户又滑走，靠它作废过期的激活。
  int _activateSeq = 0;

  /// 当前真正在播的页 index（[_activate] 成功后更新）——只有这页渲染视频，其余
  /// 页显示封面。
  int _activeIndex = -1;

  /// 翻页 debounce：快滑只在停稳后才真正换源（见 [_onPageChanged]）。
  Timer? _pageSettleTimer;

  /// iOS Safari「每次点击 unmute 当前播放」监听的反注册函数。
  void Function()? _iosTapUnsub;

  /// 用户是否已解锁声音。iOS Safari 点一次激活后置 true（同一 `<video>` 之后
  /// 换源持续有声）；其它 web 首次交互后置 true（sticky）。
  bool _audioUnlocked = false;

  bool get _isIosWebSafari =>
      webFullscreenMode == NiumaWebFullscreenMode.nativeVideoElement;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    if (_isIosWebSafari) {
      // iOS Safari：WebKit 不发 sticky 激活，带声音播放每次都要在用户手势同步栈
      // 内。复用同一 `<video>` 后，点一下屏幕在手势栈内 unmute、并标记已解锁，之后
      // 换源 autoplay 就能持续有声（同一已激活元素）。
      _iosTapUnsub = onEveryUserTap(_unmuteForIosSafari);
    } else {
      onFirstUserGesture(_unlockAudio);
    }
    _activate(0, initial: true);
  }

  /// 激活第 [index] 条：换源（首条走 initialize）→ 静音策略 → 循环 → 播放 →
  /// 标记为激活页（这页才渲染视频）。
  ///
  /// 真实业务应在这里先「请求详情拿到该条 URL」再 `load`；demo 直接用已知 URL。
  Future<void> _activate(int index, {bool initial = false}) async {
    final seq = ++_activateSeq;
    try {
      if (initial) {
        await _controller.initialize();
      } else {
        await _controller.load(_sources[index]);
      }
    } catch (e) {
      debugPrint('[feed] #$index load failed: $e');
      return;
    }
    if (!mounted || seq != _activateSeq) return; // 用户已滑走，作废

    if (kIsWeb) {
      // 未解锁前静音自动播（绕过 autoplay 拦截）；解锁后带声音。iOS Safari 复用
      // 同一 `<video>`，点一次激活后 _audioUnlocked=true，换源后持续有声。
      await _controller.setVolume(_audioUnlocked ? 1 : 0);
    }
    await _controller.setLooping(true);
    await _controller.play();
    if (mounted) setState(() => _activeIndex = index);
  }

  void _onPageChanged(int index) {
    _pageSettleTimer?.cancel();
    _pageSettleTimer =
        Timer(const Duration(milliseconds: 300), () => _activate(index));
  }

  void _unlockAudio() {
    if (_audioUnlocked) return;
    _audioUnlocked = true;
    _controller.setVolume(1);
  }

  void _unmuteForIosSafari() {
    // 点一下在手势栈内 unmute——同一 `<video>` 一旦有声激活，后续换源 autoplay
    // 持续有声（不用每条都点）。标记 _audioUnlocked 让换源后保持有声。
    _audioUnlocked = true;
    _controller.setVolume(1);
  }

  /// app 进后台（home / 切走 / web 页面隐藏）暂停，回前台续播——否则 feed 会在
  /// 后台继续播。（reparent 自愈也加了「页面隐藏不自愈」双保险，见 web backend。）
  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _controller.play();
    } else {
      _controller.pause();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _iosTapUnsub?.call();
    _pageSettleTimer?.cancel();
    _pageController.dispose();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        fit: StackFit.expand,
        children: [
          // video 放进「当前激活页」item 内 → 跟着 PageView 一起滑（跟手、像真
          // feed）。非激活页显示封面占位。整个 feed 仍只有一个 `<video>`（同一
          // controller）——只激活页渲染 NiumaPlayerView，不冲突。
          PageView.builder(
            controller: _pageController,
            scrollDirection: Axis.vertical,
            itemCount: _sources.length,
            onPageChanged: _onPageChanged,
            itemBuilder: (context, index) => _FeedItem(
              index: index,
              total: _sources.length,
              active: index == _activeIndex,
              controller: _controller,
            ),
          ),
        ],
      ),
    );
  }
}

/// 单页：激活页（当前完全停稳那页）渲染真实视频——它在 page item 内，所以跟着
/// PageView 一起滑（跟手）。非激活页显示封面占位。整个 feed 只有一个 `<video>`
/// （同一 controller），靠「只激活页渲染 NiumaPlayerView」保证同一时刻只 mount
/// 一处、不冲突。
class _FeedItem extends StatelessWidget {
  const _FeedItem({
    required this.index,
    required this.total,
    required this.active,
    required this.controller,
  });

  final int index;
  final int total;
  final bool active;
  final NiumaPlayerController controller;

  @override
  Widget build(BuildContext context) {
    return Stack(
      fit: StackFit.expand,
      children: [
        if (active)
          ValueListenableBuilder<NiumaPlayerValue>(
            valueListenable: controller,
            builder: (context, value, _) {
              // 激活页正常已就绪（_activate 在 play 后才置 active）；换源/缓冲未就
              // 绪时用黑底兜底。
              if (!value.initialized) {
                return const ColoredBox(color: Colors.black);
              }
              final size = value.size;
              final w = size.width <= 0 ? 16.0 : size.width;
              final h = size.height <= 0 ? 9.0 : size.height;
              return ColoredBox(
                color: Colors.black,
                child: Center(
                  child: FittedBox(
                    fit: BoxFit.contain,
                    clipBehavior: Clip.hardEdge,
                    child: SizedBox(
                      width: w,
                      height: h,
                      child: NiumaPlayerView(controller),
                    ),
                  ),
                ),
              );
            },
          )
        else
          const ColoredBox(color: Colors.black),
        Positioned(
          right: 12,
          bottom: 24,
          child: Text(
            '${index + 1} / $total',
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ),
      ],
    );
  }
}
