import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/api/generation/generation_diagnostics.dart';
import 'package:cardflow/api/images/image_search_service.dart';
import 'package:cardflow/domain/generation/generation_attachment.dart';

import '../../../helpers/fake_http_adapter.dart';

/// Итерация 7.9: поиск картинок в Openverse без ключа (ADR-023).
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
          'license_url': 'https://creativecommons.org/licenses/by-sa/2.0/',
          'creator': 'Allen Gathman',
          'foreign_landing_url': 'https://example.test/landing-$index',
          'attribution':
              '"Diagram $index" by Allen Gathman is licensed under CC BY-SA 2.0.',
        },
    ],
  };

  ImageSearchService serviceWith(
    FakeHttpAdapter adapter, {
    int? maxImageBytes,
    GenerationDiagnostics? diagnostics,
  }) {
    return ImageSearchService(
      dio: dioWithAdapter(adapter),
      maxImageBytes: maxImageBytes ?? 5 * 1024 * 1024,
      diagnostics: diagnostics,
    );
  }

  test('ищет по query и скачивает thumbnail как картинку', () async {
    final adapter = FakeHttpAdapter((RequestOptions options) {
      if (options.uri.path.endsWith('/v1/images/')) {
        return jsonResponse(searchPayload());
      }
      if (options.uri.path.endsWith('/thumb/')) {
        return bytesResponse(jpeg);
      }
      return bytesResponse(<int>[1, 2, 3], contentType: 'text/plain');
    });
    final service = serviceWith(adapter);

    final result = await service.findImage('  photosynthesis diagram  ');

    expect(result, isNotNull);
    expect(result!.bytes, jpeg);
    expect(result.mediaType, AttachmentMediaType.jpeg);
    expect(result.query, 'photosynthesis diagram');
    expect(result.sourceUrl, contains('/thumb/'));
    expect(result.attribution, contains('CC BY-SA'));

    expect(adapter.requests, hasLength(2));
    final search = adapter.requests.first;
    expect(search.uri.host, 'api.openverse.org');
    expect(search.uri.queryParameters['q'], 'photosynthesis diagram');
    expect(search.uri.queryParameters['page_size'], '5');
    expect(search.uri.queryParameters['license'], 'cc0,pdm,by,by-sa');
    expect(
      search.headers['User-Agent'],
      'CardFlow/1.0',
      reason: 'Openverse просит User-Agent для анонимных запросов',
    );
  });

  test('пустой query → null без сетевых запросов', () async {
    final adapter = FakeHttpAdapter((_) => jsonResponse(searchPayload()));
    final service = serviceWith(adapter);

    expect(await service.findImage('   '), isNull);
    expect(adapter.requests, isEmpty);
  });

  test('PNG определяется по сигнатуре', () async {
    final adapter = FakeHttpAdapter((RequestOptions options) {
      if (options.uri.path.endsWith('/v1/images/')) {
        return jsonResponse(searchPayload());
      }
      return bytesResponse(png, contentType: 'image/png');
    });
    final result = await serviceWith(adapter).findImage('scheme');

    expect(result!.mediaType, AttachmentMediaType.png);
    expect(result.mimeType, 'image/png');
  });

  test('первый результат не скачался — пробует следующий', () async {
    var downloads = 0;
    final adapter = FakeHttpAdapter((RequestOptions options) {
      if (options.uri.path.endsWith('/v1/images/')) {
        return jsonResponse(searchPayload(count: 2));
      }
      downloads++;
      if (downloads == 1) {
        return bytesResponse(<int>[1, 2, 3], contentType: 'text/plain');
      }
      return bytesResponse(jpeg);
    });

    final result = await serviceWith(adapter).findImage('eiffel tower');

    expect(result, isNotNull);
    expect(downloads, 2);
    expect(result!.sourceUrl, contains('image-1'));
  });

  test('нет результатов → null', () async {
    final adapter = FakeHttpAdapter(
      (_) => jsonResponse(<String, Object?>{'results': <Object?>[]}),
    );
    expect(await serviceWith(adapter).findImage('ничего'), isNull);
  });

  test('картинка больше лимита пропускается', () async {
    final adapter = FakeHttpAdapter((RequestOptions options) {
      if (options.uri.path.endsWith('/v1/images/')) {
        return jsonResponse(searchPayload());
      }
      return bytesResponse(<int>[...jpeg, ...List<int>.filled(100, 0)]);
    });

    expect(
      await serviceWith(adapter, maxImageBytes: 20).findImage('big image'),
      isNull,
    );
  });

  test('ошибка сети → null, без исключения', () async {
    final adapter = FakeHttpAdapter(
      (RequestOptions options) =>
          throw dioException(options, DioExceptionType.connectionError),
    );
    expect(await serviceWith(adapter).findImage('offline'), isNull);
  });

  test('битый JSON поиска → null', () async {
    final adapter = FakeHttpAdapter(
      (_) => textResponse('<html>Service Unavailable</html>'),
    );
    expect(await serviceWith(adapter).findImage('broken'), isNull);
  });

  // Итерация 7.10, ADR-024: поиск картинок виден в debug-диагностике —
  // без этого «картинок нет» не отличить от «скачать не удалось».
  test('успешный поиск пишется в диагностику', () async {
    final List<String> messages = <String>[];
    final adapter = FakeHttpAdapter((RequestOptions options) {
      if (options.uri.path.endsWith('/v1/images/')) {
        return jsonResponse(searchPayload());
      }
      return bytesResponse(jpeg);
    });
    final service = serviceWith(
      adapter,
      diagnostics: GenerationDiagnostics(enabled: true, sink: messages.add),
    );

    await service.findImage('eiffel tower');

    expect(messages, hasLength(1));
    expect(messages.single, contains('eiffel tower'));
    expect(messages.single, contains('скачано'));
    expect(messages.single, contains('jpeg'));
  });

  test('ошибка сети и пустая выдача пишутся в диагностику', () async {
    final List<String> messages = <String>[];
    final diagnostics = GenerationDiagnostics(
      enabled: true,
      sink: messages.add,
    );
    final offline = FakeHttpAdapter(
      (RequestOptions options) =>
          throw dioException(options, DioExceptionType.connectionError),
    );
    expect(
      await serviceWith(offline, diagnostics: diagnostics).findImage('offline'),
      isNull,
    );

    final empty = FakeHttpAdapter(
      (_) => jsonResponse(<String, Object?>{'results': <Object?>[]}),
    );
    expect(
      await serviceWith(empty, diagnostics: diagnostics).findImage('нет'),
      isNull,
    );

    expect(messages, hasLength(2));
    expect(messages.first, contains('ошибка запроса'));
    expect(messages.last, contains('нет подходящей картинки'));
  });

  test('диагностика выключена — поиск ничего не пишет', () async {
    final List<String> messages = <String>[];
    final adapter = FakeHttpAdapter((RequestOptions options) {
      if (options.uri.path.endsWith('/v1/images/')) {
        return jsonResponse(searchPayload());
      }
      return bytesResponse(jpeg);
    });
    final service = serviceWith(
      adapter,
      diagnostics: GenerationDiagnostics(enabled: false, sink: messages.add),
    );

    await service.findImage('eiffel tower');
    expect(messages, isEmpty);
  });
}
