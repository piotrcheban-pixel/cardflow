import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/api/images/image_provider.dart';
import 'package:cardflow/api/images/wikipedia_image_provider.dart';
import 'package:cardflow/domain/generation/card_image_kind.dart';

import '../../../helpers/fake_http_adapter.dart';

/// Wikipedia pageimages как провайдер кандидатов (7.14; ADR-028).
void main() {
  Map<String, Object?> pagesPayload({
    String topic = 'Спайность',
    String? thumb = 'https://upload.wikimedia.org/thumb/spainost.png',
    bool withThumbnail = true,
    int count = 1,
    bool asList = true,
  }) {
    final List<Map<String, Object?>> pages = <Map<String, Object?>>[
      for (var index = 0; index < count; index++)
        <String, Object?>{
          'pageid': 100 + index,
          'ns': 0,
          'title': index == 0 ? topic : '$topic $index',
          if (withThumbnail)
            'thumbnail': <String, Object?>{
              'source': index == 0
                  ? thumb
                  : 'https://upload.wikimedia.org/thumb/p$index.png',
              'width': 800,
              'height': 600,
            },
        },
    ];
    return <String, Object?>{
      'batchcomplete': true,
      'query': <String, Object?>{
        'pages': asList
            ? pages
            : <String, Object?>{
                for (var index = 0; index < pages.length; index++)
                  '${100 + index}': pages[index],
              },
      },
    };
  }

  WikipediaImageProvider providerWith(
    FakeHttpAdapter adapter, {
    List<String> languages = const <String>['ru', 'en'],
  }) => WikipediaImageProvider(
    dio: dioWithAdapter(adapter),
    languages: languages,
  );

  test('русский запрос → кандидат с превью статьи ru.wikipedia.org', () async {
    final adapter = FakeHttpAdapter((_) => jsonResponse(pagesPayload()));
    final candidates = await providerWith(adapter).search(
      const ImageProviderQuery(
        query: '  спайность минерала  ',
        kind: GeneratedCardImageKind.photo,
      ),
    );

    expect(candidates, hasLength(1));
    expect(candidates.single.provider, 'wikipedia');
    expect(candidates.single.url, contains('/thumb/spainost.png'));
    expect(candidates.single.width, 800);
    expect(candidates.single.attribution, contains('Спайность'));
    final RequestOptions request = adapter.requests.single;
    expect(request.uri.host, 'ru.wikipedia.org');
    expect(request.uri.queryParameters['generator'], 'search');
    expect(request.uri.queryParameters['prop'], 'pageimages');
  });

  test('ru пуст → пробует en', () async {
    final adapter = FakeHttpAdapter((RequestOptions options) {
      if (options.uri.host.startsWith('ru.')) {
        return jsonResponse(<String, Object?>{});
      }
      return jsonResponse(pagesPayload(topic: 'Cleavage (mineralogy)'));
    });
    final candidates = await providerWith(adapter).search(
      const ImageProviderQuery(
        query: 'спайность',
        kind: GeneratedCardImageKind.photo,
      ),
    );

    expect(candidates.single.attribution, contains('Cleavage'));
    expect(adapter.requests, hasLength(2));
    expect(adapter.requests.last.uri.host, 'en.wikipedia.org');
  });

  test('страницы картой (formatversion=1) поддерживаются', () async {
    final adapter = FakeHttpAdapter(
      (_) => jsonResponse(pagesPayload(asList: false)),
    );
    final candidates = await providerWith(adapter).search(
      const ImageProviderQuery(
        query: 'спайность',
        kind: GeneratedCardImageKind.photo,
      ),
    );
    expect(candidates, hasLength(1));
  });

  test('статья без превью пропускается', () async {
    final adapter = FakeHttpAdapter(
      (_) => jsonResponse(pagesPayload(withThumbnail: false)),
    );
    expect(
      await providerWith(adapter).search(
        const ImageProviderQuery(
          query: 'спайность',
          kind: GeneratedCardImageKind.photo,
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
}
