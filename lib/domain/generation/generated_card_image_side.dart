/// Сторона, выбранная моделью для внешнего поиска изображения (схема v9).
///
/// С 7.19 ИИ назначает изображения обеим сторонам карточки независимо:
/// `question_image_ids` — лицевая сторона, `answer_image_ids` — обратная.
/// Объект `image` (внешний поиск настоящей фотографии) тоже несёт сторону:
/// без неё изображение-ответ могло попасть на лицевую сторону.
library;

/// Сторона изображения, выбранная моделью.
enum GeneratedCardImageSide {
  /// Лицевая сторона: изображение — стимул вопроса.
  question('question'),

  /// Обратная сторона: изображение раскрывает ответ.
  answer('answer'),

  /// Изображение не нужно: поиск не выполняется.
  none('none');

  const GeneratedCardImageSide(this.wireName);

  /// Значение в JSON ответа модели.
  final String wireName;

  /// Разбирает значение схемы; неизвестное/отсутствующее → [question].
  ///
  /// Ответы v5–v8 не знали стороны, а единственная иллюстрация показывалась на
  /// лицевой стороне — поэтому совместимый разбор считает её стороной вопроса.
  static GeneratedCardImageSide parseOrDefault(Object? value) {
    if (value is! String) return GeneratedCardImageSide.question;
    final String normalized = value.trim().toLowerCase();
    for (final GeneratedCardImageSide side in values) {
      if (side.wireName == normalized) return side;
    }
    return GeneratedCardImageSide.question;
  }
}
