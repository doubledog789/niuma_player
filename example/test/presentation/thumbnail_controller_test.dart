import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart' as http_testing;
import 'package:niuma_player/niuma_player.dart';
import 'package:niuma_player_example/niuma_ui/thumbnail/thumbnail_controller.dart';
import 'package:niuma_player_example/niuma_ui/thumbnail/thumbnail_track.dart';

NiumaPlayerController _controllerWith(String? thumbnailVtt,
    {List<SourceMiddleware> middlewares = const []}) {
  final ds = NiumaDataSource.network('https://example.com/v.mp4');
  return NiumaPlayerController(
    NiumaMediaSource.single(ds, thumbnailVtt: thumbnailVtt),
    middlewares: middlewares,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('ThumbnailController.thumbnailFor', () {
    test('source.thumbnailVtt 为 null 时返回 null', () async {
      final controller = _controllerWith(null);
      final thumbs = ThumbnailController(controller);
      await thumbs.load();
      expect(thumbs.thumbnailFor(const Duration(seconds: 3)), isNull);
      expect(thumbs.state, ThumbnailLoadState.none);
      thumbs.dispose();
      await controller.dispose();
    });

    test('VTT fetch 失败时 thumbnailFor 返回 null（静默降级，D1）', () async {
      final controller = _controllerWith('https://x/thumbs.vtt');
      final thumbs = ThumbnailController(
        controller,
        fetcher: (uri, headers) async {
          throw const FormatException('boom');
        },
      );
      await thumbs.load();
      expect(thumbs.thumbnailFor(const Duration(seconds: 3)), isNull);
      expect(thumbs.state, ThumbnailLoadState.failed);
      thumbs.dispose();
      await controller.dispose();
    });

    test('fetcher 超时被静默降级（I7 timeout）', () async {
      final controller = _controllerWith('https://x/thumbs.vtt');
      final thumbs = ThumbnailController(
        controller,
        fetcher: (uri, headers) async {
          throw TimeoutException('fetcher timed out', const Duration(seconds: 30));
        },
      );
      await thumbs.load();
      expect(thumbs.thumbnailFor(const Duration(seconds: 3)), isNull);
      expect(thumbs.state, ThumbnailLoadState.failed);
      thumbs.dispose();
      await controller.dispose();
    });

    test('多次 load 只触发一次 fetch（I6 idempotent）', () async {
      var fetchCount = 0;
      final controller = _controllerWith('https://x/thumbs.vtt');
      final thumbs = ThumbnailController(
        controller,
        fetcher: (uri, headers) async {
          fetchCount++;
          return 'WEBVTT\n\n00:00.000 --> 00:05.000\nx.jpg#xywh=0,0,1,1\n';
        },
      );
      // 并发触发两次：共享同一个 in-flight future。
      final a = thumbs.load();
      final b = thumbs.load();
      await Future.wait([a, b]);
      expect(fetchCount, 1);
      thumbs.dispose();
      await controller.dispose();
    });

    test('成功 fetch + 解析后能查出对应 frame', () async {
      const vttBody = '''
WEBVTT

00:00.000 --> 00:05.000
sprite.jpg#xywh=0,0,128,72

00:05.000 --> 00:10.000
sprite.jpg#xywh=128,0,128,72
''';
      final fetched = <Uri>[];
      final controller = _controllerWith('https://cdn.com/x/thumbs.vtt');
      final thumbs = ThumbnailController(
        controller,
        fetcher: (uri, headers) async {
          fetched.add(uri);
          return vttBody;
        },
      );
      await thumbs.load();

      expect(fetched.single, Uri.parse('https://cdn.com/x/thumbs.vtt'));
      final frame = thumbs.thumbnailFor(const Duration(seconds: 3));
      expect(frame, isNotNull);
      expect(frame!.region.left, 0);
      final frame2 = thumbs.thumbnailFor(const Duration(seconds: 7));
      expect(frame2, isNotNull);
      expect(frame2!.region.left, 128);
      expect(thumbs.thumbnailFor(const Duration(seconds: 99)), isNull);

      thumbs.dispose();
      await controller.dispose();
    });
  });

  group('ThumbnailController.state', () {
    test('thumbnailVtt: null → none', () {
      final controller = _controllerWith(null);
      final thumbs = ThumbnailController(controller);
      expect(thumbs.state, ThumbnailLoadState.none);
      thumbs.dispose();
      controller.dispose();
    });

    test('配置但 load 未跑 → idle', () {
      final controller = _controllerWith('https://x/thumbs.vtt');
      final thumbs = ThumbnailController(
        controller,
        fetcher: (uri, headers) async => 'WEBVTT\n',
      );
      expect(thumbs.state, ThumbnailLoadState.idle);
      thumbs.dispose();
      controller.dispose();
    });

    test('fetch 进行中 → loading（用 Completer 控制完成时点）', () async {
      final fetchGate = Completer<String>();
      final controller = _controllerWith('https://x/thumbs.vtt');
      final thumbs = ThumbnailController(
        controller,
        fetcher: (uri, headers) => fetchGate.future,
      );
      final loading = thumbs.load();
      await Future<void>.delayed(Duration.zero);
      expect(thumbs.state, ThumbnailLoadState.loading);

      fetchGate.complete('WEBVTT\n');
      await loading;
      thumbs.dispose();
      await controller.dispose();
    });

    test('成功 fetch + 解析 → ready', () async {
      final controller = _controllerWith('https://x/thumbs.vtt');
      final thumbs = ThumbnailController(
        controller,
        fetcher: (uri, headers) async =>
            'WEBVTT\n\n00:00.000 --> 00:05.000\nx.jpg#xywh=0,0,1,1\n',
      );
      await thumbs.load();
      expect(thumbs.state, ThumbnailLoadState.ready);
      thumbs.dispose();
      await controller.dispose();
    });

    test('解析返回空 cue（合法 WEBVTT 但 0 cue）→ ready（thumbnailFor 仍返回 null）',
        () async {
      final controller = _controllerWith('https://x/thumbs.vtt');
      final thumbs = ThumbnailController(
        controller,
        fetcher: (uri, headers) async => 'WEBVTT\n',
      );
      await thumbs.load();
      expect(thumbs.state, ThumbnailLoadState.ready);
      expect(thumbs.thumbnailFor(const Duration(seconds: 3)), isNull);
      thumbs.dispose();
      await controller.dispose();
    });

    test('fetch 抛异常 → failed', () async {
      final controller = _controllerWith('https://x/thumbs.vtt');
      final thumbs = ThumbnailController(
        controller,
        fetcher: (uri, headers) async {
          throw const FormatException('boom');
        },
      );
      await thumbs.load();
      expect(thumbs.state, ThumbnailLoadState.failed);
      thumbs.dispose();
      await controller.dispose();
    });

    test('已 dispose 的 controller 不进入 loading（entry guard）', () async {
      var fetchCalled = false;
      final controller = _controllerWith('https://x/thumbs.vtt');
      final thumbs = ThumbnailController(
        controller,
        fetcher: (uri, headers) async {
          fetchCalled = true;
          return 'WEBVTT\n';
        },
      );
      thumbs.dispose();
      await thumbs.load();
      expect(fetchCalled, isFalse);
      expect(thumbs.state, ThumbnailLoadState.idle);
      await controller.dispose();
    });

    test('dispose 中途的 fetcher 不写已 disposed 的字段（race）', () async {
      final fetchGate = Completer<String>();
      final controller = _controllerWith('https://x/thumbs.vtt');
      final thumbs = ThumbnailController(
        controller,
        fetcher: (uri, headers) => fetchGate.future,
      );
      final loading = thumbs.load();
      await Future<void>.delayed(Duration.zero);
      thumbs.dispose();
      fetchGate.complete(
        'WEBVTT\n\n00:00.000 --> 00:05.000\nx.jpg#xywh=0,0,1,1\n',
      );
      await loading;
      expect(thumbs.state, isNot(ThumbnailLoadState.ready));
      expect(thumbs.thumbnailFor(const Duration(seconds: 3)), isNull);
      await controller.dispose();
    });
  });

  group('ThumbnailController 走 middleware（TG7 / D3）', () {
    test('HeaderInjectionMiddleware 注入的 headers 真到达 fetcher', () async {
      Map<String, String>? capturedHeaders;
      final controller = _controllerWith(
        'https://x/thumbs.vtt',
        middlewares: const [HeaderInjectionMiddleware({'X-Token': 'foo'})],
      );
      final thumbs = ThumbnailController(
        controller,
        fetcher: (uri, headers) async {
          capturedHeaders = headers;
          return 'WEBVTT\n';
        },
      );
      await thumbs.load();
      expect(capturedHeaders, isNotNull);
      expect(capturedHeaders!['X-Token'], 'foo');
      thumbs.dispose();
      await controller.dispose();
    });

    test('SignedUrlMiddleware 改写过的 URL 真到达 fetcher', () async {
      Uri? capturedUri;
      final controller = _controllerWith(
        'https://x/thumbs.vtt',
        middlewares: [SignedUrlMiddleware((u) async => '$u?sig=bar')],
      );
      final thumbs = ThumbnailController(
        controller,
        fetcher: (uri, headers) async {
          capturedUri = uri;
          return 'WEBVTT\n';
        },
      );
      await thumbs.load();
      expect(capturedUri, isNotNull);
      expect(capturedUri.toString(), contains('?sig=bar'));
      thumbs.dispose();
      await controller.dispose();
    });
  });

  group('fetchThumbnailVtt（默认 fetcher 实现）', () {
    test('Content-Length 早拒超过 maxBytes 的 body（R2-C1）', () async {
      const cap = 1024;
      final oversize = Uint8List(cap + 256)..fillRange(0, cap + 256, 0x61);
      final mock = http_testing.MockClient(
        (req) async => http.Response.bytes(oversize, 200),
      );
      Object? caught;
      try {
        await fetchThumbnailVtt(
          Uri.parse('https://x/thumbs.vtt'),
          const <String, String>{},
          mock,
          maxBytes: cap,
        );
      } catch (e) {
        caught = e;
      }
      expect(caught, isA<http.ClientException>());
      expect(caught.toString(), contains('Content-Length'));
    });

    test('没 Content-Length 时仍流式中止（R2-C1 streaming abort）', () async {
      const cap = 1024;
      Stream<List<int>> chunks() async* {
        final chunk = Uint8List(256)..fillRange(0, 256, 0x61);
        for (var i = 0; i < 8; i++) {
          yield chunk;
        }
      }

      final mock = http_testing.MockClient.streaming(
        (req, body) async => http.StreamedResponse(chunks(), 200),
      );
      Object? caught;
      try {
        await fetchThumbnailVtt(
          Uri.parse('https://x/thumbs.vtt'),
          const <String, String>{},
          mock,
          maxBytes: cap,
        );
      } catch (e) {
        caught = e;
      }
      expect(caught, isA<http.ClientException>());
      expect(caught.toString(), contains('exceeded'));
    });

    test('接受正常大小的 VTT body', () async {
      final body = utf8.encode(
        'WEBVTT\n\n00:00.000 --> 00:05.000\nx.jpg#xywh=0,0,1,1\n',
      );
      final mock = http_testing.MockClient(
        (req) async => http.Response.bytes(body, 200),
      );
      final result = await fetchThumbnailVtt(
        Uri.parse('https://x/thumbs.vtt'),
        const <String, String>{},
        mock,
      );
      expect(result, contains('WEBVTT'));
    });

    test('ThumbnailController 暴露 fetchTimeout / maxBodyBytes 默认值', () {
      final controller = _controllerWith('https://x/thumbs.vtt');
      final thumbs = ThumbnailController(controller);
      expect(thumbs.fetchTimeout, const Duration(seconds: 30));
      expect(thumbs.maxBodyBytes, 5 * 1024 * 1024);
      thumbs.dispose();
      controller.dispose();
    });
  });
}
