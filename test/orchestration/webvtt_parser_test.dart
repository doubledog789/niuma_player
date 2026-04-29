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

    // C1: 老 Mac \r 行结束符也要识别。
    test('支持纯 \\r 行结束符（老 Mac 风格）', () {
      const input =
          'WEBVTT\r\r00:00.000 --> 00:05.000\rsprite.jpg#xywh=0,0,128,72\r';
      final cues = WebVttParser.parseThumbnails(input);
      expect(cues.length, 1);
      expect(cues[0].spriteUrl, 'sprite.jpg');
      expect(cues[0].region.left, 0);
    });

    test('支持 \\r\\n 行结束符（Windows 风格）', () {
      const input =
          'WEBVTT\r\n\r\n00:00.000 --> 00:05.000\r\nsprite.jpg#xywh=0,0,128,72\r\n';
      final cues = WebVttParser.parseThumbnails(input);
      expect(cues.length, 1);
      expect(cues[0].spriteUrl, 'sprite.jpg');
    });

    // C3: WEBVTT 后必须是 EOL 或 \s——'WEBVTTfoo' 必须被拒。
    test('"WEBVTTfoo" 不是合法签名，抛 FormatException', () {
      const input =
          'WEBVTTfoo\n00:00.000 --> 00:05.000\nx#xywh=0,0,1,1\n';
      expect(() => WebVttParser.parseThumbnails(input), throwsFormatException);
    });

    test('"WEBVTT - some title" 是合法签名（空格后跟可选标题）', () {
      const input = 'WEBVTT - some title\n'
          '\n'
          '00:00.000 --> 00:05.000\n'
          'sprite.jpg#xywh=0,0,128,72\n';
      final cues = WebVttParser.parseThumbnails(input);
      expect(cues.length, 1);
    });

    test('"WEBVTT" 后是 \\t（tab）也合法', () {
      const input = 'WEBVTT\theader\n'
          '\n'
          '00:00.000 --> 00:05.000\n'
          'sprite.jpg#xywh=0,0,128,72\n';
      final cues = WebVttParser.parseThumbnails(input);
      expect(cues.length, 1);
    });

    // C2: sprite URL 中带 # 路径时，应取最后一个 #xywh= 切分。
    test('sprite URL 含 query 串时正确切分（保留 query）', () {
      const input = '''
WEBVTT

00:00.000 --> 00:05.000
sprite.jpg?v=1#xywh=0,0,128,72
''';
      final cues = WebVttParser.parseThumbnails(input);
      expect(cues.length, 1);
      expect(cues[0].spriteUrl, 'sprite.jpg?v=1');
    });

    test('sprite URL 含其它 # 片段时取最后一个 #xywh=', () {
      const input = '''
WEBVTT

00:00.000 --> 00:05.000
sprite.jpg#frag1#xywh=0,0,128,72
''';
      final cues = WebVttParser.parseThumbnails(input);
      expect(cues.length, 1);
      expect(cues[0].spriteUrl, 'sprite.jpg#frag1');
      expect(cues[0].region.left, 0);
      expect(cues[0].region.width, 128);
    });

    // C4: NOTE / STYLE / REGION 块必须显式跳过。
    test('NOTE 块（含 --> 也跳过）', () {
      const input = '''
WEBVTT

NOTE
this is a note with --> arrow inside

00:00.000 --> 00:05.000
sprite.jpg#xywh=0,0,128,72
''';
      final cues = WebVttParser.parseThumbnails(input);
      expect(cues.length, 1);
      expect(cues[0].spriteUrl, 'sprite.jpg');
    });

    test('STYLE 块跳过', () {
      const input = '''
WEBVTT

STYLE
::cue { color: red; }

00:00.000 --> 00:05.000
sprite.jpg#xywh=0,0,128,72
''';
      final cues = WebVttParser.parseThumbnails(input);
      expect(cues.length, 1);
    });

    test('REGION 块跳过', () {
      const input = '''
WEBVTT

REGION
id:fred
width:40%

00:00.000 --> 00:05.000
sprite.jpg#xywh=0,0,128,72
''';
      final cues = WebVttParser.parseThumbnails(input);
      expect(cues.length, 1);
    });

    test('cue identifier line（时间码上方一行 id）支持', () {
      const input = '''
WEBVTT

cue-1
00:00.000 --> 00:05.000
sprite.jpg#xywh=0,0,128,72

cue-2
00:05.000 --> 00:10.000
sprite.jpg#xywh=128,0,128,72
''';
      final cues = WebVttParser.parseThumbnails(input);
      expect(cues.length, 2);
      expect(cues[0].region.left, 0);
      expect(cues[1].region.left, 128);
    });

    // 额外：UTF-8 BOM 容错。
    test('UTF-8 BOM 前缀的 VTT 也能解析', () {
      // U+FEFF (BOM) 后接 WEBVTT
      const bom = '﻿';
      const input = '${bom}WEBVTT\n'
          '\n'
          '00:00.000 --> 00:05.000\n'
          'sprite.jpg#xywh=0,0,128,72\n';
      final cues = WebVttParser.parseThumbnails(input);
      expect(cues.length, 1);
      expect(cues[0].spriteUrl, 'sprite.jpg');
    });
  });
}
