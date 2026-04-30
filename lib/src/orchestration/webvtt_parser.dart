import 'dart:ui' show Rect;

import 'thumbnail_track.dart';

/// WebVTT 解析器（thumbnail 变种）。
///
/// 只识别形如 `bbb-sprite.jpg#xywh=0,0,128,72` 的 cue 内容。
/// 字幕变种（cue body 是文本）暂不支持。
abstract class WebVttParser {
  WebVttParser._();

  /// UTF-8 BOM 字符（U+FEFF）。某些工具会在 VTT 文件开头加 BOM；
  /// 我们在 split 之前先剥离它，避免签名校验把 BOM 算进 `WEBVTT` 前缀里。
  static const String _utf8Bom = '﻿';

  /// 解析 [input] 并返回所有 cue。
  ///
  /// - 输入必须以 `WEBVTT` 开头，且 `WEBVTT` 后必须是行尾或空白（按 RFC 8216 §4.5）。
  /// - 行结束符兼容 `\r\n` / `\n` / `\r`（老 Mac 风格）。
  /// - UTF-8 BOM（`﻿`）若存在会被自动剥离。
  /// - `NOTE` / `STYLE` / `REGION` 块会被显式跳过——即使其内容含 `-->` 也不会被误判为 cue。
  /// - 单条 cue 出错（时间码 / xywh 无法解析）会被跳过，不影响其它 cue。
  /// - 返回结果按 [WebVttCue.start] 升序。
  static List<WebVttCue> parseThumbnails(String input) {
    // BOM 容错：某些工具（含 ffmpeg 部分版本）输出的 VTT 带 UTF-8 BOM，
    // 不剥离会让签名检查把 BOM 字符算进 `WEBVTT` 前缀，从而误判为非法。
    final stripped =
        input.startsWith(_utf8Bom) ? input.substring(_utf8Bom.length) : input;
    // 行结束符兼容：\r\n / \n / \r（老 Mac）。
    final lines = stripped.split(RegExp(r'\r\n|\r|\n'));
    if (lines.isEmpty || !_isValidSignature(lines.first)) {
      throw const FormatException('输入不是合法的 WebVTT（缺 "WEBVTT" 头）');
    }

    final cues = <WebVttCue>[];
    var i = 1;
    while (i < lines.length) {
      final line = lines[i].trim();
      if (line.isEmpty) {
        i++;
        continue;
      }
      // C4: NOTE / STYLE / REGION 块整块跳过，直到下一个空行（或 EOF）。
      if (_isBlockHeader(line)) {
        i++;
        while (i < lines.length && lines[i].trim().isNotEmpty) {
          i++;
        }
        continue;
      }
      // 当前行可能是 cue identifier（时间码上方的可选 id 行），
      // 也可能直接是时间码行。先尝试当时间码解析；若不是，认为是 identifier，
      // 跳到下一行再尝试。
      var times = _parseTimes(line);
      if (times == null) {
        // 这是 cue identifier 行；下一行才是时间码。
        i++;
        if (i >= lines.length) break;
        final maybeTimes = lines[i].trim();
        times = _parseTimes(maybeTimes);
        if (times == null) {
          // 既不是 identifier+时间码也不是合法时间码——跳过，吃完整块。
          while (i < lines.length && lines[i].trim().isNotEmpty) {
            i++;
          }
          continue;
        }
      }
      // 这是 cue 时间行；下一个非空行是 cue 内容。
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

  /// 校验首行签名：`WEBVTT` 后必须是 EOL 或空白（按 RFC）。
  /// 拒绝形如 `WEBVTTfoo` 的伪合法输入（C3）。
  static bool _isValidSignature(String firstLine) {
    return RegExp(r'^WEBVTT(\s|$)').hasMatch(firstLine);
  }

  /// 判断 [line]（已 trim）是否是 NOTE / STYLE / REGION 块头。
  /// 块头独占一行，或后跟空白/参数都算。
  static bool _isBlockHeader(String line) {
    return line == 'NOTE' ||
        line.startsWith('NOTE ') ||
        line.startsWith('NOTE\t') ||
        line == 'STYLE' ||
        line.startsWith('STYLE ') ||
        line.startsWith('STYLE\t') ||
        line == 'REGION' ||
        line.startsWith('REGION ') ||
        line.startsWith('REGION\t');
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
    // C2: 用 lastIndexOf 取最后一次出现的 `#xywh=`，避免 sprite URL 自身含 `#`
    // 片段（fragment）时把 `#xywh=` 的 anchor 错切到前一个 `#`。
    final hashIdx = body.lastIndexOf('#xywh=');
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
