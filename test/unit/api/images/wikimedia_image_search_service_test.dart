import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/api/generation/generation_diagnostics.dart';
import 'package:cardflow/api/images/wikimedia_image_search_service.dart';
import 'package:cardflow/domain/generation/generation_attachment.dart';

import '../../../helpers/fake_http_adapter.dart';

/// Wikimedia Commons как источник иллюстраций (ADR-027, итерация 7.11).
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
                  'url': 'https://upload.wikimedia.org/kremlin-$index.jpg',
                  'thumburl': index == 0
                      ? thumburl
                      : 'https://upload.wikimedia.org/thumb/kremlin-$index.jpg',
                  'mime': mime,
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

  WikimediaImageSearchService serviceWith(
    FakeHttpAdapter adapter, {
    GenerationDiagnostics? diagnostics,
    int? maxImageBytes,
  }) {
    return WikimediaImageSearchService(
      dio: dioWithAdapter(adapter),
      diagnostics: diagnostics,
      maxImageBytes: maxImageBytes ?? 5 * 1024 * 1024,
    );
  }

  test('ищет по русскому запросу и скачивает thumbnail', () async {
    final adapter = FakeHttpAdapter((RequestOptions options) {
      if (options.uri.path.endsWith('/w/api.php')) {
        return jsonResponse(pagesPayload());
      }
      return bytesResponse(jpeg);
    });
    final service = serviceWith(adapter);

    final result = await service.findImage('  Московский Кремль  ');

    expect(result, isNotNull);
    expect(result!.bytes, jpeg);
    expect(result.mediaType, AttachmentMediaType.jpeg);
    expect(result.query, 'Московский Кремль');
    expect(result.sourceUrl, contains('/thumb/kremlin.jpg'));
    expect(result.attribution, contains('CC BY-SA 4.0'));
    expect(
      result.attribution,
      contains('Иван Петров'),
      reason: 'HTML автора вычищается',
    );
    expect(result.attribution, isNot(contains('<a')));

    expect(adapter.requests, hasLength(2));
    final RequestOptions search = adapter.requests.first;
    expect(search.uri.host, 'commons.wikimedia.org');
    expect(search.uri.queryParameters['action'], 'query');
    expect(search.uri.queryParameters['generator'], 'search');
    expect(search.uri.queryParameters['gsrsearch'], 'Московский Кремль');
    expect(search.uri.queryParameters['gsrnamespace'], '6');
    expect(search.uri.queryParameters['iiprop'], 'url|mime|extmetadata');
    expect(search.uri.queryParameters['iiurlwidth'], '800');
    expect(search.headers['User-Agent'], contains('CardFlow'));
  });

  test('пустой query → null без сетевых запросов', () async {
    final adapter = FakeHttpAdapter((_) => jsonResponse(pagesPayload()));
    expect(await serviceWith(adapter).findImage('   '), isNull);
    expect(adapter.requests, isEmpty);
  });

  test('PDF/DJVU/SVG из Commons пропускаются по MIME', () async {
    final adapter = FakeHttpAdapter(
      (RequestOptions options) =>
          jsonResponse(pagesPayload(mime: 'application/pdf')),
    );

    expect(await serviceWith(adapter).findImage('кремль'), isNull);
    expect(adapter.requests, hasLength(1), reason: 'скачивания не было');
  });

  test('PNG определяется по сигнатуре', () async {
    final adapter = FakeHttpAdapter((RequestOptions options) {
      if (options.uri.path.endsWith('/w/api.php')) {
        return jsonResponse(pagesPayload(mime: 'image/png'));
      }
      return bytesResponse(png, contentType: 'image/png');
    });

    final result = await serviceWith(adapter).findImage('схема');
    expect(result!.mediaType, AttachmentMediaType.png);
    expect(result.mimeType, 'image/png');
  });

  test('первый результат не скачался — пробует следующий', () async {
    var downloads = 0;
    final adapter = FakeHttpAdapter((RequestOptions options) {
      if (options.uri.path.endsWith('/w/api.php')) {
        return jsonResponse(pagesPayload(count: 2));
      }
      downloads++;
      if (downloads == 1) {
        return bytesResponse(<int>[1, 2, 3], contentType: 'image/jpeg');
      }
      return bytesResponse(jpeg);
    });

    final result = await serviceWith(adapter).findImage('кремль');

    expect(result, isNotNull);
    expect(downloads, 2);
    expect(result!.sourceUrl, contains('kremlin-1.jpg'));
  });

  test('thumburl отсутствует — скачивается оригинал', () async {
    final adapter = FakeHttpAdapter((RequestOptions options) {
      if (options.uri.path.endsWith('/w/api.php')) {
        return jsonResponse(pagesPayload(thumburl: null));
      }
      return bytesResponse(jpeg);
    });

    final result = await serviceWith(adapter).findImage('кремль');
    expect(result!.sourceUrl, contains('kremlin-0.jpg'));
  });

  test('картинка больше лимита пропускается', () async {
    final adapter = FakeHttpAdapter((RequestOptions options) {
      if (options.uri.path.endsWith('/w/api.php')) {
        return jsonResponse(pagesPayload());
      }
      return bytesResponse(<int>[...jpeg, ...List<int>.filled(100, 0)]);
    });

    expect(
      await serviceWith(adapter, maxImageBytes: 20).findImage('кремль'),
      isNull,
    );
  });

  test('ошибка сети → null без исключения и с диагностикой', () async {
    final List<String> messages = <String>[];
    final adapter = FakeHttpAdapter(
      (RequestOptions options) =>
          throw dioException(options, DioExceptionType.connectionError),
    );

    final result = await serviceWith(
      adapter,
      diagnostics: GenerationDiagnostics(enabled: true, sink: messages.add),
    ).findImage('кремль');

    expect(result, isNull);
    expect(messages, hasLength(1));
    expect(messages.single, contains('Wikimedia Commons'));
    expect(messages.single, contains('ошибка запроса'));
  });

  test('пустая выдача → null и диагностика', () async {
    final List<String> messages = <String>[];
    final adapter = FakeHttpAdapter(
      (_) => jsonResponse(<String, Object?>{'batchcomplete': ''}),
    );

    final result = await serviceWith(
      adapter,
      diagnostics: GenerationDiagnostics(enabled: true, sink: messages.add),
    ).findImage('кремль');

    expect(result, isNull);
    expect(messages.single, contains('нет подходящей картинки'));
  });

  // API с `formatversion=2` отдаёт `query.pages` списком — разбор не должен
  // зависеть от формы ответа.
  test('pages списком (formatversion=2) разбирается', () async {
    final adapter = FakeHttpAdapter((RequestOptions options) {
      if (options.uri.path.endsWith('/w/api.php')) {
        return jsonResponse(<String, Object?>{
          'batchcomplete': true,
          'query': <String, Object?>{
            'pages': <Object?>[
              <String, Object?>{
                'pageid': 7,
                'ns': 6,
                'title': 'File:Московский Кремль.jpg',
                'index': 1,
                'imageinfo': <Object?>[
                  <String, Object?>{
                    'url': 'https://upload.wikimedia.org/kremlin.jpg',
                    'thumburl':
                        'https://upload.wikimedia.org/thumb/kremlin.jpg',
                    'mime': 'image/jpeg',
                    'extmetadata': <String, Object?>{
                      'LicenseShortName': <String, Object?>{'value': 'CC0'},
                    },
                  },
                ],
              },
            ],
          },
        });
      }
      return bytesResponse(jpeg);
    });

    final result = await serviceWith(adapter).findImage('кремль');

    expect(result, isNotNull);
    expect(result!.attribution, contains('CC0'));
  });

  test('успех пишется в диагностику', () async {
    final List<String> messages = <String>[];
    final adapter = FakeHttpAdapter((RequestOptions options) {
      if (options.uri.path.endsWith('/w/api.php')) {
        return jsonResponse(pagesPayload());
      }
      return bytesResponse(jpeg);
    });

    await serviceWith(
      adapter,
      diagnostics: GenerationDiagnostics(enabled: true, sink: messages.add),
    ).findImage('кремль');

    expect(messages.single, contains('Wikimedia Commons: скачано'));
    expect(messages.single, contains('jpeg'));
  });
}
