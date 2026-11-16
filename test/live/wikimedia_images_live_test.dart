// Live-проверка источников иллюстраций (ADR-027, ADR-028, итерации 7.11/7.12).
//
// Тесты ходят в сеть (Commons/Wikipedia API) и не требуют ключей: запуск только
// по `--tags live`, чтобы обычный прогон оставался офлайновым.
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/api/generation/generation_diagnostics.dart';
import 'package:cardflow/api/images/composite_card_image_finder.dart';
import 'package:cardflow/api/images/image_provider.dart';
import 'package:cardflow/api/images/image_search_service.dart';
import 'package:cardflow/api/images/wikimedia_image_provider.dart';
import 'package:cardflow/api/images/wikipedia_image_provider.dart';
import 'package:cardflow/domain/generation/card_image_finder.dart';
import 'package:cardflow/domain/generation/card_image_kind.dart';
import 'package:cardflow/domain/generation/generation_attachment.dart';

void main() {
  test(
    'живой Wikimedia Commons: русский image_query → JPEG/PNG',
    () async {
      final Dio dio = Dio();
      addTearDown(() => dio.close(force: true));
      final List<String> diagnostics = <String>[];
      final service = ImageSearchService(
        dio: dio,
        providers: <ImageProvider>[WikimediaImageProvider(dio: dio)],
        diagnostics: GenerationDiagnostics(
          enabled: true,
          sink: diagnostics.add,
        ),
      );

      final image = await service.findImage(
        'Московский Кремль',
        kind: GeneratedCardImageKind.photo,
      );

      expect(
        image,
        isNotNull,
        reason: 'Commons должен ответить на русский запрос',
      );
      expect(
        image!.mediaType == AttachmentMediaType.jpeg ||
            image.mediaType == AttachmentMediaType.png,
        isTrue,
      );
      expect(image.bytes, isNotEmpty);
      expect(image.attribution, isNotNull);
      // ignore: avoid_print — evidence без тел выдачи Commons.
      print(
        'LIVE Wikimedia OK: ${image.mediaType.name}, '
        'bytes=${image.bytes.length}, attribution=${image.attribution}',
      );
      expect(diagnostics.join('\n'), contains('wikimedia'));
    },
    timeout: const Timeout(Duration(minutes: 2)),
    tags: <String>['live'],
  );

  // ADR-028: Wikipedia ищет статью, а не файл, и находит картинку там, где
  // Commons по русской словоформе даёт 0 файлов.
  test(
    'живой Wikipedia: русский запрос → превью статьи',
    () async {
      final Dio dio = Dio();
      addTearDown(() => dio.close(force: true));
      final List<String> diagnostics = <String>[];
      final service = ImageSearchService(
        dio: dio,
        providers: <ImageProvider>[WikipediaImageProvider(dio: dio)],
        diagnostics: GenerationDiagnostics(
          enabled: true,
          sink: diagnostics.add,
        ),
      );

      final image = await service.findImage('плотность минерала');

      expect(image, isNotNull, reason: 'Wikipedia должна найти статью');
      expect(image!.bytes, isNotEmpty);
      expect(
        image.mediaType == AttachmentMediaType.jpeg ||
            image.mediaType == AttachmentMediaType.png,
        isTrue,
      );
      // ignore: avoid_print — evidence без тел выдачи Wikipedia.
      print(
        'LIVE Wikipedia OK: ${image.mediaType.name}, '
        'bytes=${image.bytes.length}, attribution=${image.attribution}',
      );
      expect(diagnostics.join('\n'), contains('wikipedia'));
    },
    timeout: const Timeout(Duration(minutes: 2)),
    tags: <String>['live'],
  );

  test(
    'живая цепочка источников: «спайность минерала» → картинка',
    () async {
      final Dio dio = Dio();
      addTearDown(() => dio.close(force: true));
      final List<String> diagnostics = <String>[];
      final GenerationDiagnostics diag = GenerationDiagnostics(
        enabled: true,
        sink: diagnostics.add,
      );
      final finder = CompositeCardImageFinder(<CardImageFinder>[
        ImageSearchService(
          dio: dio,
          providers: <ImageProvider>[WikimediaImageProvider(dio: dio)],
          diagnostics: diag,
        ),
        ImageSearchService(
          dio: dio,
          providers: <ImageProvider>[WikipediaImageProvider(dio: dio)],
          diagnostics: diag,
        ),
      ]);

      final image = await finder.findImage('спайность минерала');

      expect(image, isNotNull, reason: 'хотя бы один источник должен найти');
      // ignore: avoid_print — evidence с итогом каждого источника.
      print(
        'LIVE composite OK: ${image!.mediaType.name}, bytes=${image.bytes.length}',
      );
      for (final String line in diagnostics) {
        // ignore: avoid_print
        print(line);
      }
    },
    timeout: const Timeout(Duration(minutes: 3)),
    tags: <String>['live'],
  );
}
