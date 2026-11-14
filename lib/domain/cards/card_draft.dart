import 'card.dart';
import 'card_media.dart';
import 'cloze_markup.dart';
import 'occlusion.dart';

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

  /// Изображение и маски Image Occlusion.
  occlusion,
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

  /// У cloze нет корректного пропуска.
  clozeMissing,

  /// У occlusion нет изображения.
  occlusionImageMissing,

  /// У occlusion нет ни одной маски.
  occlusionMasksMissing,

  /// JSON occlusion повреждён или координаты выходят за изображение.
  occlusionInvalid,
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
    this.mediaIds = const <String>[],
    this.latex,
    this.occlusionJson,
    this.imageUpload,
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

  /// Существующие идентификаторы медиа карточки.
  final List<String> mediaIds;

  /// Дополнительная LaTeX-разметка из импорта.
  final String? latex;

  /// Сериализованные маски Image Occlusion.
  final String? occlusionJson;

  /// Новое изображение, которое репозиторий должен сохранить.
  final CardImageUpload? imageUpload;

  /// Разбирает строку тегов из формы: запятые → trim → убрать `#` → пустые
  /// и дубликаты. Порядок сохраняется (SPEC A8.4).
  static List<String> parseTags(String raw) {
    final result = <String>[];
    for (final String part in raw.split(',')) {
      var tag = part.trim();
      while (tag.startsWith('#')) {
        tag = tag.substring(1).trim();
      }
      if (tag.isEmpty || result.contains(tag)) continue;
      result.add(tag);
    }
    return List<String>.unmodifiable(result);
  }

  /// Нормализованный черновик: trim сторон, подсказки и цитаты; теги — как
  /// [parseTags]. Пустые подсказка/цитата → `null`.
  CardDraft normalized() {
    final String normalizedHint = (hint ?? '').trim();
    final String normalizedExcerpt = (sourceExcerpt ?? '').trim();
    final String normalizedLatex = (latex ?? '').trim();
    return CardDraft(
      front: front.trim(),
      back: back.trim(),
      hint: normalizedHint.isEmpty ? null : normalizedHint,
      tags: parseTags(tags.join(',')),
      cardType: cardType,
      sourceExcerpt: normalizedExcerpt.isEmpty ? null : normalizedExcerpt,
      mediaIds: List<String>.unmodifiable(mediaIds),
      latex: normalizedLatex.isEmpty ? null : normalizedLatex,
      occlusionJson: occlusionJson,
      imageUpload: imageUpload,
    );
  }

  /// Ошибки валидации по полям; пустая карта — черновик валиден.
  ///
  /// Валидация идёт по нормализованным значениям: пробелы по краям не делают
  /// front непустым (SPEC A8.4, ADR-009).
  Map<CardDraftField, CardValidationError> validate() {
    final CardDraft value = normalized();
    final errors = <CardDraftField, CardValidationError>{};
    if (value.front.isEmpty) {
      errors[CardDraftField.front] = CardValidationError.frontEmpty;
    } else if (value.front.length > frontMaxLength) {
      errors[CardDraftField.front] = CardValidationError.frontTooLong;
    }
    // У cloze back может быть пустым (SPEC A8.1, правило 3); длина проверяется
    // для всех типов.
    if (value.back.isEmpty) {
      if (value.cardType != CardType.cloze) {
        errors[CardDraftField.back] = CardValidationError.backEmpty;
      }
    } else if (value.back.length > backMaxLength) {
      errors[CardDraftField.back] = CardValidationError.backTooLong;
    }
    if (value.cardType == CardType.cloze &&
        !ClozeMarkup.parse(value.front).hasGaps) {
      errors[CardDraftField.front] = CardValidationError.clozeMissing;
    }
    if (value.occlusionJson != null) {
      if (value.mediaIds.isEmpty && value.imageUpload == null) {
        errors[CardDraftField.occlusion] =
            CardValidationError.occlusionImageMissing;
      } else {
        final document = OcclusionDocument.tryParse(value.occlusionJson);
        if (document == null || value.cardType == CardType.basicReversed) {
          errors[CardDraftField.occlusion] =
              CardValidationError.occlusionInvalid;
        } else if (document.masks.isEmpty) {
          errors[CardDraftField.occlusion] =
              CardValidationError.occlusionMasksMissing;
        }
      }
    }
    if (value.tags.length > maxTags) {
      errors[CardDraftField.tags] = CardValidationError.tagsTooMany;
    }
    final String? excerpt = value.sourceExcerpt;
    if (excerpt != null && excerpt.length > sourceExcerptMaxLength) {
      errors[CardDraftField.sourceExcerpt] =
          CardValidationError.sourceExcerptTooLong;
    }
    return errors;
  }

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
          other.sourceExcerpt == sourceExcerpt &&
          _listEquals(other.mediaIds, mediaIds) &&
          other.latex == latex &&
          other.occlusionJson == occlusionJson &&
          other.imageUpload == imageUpload;

  @override
  int get hashCode => Object.hash(
    front,
    back,
    hint,
    Object.hashAll(tags),
    cardType,
    sourceExcerpt,
    Object.hashAll(mediaIds),
    latex,
    occlusionJson,
    imageUpload,
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
