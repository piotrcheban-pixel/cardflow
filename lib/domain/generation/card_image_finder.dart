/// Порт поиска иллюстраций для сгенерированных карточек (итерация 7.9).
///
/// Домен не знает о HTTP: реализация — `lib/api/images/image_search_service.dart`.
/// С 7.14 запрос несёт запасной вариант и вид иллюстрации (`photo | diagram |
/// illustration`), а набор уже использованных URL позволяет не повторять одну
/// и ту же картинку в пределах колоды/запуска.
library;

import 'package:cardflow/domain/generation/card_image_kind.dart';
import 'package:cardflow/domain/generation/generated_card_image.dart';

/// Поиск одной иллюстрации по запросу модели.
abstract interface class CardImageFinder {
  /// Ищет и скачивает картинку; `null` — подходящей нет/ошибка поиска.
  ///
  /// [fallbackQuery] пробуется, если основной [query] не дал результата.
  /// [kind] задаёт предпочтительный тип (фото/схема/метафора).
  /// [excludedSourceUrls] — URL, уже занятые другими карточками: найденная по
  /// ним картинка не возвращается повторно (правило «одна картинка на колоду»).
  Future<GeneratedCardImage?> findImage(
    String query, {
    String? fallbackQuery,
    GeneratedCardImageKind kind = GeneratedCardImageKind.photo,
    Set<String>? excludedSourceUrls,
  });
}
