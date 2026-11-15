import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/api/generation/generation_diagnostics.dart';
import 'package:cardflow/api/images/wikipedia_image_search_service.dart';
import 'package:cardflow/domain/generation/generation_attachment.dart';

import '../../../helpers/fake_http_adapter.dart';

/// Wikipedia pageimages как источник иллюстраций (ADR-028, итерация 7.12).
void main() {
  final Uint8List jpeg = Uint8List.fromList(<int>[
    0xFF,
    0xD8,
    0xFF,
    0xE0,
    0x00,
    0x10,
    0x4A,
    0x46,
    0x49,
    0x46,
  ]);
  final Uint8List png = Uint8List.fromList(<int>[
    0x89,
    0x50,
    0x4E,
    0x47,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
    0,
    0,
  ]);

  Map<String, Object?> pagesPayload({
    String topic = 'Спайность',
    String? thumb = 'https://upload.wikimedia.org/thumb/spainost.png',
    bool withThumbnail = true,
    int count = 1,
  }) {
    return <String, Object?>{
      'batchcomplete': true,
      'query': <String, Object?>{
        'pages': <Object?>[
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
        ],
      },
    };
  }

  WikipediaImageSearchService serviceWith(
    FakeHttpAdapter adapter, {
    GenerationDiagnostics? diagnostics,
    List<String> languages = const <String>['ru', 'en'],
    int maxImageBytes = 5 * 1024 * 1024,
  }) {
    return WikipediaImageSearchService(
      dio: dioWithAdapter(adapter),
      diagnostics: diagnostics,
      languages: languages,
      maxImageBytes: maxImageBytes,
    );
  }

  test('русский запрос → превью статьи ru.wikipedia.org', () async {
    final adapter = FakeHttpAdapter((RequestOptions options) {
      if (options.uri.path.endsWith('/w/api.php')) {
        return jsonResponse(pagesPayload());
      }
      return bytesResponse(png, contentType: 'image/png');
    });
    final service = serviceWith(adapter);

    final result = await service.findImage('  спайность минерала  ');

    expect(result, isNotNull);
    expect(result!.bytes, png);
    expect(result.mediaType, AttachmentMediaType.png);
    expect(result.query, 'спайность минерала');
    expect(result.attribution, contains('Спайность'));
    expect(result.attribution, contains('Wikipedia'));
    expect(adapter.requests, hasLength(2));
    final RequestOptions search = adapter.requests.first;
    expect(search.uri.host, 'ru.wikipedia.org');
    expect(search.uri.queryParameters['generator'], 'search');
    expect(search.uri.queryParameters['gsrsearch'], 'спайность минерала');
    expect(search.uri.queryParameters['gsrnamespace'], '0');
    expect(search.uri.queryParameters['prop'], 'pageimages');
    expect(search.uri.queryParameters['pithumbsize'], '800');
    expect(search.headers['User-Agent'], contains('CardFlow'));
  });

  test('ru без результата → ищем в en', () async {
    final adapter = FakeHttpAdapter((RequestOptions options) {
      if (options.uri.path.endsWith('/w/api.php')) {
        if (options.uri.host == 'ru.wikipedia.org') {
          return jsonResponse(<String, Object?>{'batchcomplete': true});
        }
        return jsonResponse(pagesPayload(topic: 'Cleavage (crystal)'));
      }
      return bytesResponse(jpeg);
    });

    final result = await serviceWith(adapter).findImage('cleavage mineral');

    expect(result, isNotNull);
    expect(result!.attribution, contains('Cleavage (crystal)'));
    expect(adapter.requests, hasLength(3));
    expect(adapter.requests[1].uri.host, 'en.wikipedia.org');
  });

  test('статья без превью пропускается', () async {
    final adapter = FakeHttpAdapter(
      (_) => jsonResponse(pagesPayload(withThumbnail: false)),
    );

    final result = await serviceWith(
      adapter,
      languages: const <String>['ru'],
    ).findImage('раствор Клеричи');

    expect(result, isNull);
    expect(adapter.requests, hasLength(1), reason: 'скачивания не было');
  });

  test('несколько статей: скачивается первое рабочее превью', () async {
    var downloads = 0;
    final adapter = FakeHttpAdapter((RequestOptions options) {
      if (options.uri.path.endsWith('/w/api.php')) {
        return jsonResponse(pagesPayload(count: 2));
      }
      downloads++;
      if (downloads == 1) {
        return bytesResponse(<int>[1, 2, 3], contentType: 'image/png');
      }
      return bytesResponse(png, contentType: 'image/png');
    });

    final result = await serviceWith(
      adapter,
      languages: const <String>['ru'],
    ).findImage('спайность');

    expect(result, isNotNull);
    expect(downloads, 2);
    expect(result!.sourceUrl, contains('p1.png'));
  });

  test('картинка больше лимита пропускается', () async {
    final adapter = FakeHttpAdapter((RequestOptions options) {
      if (options.uri.path.endsWith('/w/api.php')) {
        return jsonResponse(pagesPayload());
      }
      return bytesResponse(<int>[...jpeg, ...List<int>.filled(100, 0)]);
    });

    expect(
      await serviceWith(
        adapter,
        languages: const <String>['ru'],
        maxImageBytes: 20,
      ).findImage('минерал'),
      isNull,
    );
  });

  test('ошибка сети → null и диагностика', () async {
    final List<String> messages = <String>[];
    final adapter = FakeHttpAdapter(
      (RequestOptions options) =>
          throw dioException(options, DioExceptionType.connectionError),
    );

    final result = await serviceWith(
      adapter,
      languages: const <String>['ru'],
      diagnostics: GenerationDiagnostics(enabled: true, sink: messages.add),
    ).findImage('минерал');

    expect(result, isNull);
    expect(messages, hasLength(1));
    expect(messages.single, contains('Wikipedia (ru)'));
    expect(messages.single, contains('ошибка запроса'));
  });

  test('пустой query → null без сетевых запросов', () async {
    final adapter = FakeHttpAdapter((_) => jsonResponse(pagesPayload()));
    expect(await serviceWith(adapter).findImage('   '), isNull);
    expect(adapter.requests, isEmpty);
  });

  test('успех пишется в диагностику с языком и статьёй', () async {
    final List<String> messages = <String>[];
    final adapter = FakeHttpAdapter((RequestOptions options) {
      if (options.uri.path.endsWith('/w/api.php')) {
        return jsonResponse(pagesPayload());
      }
      return bytesResponse(png, contentType: 'image/png');
    });

    await serviceWith(
      adapter,
      languages: const <String>['ru'],
      diagnostics: GenerationDiagnostics(enabled: true, sink: messages.add),
    ).findImage('спайность');

    expect(messages.single, contains('Wikipedia (ru): статья «Спайность»'));
    expect(messages.single, contains('png'));
  });
}
