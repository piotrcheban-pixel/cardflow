import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/api/images/image_provider.dart';
import 'package:cardflow/api/images/openverse_image_provider.dart';
import 'package:cardflow/domain/generation/card_image_kind.dart';

import '../../../helpers/fake_http_adapter.dart';

/// Openverse как провайдер кандидатов (7.14; лицензии CC).
void main() {
  Map<String, Object?> searchPayload({int count = 1}) => <String, Object?>{
    'result_count': count,
    'results': <Object?>[
      for (var index = 0; index < count; index++)
        <String, Object?>{
          'id': 'image-$index',
          'title': 'Diagram $index',
          'url': 'https://example.test/original-$index.jpg',
          'thumbnail':
              'https://api.openverse.org/v1/images/image-$index/thumb/',
          'license': 'by-sa',
          'license_version': '2.0',
          'creator': 'Allen Gathman',
          'width': 1024,
          'height': 768,
          'attribution':
              '"Diagram $index" by Allen Gathman is licensed under CC BY-SA 2.0.',
        },
    ],
  };

  OpenverseImageProvider providerWith(FakeHttpAdapter adapter) =>
      OpenverseImageProvider(dio: dioWithAdapter(adapter));

  test('ищет по query и отдаёт thumbnail и лицензию', () async {
    final adapter = FakeHttpAdapter((_) => jsonResponse(searchPayload()));
    final candidates = await providerWith(adapter).search(
      const ImageProviderQuery(
        query: '  photosynthesis diagram  ',
        kind: GeneratedCardImageKind.diagram,
      ),
    );

    expect(candidates, hasLength(1));
    final ImageCandidate candidate = candidates.single;
    expect(candidate.provider, 'openverse');
    expect(candidate.url, contains('/thumb/'));
    expect(candidate.license, 'CC BY-SA 2.0');
    expect(candidate.author, 'Allen Gathman');
    expect(candidate.width, 1024);

    final RequestOptions search = adapter.requests.single;
    expect(search.uri.host, 'api.openverse.org');
    expect(search.uri.queryParameters['q'], 'photosynthesis diagram');
    expect(search.uri.queryParameters['page_size'], '5');
    expect(search.uri.queryParameters['license'], 'cc0,pdm,by,by-sa');
    expect(search.uri.queryParameters['mature'], 'false');
    expect(search.headers['User-Agent'], 'CardFlow/1.0');
  });

  test('без thumbnail берётся оригинал', () async {
    final adapter = FakeHttpAdapter(
      (_) => jsonResponse(<String, Object?>{
        'results': <Object?>[
          <String, Object?>{
            'url': 'https://example.test/original.png',
            'license': 'cc0',
            'creator': null,
          },
        ],
      }),
    );
    final candidates = await providerWith(adapter).search(
      const ImageProviderQuery(
        query: 'scheme',
        kind: GeneratedCardImageKind.diagram,
      ),
    );
    expect(candidates.single.url, 'https://example.test/original.png');
    expect(candidates.single.license, 'CC0');
  });

  test('results не список → пусто', () async {
    final adapter = FakeHttpAdapter(
      (_) => jsonResponse(<String, Object?>{'results': 'oops'}),
    );
    expect(
      await providerWith(adapter).search(
        const ImageProviderQuery(
          query: 'x',
          kind: GeneratedCardImageKind.photo,
        ),
      ),
      isEmpty,
    );
  });

  test('пустой запрос → пусто без сетевых запросов', () async {
    final adapter = FakeHttpAdapter((_) => jsonResponse(searchPayload()));
    expect(
      await providerWith(adapter).search(
        const ImageProviderQuery(
          query: '   ',
          kind: GeneratedCardImageKind.photo,
        ),
      ),
      isEmpty,
    );
    expect(adapter.requests, isEmpty);
  });

  test('HTTP 429 пробрасывается (цепочка делает один ретрай)', () async {
    final adapter = FakeHttpAdapter(
      (_) => jsonResponse(<String, Object?>{}, statusCode: 429),
    );
    await expectLater(
      providerWith(adapter).search(
        const ImageProviderQuery(
          query: 'x',
          kind: GeneratedCardImageKind.photo,
        ),
      ),
      throwsA(isA<DioException>()),
    );
  });
}
