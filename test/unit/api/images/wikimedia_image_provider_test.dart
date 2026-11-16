import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/api/images/image_provider.dart';
import 'package:cardflow/api/images/wikimedia_image_provider.dart';
import 'package:cardflow/domain/generation/card_image_kind.dart';

import '../../../helpers/fake_http_adapter.dart';

/// Wikimedia Commons как провайдер кандидатов (7.14; скачивание — в цепочке).
void main() {
  Map<String, Object?> pagesPayload({
    String mime = 'image/jpeg',
    String? thumburl = 'https://upload.wikimedia.org/thumb/kremlin.jpg',
    String? url = 'https://upload.wikimedia.org/kremlin.jpg',
    String? license = 'CC BY-SA 4.0',
    String? artist = '<a href="https://example.test">Иван Петров</a>',
    int count = 1,
  }) {
    return <String, Object?>{
      'batchcomplete': '',
      'query': <String, Object?>{
        'pages': <String, Object?>{
          for (var index = 0; index < count; index++)
            'page-$index': <String, Object?>{
              'pageid': 1000 + index,
              'ns': 6,
              'title': 'File:Московский Кремль $index.jpg',
              'index': index + 1,
              'imageinfo': <Object?>[
                <String, Object?>{
                  'url': url,
                  'thumburl': index == 0 ? thumburl : null,
                  'mime': mime,
                  'thumbwidth': 800,
                  'thumbheight': 533,
                  'extmetadata': <String, Object?>{
                    if (artist != null)
                      'Artist': <String, Object?>{'value': artist},
                    if (license != null)
                      'LicenseShortName': <String, Object?>{'value': license},
                  },
                },
              ],
            },
        },
      },
    };
  }

  WikimediaImageProvider providerWith(FakeHttpAdapter adapter) =>
      WikimediaImageProvider(dio: dioWithAdapter(adapter));

  test('ищет по запросу и отдаёт кандидатов с атрибуцией', () async {
    final adapter = FakeHttpAdapter((_) => jsonResponse(pagesPayload()));
    final provider = providerWith(adapter);

    final candidates = await provider.search(
      const ImageProviderQuery(
        query: '  Московский Кремль  ',
        kind: GeneratedCardImageKind.photo,
      ),
    );

    expect(candidates, hasLength(1));
    final ImageCandidate candidate = candidates.single;
    expect(candidate.provider, 'wikimedia');
    expect(candidate.url, contains('/thumb/kremlin.jpg'));
    expect(candidate.width, 800);
    expect(candidate.height, 533);
    expect(candidate.author, 'Иван Петров', reason: 'HTML автора вычищается');
    expect(candidate.license, 'CC BY-SA 4.0');
    expect(candidate.attribution, contains('CC BY-SA 4.0'));
    expect(candidate.attribution, isNot(contains('<a')));

    expect(adapter.requests, hasLength(1));
    final RequestOptions search = adapter.requests.first;
    expect(search.uri.host, 'commons.wikimedia.org');
    expect(search.uri.queryParameters['action'], 'query');
    expect(search.uri.queryParameters['generator'], 'search');
    expect(search.uri.queryParameters['gsrsearch'], 'Московский Кремль');
    expect(search.uri.queryParameters['gsrnamespace'], '6');
    expect(search.uri.queryParameters['iiprop'], contains('size'));
    expect(search.headers['User-Agent'], contains('CardFlow'));
  });

  test('отсутствующий thumburl заменяется оригиналом', () async {
    final adapter = FakeHttpAdapter(
      (_) => jsonResponse(pagesPayload(thumburl: null)),
    );
    final candidates = await providerWith(adapter).search(
      const ImageProviderQuery(
        query: 'кремль',
        kind: GeneratedCardImageKind.photo,
      ),
    );
    expect(candidates.single.url, 'https://upload.wikimedia.org/kremlin.jpg');
  });

  test('страницы списком (formatversion=2) тоже поддерживаются', () async {
    final adapter = FakeHttpAdapter(
      (_) => jsonResponse(<String, Object?>{
        'query': <String, Object?>{
          'pages': <Object?>[
            <String, Object?>{
              'title': 'File:A.jpg',
              'index': 1,
              'imageinfo': <Object?>[
                <String, Object?>{
                  'url': 'https://upload.wikimedia.org/a.jpg',
                  'mime': 'image/png',
                  'width': 1024,
                  'height': 768,
                },
              ],
            },
          ],
        },
      }),
    );
    final candidates = await providerWith(adapter).search(
      const ImageProviderQuery(
        query: 'a',
        kind: GeneratedCardImageKind.diagram,
      ),
    );
    expect(candidates.single.width, 1024);
  });

  test('SVG/PDF пропускаются: принимаем только JPEG/PNG', () async {
    final adapter = FakeHttpAdapter(
      (_) => jsonResponse(pagesPayload(mime: 'image/svg+xml')),
    );
    expect(
      await providerWith(adapter).search(
        const ImageProviderQuery(
          query: 'схема',
          kind: GeneratedCardImageKind.diagram,
        ),
      ),
      isEmpty,
    );
  });

  test('пустой запрос → пусто без сетевых запросов', () async {
    final adapter = FakeHttpAdapter((_) => jsonResponse(pagesPayload()));
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

  test(
    'HTTP 500 пробрасывается вызывающему (цепочка решает про ретрай)',
    () async {
      final adapter = FakeHttpAdapter(
        (_) => jsonResponse(<String, Object?>{}, statusCode: 500),
      );
      await expectLater(
        providerWith(adapter).search(
          const ImageProviderQuery(
            query: 'кремль',
            kind: GeneratedCardImageKind.photo,
          ),
        ),
        throwsA(isA<DioException>()),
      );
    },
  );
}
