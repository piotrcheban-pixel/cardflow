import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/domain/generation/image_query.dart';

/// Запрет картинок в пожеланиях (ADR-028).
///
/// fix-gen (Д2): производный запрос из текста вопроса удалён — внешний поиск
/// выполняется только по `image_query` модели; его поведение проверяют тесты
/// `generation_fix_gen_test.dart` и `content_validator_test.dart`.
void main() {
  group('wishesForbidImages', () {
    test('русские формулировки запрета', () {
      expect(wishesForbidImages('Без картинок, только текст'), isTrue);
      expect(wishesForbidImages('не добавляй картинки'), isTrue);
      expect(wishesForbidImages('Не ищи изображения'), isTrue);
      expect(wishesForbidImages('без иллюстраций'), isTrue);
    });

    test('английские формулировки запрета', () {
      expect(wishesForbidImages('no images please'), isTrue);
      expect(wishesForbidImages("don't add any pictures"), isTrue);
    });

    test('обычные пожелания не запрещают картинки', () {
      expect(wishesForbidImages('Покороче, 10 карточек'), isFalse);
      expect(wishesForbidImages('Акцент на схемах и фотосинтезе'), isFalse);
      expect(wishesForbidImages(null), isFalse);
      expect(wishesForbidImages('   '), isFalse);
    });
  });
}
