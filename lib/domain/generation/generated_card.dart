import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/generation/card_image_kind.dart';
import 'package:cardflow/domain/generation/generated_card_image.dart';
import 'package:cardflow/domain/generation/generated_card_image_side.dart';

/// Пометки качества сгенерированной карточки (SPEC A8.4).
///
/// Карточка с пометкой не отбрасывается: предпросмотр (итерация 3c) показывает
/// её и даёт отредактировать.
enum CardIssueCode {
  /// `front` пустой.
  emptyFront,

  /// `front` длиннее 500 символов.
  frontTooLong,

  /// `back` длиннее 2000 символов.
  backTooLong,

  /// Для `cloze` нет ни одного пропуска `{{cN::…}}`.
  clozeMissing,

  /// Формула `$…$`/`$$…$$` не парсится `flutter_math_fork`.
  latexBroken,

  /// `source_excerpt` не найдена в исходном тексте (цитата обнулена).
  excerptMismatch,

  /// Теги скорректированы (обрезаны до 3 / удалены пустые и `#`).
  tagsAdjusted,

  /// Occlusion без найденной иллюстрации: карточка стала обычной (итерация 7.9).
  occlusionImageMissing,

  /// Изображение не найдено: внешний поиск не дал результата (ADR-028).
  ///
  /// С 7.19 карточка остаётся **без** изображения; заглушка не создаётся
  /// (ADR-041).
  imageNotFound,

  /// `image_id`/`*_image_ids` вне каталога `<images>` — id отброшен (fix-gen).
  imageIdUnknown,

  /// `image_query` сброшен локальным валидатором (fix-gen).
  imageQueryAdjusted,

  /// Абстрактное понятие (аксиома/закон/теорема/формула): картинку не ищем.
  abstractImageQuery,

  /// Ответ (или формула из ответа) целиком содержится во `front` — карточка
  /// проверяет вопрос, в котором уже есть ответ (SPEC A8.1, правило 2).
  answerInFront,

  /// `front` без вопросительного знака и не cloze — похоже на заголовок
  /// (SPEC A8.1, правило 2).
  frontLooksLikeHeading,

  /// `back` длиннее ~200 символов или трёх предложений (правило 3).
  backTooVerbose,

  /// `back` — только расшифровка обозначений («x — …, y — …») без утверждения.
  backOnlyNotation,

  /// Unicode-математика вместо LaTeX (`F₁`, `α`, `√2`).
  unicodeMath,

  /// Markdown-выделение в тексте карточки (`**…**`, `_…_`, `#`).
  markdownInText,

  /// Один image id указан и для вопроса, и для ответа: оставлен на стороне
  /// вопроса, из ответа удалён (7.19).
  imageDuplicatedSide,

  /// Байты изображения пустые или не совпадают с заявленным MIME: изображение
  /// не сохранено (7.19).
  imageInvalid,
}

/// Карточка, полученная от модели и прошедшая локальную валидацию (SPEC A8.4).
///
/// Immutable-модель домена: без Flutter, БД и UI. С 7.19 изображения
/// хранятся отдельно для вопроса и ответа (ADR-042): модель может назначить
/// разные изображения сторонам, несколько на сторону или ни одного.
class GeneratedCard {
  /// Создаёт карточку-кандидата.
  const GeneratedCard({
    required this.front,
    required this.back,
    required this.cardType,
    this.hint,
    this.tags = const <String>[],
    this.sourceExcerpt,
    this.sourceFile,
    this.issues = const <CardIssueCode>[],
    this.imageQuery,
    this.imageFallbackQuery,
    this.imageKind = GeneratedCardImageKind.photo,
    this.imageSide = GeneratedCardImageSide.none,
    this.questionImageIds = const <String>[],
    this.answerImageIds = const <String>[],
    this.questionImages = const <GeneratedCardImage>[],
    this.answerImages = const <GeneratedCardImage>[],
    this.isOcclusion = false,
    this.occlusionJson,
    this.sectionId,
  });

  /// Лицевая сторона (вопрос).
  final String front;

  /// Обратная сторона (ответ; для cloze может быть пустой).
  final String back;

  /// Тип карточки (`basic | basic_reversed | cloze`).
  final CardType cardType;

  /// Подсказка без раскрытия ответа.
  final String? hint;

  /// Теги (нормализованные: до 3, без `#`).
  final List<String> tags;

  /// Цитата для кнопки «Почему?» (SPEC A6.4).
  final String? sourceExcerpt;

  /// Имя файла/раздела-источника.
  final String? sourceFile;

  /// Машинные пометки качества (A8.4).
  final List<CardIssueCode> issues;

  /// Короткий id раздела плана (`section_id`, v8) — подсказка, не контракт.
  final String? sectionId;

  /// Краткий поисковый запрос на английском (`image.query`, v9).
  final String? imageQuery;

  /// Более общий запасной запрос модели (`image.fallback_query`).
  final String? imageFallbackQuery;

  /// Вид иллюстрации (`image.kind`): фото, схема или метафора.
  final GeneratedCardImageKind imageKind;

  /// Сторона, выбранная моделью для внешнего поиска (`image.side`, v9).
  final GeneratedCardImageSide imageSide;

  /// Идентификаторы изображений вопроса из каталога `<images>` (v9).
  final List<String> questionImageIds;

  /// Идентификаторы изображений ответа из каталога `<images>` (v9).
  final List<String> answerImageIds;

  /// Разрешённые изображения вопроса (байты из каталога/поиска).
  final List<GeneratedCardImage> questionImages;

  /// Разрешённые изображения ответа.
  final List<GeneratedCardImage> answerImages;

  /// Модель запросила формат occlusion (`card_type: "occlusion"`).
  ///
  /// В БД и экспорте карточка остаётся `basic` с `occlusion_json` (SPEC A5).
  final bool isOcclusion;

  /// JSON масок occlusion для импорта (итерация 7.9).
  final String? occlusionJson;

  /// Первое изображение карточки (вопрос, иначе ответ); `null` — нет.
  GeneratedCardImage? get image => questionImages.isNotEmpty
      ? questionImages.first
      : (answerImages.isEmpty ? null : answerImages.first);

  /// Есть ли изображения хотя бы у одной стороны.
  bool get hasImages => questionImages.isNotEmpty || answerImages.isNotEmpty;

  /// Есть ли пометки, требующие внимания пользователя.
  bool get hasIssues => issues.isNotEmpty;

  /// Копия с изменёнными полями.
  GeneratedCard copyWith({
    String? front,
    String? back,
    CardType? cardType,
    String? hint,
    List<String>? tags,
    String? sourceExcerpt,
    String? sourceFile,
    List<CardIssueCode>? issues,
    String? imageQuery,
    String? imageFallbackQuery,
    GeneratedCardImageKind? imageKind,
    GeneratedCardImageSide? imageSide,
    List<String>? questionImageIds,
    List<String>? answerImageIds,
    List<GeneratedCardImage>? questionImages,
    List<GeneratedCardImage>? answerImages,
    bool? isOcclusion,
    String? occlusionJson,
  }) {
    return GeneratedCard(
      front: front ?? this.front,
      back: back ?? this.back,
      cardType: cardType ?? this.cardType,
      hint: hint ?? this.hint,
      tags: tags ?? this.tags,
      sourceExcerpt: sourceExcerpt ?? this.sourceExcerpt,
      sourceFile: sourceFile ?? this.sourceFile,
      issues: issues ?? this.issues,
      imageQuery: imageQuery ?? this.imageQuery,
      imageFallbackQuery: imageFallbackQuery ?? this.imageFallbackQuery,
      imageKind: imageKind ?? this.imageKind,
      imageSide: imageSide ?? this.imageSide,
      questionImageIds: questionImageIds ?? this.questionImageIds,
      answerImageIds: answerImageIds ?? this.answerImageIds,
      questionImages: questionImages ?? this.questionImages,
      answerImages: answerImages ?? this.answerImages,
      isOcclusion: isOcclusion ?? this.isOcclusion,
      occlusionJson: occlusionJson ?? this.occlusionJson,
    );
  }

  /// Копия с явно сброшенными `imageId`/`image` (без «умолчаний» copyWith).
  GeneratedCard clearedImageSelection() {
    return GeneratedCard(
      front: front,
      back: back,
      cardType: cardType,
      hint: hint,
      tags: tags,
      sourceExcerpt: sourceExcerpt,
      sourceFile: sourceFile,
      issues: issues,
      imageQuery: null,
      imageFallbackQuery: null,
      imageKind: imageKind,
      imageSide: GeneratedCardImageSide.none,
      isOcclusion: isOcclusion,
      occlusionJson: occlusionJson,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is GeneratedCard &&
        other.front == front &&
        other.back == back &&
        other.cardType == cardType &&
        other.hint == hint &&
        _listEquals(other.tags, tags) &&
        other.sourceExcerpt == sourceExcerpt &&
        other.sourceFile == sourceFile &&
        _listEquals(other.issues, issues) &&
        other.imageQuery == imageQuery &&
        other.imageFallbackQuery == imageFallbackQuery &&
        other.imageKind == imageKind &&
        other.imageSide == imageSide &&
        _listEquals(other.questionImageIds, questionImageIds) &&
        _listEquals(other.answerImageIds, answerImageIds) &&
        identical(other.questionImages, questionImages) &&
        identical(other.answerImages, answerImages) &&
        other.isOcclusion == isOcclusion &&
        other.occlusionJson == occlusionJson;
  }

  @override
  int get hashCode => Object.hash(
    front,
    back,
    cardType,
    hint,
    Object.hashAll(tags),
    sourceExcerpt,
    sourceFile,
    Object.hashAll(issues),
    imageQuery,
    imageFallbackQuery,
    imageKind,
    imageSide,
    Object.hashAll(questionImageIds),
    Object.hashAll(answerImageIds),
    identityHashCode(questionImages),
    identityHashCode(answerImages),
    isOcclusion,
    occlusionJson,
  );

  @override
  String toString() =>
      'GeneratedCard(front: $front, type: ${cardType.wireName}, '
      'issues: ${issues.map((issue) => issue.name).toList()})';
}

bool _listEquals<T>(List<T> a, List<T> b) {
  if (identical(a, b)) return true;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}
