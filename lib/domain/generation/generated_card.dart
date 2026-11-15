import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/generation/generated_card_image.dart';

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
}

/// Карточка, полученная от модели и прошедшая локальную валидацию (SPEC A8.4).
///
/// Immutable-модель домена: без Flutter, БД и UI.
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
    this.image,
    this.isOcclusion = false,
    this.occlusionJson,
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

  /// Цитата для кнопки «Почему?» (SPEC A6.4); `null`, если не найдена в исходнике.
  final String? sourceExcerpt;

  /// Имя файла/раздела-источника.
  final String? sourceFile;

  /// Машинные пометки качества (A8.4).
  final List<CardIssueCode> issues;

  /// Краткий поисковый запрос на английском (итерация 7.9, ADR-023).
  final String? imageQuery;

  /// Найденная и скачанная иллюстрация; `null` — не искали/не нашли.
  final GeneratedCardImage? image;

  /// Модель запросила формат occlusion (`card_type: "occlusion"`).
  ///
  /// В БД и экспорте карточка остаётся `basic` с `occlusion_json` (SPEC A5).
  final bool isOcclusion;

  /// JSON масок occlusion для импорта (итерация 7.9).
  final String? occlusionJson;

  /// Есть ли пометки, требующие внимания пользователя.
  bool get hasIssues => issues.isNotEmpty;

  /// Копия с изменёнными полями (image/occlusion — результат поиска 7.9).
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
    GeneratedCardImage? image,
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
      image: image ?? this.image,
      isOcclusion: isOcclusion ?? this.isOcclusion,
      occlusionJson: occlusionJson ?? this.occlusionJson,
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
        identical(other.image, image) &&
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
    identityHashCode(image),
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
