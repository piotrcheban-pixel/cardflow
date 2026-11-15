// Live-проверка источников иллюстраций (ADR-026, итерация 7.11).
//
// Тест ходит в сеть (Commons API) и не требует ключей: запуск только по
// `--tags live`, чтобы обычный прогон оставался офлайновым.
import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/api/generation/generation_diagnostics.dart';
import 'package:cardflow/api/images/wikimedia_image_search_service.dart';
import 'package:cardflow/domain/generation/generation_attachment.dart';

void main() {
  test(
    'живой Wikimedia Commons: русский image_query → JPEG/PNG',
    () async {
      final Dio dio = Dio();
      addTearDown(() => dio.close(force: true));
      final List<String> diagnostics = <String>[];
      final service = WikimediaImageSearchService(
        dio: dio,
        diagnostics: GenerationDiagnostics(
          enabled: true,
          sink: diagnostics.add,
        ),
      );

      final image = await service.findImage('Московский Кремль');

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
      expect(diagnostics.single, contains('Wikimedia Commons'));
    },
    timeout: const Timeout(Duration(minutes: 2)),
    tags: <String>['live'],
  );
}
