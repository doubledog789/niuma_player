import 'package:flutter_test/flutter_test.dart';
import 'package:niuma_player/src/domain/data_source.dart';
import 'package:niuma_player/src/orchestration/source_middleware.dart';

void main() {
  test('HeaderInjectionMiddleware merges headers into network source', () async {
    const m = HeaderInjectionMiddleware({'Referer': 'https://app.example.com'});
    final input = NiumaDataSource.network('https://cdn/x.mp4',
        headers: {'X-Token': 'abc'});

    final out = await m.apply(input);

    expect(out.uri, 'https://cdn/x.mp4');
    expect(out.headers, {
      'X-Token': 'abc',
      'Referer': 'https://app.example.com',
    });
  });

  test('HeaderInjectionMiddleware ignores non-network sources', () async {
    const m = HeaderInjectionMiddleware({'Referer': 'x'});
    final input = NiumaDataSource.asset('videos/intro.mp4');
    expect(await m.apply(input), same(input));
  });
}
