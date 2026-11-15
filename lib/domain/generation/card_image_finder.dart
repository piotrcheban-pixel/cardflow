/// Порт поиска иллюстраций для сгенерированных карточек (итерация 7.9).
///
/// Домен не знает о HTTP: реализация — `lib/api/images/image_search_service.dart`.
library;

import 'package:cardflow/domain/generation/generated_card_image.dart';

/// Поиск одной иллюстрации по запросу модели.
abstract interface class CardImageFinder {
  /// Ищет и скачивает картинку; `null` — подходящей нет/ошибка поиска.
  Future<GeneratedCardImage?> findImage(String query);
}
