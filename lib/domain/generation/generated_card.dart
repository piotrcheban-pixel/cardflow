import 'package:cardflow/domain/cards/card.dart';

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

  /// Теги обрезаны до 3 / удалены пустые и `#`.
  tagsAdjusted,
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

  /// Есть ли пометки, требующие внимания пользователя.
  bool get hasIssues => issues.isNotEmpty;

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
        _listEquals(other.issues, issues);
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
