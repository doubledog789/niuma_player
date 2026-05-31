import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/niuma_player.dart';
import 'package:niuma_player_example/niuma_ui/niuma_ui.dart';

/// Stub [ThumbnailController]：提供受控的 thumbnailFor 返回值，断言
/// NiumaScrubPreview 把 [scrubPosition] 透传并把 frame 接到 NiumaThumbnailView。
class _StubThumbController extends ThumbnailController {
  _StubThumbController()
      : super(
          NiumaPlayerController(
            NiumaMediaSource.single(
              NiumaDataSource.network('https://example.com/v.mp4'),
              thumbnailVtt: 'https://example.com/thumbs.vtt',
            ),
          ),
        );

  Duration? lastQueriedPosition;
  ThumbnailFrame? frameToReturn;

  @override
  ThumbnailFrame? thumbnailFor(Duration position) {
    lastQueriedPosition = position;
    return frameToReturn;
  }
}

class _NoOpImageProvider extends ImageProvider<_NoOpImageProvider> {
  const _NoOpImageProvider();

  @override
  Future<_NoOpImageProvider> obtainKey(ImageConfiguration configuration) async =>
      this;

  @override
  ImageStreamCompleter loadImage(
    _NoOpImageProvider key,
    ImageDecoderCallback decode,
  ) =>
      _NoOpStreamCompleter();
}

class _NoOpStreamCompleter extends ImageStreamCompleter {}

void main() {
  testWidgets('frame 由 thumbnails.thumbnailFor 提供，scrubPosition 透传',
      (tester) async {
    final thumbs = _StubThumbController();
    thumbs.frameToReturn = const ThumbnailFrame(
      image: _NoOpImageProvider(),
      region: Rect.fromLTWH(0, 0, 64, 36),
    );
    const at = Duration(seconds: 12);

    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: NiumaScrubPreview(
        thumbnails: thumbs,
        scrubPosition: at,
      ),
    ));

    expect(thumbs.lastQueriedPosition, at);
    expect(find.byType(NiumaThumbnailView), findsOneWidget);
  });

  testWidgets('frame == null 时返回 SizedBox.shrink（不渲染缩略图）',
      (tester) async {
    final thumbs = _StubThumbController()..frameToReturn = null;
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: NiumaScrubPreview(
        thumbnails: thumbs,
        scrubPosition: Duration.zero,
      ),
    ));

    expect(find.byType(NiumaThumbnailView), findsNothing);
  });

  testWidgets('showTime=true（默认）渲染时间标签', (tester) async {
    final thumbs = _StubThumbController();
    thumbs.frameToReturn = const ThumbnailFrame(
      image: _NoOpImageProvider(),
      region: Rect.fromLTWH(0, 0, 64, 36),
    );

    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: NiumaScrubPreview(
        thumbnails: thumbs,
        scrubPosition: const Duration(minutes: 1, seconds: 23),
      ),
    ));

    expect(find.text('01:23'), findsOneWidget);
  });

  testWidgets('showTime=false 时不渲染时间标签', (tester) async {
    final thumbs = _StubThumbController();
    thumbs.frameToReturn = const ThumbnailFrame(
      image: _NoOpImageProvider(),
      region: Rect.fromLTWH(0, 0, 64, 36),
    );

    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: NiumaScrubPreview(
        thumbnails: thumbs,
        scrubPosition: const Duration(minutes: 1, seconds: 23),
        showTime: false,
      ),
    ));

    expect(find.text('01:23'), findsNothing);
    // 但缩略图本身仍然渲染。
    expect(find.byType(NiumaThumbnailView), findsOneWidget);
  });

  testWidgets('size 可覆盖', (tester) async {
    final thumbs = _StubThumbController();
    thumbs.frameToReturn = const ThumbnailFrame(
      image: _NoOpImageProvider(),
      region: Rect.fromLTWH(0, 0, 64, 36),
    );

    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: NiumaScrubPreview(
        thumbnails: thumbs,
        scrubPosition: Duration.zero,
        size: const Size(200, 100),
      ),
    ));

    // 内部 NiumaThumbnailView 在 Container 的 1px border 内部，所以测的是
    // s - 2 在两侧。语义上声明的是"预览块 200x100"，验证一下逻辑大小：
    final box = tester.getSize(find.byType(NiumaThumbnailView));
    expect(box.width, inInclusiveRange(196, 200));
    expect(box.height, inInclusiveRange(96, 100));
  });
}
