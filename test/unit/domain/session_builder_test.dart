import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/scheduling/scheduling_card.dart';
import 'package:cardflow/domain/session/session_builder.dart';
import 'package:cardflow/domain/session/session_config.dart';
import 'package:cardflow/domain/session/session_plan.dart';

import '../../helpers/decks_fakes.dart';

/// Красная фаза итерации 6: сборка выборки конструктора (SPEC A6.7, A7.19,
/// A7.20, ADR-018) — фильтры, базовый порядок, разминка, интерливинг,
/// перемешивание, лимит карточек/минут.
void main() {
  final DateTime now = DateTime.utc(2026, 11, 14, 12);

  const SessionConfig twoDecks = SessionConfig(
    deckIds: <String>['deck-1', 'deck-2'],
    limit: SessionLimit.cards(100),
  );

  /// Снимок FSRS для карточки в состоянии `review` с заданной стабильностью.
  String reviewFsrs(
    String cardId, {
    double stability = 10,
    DateTime? due,
  }) {
    return jsonEncode(
      SchedulingCard(
        cardId: cardId,
        state: CardState.review,
        stability: stability,
        difficulty: 5,
        due: (due ?? now).toUtc(),
        lastReview: now.subtract(const Duration(days: 3)).toUtc(),
      ).toJson(),
    );
  }

  List<String> ids(List<Card> cards) => <String>[
    for (final Card card in cards) card.id,
  ];

  List<Card> build(
    List<Card> cards, {
    SessionConfig config = twoDecks,
    Map<String, int> failureCounts = const <String, int>{},
    int? seed,
  }) {
    return SessionBuilder.build(
      cards: cards,
      config: config,
      failureCounts: failureCounts,
      now: now,
      seed: seed,
    );
  }

  group('фильтры', () {
    test('колоды: только выбранные; приостановленные и отложенные исключены', () {
      final List<Card> cards = <Card>[
        makeCard(id: 'a', deckId: 'deck-1', front: 'A'),
        makeCard(id: 'b', deckId: 'deck-2', front: 'B'),
        makeCard(id: 'c', deckId: 'deck-3', front: 'C'),
        makeCard(id: 'suspended', deckId: 'deck-1', front: 'S', suspended: true),
        makeCard(
          id: 'buried-future',
          deckId: 'deck-1',
          front: 'BF',
          buriedUntil: now.add(const Duration(hours: 1)),
        ),
        makeCard(
          id: 'buried-past',
          deckId: 'deck-1',
          front: 'BP',
          buriedUntil: now.subtract(const Duration(hours: 1)),
        ),
      ];

      expect(ids(build(cards)), <String>[
        'a',
        'b',
        'buried-past',
      ], reason: 'без due: createdAt (равны) → id ASC');
    });

    test('теги: карточка проходит по любому выбранному тегу (OR)', () {
      final List<Card> cards = <Card>[
        makeCard(id: 'a', deckId: 'deck-1', front: 'A', tags: <String>['даты']),
        makeCard(id: 'b', deckId: 'deck-1', front: 'B', tags: <String>['язык']),
        makeCard(id: 'c', deckId: 'deck-1', front: 'C'),
      ];

      final List<Card> selected = build(
        cards,
        config: twoDecks.copyWith(tags: <String>{'даты', 'язык'}),
      );

      expect(ids(selected), <String>['a', 'b']);
      expect(
        ids(build(cards, config: twoDecks.copyWith(tags: <String>{'даты'}))),
        <String>['a'],
      );
      expect(
        ids(build(cards, config: twoDecks.copyWith(tags: <String>{'нет'}))),
        isEmpty,
      );
    });

    test('типы карточек: любой из выбранных', () {
      final List<Card> cards = <Card>[
        makeCard(id: 'a', deckId: 'deck-1', front: 'A'),
        makeCard(
          id: 'b',
          deckId: 'deck-1',
          front: 'B',
          cardType: CardType.cloze,
        ),
        makeCard(
          id: 'c',
          deckId: 'deck-1',
          front: 'C',
          cardType: CardType.basicReversed,
        ),
      ];

      expect(
        ids(
          build(
            cards,
            config: twoDecks.copyWith(
              cardTypes: <CardType>{CardType.cloze, CardType.basicReversed},
            ),
          ),
        ),
        <String>['b', 'c'],
      );
    });

    test('состояния: новые / в процессе / повторение', () {
      final List<Card> cards = <Card>[
        makeCard(id: 'new', deckId: 'deck-1', front: 'N'),
        makeCard(
          id: 'learning',
          deckId: 'deck-1',
          front: 'L',
          state: CardState.learning,
        ),
        makeCard(
          id: 'relearning',
          deckId: 'deck-1',
          front: 'R',
          state: CardState.relearning,
        ),
        makeCard(
          id: 'review',
          deckId: 'deck-1',
          front: 'V',
          state: CardState.review,
          due: now.add(const Duration(days: 2)),
        ),
      ];

      expect(
        ids(
          build(
            cards,
            config: twoDecks.copyWith(
              states: <SessionStateFilter>{SessionStateFilter.newCards},
            ),
          ),
        ),
        <String>['new'],
      );
      expect(
        ids(
          build(
            cards,
            config: twoDecks.copyWith(
              states: <SessionStateFilter>{SessionStateFilter.inProgress},
            ),
          ),
        ),
        <String>['learning', 'relearning'],
      );
      expect(
        ids(
          build(
            cards,
            config: twoDecks.copyWith(
              states: <SessionStateFilter>{SessionStateFilter.review},
            ),
          ),
        ),
        <String>['review'],
        reason: 'будущие due входят в фильтр «Повторение» (ADR-018)',
      );
    });

    test('пиявки: только карточки с 8+ провалами (порог A7.17)', () {
      final List<Card> cards = <Card>[
        makeCard(id: 'leech', deckId: 'deck-1', front: 'A'),
        makeCard(id: 'almost', deckId: 'deck-1', front: 'B'),
        makeCard(id: 'clean', deckId: 'deck-1', front: 'C'),
      ];
      final Map<String, int> counts = <String, int>{'leech': 8, 'almost': 7};

      final List<Card> leeches = build(
        cards,
        config: twoDecks.copyWith(
          states: <SessionStateFilter>{SessionStateFilter.leeches},
        ),
        failureCounts: counts,
      );

      expect(ids(leeches), <String>['leech']);
      expect(
        ids(
          build(
            cards,
            config: twoDecks.copyWith(
              states: <SessionStateFilter>{SessionStateFilter.leeches},
            ),
          ),
        ),
        isEmpty,
        reason: 'без счётчиков провалов пиявок нет',
      );
    });

    test('пустой набор фильтров — все карточки выбранных колод', () {
      final List<Card> cards = <Card>[
        makeCard(id: 'a', deckId: 'deck-1', front: 'A', tags: <String>['x']),
        makeCard(
          id: 'b',
          deckId: 'deck-2',
          front: 'B',
          cardType: CardType.cloze,
          state: CardState.learning,
        ),
      ];

      expect(ids(build(cards)), <String>['a', 'b']);
    });

    test('пустой список колод — пустая выборка', () {
      final List<Card> cards = <Card>[
        makeCard(id: 'a', deckId: 'deck-1', front: 'A'),
      ];

      expect(
        build(cards, config: twoDecks.copyWith(deckIds: const <String>[])),
        isEmpty,
      );
    });
  });

  group('базовый порядок', () {
    test('due ASC, затем новые по createdAt, тай-брек id ASC', () {
      final List<Card> cards = <Card>[
        makeCard(
          id: 'new-late',
          deckId: 'deck-1',
          front: 'NL',
          createdAt: now.add(const Duration(minutes: 5)),
        ),
        makeCard(
          id: 'future',
          deckId: 'deck-1',
          front: 'F',
          state: CardState.review,
          due: now.add(const Duration(hours: 1)),
        ),
        makeCard(
          id: 'overdue-2',
          deckId: 'deck-1',
          front: 'O2',
          state: CardState.review,
          due: now.subtract(const Duration(hours: 1)),
        ),
        makeCard(
          id: 'overdue-1',
          deckId: 'deck-1',
          front: 'O1',
          state: CardState.learning,
          due: now.subtract(const Duration(hours: 2)),
        ),
        makeCard(
          id: 'new-early',
          deckId: 'deck-1',
          front: 'NE',
          createdAt: now.subtract(const Duration(minutes: 5)),
        ),
      ];

      expect(ids(build(cards)), <String>[
        'overdue-1',
        'overdue-2',
        'future',
        'new-early',
        'new-late',
      ]);
    });
  });

  group('разминка (A7.19)', () {
    test('до 4 выученных карточек с максимальной stability — в начале', () {
      final List<Card> cards = <Card>[
        makeCard(
          id: 'r-100',
          deckId: 'deck-1',
          front: 'A',
          state: CardState.learning,
          due: now.subtract(const Duration(minutes: 30)),
        ),
        makeCard(
          id: 'r-30',
          deckId: 'deck-1',
          front: 'B',
          state: CardState.learning,
          due: now.subtract(const Duration(minutes: 20)),
        ),
        makeCard(
          id: 'r-5',
          deckId: 'deck-1',
          front: 'C',
          state: CardState.learning,
          due: now.subtract(const Duration(minutes: 10)),
        ),
        makeCard(
          id: 'learned-100',
          deckId: 'deck-1',
          front: 'D',
          state: CardState.review,
          due: now,
          fsrsJson: reviewFsrs('learned-100', stability: 100),
        ),
        makeCard(
          id: 'learned-30',
          deckId: 'deck-1',
          front: 'E',
          state: CardState.review,
          due: now.add(const Duration(minutes: 10)),
          fsrsJson: reviewFsrs(
            'learned-30',
            stability: 30,
            due: now.add(const Duration(minutes: 10)),
          ),
        ),
        makeCard(
          id: 'learned-5',
          deckId: 'deck-1',
          front: 'F',
          state: CardState.review,
          due: now.add(const Duration(minutes: 20)),
          fsrsJson: reviewFsrs(
            'learned-5',
            stability: 5,
            due: now.add(const Duration(minutes: 20)),
          ),
        ),
        makeCard(id: 'new', deckId: 'deck-1', front: 'G'),
      ];

      final List<String> base = ids(build(cards));
      expect(base.take(3), <String>['r-100', 'r-30', 'r-5']);

      final List<String> warmed = ids(
        build(cards, config: twoDecks.copyWith(warmup: true)),
      );

      expect(warmed, <String>[
        'learned-100',
        'learned-30',
        'learned-5',
        'r-100',
        'r-30',
        'r-5',
        'new',
      ]);
    });

    test('не больше 4 карточек разминки', () {
      final List<Card> cards = <Card>[
        for (int index = 0; index < 6; index++)
          makeCard(
            id: 'learned-$index',
            deckId: 'deck-1',
            front: 'L$index',
            state: CardState.review,
            due: now.add(Duration(minutes: index)),
            fsrsJson: reviewFsrs(
              'learned-$index',
              stability: 100 - index.toDouble(),
              due: now.add(Duration(minutes: index)),
            ),
          ),
      ];

      final List<String> warmed = ids(
        build(cards, config: twoDecks.copyWith(warmup: true)),
      );

      expect(warmed.take(4), <String>[
        'learned-0',
        'learned-1',
        'learned-2',
        'learned-3',
      ]);
      expect(warmed, hasLength(6));
    });

    test('битый fsrs_json не роняет сборку и не делает карточку лёгкой', () {
      final List<Card> cards = <Card>[
        makeCard(
          id: 'broken',
          deckId: 'deck-1',
          front: 'X',
          state: CardState.review,
          due: now,
          fsrsJson: '{не json',
        ),
        makeCard(
          id: 'learned',
          deckId: 'deck-1',
          front: 'Y',
          state: CardState.review,
          due: now.add(const Duration(minutes: 1)),
          fsrsJson: reviewFsrs(
            'learned',
            stability: 42,
            due: now.add(const Duration(minutes: 1)),
          ),
        ),
      ];

      final List<String> warmed = ids(
        build(cards, config: twoDecks.copyWith(warmup: true)),
      );

      expect(warmed, <String>['learned', 'broken']);
    });

    test('без выученных карточек разминка не меняет порядок', () {
      final List<Card> cards = <Card>[
        makeCard(id: 'a', deckId: 'deck-1', front: 'A'),
        makeCard(
          id: 'b',
          deckId: 'deck-1',
          front: 'B',
          createdAt: now.add(const Duration(minutes: 1)),
        ),
      ];

      expect(
        ids(build(cards, config: twoDecks.copyWith(warmup: true))),
        ids(build(cards)),
      );
    });
  });

  group('интерливинг (A7.19)', () {
    test('round-robin по колодам, ≈50/50', () {
      final List<Card> cards = <Card>[
        makeCard(
          id: 'a1',
          deckId: 'deck-1',
          front: 'A1',
          createdAt: now.add(const Duration(minutes: 1)),
        ),
        makeCard(
          id: 'a2',
          deckId: 'deck-1',
          front: 'A2',
          createdAt: now.add(const Duration(minutes: 2)),
        ),
        makeCard(
          id: 'b1',
          deckId: 'deck-2',
          front: 'B1',
          createdAt: now.add(const Duration(minutes: 3)),
        ),
        makeCard(
          id: 'b2',
          deckId: 'deck-2',
          front: 'B2',
          createdAt: now.add(const Duration(minutes: 4)),
        ),
      ];

      expect(ids(build(cards)), <String>['a1', 'a2', 'b1', 'b2']);
      expect(
        ids(build(cards, config: twoDecks.copyWith(interleave: true))),
        <String>['a1', 'b1', 'a2', 'b2'],
      );
    });

    test('одна колода — интерливинг ничего не меняет', () {
      final List<Card> cards = <Card>[
        makeCard(id: 'a', deckId: 'deck-1', front: 'A'),
        makeCard(
          id: 'b',
          deckId: 'deck-1',
          front: 'B',
          createdAt: now.add(const Duration(minutes: 1)),
        ),
      ];

      expect(
        ids(
          build(
            cards,
            config: twoDecks.copyWith(
              deckIds: <String>['deck-1'],
              interleave: true,
            ),
          ),
        ),
        <String>['a', 'b'],
      );
    });
  });

  group('перемешивание', () {
    test('детерминировано по seed и меняет порядок', () {
      final List<Card> cards = <Card>[
        for (int index = 0; index < 8; index++)
          makeCard(
            id: 'card-$index',
            deckId: 'deck-1',
            front: 'C$index',
            createdAt: now.add(Duration(minutes: index)),
          ),
      ];
      final SessionConfig shuffled = twoDecks.copyWith(shuffle: true);

      final List<String> first = ids(build(cards, config: shuffled, seed: 7));
      final List<String> second = ids(build(cards, config: shuffled, seed: 7));
      final List<String> base = ids(build(cards));

      expect(first, second, reason: 'seed фиксирует порядок');
      expect(first, isNot(base));
      expect(first.toSet(), base.toSet(), reason: 'состав тот же');
    });

    test('разминка остаётся в начале при перемешивании', () {
      final List<Card> cards = <Card>[
        makeCard(
          id: 'learned',
          deckId: 'deck-1',
          front: 'L',
          state: CardState.review,
          due: now.add(const Duration(minutes: 5)),
          fsrsJson: reviewFsrs(
            'learned',
            stability: 50,
            due: now.add(const Duration(minutes: 5)),
          ),
        ),
        for (int index = 0; index < 6; index++)
          makeCard(
            id: 'new-$index',
            deckId: 'deck-1',
            front: 'N$index',
            createdAt: now.add(Duration(minutes: index)),
          ),
      ];

      final List<String> shuffled = ids(
        build(
          cards,
          config: twoDecks.copyWith(warmup: true, shuffle: true),
          seed: 3,
        ),
      );

      expect(shuffled.first, 'learned');
      expect(shuffled, hasLength(7));
    });
  });

  group('лимит', () {
    test('лимит карточек режет выборку после порядка', () {
      final List<Card> cards = <Card>[
        for (int index = 0; index < 5; index++)
          makeCard(
            id: 'card-$index',
            deckId: 'deck-1',
            front: 'C$index',
            createdAt: now.add(Duration(minutes: index)),
          ),
      ];

      expect(
        ids(
          build(
            cards,
            config: twoDecks.copyWith(limit: const SessionLimit.cards(3)),
          ),
        ),
        <String>['card-0', 'card-1', 'card-2'],
      );
    });

    test('лимит минут не режет карточки и задаёт бюджет плана', () {
      final List<Card> cards = <Card>[
        for (int index = 0; index < 5; index++)
          makeCard(
            id: 'card-$index',
            deckId: 'deck-1',
            front: 'C$index',
            createdAt: now.add(Duration(minutes: index)),
          ),
      ];
      final SessionConfig config = twoDecks.copyWith(
        limit: const SessionLimit.minutes(10),
      );

      final SessionPlan plan = SessionBuilder.plan(
        cards: cards,
        config: config,
        failureCounts: const <String, int>{},
        now: now,
      );

      expect(plan.cards, hasLength(5));
      expect(plan.timeBudget, const Duration(minutes: 10));
      expect(plan.mode, SessionMode.classic);
    });

    test('план с лимитом карточек: бюджет времени не задан, режим из конфига', () {
      final List<Card> cards = <Card>[
        makeCard(id: 'a', deckId: 'deck-1', front: 'A'),
      ];

      final SessionPlan plan = SessionBuilder.plan(
        cards: cards,
        config: twoDecks.copyWith(
          limit: const SessionLimit.cards(1),
          mode: SessionMode.feed,
        ),
        failureCounts: const <String, int>{},
        now: now,
      );

      expect(plan.timeBudget, isNull);
      expect(plan.mode, SessionMode.feed);
      expect(ids(plan.cards), <String>['a']);
    });
  });

  group('select (доступность для UI)', () {
    test('select не применяет лимит и отдаёт базовый порядок', () {
      final List<Card> cards = <Card>[
        for (int index = 0; index < 4; index++)
          makeCard(
            id: 'card-$index',
            deckId: 'deck-1',
            front: 'C$index',
            createdAt: now.add(Duration(minutes: index)),
          ),
      ];

      final List<Card> selected = SessionBuilder.select(
        cards: cards,
        config: twoDecks.copyWith(
          limit: const SessionLimit.cards(2),
          shuffle: true,
        ),
        failureCounts: const <String, int>{},
        now: now,
      );

      expect(ids(selected), <String>[
        'card-0',
        'card-1',
        'card-2',
        'card-3',
      ]);
    });
  });
}
