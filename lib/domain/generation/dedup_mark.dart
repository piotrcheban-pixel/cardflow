/// Пометка дедупа, которую можно записать в журнал прогона (TASK «Срез 13»,
/// часть 1, п. 3).
///
/// [DedupReport] в памяти ссылается на карточки id-шниками каскада. В БД
/// черновик идентифицируется парой (`run_id`, `content_hash`), поэтому
/// пометка несёт:
/// - [contentHash] — ключ пометки (черновик прогона);
/// - [duplicateOf] — вторая сторона пары: `content_hash` другого черновика
///   этого прогона либо `deck:<cards.id>` для карточки целевой колоды;
/// - [level] — уровень каскада.
///
/// Пометка не удаляет карточку: импорт в колоду её сохраняет, а после
/// перезапуска прогона пары восстанавливаются из строк (L219).
library;

import 'package:cardflow/domain/generation/dedup_report.dart';
import 'package:cardflow/domain/generation/validation/semantic_matcher.dart';

/// Загрузка карточек целевой колоды для дедупа (этап Dedup).
///
/// Колода читается **до импорта** нового прогона: пара «уже в колоде» должна
/// быть помечена, а не обнаружена после записи. `null`-загрузчик — сверка идёт
/// только внутри прогона (колоды нет/она не подключена).
typedef DeckCardsLoader = Future<List<DedupCard>> Function(String deckId);

/// Запись пометок дедупа в журнал прогона (реализация — `card_drafts`).
typedef DedupMarkSink = Future<void> Function(
  String runId,
  List<DedupMark> marks,
);

/// Пометка «черновик [contentHash] похож на [duplicateOf]» с уровнем каскада.
class DedupMark {
  /// Создаёт пометку; ключ и вторая сторона обязаны быть непустыми.
  const DedupMark({
    required this.contentHash,
    required this.duplicateOf,
    required this.level,
  }) : assert(contentHash != '', 'У пометки обязан быть ключ черновика'),
       assert(duplicateOf != '', 'У пометки обязана быть вторая сторона');

  /// Хеш содержимого черновика (`run_id` + он = ключ строки `card_drafts`).
  final String contentHash;

  /// Вторая сторона: `content_hash` черновика или `deck:<cards.id>`.
  final String duplicateOf;

  /// Уровень каскада, на котором найдена пара.
  final DedupLevel level;

  /// Вторая сторона — карточка целевой колоды (а не текущего прогона).
  bool get isDeckCard => duplicateOf.startsWith(deckPrefix);

  /// Пара — две карточки одного содержимого (точный дубль внутри прогона).
  ///
  /// У обеих сторон один `content_hash`, поэтому в журнале «вторая сторона»
  /// равна ключу пометки: отдельного id у одинаковых строк может и не быть
  /// (уникальный индекс `run_id + content_hash` хранит одну строку).
  bool get isIdenticalContent => duplicateOf == contentHash;

  /// Префикс второй стороны для карточки, уже лежащей в колоде.
  static const String deckPrefix = 'deck:';

  /// Префикс синтетической первой стороны пары для одинакового содержимого.
  ///
  /// [DedupPair] требует разные id сторон; у точного дубля внутри прогона
  /// второй строки нет, поэтому в восстановленном отчёте первая сторона —
  /// этот маркер, а не выдуманный черновик.
  static const String identicalSidePrefix = 'same:';

  /// Ключ карточки колоды в пометке.
  static String deckKey(String cardId) => '$deckPrefix$cardId';

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is DedupMark &&
          other.contentHash == contentHash &&
          other.duplicateOf == duplicateOf &&
          other.level == level;

  @override
  int get hashCode => Object.hash(contentHash, duplicateOf, level);

  @override
  String toString() =>
      'DedupMark($contentHash ~ $duplicateOf, ${level.wireName})';
}
