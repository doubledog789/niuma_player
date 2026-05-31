import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'package:niuma_player/niuma_player.dart';

import 'thumbnail_cache.dart';
import 'thumbnail_frame.dart';
import 'thumbnail_resolver.dart';
import 'thumbnail_track.dart';
import 'webvtt_parser.dart';

/// 拉取 WebVTT body 的函数签名。
///
/// 默认是 `http.get` 的薄封装。测试注入 fake 避免真实网络调用。
/// 抛异常或返回非 VTT body 都是安全的——[ThumbnailController] 把任何失败视为
/// "thumbnails 关闭"，[thumbnailFor] 永远返回 null。
typedef ThumbnailFetcher = Future<String> Function(
  Uri uri,
  Map<String, String> headers,
);

/// 暴露给测试用的内部 helper：用给定的 [client] 流式拉取 VTT body，
/// 遵守 [timeout]（wall-clock）和 [maxBytes]（body 大小上限）。
///
/// 实现使用 [http.Client.send]（不是 `client.get`），因此在做 size cap
/// 检查之前**不会**把 body 完整 buffer 到内存。流程是：
///   1. 打开响应流 + 给 headers 阶段加 [timeout]；
///   2. 拒绝非 2xx 状态码；
///   3. 如果服务器声明了 `Content-Length` 且已超过 [maxBytes]，
///      在读 body 前直接拒绝；
///   4. 否则边累积 chunk 边检查；一旦累计超过 [maxBytes] 立即中止——
///      恶意服务器无法骗 VM 先 buffer 任意字节。
///
/// 非 2xx、超大 body、timeout 都抛 [http.ClientException]。
@visibleForTesting
Future<String> fetchThumbnailVtt(
  Uri uri,
  Map<String, String> headers,
  http.Client client, {
  Duration timeout = const Duration(seconds: 30),
  int maxBytes = 5 * 1024 * 1024,
}) async {
  try {
    final request = http.Request('GET', uri);
    request.headers.addAll(headers);
    final streamed = await client.send(request).timeout(timeout);
    if (streamed.statusCode < 200 || streamed.statusCode >= 300) {
      throw http.ClientException(
        'thumbnail VTT fetch failed: HTTP ${streamed.statusCode}',
        uri,
      );
    }
    final declared = streamed.contentLength;
    if (declared != null && declared > maxBytes) {
      throw http.ClientException(
        'thumbnail VTT body too large per Content-Length: '
        '$declared (max $maxBytes)',
        uri,
      );
    }
    final builder = BytesBuilder(copy: false);
    await for (final chunk in streamed.stream) {
      builder.add(chunk);
      if (builder.length > maxBytes) {
        throw http.ClientException(
          'thumbnail VTT body exceeded $maxBytes bytes during streaming',
          uri,
        );
      }
    }
    return utf8.decode(builder.toBytes());
  } finally {
    client.close();
  }
}

/// 缩略图取帧协调器（参考皮自包含层）。
///
/// 从 [controller] 上读 `source.thumbnailVtt` 拿 VTT URL、复用 `controller.middlewares`
/// 跑 header / signed-url 流水线，再 fetch + 解析 + 按 position 取帧。**核已不再
/// 承载这套逻辑**——这是接入方按需拷贝的参考实现。
///
/// 是个 [ChangeNotifier]：[load] 推进 [state] 时 `notifyListeners`，UI 监听后
/// 重建。任何 fetch / 解析失败都静默降级（[thumbnailFor] 永远返回 null），
/// 不影响视频播放。
class ThumbnailController extends ChangeNotifier {
  /// 创建一个缩略图取帧协调器。
  ///
  /// 默认 [fetcher] 用 `http.Client()` 抓取，遵守 [fetchTimeout] / [maxBodyBytes]；
  /// 测试可注入 fake [fetcher] 驱动各分支不碰真实网络。
  ThumbnailController(
    this.controller, {
    ThumbnailFetcher? fetcher,
    this.fetchTimeout = const Duration(seconds: 30),
    this.maxBodyBytes = 5 * 1024 * 1024,
  })  : _fetcher = fetcher ?? _defaultFetcher(fetchTimeout, maxBodyBytes),
        _state = controller.source.thumbnailVtt == null
            ? ThumbnailLoadState.none
            : ThumbnailLoadState.idle;

  /// 提供 VTT URL（`source.thumbnailVtt`）和 middleware 流水线的 player controller。
  final NiumaPlayerController controller;

  /// 默认 fetcher 的 wall-clock 硬上限。
  final Duration fetchTimeout;

  /// VTT body 大小硬上限（字节）。
  final int maxBodyBytes;

  final ThumbnailFetcher _fetcher;
  final ThumbnailCache _cache = ThumbnailCache();
  List<WebVttCue> _cues = const <WebVttCue>[];
  String? _resolvedUrl;
  Future<void>? _loadFuture;
  bool _disposed = false;

  ThumbnailLoadState _state;

  /// 当前缩略图加载状态。
  ThumbnailLoadState get state => _state;

  static ThumbnailFetcher _defaultFetcher(Duration timeout, int maxBytes) {
    return (uri, headers) => fetchThumbnailVtt(
          uri,
          headers,
          http.Client(),
          timeout: timeout,
          maxBytes: maxBytes,
        );
  }

  /// 启动加载：跑 middleware → fetch → 解析。单次加载内幂等（并发调用共享
  /// 同一进行中的 future）；完成后清空缓存的 future，允许未来再触发重载。
  Future<void> load() {
    if (_loadFuture != null) return _loadFuture!;
    final future = _runLoad().whenComplete(() {
      _loadFuture = null;
    });
    _loadFuture = future;
    return future;
  }

  Future<void> _runLoad() async {
    if (_disposed) return;
    final url = controller.source.thumbnailVtt;
    if (url == null) return;
    _setState(ThumbnailLoadState.loading);
    try {
      final ds = await runSourceMiddlewares(
        NiumaDataSource.network(url),
        controller.middlewares,
      );
      if (_disposed) return;
      final body = await _fetcher(
        Uri.parse(ds.uri),
        ds.headers ?? const <String, String>{},
      );
      if (_disposed) return;
      final cues = WebVttParser.parseThumbnails(body);
      if (_disposed) return;
      _cues = cues;
      _resolvedUrl = ds.uri;
      _setState(ThumbnailLoadState.ready);
    } catch (e) {
      if (_disposed) return;
      debugPrint('[niuma_ui] thumbnail VTT 加载失败：$e（不影响播放）');
      _cues = const <WebVttCue>[];
      _resolvedUrl = null;
      _setState(ThumbnailLoadState.failed);
    }
  }

  void _setState(ThumbnailLoadState next) {
    if (_state == next) return;
    _state = next;
    notifyListeners();
  }

  /// 根据当前播放位置 [position] 返回对应的 [ThumbnailFrame]，没有命中或缩略图
  /// 还未就绪时返回 `null`。所有合法输入下不抛。
  ThumbnailFrame? thumbnailFor(Duration position) {
    if (_cues.isEmpty || _resolvedUrl == null) return null;
    return ThumbnailResolver.resolve(
      position: position,
      cues: _cues,
      baseUrl: _resolvedUrl!,
      cache: _cache,
    );
  }

  @override
  void dispose() {
    _disposed = true;
    _cache.clear();
    super.dispose();
  }
}
