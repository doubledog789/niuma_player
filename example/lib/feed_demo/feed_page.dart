// 短视频 / 短剧 feed demo —— 演示用 NiumaPlayerPool 做
// 「翻页预加载 + controller 复用 + 容量上限防 OOM」。
//
// 核心思路：竖向 PageView 一页一条视频，当前页 controller 从池里 acquire。
// 非 Android 平台预加载下一条；Android native/IJK 多实例的瓶颈是
// MediaCodec buffer slot，因此示例在 Android 上只保留当前页，离屏后显式
// evict，避免多个 decoder 同时存活。
import 'dart:async';

import 'package:flutter/foundation.dart'
    show TargetPlatform, defaultTargetPlatform, kIsWeb;
import 'package:flutter/material.dart';
import 'package:niuma_player/niuma_player.dart';

import 'audio_unlock.dart'
    if (dart.library.js_interop) 'audio_unlock_web.dart';

/// 公共测试 mp4，6 条不同 URL —— URL 不同才能体现池按 key（source 主 URL）
/// 区分 / 复用 controller。全部**有音轨 + 较长**（前面那批 test-videos.co.uk
/// 是哑的纯画面、且只有 10s，已弃）。
///
/// 选源硬性要求（都踩过坑）：
/// 1. **有音轨**——纯画面测试片（如 test-videos.co.uk）是哑的，feed 听不到声音。
/// 2. **偶数宽**——奇数宽（如 853）H.264 在 Android 硬解（MediaCodec）上常出黑帧。
/// 3. **别用「超大 + 非 faststart」**——moov 在文件末尾时浏览器要下完整个文件才
///    能起播；几 MB 无所谓，249MB 那种就等于"播不了"。faststart（moov 在头）的
///    大文件可边下边播。
/// 4. **有 Content-Length**——chunked 无长度的源（如 samplelib）range / seek 不稳。
const List<String> _videoUrls = [
  // movie_300：320×240、约 5min、有声音、faststart、2.7MB —— 小而长，作首屏。
  'https://media.w3.org/2010/05/video/movie_300.mp4',
  // Sintel 预告：854×480 / 1920×818、约 52s、有声音。
  'https://media.w3.org/2010/05/sintel/trailer.mp4',
  'https://media.w3.org/2010/05/sintel/trailer_hd.mp4',
  // MDN cc0 短片：有声音、faststart，给池 key 增加多样性。
  'https://mdn.github.io/learning-area/html/multimedia-and-embedding/video-and-audio-content/rabbit320.mp4',
  'https://interactive-examples.mdn.mozilla.net/media/cc0-videos/flower.mp4',
  // Big Buck Bunny 全片：424×240、约 10min、有声音、faststart、38MB —— 放最后。
  'https://artplayer.org/assets/sample/bbb-video.mp4',
];

class FeedPage extends StatefulWidget {
  const FeedPage({super.key});

  @override
  State<FeedPage> createState() => _FeedPageState();
}

class _FeedPageState extends State<FeedPage> {
  final _pageController = PageController();

  /// 每条视频包成单源 NiumaMediaSource，池按它的主 URL 当 key。
  late final List<NiumaMediaSource> _sources = _videoUrls
      .map((u) => NiumaMediaSource.single(NiumaDataSource.network(u)))
      .toList(growable: false);

  NiumaPlayerPool? _pool;

  /// 已 acquire 到、当前页可直接渲染的 controller（index -> controller）。
  /// 池负责生命周期，这里只缓存「拿到手的引用」给对应页 widget 用。
  final Map<int, NiumaPlayerController> _ready = {};

  int _currentIndex = 0;
  int _activationSeq = 0;

  /// web：用户首次与页面交互前，feed 静音自动播（绕开浏览器 autoplay 拦截）；
  /// 交互后置 true，之后的页带声音。原生端一直有声音、此标志不参与。
  bool _audioUnlocked = false;

  bool get _isAndroid =>
      !kIsWeb && defaultTargetPlatform == TargetPlatform.android;

  /// iPhone Safari：iOS 限制"同时只能播一个 `<video>`"，feed 多实例会互抢、
  /// 快滑时频繁 buffering↔ready 抖动——这里降为单实例 + 跳预加载，和 Android 一样。
  bool get _isIosWebSafari =>
      webFullscreenMode == NiumaWebFullscreenMode.nativeVideoElement;

  /// release 时必须传池 key；SDK 暴露 [NiumaPlayerPool.keyFor] 避免示例
  /// 复制内部规则。
  String _keyOf(int index) => NiumaPlayerPool.keyFor(_sources[index]);

  @override
  void initState() {
    super.initState();
    // web：首次任意交互后解锁音频（非 web 为空操作）。
    onFirstUserGesture(_unlockAudio);
    _bootstrap();
  }

  /// 用户首次与页面交互后解锁音频：标记 + 给当前页 controller 取消静音。
  /// 仅 web 触发（见 audio_unlock_web.dart）。
  void _unlockAudio() {
    if (_audioUnlocked) return;
    _audioUnlocked = true;
    _ready[_currentIndex]?.setVolume(1);
  }

  Future<void> _bootstrap() async {
    final heapMb = await const DefaultPlatformBridge().processHeapLimitMb();
    // Android native/IJK 多实例的瓶颈主要是 MediaCodec buffer slot，不是
    // Dart/Java heap。Feed demo 在 Android 上保守限制为 1，避免滑动时同时
    // 拉起多个硬解 decoder。
    final cap = (_isAndroid || _isIosWebSafari)
        ? 1
        : NiumaPlayerPool.computeCapacityForHeap(heapMb);
    debugPrint('[feed] heapLimit=${heapMb}MB -> pool capacity=$cap');
    if (!mounted) return;
    setState(() {
      _pool = NiumaPlayerPool(
        capacity: cap,
        controllerFactory: (s) => NiumaPlayerController(s),
      );
    });
    await _activate(_currentIndex);
  }

  /// 激活某一页：acquire 当前页并播，预加载下一条，release 上一条。
  ///
  /// **关键**：`_ready` 只保留「当前页」这一个 controller 引用。其余页一律由
  /// 池按容量 LRU / stale 回收——feed 不再缓存它们的引用，从根上杜绝「拿一个
  /// 已被池 dispose 的 controller 去渲染」导致的报错。非当前页渲染时拿到 null
  /// → 显示 loading，滑过去成为当前页时再 acquire。
  Future<void> _activate(int index) async {
    final seq = ++_activationSeq;
    final pool = _pool;
    _currentIndex = index;
    debugPrint('[feed] page -> $index (key=${_keyOf(index)})');
    if (pool == null) return;

    final staleReady = Map<int, NiumaPlayerController>.from(_ready);
    staleReady.remove(index);
    if (staleReady.isNotEmpty) {
      // 先让 widget 树解绑旧 controller，再 dispose 它的 native backend。
      _ready.removeWhere((i, _) => i != index);
      if (mounted) setState(() {});
      await WidgetsBinding.instance.endOfFrame;
    }

    // 先释放所有非当前页，再 acquire 新页。Android 上这一步尤其重要：
    // 旧 native decoder 不先 dispose，新 decoder 初始化时可能抢不到足够
    // MediaCodec buffer slots。
    for (final entry in staleReady.entries) {
      final key = _keyOf(entry.key);
      if (pool.holds(key)) {
        await entry.value.pause();
        pool.release(key);
        await pool.evict(key);
      }
    }
    if (!mounted || _pool != pool || _activationSeq != seq) return;

    final NiumaPlayerController c;
    try {
      c = await pool.acquire(_sources[index]);
    } catch (e) {
      // 源失败（如 403 / 网络错）——别让 feed 崩,记一笔,这一页空着,其它页照常。
      debugPrint('[feed] acquire #$index FAILED: $e');
      return;
    }
    // 容量重建 / 快速连滑导致的过期 future 作废。
    if (!mounted || _pool != pool || _activationSeq != seq) {
      pool.release(_keyOf(index));
      await pool.evict(_keyOf(index));
      return;
    }

    // 只留当前页引用，其余引用全部丢弃（对应 controller 由池负责回收）。
    _ready
      ..clear()
      ..[index] = c;
    setState(() {});
    await c.setLooping(true); // 短视频 feed：当前条循环播放（抖音式）。
    // web（尤其 iOS Safari）禁止带声音的自动播放：feed 滑动后自动起播，play()
    // 已脱离用户手势，必须先静音才能自动播（静音自动播浏览器始终允许）。用户
    // 首次与页面交互后（onFirstUserGesture → _unlockAudio）解锁，之后的页带声音。
    // 原生端不受此限、一直有声音。
    if (kIsWeb) await c.setVolume(_audioUnlocked ? 1 : 0);
    if (!mounted || _pool != pool || _activationSeq != seq) {
      await c.pause();
      pool.release(_keyOf(index));
      await pool.evict(_keyOf(index));
      return;
    }
    await c.play();

    // 预加载下一条（建好 + init 后池内部会 pause）。Android 上跳过预加载：
    // 即使 pause，native decoder 也可能仍占 MediaCodec buffer。
    final next = index + 1;
    if (!_isAndroid && !_isIosWebSafari && next < _sources.length) {
      debugPrint('[feed] preload #$next (key=${_keyOf(next)})');
      unawaited(
        pool.preload(_sources[next]).catchError((Object e) {
          debugPrint('[feed] preload #$next FAILED: $e');
        }),
      );
    }

    // 保证快速跳页 / 反向滑动后，没有旧 key 残留为 active。
    for (var i = 0; i < _sources.length; i++) {
      if (i == index) continue;
      final key = _keyOf(i);
      if (pool.holds(key)) pool.release(key);
    }
  }

  @override
  void dispose() {
    _pageController.dispose();
    unawaited(_pool?.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: PageView.builder(
        controller: _pageController,
        scrollDirection: Axis.vertical,
        itemCount: _sources.length,
        onPageChanged: _activate,
        itemBuilder: (context, index) => _FeedItem(
          controller: _ready[index],
          index: index,
          total: _sources.length,
        ),
      ),
    );
  }
}

/// 单页：填满竖屏的播放画面 + 点击 toggle + 右下角页码 + 未就绪时盖
/// 黑底 loading。controller 为 null（还没 acquire 到）时只显示 loading。
class _FeedItem extends StatelessWidget {
  const _FeedItem({
    required this.controller,
    required this.index,
    required this.total,
  });

  final NiumaPlayerController? controller;
  final int index;
  final int total;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    return Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Colors.black),
        if (c != null)
          ValueListenableBuilder<NiumaPlayerValue>(
            valueListenable: c,
            builder: (context, value, _) {
              if (!value.initialized) return const _Loading();
              return GestureDetector(
                onTap: () => value.isPlaying ? c.pause() : c.play(),
                child: _FilledVideo(controller: c, value: value),
              );
            },
          )
        else
          const _Loading(),
        Positioned(
          right: 12,
          bottom: 24,
          child: Text(
            '${index + 1} / $total',
            style: const TextStyle(color: Colors.white70, fontSize: 14),
          ),
        ),
        // 临时调试角标：把"黑屏到底是哪种状态"显示出来，验证完可整块删。
        Positioned(left: 8, top: 8, child: _DebugBadge(controller: c, index: index)),
      ],
    );
  }
}

/// 临时调试角标：controller 为 null（未 acquire / acquire 失败）时直说；否则
/// 实时显示 phase / 是否在播 / 视频尺寸 / 错误类别——快滑黑屏时一眼定位。
class _DebugBadge extends StatelessWidget {
  const _DebugBadge({required this.controller, required this.index});

  final NiumaPlayerController? controller;
  final int index;

  @override
  Widget build(BuildContext context) {
    final c = controller;
    if (c == null) {
      return _box('#${index + 1} 无 controller（未 acquire / 失败）');
    }
    return ValueListenableBuilder<NiumaPlayerValue>(
      valueListenable: c,
      builder: (context, v, _) => _box(
        '#${index + 1} ${v.phase.name} ${v.isPlaying ? "▶" : "⏸"} '
        '${v.size.width.toInt()}x${v.size.height.toInt()}'
        '${v.hasError ? " ⚠${v.error?.category.name}" : ""}',
      ),
    );
  }

  Widget _box(String s) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
        color: Colors.black54,
        child: Text(s, style: const TextStyle(color: Colors.white, fontSize: 11)),
      );
}

/// 按视频真实宽高比居中显示（contain，不裁切），竖屏上下留黑边。
/// 想要沉浸式铺满可把 BoxFit.contain 改成 BoxFit.cover。
class _FilledVideo extends StatelessWidget {
  const _FilledVideo({required this.controller, required this.value});

  final NiumaPlayerController controller;
  final NiumaPlayerValue value;

  @override
  Widget build(BuildContext context) {
    final size = value.size;
    final w = (size.width <= 0 ? 16.0 : size.width);
    final h = (size.height <= 0 ? 9.0 : size.height);
    return FittedBox(
      fit: BoxFit.contain,
      clipBehavior: Clip.hardEdge,
      child: SizedBox(
        width: w,
        height: h,
        child: NiumaPlayerView(controller),
      ),
    );
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    return const ColoredBox(
      color: Colors.black,
      child: Center(
        child: CircularProgressIndicator(color: Colors.white),
      ),
    );
  }
}
