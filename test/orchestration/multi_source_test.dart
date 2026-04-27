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

  test('NiumaMediaSource.single wraps a NiumaDataSource', () {
    final ds = NiumaDataSource.network('https://cdn/x.mp4');
    final src = NiumaMediaSource.single(ds);
    expect(src.lines, hasLength(1));
    expect(src.lines.first.source, same(ds));
    expect(src.lines.first.id, 'default');
    expect(src.defaultLineId, 'default');
  });

  test('NiumaMediaSource.lines validates defaultLineId is in lines', () {
    expect(
      () => NiumaMediaSource.lines(
        lines: [
          MediaLine(
            id: 'a',
            label: 'A',
            source: NiumaDataSource.network('https://cdn/a'),
          ),
        ],
        defaultLineId: 'b',
      ),
      throwsA(isA<ArgumentError>()),
    );
  });

  test('NiumaMediaSource.currentLine resolves by id', () {
    final src = NiumaMediaSource.lines(
      lines: [
        MediaLine(
          id: 'a',
          label: 'A',
          source: NiumaDataSource.network('https://cdn/a'),
        ),
        MediaLine(
          id: 'b',
          label: 'B',
          source: NiumaDataSource.network('https://cdn/b'),
        ),
      ],
      defaultLineId: 'b',
    );
    expect(src.currentLine.id, 'b');
  });

  test('MultiSourcePolicy.autoFailover defaults', () {
    const p = MultiSourcePolicy.autoFailover();
    expect(p.maxAttempts, 1);
    expect(p.enabled, isTrue);
  });

  test('MultiSourcePolicy.manual disables failover', () {
    const p = MultiSourcePolicy.manual();
    expect(p.enabled, isFalse);
  });
}
