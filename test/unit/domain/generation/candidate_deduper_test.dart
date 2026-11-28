import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/generation/candidate_deduper.dart';
import 'package:cardflow/domain/generation/dedup_report.dart';
import 'package:cardflow/domain/generation/generated_card.dart';
import 'package:cardflow/domain/generation/validation/semantic_matcher.dart';

/// Контракт среза 16, часть 2: проверка кандидата на смысловой дубль **до**
/// принятия. Каскад тот же, что у этапа Dedup (ADR-050 §3.4) — новых правил
/// нет; детектор помнит принятое и отдаёт сильнейший уровень пары.
void main() {
  GeneratedCard cardOf(String front, String back, {String? unitId}) =>
      GeneratedCard(
        front: front,
        back: back,
        cardType: CardType.basic,
        unitId: unitId ?? 'ku:1',
      );

  DedupCard known(String id, String front, String back) =>
      DedupCard(id: id, front: front, back: back);

  test('без известных карточек кандидат уникален', () {
    final CascadeDeduper deduper = CascadeDeduper(
      matcher: const SemanticMatcher(),
    );
    expect(deduper.check(cardOf('Что такое сила?', 'Мера действия.')), isNull);
    expect(deduper.levels, isEmpty);
  });

  test('точный дубль известной карточки — hit уровня exact', () {
    final CascadeDeduper deduper = CascadeDeduper(
      matcher: const SemanticMatcher(),
      existing: <DedupCard>[
        known('deck-1', 'Что такое сила?', 'Мера взаимодействия тел.'),
      ],
    );
    final DuplicateHit? hit = deduper.check(
      cardOf('Что такое сила?', 'Мера взаимодействия тел.'),
    );
    expect(hit, isNotNull);
    expect(hit!.level, DedupLevel.exact);
    expect(hit.otherId, 'deck-1');
    expect(deduper.levels, <DedupLevel, int>{DedupLevel.exact: 1});
    expect(deduper.pairs, hasLength(1));
    expect(deduper.pairs.single.leftId, 'deck-1');
  });

  test('нормализованный дубль: регистр и пунктуация не различаются', () {
    final CascadeDeduper deduper = CascadeDeduper(
      matcher: const SemanticMatcher(),
      existing: <DedupCard>[
        known('deck-1', 'Что такое сила?', 'Мера взаимодействия тел.'),
      ],
    );
    final DuplicateHit? hit = deduper.check(
      cardOf('что такое сила', 'МЕРА взаимодействия тел'),
    );
    expect(hit?.level, DedupLevel.normalized);
  });

  test('принятое запоминается: следующий кандидат сверяется и с ним', () {
    final CascadeDeduper deduper = CascadeDeduper(
      matcher: const SemanticMatcher(),
    );
    final GeneratedCard accepted = cardOf(
      'Что такое импульс тела?',
      'Произведение массы на скорость.',
    );
    expect(deduper.check(accepted), isNull);
    deduper.remember(accepted);
    final DuplicateHit? hit = deduper.check(
      cardOf('Что такое импульс тела?', 'Произведение массы на скорость.'),
    );
    expect(hit?.level, DedupLevel.exact);
    expect(deduper.levels.values.single, 1);
  });

  test('уникальный кандидат не попадает в счётчики дублей', () {
    final CascadeDeduper deduper = CascadeDeduper(
      matcher: const SemanticMatcher(),
      existing: <DedupCard>[
        known('deck-1', 'Что такое сила?', 'Мера взаимодействия тел.'),
      ],
    );
    expect(
      deduper.check(cardOf('Что такое масса?', 'Мера инертности.')),
      isNull,
    );
    expect(deduper.levels, isEmpty);
    expect(deduper.pairs, isEmpty);
  });
}
