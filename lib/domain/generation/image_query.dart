/// Правила пожеланий, влияющих на иллюстрации (ADR-028, итерация 7.12).
///
/// Промпт `gen-ru-v5` просит модель не искать картинки, если пользователь этого
/// не хочет; приложение дополнительно не ищет их само. Чистые правила без
/// Flutter/сети.
library;

/// Пользователь запретил картинки в пожеланиях к генерации.
///
/// Промпт (правило 7) просит модель не заполнять `image_id`/`image_query` в
/// этом случае; приложение не ищет иллюстрацию даже при запросе от модели.
bool wishesForbidImages(String? wishes) {
  if (wishes == null || wishes.trim().isEmpty) return false;
  final String value = wishes.toLowerCase();
  final List<RegExp> patterns = <RegExp>[
    RegExp(r'без\s+(?:картин|изображен|иллюстрац|фото)', unicode: true),
    RegExp(
      r'не\s+(?:добав|встав|ищ|рис)\S*\s+'
      r'(?:картин|изображен|иллюстрац|фото)',
      unicode: true,
    ),
    RegExp(r'без\s+картинок|no\s+(?:images?|pictures?|photos?)', unicode: true),
    RegExp(
      r"(?:don'?t|do\s+not)\s+(?:add|include|use|search)[^.!?]{0,30}"
      r'(?:image|picture|photo)',
      unicode: true,
    ),
  ];
  return patterns.any((RegExp pattern) => pattern.hasMatch(value));
}
