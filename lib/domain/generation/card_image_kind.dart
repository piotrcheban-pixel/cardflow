/// Тип иллюстрации карточки (итерация 7.14, схема `gen-ru-v6`).
///
/// Модель выбирает тип по смыслу карточки: `photo` — конкретный объект,
/// `diagram` — закон/процесс/структура/формула, `illustration` — визуальная
/// метафора абстрактного понятия. От типа зависят фильтры поиска и показ
/// (16:9 для фото и метафоры, 4:3 для схемы). Домен без Flutter.
library;

/// Вид иллюстрации карточки.
enum GeneratedCardImageKind {
  /// Фотография конкретного объекта.
  photo('photo'),

  /// Схема, чертёж, график, диаграмма процесса.
  diagram('diagram'),

  /// Иллюстрация-метафора абстрактного понятия.
  illustration('illustration');

  const GeneratedCardImageKind(this.wireName);

  /// Значение в JSON ответа модели и в метаданных медиа.
  final String wireName;

  /// Разбирает wire-значение; `null` — поле отсутствует или неизвестно.
  static GeneratedCardImageKind? tryParse(Object? value) {
    if (value is! String) return null;
    final String normalized = value.trim().toLowerCase();
    for (final GeneratedCardImageKind kind in values) {
      if (kind.wireName == normalized) return kind;
    }
    return null;
  }
}
