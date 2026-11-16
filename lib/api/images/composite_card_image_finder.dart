/// Составной поиск иллюстраций: источники по очереди (ADR-027, итерация 7.11).
///
/// Первый источник, который вернул картинку, выигрывает. Ошибка/пустая выдача
/// одного источника не отменяет остальные: генерация карточки продолжается
/// без иллюстрации, если не помог никто.
///
/// С 7.14 production-цепочка — `ImageSearchService` (провайдеры + фильтры и
/// ретраи), а этот класс остаётся простым композитом для тестов/живых
/// проверок: он пробрасывает запрос, запасной запрос и вид иллюстрации.
library;

import 'package:cardflow/domain/generation/card_image_finder.dart';
import 'package:cardflow/domain/generation/card_image_kind.dart';
import 'package:cardflow/domain/generation/generated_card_image.dart';

/// Пробует источники иллюстраций по порядку.
class CompositeCardImageFinder implements CardImageFinder {
  /// Создаёт составной поиск с порядком источников [finders].
  const CompositeCardImageFinder(this.finders);

  /// Источники в порядке приоритета.
  final List<CardImageFinder> finders;

  @override
  Future<GeneratedCardImage?> findImage(
    String query, {
    String? fallbackQuery,
    GeneratedCardImageKind kind = GeneratedCardImageKind.photo,
    Set<String>? excludedSourceUrls,
  }) async {
    for (final CardImageFinder finder in finders) {
      final GeneratedCardImage? image = await finder.findImage(
        query,
        fallbackQuery: fallbackQuery,
        kind: kind,
        excludedSourceUrls: excludedSourceUrls,
      );
      if (image != null) return image;
    }
    return null;
  }

  @override
  String toString() => 'CompositeCardImageFinder(${finders.length})';
}
