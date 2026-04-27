import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/src/domain/data_source.dart';
import 'package:niuma_player/src/orchestration/multi_source.dart';

void main() {
  test('MediaQuality equality', () {
    expect(
      const MediaQuality(heightPx: 720, bitrate: 1500000),
      equals(const MediaQuality(heightPx: 720, bitrate: 1500000)),
    );
    expect(
      const MediaQuality(heightPx: 720),
      isNot(equals(const MediaQuality(heightPx: 1080))),
    );
  });

  test('MediaLine carries source + label + priority', () {
    final line = MediaLine(
      id: 'cdn-a-720',
      label: '720P',
      source: NiumaDataSource.network('https://cdn-a/720.mp4'),
      quality: const MediaQuality(heightPx: 720),
      priority: 10,
    );
    expect(line.id, 'cdn-a-720');
    expect(line.priority, 10);
    expect(line.source.uri, 'https://cdn-a/720.mp4');
  });
}
