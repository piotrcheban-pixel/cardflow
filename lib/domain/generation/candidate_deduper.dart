/// Проверка кандидата на смысловой дубль **до** принятия (TASK «Срез 16», ч. 2).
///
/// До среза 16 дубли искались после генерации по уже принятым карточкам: дубль
/// закрывал слот, попадал в [CardSink] и только помечался. Теперь каскад
/// `SemanticMatcher` спрашивается в момент приёма: кандидат-дубль откладывается,
/// слот остаётся открытым, а второй запрос идёт с другим углом.
///
/// Новых правил здесь нет: используется тот же каскад ADR-050 §3.4, что и в
/// этапе Dedup среза 13.
library;

import 'package:cardflow/domain/generation/dedup_report.dart';
import 'package:cardflow/domain/generation/generated_card.dart';
import 'package:cardflow/domain/generation/validation/semantic_matcher.dart';

/// Результат проверки кандидата: уровень каскада и вторая сторона пары.
final class DuplicateHit {
  /// Создаёт попадание.
  const DuplicateHit({required this.level, required this.otherId});

  /// Уровень каскада (`exact` сильнее `semantic`).
  final DedupLevel level;

  /// Идентификатор карточки, с которой кандидат совпал (принятая или колода).
  final String otherId;

  @override
  String toString() => 'DuplicateHit(${level.wireName}, $otherId)';
}

/// Порт проверки кандидата на дубль до закрытия слота.
abstract interface class CandidateDeduper {
  /// Уровень дубля и вторая сторона пары; `null` — кандидат уникален.
  DuplicateHit? check(GeneratedCard card);

  /// Запоминает принятую карточку: следующие кандидаты сверяются и с ней.
  void remember(GeneratedCard card);

  /// Сколько кандидатов отложено по каждому уровню каскада.
  Map<DedupLevel, int> get levels;

  /// Пары каскада, найденные при проверке (для отчёта прогона).
  List<DedupPair> get pairs;
}

/// Каскад [SemanticMatcher] поверх принятых карточек прогона и колоды.
///
/// Состояние — «что уже принято»: колода загружается один раз при создании,
/// принятые карточки добавляет вызывающий слой через [remember]. Проверка
/// кандидата — один вызов каскада по известным карточкам, без удаления и без
/// изменения текста.
final class CascadeDeduper implements CandidateDeduper {
  /// Создаёт детектор; [existing] — карточки целевой колоды.
  CascadeDeduper({
    required this.matcher,
    Iterable<DedupCard> existing = const <DedupCard>[],
  }) : _known = List<DedupCard>.of(existing);

  /// Матчер каскада (тот же, что у этапа Dedup).
  final SemanticMatcher matcher;

  final List<DedupCard> _known;
  final Map<DedupLevel, int> _levels = <DedupLevel, int>{};
  final List<DedupPair> _pairs = <DedupPair>[];
  var _nextId = 0;

  @override
  Map<DedupLevel, int> get levels => Map<DedupLevel, int>.unmodifiable(_levels);

  @override
  List<DedupPair> get pairs => List<DedupPair>.unmodifiable(_pairs);

  @override
  DuplicateHit? check(GeneratedCard card) {
    if (_known.isEmpty) return null;
    final String id = 'candidate:#${_nextId++}';
    final DedupCard candidate = DedupCard(
      id: id,
      front: card.front,
      back: card.back,
    );
    final DedupReport report = matcher.match(<DedupCard>[
      candidate,
    ], existing: _known);
    if (report.pairs.isEmpty) return null;
    DedupPair strongest = report.pairs.first;
    for (final DedupPair pair in report.pairs) {
      if (pair.level.index < strongest.level.index) strongest = pair;
    }
    _levels[strongest.level] = (_levels[strongest.level] ?? 0) + 1;
    _pairs.add(
      DedupPair(
        leftId: strongest.leftId,
        rightId: id,
        level: strongest.level,
        similarity: strongest.similarity,
      ),
    );
    return DuplicateHit(level: strongest.level, otherId: strongest.leftId);
  }

  @override
  void remember(GeneratedCard card) {
    _known.add(
      DedupCard(
        id: 'accepted:#${_nextId++}',
        front: card.front,
        back: card.back,
      ),
    );
  }
}
