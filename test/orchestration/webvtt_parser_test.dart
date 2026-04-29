import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/src/orchestration/webvtt_parser.dart';

void main() {
  group('WebVttParser.parseThumbnails', () {
    test('解析 MM:SS.mmm 格式的 cue', () {
      const input = '''
WEBVTT

00:00.000 --> 00:05.000
bbb-sprite.jpg#xywh=0,0,128,72

00:05.000 --> 00:10.000
bbb-sprite.jpg#xywh=128,0,128,72
''';
      final cues = WebVttParser.parseThumbnails(input);
      expect(cues.length, 2);
      expect(cues[0].start, Duration.zero);
      expect(cues[0].end, const Duration(seconds: 5));
      expect(cues[0].spriteUrl, 'bbb-sprite.jpg');
      expect(cues[0].region.left, 0);
      expect(cues[0].region.top, 0);
      expect(cues[0].region.width, 128);
      expect(cues[0].region.height, 72);
    });

    test('解析 HH:MM:SS.mmm 格式（长视频）', () {
      const input = '''
WEBVTT

01:23:45.000 --> 01:23:50.000
sprite.jpg#xywh=0,0,160,90
''';
      final cues = WebVttParser.parseThumbnails(input);
      expect(cues.length, 1);
      expect(cues[0].start, const Duration(hours: 1, minutes: 23, seconds: 45));
    });

    test('忽略坏的 cue，保留好的', () {
      const input = '''
WEBVTT

00:00.000 --> 00:05.000
sprite.jpg#xywh=BAD

00:05.000 --> 00:10.000
sprite.jpg#xywh=128,0,128,72
''';
      final cues = WebVttParser.parseThumbnails(input);
      expect(cues.length, 1);
      expect(cues[0].region.left, 128);
    });

    test('缺 WEBVTT 头时抛 FormatException', () {
      expect(() => WebVttParser.parseThumbnails('00:00.000 --> 00:05.000'),
          throwsFormatException);
    });

    test('空文件返回空列表', () {
      final cues = WebVttParser.parseThumbnails('WEBVTT\n');
      expect(cues, isEmpty);
    });

    test('解析多张 sprite 引用（长视频常见）', () {
      const input = '''
WEBVTT

00:00.000 --> 00:05.000
sprite-1.jpg#xywh=0,0,128,72

00:05.000 --> 00:10.000
sprite-2.jpg#xywh=0,0,128,72
''';
      final cues = WebVttParser.parseThumbnails(input);
      expect(cues.map((c) => c.spriteUrl).toSet(),
          {'sprite-1.jpg', 'sprite-2.jpg'});
    });
  });
}
