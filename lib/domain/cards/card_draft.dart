import 'card.dart';

/// Поле ручной формы карточки, к которому относится ошибка валидации.
enum CardDraftField {
  /// Вопрос (front).
  front,

  /// Ответ (back).
  back,

  /// Теги.
  tags,

  /// Цитата для кнопки «Почему?».
  sourceExcerpt,
}

/// Ошибка валидации черновика карточки (SPEC A8.4, L14).
enum CardValidationError {
  /// Вопрос пуст.
  frontEmpty,

  /// Вопрос длиннее [CardDraft.frontMaxLength].
  frontTooLong,

  /// Ответ пуст (для `basic`/`basic_reversed`).
  backEmpty,

  /// Ответ длиннее [CardDraft.backMaxLength].
  backTooLong,

  /// Больше [CardDraft.maxTags] тегов.
  tagsTooMany,

  /// Цитата длиннее [CardDraft.sourceExcerptMaxLength].
  sourceExcerptTooLong,
}

/// Иммутабельный черновик карточки: то, что пользователь ввёл в форме
/// (SPEC A6.3, A8.4, ADR-009). Домен не зависит от Flutter.
class CardDraft {
  /// Создаёт черновик.
  const CardDraft({
    required this.front,
    required this.back,
    this.hint,
    this.tags = const <String>[],
    this.cardType = CardType.basic,
    this.sourceExcerpt,
  });

  /// Пустой черновик новой карточки.
  factory CardDraft.empty() =>
      const CardDraft(front: '', back: '', tags: <String>[]);

  /// Максимальная длина `front` (SPEC A8.4).
  static const int frontMaxLength = 500;

  /// Максимальная длина `back` (SPEC A8.4).
  static const int backMaxLength = 2000;

  /// Максимум тегов у карточки (SPEC A8.4).
  static const int maxTags = 3;

  /// Максимальная длина цитаты «Почему?» (A8.1, правило 8).
  static const int sourceExcerptMaxLength = 400;

  /// Вопрос.
  final String front;

  /// Ответ.
  final String back;

  /// Подсказка без раскрытия ответа.
  final String? hint;

  /// Теги (без `#`).
  final List<String> tags;

  /// Тип карточки.
  final CardType cardType;

  /// Цитата для кнопки «Почему?».
  final String? sourceExcerpt;

  /// Разбирает строку тегов из формы: запятые → trim → убрать `#` → пустые
  /// и дубликаты. Порядок сохраняется (SPEC A8.4).
  static List<String> parseTags(String raw) => const <String>['red-phase'];

  /// Нормализованный черновик: trim сторон, подсказки и цитаты; теги — как
  /// [parseTags]. Пустые подсказка/цитата → `null`.
  CardDraft normalized() => this;

  /// Ошибки валидации по полям; пустая карта — черновик валиден.
  Map<CardDraftField, CardValidationError> validate() =>
      const <CardDraftField, CardValidationError>{};

  /// Валиден ли черновик.
  bool get isValid => validate().isEmpty;

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is CardDraft &&
          other.front == front &&
          other.back == back &&
          other.hint == hint &&
          _listEquals(other.tags, tags) &&
          other.cardType == cardType &&
          other.sourceExcerpt == sourceExcerpt;

  @override
  int get hashCode => Object.hash(
    front,
    back,
    hint,
    Object.hashAll(tags),
    cardType,
    sourceExcerpt,
  );

  static bool _listEquals(List<String> a, List<String> b) {
    if (identical(a, b)) return true;
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}
