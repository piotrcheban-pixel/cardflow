import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/api/images/image_provider.dart';
import 'package:cardflow/api/images/pexels_image_provider.dart';
import 'package:cardflow/api/images/pixabay_image_provider.dart';
import 'package:cardflow/domain/generation/card_image_kind.dart';

import '../../../helpers/fake_http_adapter.dart';

/// Провайдеры с ключом: Pixabay и Pexels (7.14). Без ключа в цепочку не входят.
void main() {
  test('Pixabay: ключ в query, safe search, атрибуция и размеры', () async {
    final adapter = FakeHttpAdapter(
      (_) => jsonResponse(<String, Object?>{
        'hits': <Object?>[
          <String, Object?>{
            'largeImageURL': 'https://pixabay.test/large.jpg',
            'webformatURL': 'https://pixabay.test/web.jpg',
            'imageWidth': 1920,
            'imageHeight': 1080,
            'user': 'PhotoAuthor',
            'tags': 'bridge, truss',
          },
        ],
      }),
    );
    final provider = PixabayImageProvider(
      dio: dioWithAdapter(adapter),
      apiKey: 'pix-key',
    );

    final candidates = await provider.search(
      const ImageProviderQuery(
        query: 'truss bridge',
        kind: GeneratedCardImageKind.photo,
      ),
    );

    expect(candidates, hasLength(1));
    expect(candidates.single.provider, 'pixabay');
    expect(candidates.single.url, 'https://pixabay.test/large.jpg');
    expect(candidates.single.width, 1920);
    expect(candidates.single.author, 'PhotoAuthor');
    expect(candidates.single.license, 'Pixabay License');
    final RequestOptions request = adapter.requests.single;
    expect(request.uri.host, 'pixabay.com');
    expect(request.uri.queryParameters['key'], 'pix-key');
    expect(request.uri.queryParameters['q'], 'truss bridge');
    expect(request.uri.queryParameters['safesearch'], 'true');
    expect(request.uri.queryParameters['lang'], 'en');
  });

  test('Pixabay: пустой запрос → пусто без сети', () async {
    final adapter = FakeHttpAdapter((_) => jsonResponse(<String, Object?>{}));
    final provider = PixabayImageProvider(
      dio: dioWithAdapter(adapter),
      apiKey: 'pix-key',
    );
    expect(
      await provider.search(
        const ImageProviderQuery(
          query: '   ',
          kind: GeneratedCardImageKind.photo,
        ),
      ),
      isEmpty,
    );
    expect(adapter.requests, isEmpty);
  });

  test('Pexels: ключ в заголовке, атрибуция и размеры', () async {
    final adapter = FakeHttpAdapter(
      (_) => jsonResponse(<String, Object?>{
        'photos': <Object?>[
          <String, Object?>{
            'src': <String, Object?>{
              'large': 'https://pexels.test/large.jpg',
              'medium': 'https://pexels.test/medium.jpg',
            },
            'width': 1200,
            'height': 800,
            'photographer': 'Jane Doe',
          },
        ],
      }),
    );
    final provider = PexelsImageProvider(
      dio: dioWithAdapter(adapter),
      apiKey: 'pex-key',
    );

    final candidates = await provider.search(
      const ImageProviderQuery(
        query: 'balance scale',
        kind: GeneratedCardImageKind.illustration,
      ),
    );

    expect(candidates, hasLength(1));
    expect(candidates.single.provider, 'pexels');
    expect(candidates.single.url, 'https://pexels.test/large.jpg');
    expect(candidates.single.author, 'Jane Doe');
    expect(candidates.single.license, 'Pexels License');
    final RequestOptions request = adapter.requests.single;
    expect(request.uri.host, 'api.pexels.com');
    expect(request.uri.queryParameters['query'], 'balance scale');
    expect(request.headers['Authorization'], 'pex-key');
    expect(
      request.uri.toString(),
      isNot(contains('pex-key')),
      reason: 'ключ не должен попадать в URL',
    );
  });

  test('Pexels: photos не список → пусто', () async {
    final adapter = FakeHttpAdapter(
      (_) => jsonResponse(<String, Object?>{'photos': 'oops'}),
    );
    final provider = PexelsImageProvider(
      dio: dioWithAdapter(adapter),
      apiKey: 'pex-key',
    );
    expect(
      await provider.search(
        const ImageProviderQuery(
          query: 'x',
          kind: GeneratedCardImageKind.photo,
        ),
      ),
      isEmpty,
    );
  });

  test('оба провайдера пробрасывают HTTP-ошибку цепочке', () async {
    final adapter = FakeHttpAdapter(
      (_) => jsonResponse(<String, Object?>{}, statusCode: 503),
    );
    final dio = dioWithAdapter(adapter);
    for (final ImageProvider provider in <ImageProvider>[
      PixabayImageProvider(dio: dio, apiKey: 'k'),
      PexelsImageProvider(dio: dio, apiKey: 'k'),
    ]) {
      await expectLater(
        provider.search(
          const ImageProviderQuery(
            query: 'x',
            kind: GeneratedCardImageKind.photo,
          ),
        ),
        throwsA(isA<DioException>()),
        reason: provider.name,
      );
    }
  });
}
