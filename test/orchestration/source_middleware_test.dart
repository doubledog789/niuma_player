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

  test('SignedUrlMiddleware swaps URL via signer', () async {
    final m = SignedUrlMiddleware((raw) async => '$raw?sig=ABC');
    final out = await m.apply(NiumaDataSource.network('https://cdn/x.mp4',
        headers: {'X-Token': 'abc'}));

    expect(out.uri, 'https://cdn/x.mp4?sig=ABC');
    expect(out.headers, {'X-Token': 'abc'});
  });

  test('SignedUrlMiddleware ignores non-network sources', () async {
    var called = false;
    final m = SignedUrlMiddleware((url) async {
      called = true;
      return url;
    });
    await m.apply(NiumaDataSource.file('/tmp/v.mp4'));
    expect(called, isFalse);
  });

  test('runMiddlewares applies left-to-right', () async {
    final result = await runSourceMiddlewares(
      NiumaDataSource.network('https://cdn/x.mp4'),
      const [
        HeaderInjectionMiddleware({'A': '1'}),
        HeaderInjectionMiddleware({'B': '2'}),
      ],
    );
    expect(result.headers, {'A': '1', 'B': '2'});
  });

  test('runMiddlewares with empty list returns input as-is', () async {
    final input = NiumaDataSource.network('https://cdn/x.mp4');
    expect(await runSourceMiddlewares(input, const []), same(input));
  });
}
