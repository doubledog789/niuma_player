import 'dart:ui' show Rect;

import 'thumbnail_track.dart';

/// WebVTT 解析器（thumbnail 变种）。
///
/// 只识别形如 `bbb-sprite.jpg#xywh=0,0,128,72` 的 cue 内容。
/// 字幕变种（cue body 是文本）暂不支持。
abstract class WebVttParser {
  WebVttParser._();

  /// 解析 [input] 并返回所有 cue。
  ///
  /// - 输入必须以 `WEBVTT` 开头（大小写敏感，按 RFC 8216 §4.5）。
  /// - 单条 cue 出错（时间码 / xywh 无法解析）会被跳过，不影响其它 cue。
  /// - 返回结果按 [WebVttCue.start] 升序。
  static List<WebVttCue> parseThumbnails(String input) {
    final lines = input.split(RegExp(r'\r?\n'));
    if (lines.isEmpty || !lines.first.trim().startsWith('WEBVTT')) {
      throw const FormatException('输入不是合法的 WebVTT（缺 "WEBVTT" 头）');
    }

    final cues = <WebVttCue>[];
    var i = 1;
    while (i < lines.length) {
      final line = lines[i].trim();
      if (line.isEmpty || !line.contains('-->')) {
        i++;
        continue;
      }
      // 这是 cue 时间行；下一个非空行是 cue 内容。
      final times = _parseTimes(line);
      if (times == null) {
        i++;
        continue;
      }
      i++;
      while (i < lines.length && lines[i].trim().isEmpty) {
        i++;
      }
      if (i >= lines.length) break;
      final body = lines[i].trim();
      final cue = _parseSpriteRef(body, times.$1, times.$2);
      if (cue != null) cues.add(cue);
      i++;
    }
    return cues;
  }

  static (Duration, Duration)? _parseTimes(String line) {
    final m = RegExp(
      r'^((?:\d{2}:)?\d{2}:\d{2}\.\d{3})\s*-->\s*((?:\d{2}:)?\d{2}:\d{2}\.\d{3})',
    ).firstMatch(line);
    if (m == null) return null;
    final start = _parseTimestamp(m.group(1)!);
    final end = _parseTimestamp(m.group(2)!);
    if (start == null || end == null) return null;
    return (start, end);
  }

  static Duration? _parseTimestamp(String s) {
    final parts = s.split(':');
    try {
      int hours = 0, minutes, seconds, ms;
      if (parts.length == 3) {
        hours = int.parse(parts[0]);
        minutes = int.parse(parts[1]);
        final secMs = parts[2].split('.');
        seconds = int.parse(secMs[0]);
        ms = int.parse(secMs[1]);
      } else {
        minutes = int.parse(parts[0]);
        final secMs = parts[1].split('.');
        seconds = int.parse(secMs[0]);
        ms = int.parse(secMs[1]);
      }
      return Duration(
        hours: hours,
        minutes: minutes,
        seconds: seconds,
        milliseconds: ms,
      );
    } catch (_) {
      return null;
    }
  }

  static WebVttCue? _parseSpriteRef(String body, Duration start, Duration end) {
    final hashIdx = body.indexOf('#xywh=');
    if (hashIdx < 0) return null;
    final spriteUrl = body.substring(0, hashIdx);
    final coords = body.substring(hashIdx + 6).split(',');
    if (coords.length != 4) return null;
    try {
      final x = int.parse(coords[0]).toDouble();
      final y = int.parse(coords[1]).toDouble();
      final w = int.parse(coords[2]).toDouble();
      final h = int.parse(coords[3]).toDouble();
      return WebVttCue(
        start: start,
        end: end,
        spriteUrl: spriteUrl,
        region: Rect.fromLTWH(x, y, w, h),
      );
    } catch (_) {
      return null;
    }
  }
}
