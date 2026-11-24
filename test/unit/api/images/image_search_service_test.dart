import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:cardflow/api/images/image_provider.dart';
import 'package:cardflow/api/images/image_providers.dart';
import 'package:cardflow/api/images/image_search_service.dart';
import 'package:cardflow/domain/generation/card_image_kind.dart';
import 'package:cardflow/domain/generation/generation_attachment.dart';

import '../../../helpers/fake_http_adapter.dart';

/// Цепочка провайдеров картинок (7.14): приоритет, фильтры, ретраи, кэш.
void main() {
  final Uint8List png800x450 = _png(800, 450);
  final Uint8List png300x200 = _png(300, 200);
  final Uint8List png1200x300 = _png(1200, 300);

  ImageCandidate candidate(String provider, String url) =>
      ImageCandidate(provider: provider, url: url);

  /// Dio, отдающий заданные байты по URL.
  Dio dioWithImages(
    Map<String, Uint8List> byUrl, {
    void Function()? onRequest,
    void Function()? onDone,
    Duration? delay,
  }) {
    return dioWithAdapter(
      FakeHttpAdapter((RequestOptions options) async {
        onRequest?.call();
        if (delay != null) await Future<void>.delayed(delay);
        onDone?.call();
        final Uint8List? bytes = byUrl[options.uri.toString()];
        if (bytes == null) return bytesResponse(<int>[1, 2, 3]);
        return bytesResponse(bytes, contentType: 'image/png');
      }),
    );
  }

  test('приоритет провайдеров: первый с картинкой выигрывает', () async {
    final first = _FakeProvider('one', <ImageCandidate>[
      candidate('one', 'https://img.test/one.png'),
    ]);
    final second = _FakeProvider('two', <ImageCandidate>[
      candidate('two', 'https://img.test/two.png'),
    ]);
    final service = ImageSearchService(
      dio: dioWithImages(<String, Uint8List>{
        'https://img.test/one.png': png800x450,
        'https://img.test/two.png': png800x450,
      }),
      providers: <ImageProvider>[first, second],
    );

    final image = await service.findImage('truss bridge');

    expect(image, isNotNull);
    expect(image!.provider, 'one');
    expect(second.searches, isEmpty);
  });

  test('пустая выдача провайдера → следующий', () async {
    final empty = _FakeProvider('empty', const <ImageCandidate>[]);
    final second = _FakeProvider('two', <ImageCandidate>[
      candidate('two', 'https://img.test/two.png'),
    ]);
    final service = ImageSearchService(
      dio: dioWithImages(<String, Uint8List>{
        'https://img.test/two.png': png800x450,
      }),
      providers: <ImageProvider>[empty, second],
    );

    final image = await service.findImage('truss bridge');
    expect(image!.provider, 'two');
    expect(empty.searches, <String>['truss bridge']);
  });

  test('таймаут провайдера → следующий', () async {
    final slow = _FakeProvider('slow', <ImageCandidate>[
      candidate('slow', 'https://img.test/slow.png'),
    ], delay: const Duration(milliseconds: 300));
    final fast = _FakeProvider('fast', <ImageCandidate>[
      candidate('fast', 'https://img.test/fast.png'),
    ]);
    final service = ImageSearchService(
      dio: dioWithImages(<String, Uint8List>{
        'https://img.test/fast.png': png800x450,
      }),
      providers: <ImageProvider>[slow, fast],
      providerTimeout: const Duration(milliseconds: 40),
    );

    final image = await service.findImage('scheme');
    expect(image!.provider, 'fast');
  });

  test('запасной запрос пробуется, если основной пуст', () async {
    final provider = _FakeProvider(
      'p',
      const <ImageCandidate>[],
      byQuery: <String, List<ImageCandidate>>{
        'force diagram': <ImageCandidate>[
          candidate('p', 'https://img.test/force.png'),
        ],
      },
    );
    final service = ImageSearchService(
      dio: dioWithImages(<String, Uint8List>{
        'https://img.test/force.png': png800x450,
      }),
      providers: <ImageProvider>[provider],
    );

    final image = await service.findImage(
      'inclined plane forces diagram',
      fallbackQuery: 'force diagram',
    );
    expect(image, isNotNull);
    expect(provider.searches, <String>[
      'inclined plane forces diagram',
      'force diagram',
    ]);
    expect(image!.query, 'force diagram');
  });

  test('фильтр размера и пропорций: мелкое и вытянутое пропускаются', () async {
    final provider = _FakeProvider('p', <ImageCandidate>[
      candidate('p', 'https://img.test/small.png'),
      candidate('p', 'https://img.test/wide.png'),
      candidate('p', 'https://img.test/ok.png'),
    ]);
    final dio = dioWithImages(<String, Uint8List>{
      'https://img.test/small.png': png300x200,
      'https://img.test/wide.png': png1200x300,
      'https://img.test/ok.png': png800x450,
    });
    final service = ImageSearchService(
      dio: dio,
      providers: <ImageProvider>[provider],
    );

    final image = await service.findImage('x');
    expect(image!.sourceUrl, 'https://img.test/ok.png');
    expect((dio.httpClientAdapter as FakeHttpAdapter).requests, hasLength(3));
  });

  test('формат: не JPEG/PNG/WebP пропускается', () async {
    final provider = _FakeProvider('p', <ImageCandidate>[
      candidate('p', 'https://img.test/svg'),
    ]);
    final service = ImageSearchService(
      dio: dioWithImages(<String, Uint8List>{
        'https://img.test/svg': Uint8List.fromList(
          '<svg xmlns="…"></svg>'.codeUnits,
        ),
      }),
      providers: <ImageProvider>[provider],
    );
    expect(await service.findImage('x'), isNull);
  });

  test('WebP принимается (VP8X)', () async {
    final provider = _FakeProvider('p', <ImageCandidate>[
      candidate('p', 'https://img.test/pic.webp'),
    ]);
    final service = ImageSearchService(
      dio: dioWithImages(<String, Uint8List>{
        'https://img.test/pic.webp': _webp(800, 450),
      }),
      providers: <ImageProvider>[provider],
    );
    final image = await service.findImage('x');
    expect(image!.mediaType, AttachmentMediaType.webp);
  });

  test('429: один ретрай с backoff, затем следующий провайдер', () async {
    final flaky = _FakeProvider(
      'flaky',
      const <ImageCandidate>[],
      error: _httpError(429),
    );
    final good = _FakeProvider('good', <ImageCandidate>[
      candidate('good', 'https://img.test/good.png'),
    ]);
    final sleeps = <Duration>[];
    final service = ImageSearchService(
      dio: dioWithImages(<String, Uint8List>{
        'https://img.test/good.png': png800x450,
      }),
      providers: <ImageProvider>[flaky, good],
      sleep: (Duration duration) async => sleeps.add(duration),
    );

    final image = await service.findImage('x');
    expect(image!.provider, 'good');
    expect(flaky.searches, hasLength(2), reason: 'исходный + один ретрай');
    expect(sleeps, hasLength(1));
    expect(sleeps.single, const Duration(milliseconds: 300));
  });

  test('5xx после ретрая не ломает цепочку', () async {
    final broken = _FakeProvider(
      'broken',
      const <ImageCandidate>[],
      error: _httpError(500),
    );
    final service = ImageSearchService(
      dio: dioWithImages(const <String, Uint8List>{}),
      providers: <ImageProvider>[broken],
      sleep: (Duration _) async {},
    );
    expect(await service.findImage('x'), isNull);
    expect(broken.searches, hasLength(2));
  });

  test('404 не ретраится', () async {
    final broken = _FakeProvider(
      'broken',
      const <ImageCandidate>[],
      error: _httpError(404),
    );
    final service = ImageSearchService(
      dio: dioWithImages(const <String, Uint8List>{}),
      providers: <ImageProvider>[broken],
    );
    expect(await service.findImage('x'), isNull);
    expect(broken.searches, hasLength(1));
  });

  test('дубль URL: занятая картинка не возвращается повторно', () async {
    final provider = _FakeProvider('p', <ImageCandidate>[
      candidate('p', 'https://img.test/same.png'),
      candidate('p', 'https://img.test/other.png'),
    ]);
    final service = ImageSearchService(
      dio: dioWithImages(<String, Uint8List>{
        'https://img.test/same.png': png800x450,
        'https://img.test/other.png': png800x450,
      }),
      providers: <ImageProvider>[provider],
    );
    final used = <String>{'https://img.test/same.png'};

    final image = await service.findImage('x', excludedSourceUrls: used);
    expect(image!.sourceUrl, 'https://img.test/other.png');
    // Набор занятых URL ведёт пайплайн: цепочка его только читает.
    expect(used, <String>{'https://img.test/same.png'});
  });

  test('метаданные источника сохраняются', () async {
    final provider = _FakeProvider('wikimedia', <ImageCandidate>[
      ImageCandidate(
        provider: 'wikimedia',
        url: 'https://img.test/a.png',
        author: 'Иван Петров',
        license: 'CC BY-SA 4.0',
        attribution: 'File:A · Иван Петров · CC BY-SA 4.0',
      ),
    ]);
    final service = ImageSearchService(
      dio: dioWithImages(<String, Uint8List>{
        'https://img.test/a.png': png800x450,
      }),
      providers: <ImageProvider>[provider],
    );

    final image = await service.findImage(
      'x',
      kind: GeneratedCardImageKind.diagram,
    );
    expect(image!.provider, 'wikimedia');
    expect(image.author, 'Иван Петров');
    expect(image.license, 'CC BY-SA 4.0');
    expect(image.sourceUrl, 'https://img.test/a.png');
    expect(image.kind, GeneratedCardImageKind.diagram);
    expect(image.fallbackQuery, isNull);
  });

  test('кэш: повторный запрос не ходит в сеть и в провайдеры', () async {
    final provider = _FakeProvider('p', <ImageCandidate>[
      candidate('p', 'https://img.test/cache.png'),
    ]);
    final dio = dioWithImages(<String, Uint8List>{
      'https://img.test/cache.png': png800x450,
    });
    final service = ImageSearchService(
      dio: dio,
      providers: <ImageProvider>[provider],
    );

    final first = await service.findImage('cache me');
    final second = await service.findImage('cache me');
    expect(identical(first, second), isTrue);
    expect(provider.searches, hasLength(1));
    expect((dio.httpClientAdapter as FakeHttpAdapter).requests, hasLength(1));
  });

  test('не больше 4 одновременных скачиваний', () async {
    var active = 0;
    var maxActive = 0;
    final provider = _FakeProvider(
      'p',
      const <ImageCandidate>[],
      candidateForQuery: (String query) => <ImageCandidate>[
        candidate('p', 'https://img.test/$query.png'),
      ],
    );
    final dio = dioWithImages(
      <String, Uint8List>{
        for (var i = 0; i < 6; i++) 'https://img.test/q$i.png': png800x450,
      },
      delay: const Duration(milliseconds: 25),
      onRequest: () {
        active++;
        if (active > maxActive) maxActive = active;
      },
      onDone: () => active--,
    );
    final service = ImageSearchService(
      dio: dio,
      providers: <ImageProvider>[provider],
    );

    await Future.wait(<Future<void>>[
      for (var i = 0; i < 6; i++)
        service.findImage('q$i', kind: GeneratedCardImageKind.photo),
    ]);

    expect(maxActive, lessThanOrEqualTo(4));
    expect(maxActive, greaterThan(1), reason: 'загрузки идут параллельно');
  });

  test('провайдеры без ключа не попадают в цепочку', () {
    final dio = Dio();
    addTearDown(() => dio.close(force: true));
    final withoutKeys = buildImageProviders(dio: dio);
    expect(
      <String>[for (final provider in withoutKeys) provider.name],
      <String>['wikimedia', 'wikipedia', 'openverse'],
    );

    final withKeys = buildImageProviders(
      dio: dio,
      pixabayApiKey: 'pix-key',
      pexelsApiKey: 'pex-key',
    );
    expect(
      <String>[for (final provider in withKeys) provider.name],
      <String>['wikimedia', 'wikipedia', 'openverse', 'pixabay', 'pexels'],
    );
  });

  test('Pixabay/Pexels пропускаются, если ключ пустой', () {
    final dio = Dio();
    addTearDown(() => dio.close(force: true));
    final providers = buildImageProviders(dio: dio, pixabayApiKey: '  ');
    expect(<String>[
      for (final provider in providers) provider.name,
    ], isNot(contains('pixabay')));
  });

  // Аудит 2.0 (P1-04): до скачивания отсеиваются кандидаты, чьё название и
  // описание не связаны с запросом — карточка остаётся без иллюстрации, но не
  // получает чужое фото.
  group('релевантность кандидата', () {
    test('нерелевантный кандидат не скачивается', () async {
      var requests = 0;
      final provider = _FakeProvider('wikimedia', const <ImageCandidate>[
        ImageCandidate(
          provider: 'wikimedia',
          url: 'https://img.test/building.png',
          title: 'Moscow State University main building',
          description: 'University building photo',
        ),
      ]);
      final dio = dioWithImages(<String, Uint8List>{
        'https://img.test/building.png': png800x450,
      }, onRequest: () => requests++);
      final service = ImageSearchService(
        dio: dio,
        providers: <ImageProvider>[provider],
      );

      final image = await service.findImage('test reliability');

      expect(image, isNull);
      expect(requests, 0, reason: 'нерелевантное не скачиваем вовсе');
    });

    test('релевантный кандидат прикрепляется', () async {
      final provider = _FakeProvider('wikimedia', const <ImageCandidate>[
        ImageCandidate(
          provider: 'wikimedia',
          url: 'https://img.test/leaf.png',
          title: 'Leaf structure diagram',
          description: 'Cross section of a leaf',
        ),
      ]);
      final service = ImageSearchService(
        dio: dioWithImages(<String, Uint8List>{
          'https://img.test/leaf.png': png800x450,
        }),
        providers: <ImageProvider>[provider],
      );

      final image = await service.findImage('leaf structure');

      expect(image, isNotNull);
      expect(image!.sourceUrl, 'https://img.test/leaf.png');
    });

    test('кандидат без метаданных не отбрасывается', () async {
      final provider = _FakeProvider('openverse', <ImageCandidate>[
        candidate('openverse', 'https://img.test/plain.png'),
      ]);
      final service = ImageSearchService(
        dio: dioWithImages(<String, Uint8List>{
          'https://img.test/plain.png': png800x450,
        }),
        providers: <ImageProvider>[provider],
      );

      expect(await service.findImage('truss bridge'), isNotNull);
    });
  });
}

Uint8List _png(int width, int height) {
  return Uint8List.fromList(
    img.encodePng(img.Image(width: width, height: height)),
  );
}

/// Минимальный WebP VP8X с canvas-размерами.
Uint8List _webp(int width, int height) {
  final bytes = Uint8List(40);
  void writeAscii(int offset, String value) {
    for (var i = 0; i < value.length; i++) {
      bytes[offset + i] = value.codeUnitAt(i);
    }
  }

  writeAscii(0, 'RIFF');
  writeAscii(8, 'WEBP');
  writeAscii(12, 'VP8X');
  // Размер чанка (10 байт) little-endian.
  bytes[16] = 0x0A;
  // Canvas width-1 и height-1, 24 бита little-endian, начиная с 24.
  final int w = width - 1;
  final int h = height - 1;
  bytes[24] = w & 0xFF;
  bytes[25] = (w >> 8) & 0xFF;
  bytes[26] = (w >> 16) & 0xFF;
  bytes[27] = h & 0xFF;
  bytes[28] = (h >> 8) & 0xFF;
  bytes[29] = (h >> 16) & 0xFF;
  return bytes;
}

DioException _httpError(int statusCode) {
  final RequestOptions options = RequestOptions(path: '/search');
  return DioException(
    requestOptions: options,
    type: DioExceptionType.badResponse,
    response: Response<void>(requestOptions: options, statusCode: statusCode),
  );
}

/// Провайдер-фейк: ответы по запросу, задержка, ошибка и журнал вызовов.
class _FakeProvider implements ImageProvider {
  _FakeProvider(
    this.name,
    this.candidates, {
    this.byQuery = const <String, List<ImageCandidate>>{},
    this.candidateForQuery,
    this.delay,
    this.error,
  });

  @override
  final String name;

  final List<ImageCandidate> candidates;
  final Map<String, List<ImageCandidate>> byQuery;
  final List<ImageCandidate> Function(String query)? candidateForQuery;
  final Duration? delay;
  final Object? error;
  final List<String> searches = <String>[];

  @override
  Future<List<ImageCandidate>> search(ImageProviderQuery query) async {
    searches.add(query.query);
    if (delay != null) await Future<void>.delayed(delay!);
    if (error != null) throw error!;
    if (candidateForQuery != null) return candidateForQuery!(query.query);
    final List<ImageCandidate>? specific = byQuery[query.query];
    return specific ?? candidates;
  }
}
