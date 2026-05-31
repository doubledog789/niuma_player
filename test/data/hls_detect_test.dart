// test/data/hls_detect_test.dart
import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/src/data/hls_detect.dart';

void main() {
  group('isHlsUrl', () {
    test('plain .m3u8 is HLS', () {
      expect(isHlsUrl('https://x/y.m3u8'), isTrue);
    });

    test('uppercase extension is HLS', () {
      expect(isHlsUrl('https://x/y.M3U8'), isTrue);
    });

    test('query string after .m3u8 is HLS', () {
      expect(isHlsUrl('https://x/master.m3u8?token=abc&a=1'), isTrue);
    });

    test('fragment after .m3u8 is HLS', () {
      expect(isHlsUrl('https://x/y.m3u8#t=10'), isTrue);
    });

    test('mp4 is not HLS', () {
      expect(isHlsUrl('https://x/y.mp4'), isFalse);
    });

    test('extensionless path is not HLS', () {
      expect(isHlsUrl('https://x/playlist'), isFalse);
    });

    test('empty string is not HLS', () {
      expect(isHlsUrl(''), isFalse);
    });

    test('m3u8 substring not at end is not HLS', () {
      expect(isHlsUrl('https://x/m3u8/y.mp4'), isFalse);
    });
  });
}
