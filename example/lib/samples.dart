/// A demo case exposed on the home screen.
class Sample {
  const Sample({
    required this.label,
    required this.url,
    this.forceIjkOnAndroid = false,
    this.startsLooping = false,
  });

  final String label;
  final String url;

  /// When true, [NiumaPlayerOptions.forceIjkOnAndroid] is set so this sample
  /// skips the video_player attempt entirely. Useful for verifying the IJK
  /// path end-to-end on devices where video_player would otherwise succeed.
  final bool forceIjkOnAndroid;

  /// When true, `controller.setLooping(true)` is invoked once `initialize()`
  /// resolves so the video plays in a loop. Lets you visually verify that
  /// looping does not flicker through `phase=ended` on the wrap-around.
  final bool startsLooping;
}

const List<Sample> samples = <Sample>[
  Sample(
    label: 'H.264 mp4 (5MB, 10s)',
    url:
        'https://test-videos.co.uk/vids/bigbuckbunny/mp4/h264/1080/Big_Buck_Bunny_1080_10s_5MB.mp4',
  ),
  Sample(
    label: 'H.265 mp4 (1MB, 10s)',
    url:
        'https://test-videos.co.uk/vids/bigbuckbunny/mp4/h265/1080/Big_Buck_Bunny_1080_10s_1MB.mp4',
  ),
  Sample(
    label: 'HLS m3u8 (Mux test)',
    url: 'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8',
  ),
  Sample(
    label: 'HLS m3u8 (Apple bipbop)',
    url:
        'https://devstreaming-cdn.apple.com/videos/streaming/examples/img_bipbop_adv_example_ts/master.m3u8',
  ),
  Sample(
    label: '强制 IJK + HLS',
    url: 'https://test-streams.mux.dev/x36xhzz/x36xhzz.m3u8',
    forceIjkOnAndroid: true,
  ),
  Sample(
    label: '循环播放 (验证 M1 loop 修复)',
    url:
        'https://test-videos.co.uk/vids/bigbuckbunny/mp4/h264/1080/Big_Buck_Bunny_1080_10s_5MB.mp4',
    startsLooping: true,
  ),
  Sample(
    label: '错误地址 (验证 M2 错误分级)',
    url: 'https://this-host-does-not-exist.invalid/video.mp4',
  ),
];

/// One playable line inside a [MultiLineSample]. Mirrors `MediaLine` but
/// without depending on the SDK in this layer (samples are pure data).
class MultiLineDemoLine {
  const MultiLineDemoLine({
    required this.id,
    required this.label,
    required this.url,
    required this.priority,
  });

  final String id;
  final String label;
  final String url;
  final int priority;
}

/// Demo case exercising the M7 multi-line + middleware pipeline. Opens the
/// dedicated `MultiLinePlayerPage` instead of `PlayerPage`.
class MultiLineSample {
  const MultiLineSample({
    required this.label,
    required this.lines,
    required this.defaultLineId,
  });

  final String label;
  final List<MultiLineDemoLine> lines;
  final String defaultLineId;
}

const List<MultiLineSample> multiLineSamples = <MultiLineSample>[
  // 三条线路均为 Big Buck Bunny 同内容 / 10 秒 / 仅画质或编码不同。
  // 切换时位置不变 — 这是 switchLine 的正确使用场景（同内容多清晰度）。
  MultiLineSample(
    label: 'Big Buck Bunny — 多清晰度切换 (10s)',
    defaultLineId: 'sd-h264',
    lines: <MultiLineDemoLine>[
      MultiLineDemoLine(
        id: 'sd-h264',
        label: '720p H.264',
        url:
            'https://test-videos.co.uk/vids/bigbuckbunny/mp4/h264/720/Big_Buck_Bunny_720_10s_1MB.mp4',
        priority: 0,
      ),
      MultiLineDemoLine(
        id: 'hd-h264',
        label: '1080p H.264',
        url:
            'https://test-videos.co.uk/vids/bigbuckbunny/mp4/h264/1080/Big_Buck_Bunny_1080_10s_5MB.mp4',
        priority: 1,
      ),
      MultiLineDemoLine(
        id: 'hd-h265',
        label: '1080p H.265',
        url:
            'https://test-videos.co.uk/vids/bigbuckbunny/mp4/h265/1080/Big_Buck_Bunny_1080_10s_1MB.mp4',
        priority: 2,
      ),
    ],
  ),
];
