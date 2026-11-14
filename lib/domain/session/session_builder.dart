/// Сборка выборки конструктора (SPEC A6.7/A7.19/A7.20, ADR-018).
///
/// Чистые функции без Flutter и БД: UI отдаёт снимок карточек, конфиг и
/// счётчики провалов — домен решает, какие карточки и в каком порядке войдут
/// в сессию. Порядок операций: фильтры → базовый порядок → разминка →
/// перемешивание → интерливинг → лимит (ADR-018 §2).
library;

import 'dart:convert';
import 'dart:math';

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/session/leech_repository.dart';
import 'package:cardflow/domain/session/session_config.dart';
import 'package:cardflow/domain/session/session_plan.dart';

/// Чистая сборка очереди конструктора.
abstract final class SessionBuilder {
  /// Сколько карточек поднимает разминка (середина диапазона 3–5 A7.19).
  static const int warmupSize = 4;

  /// Отбирает карточки по фильтрам в базовом порядке (без разминки,
  /// перемешивания и лимита) — для счётчика «доступно» и тестов.
  ///
  /// Приостановленные и отложенные (`buriedUntil > now`) карточки не входят
  /// никогда (ADR-008/ADR-018).
  static List<Card> select({
    required Iterable<Card> cards,
    required SessionConfig config,
    required Map<String, int> failureCounts,
    required DateTime now,
  }) {
    if (config.deckIds.isEmpty) return const <Card>[];
    final DateTime utcNow = now.toUtc();
    final Set<String> decks = config.deckIds.toSet();
    final List<Card> filtered = <Card>[
      for (final Card card in cards)
        if (_matches(
          card,
          config: config,
          decks: decks,
          failureCounts: failureCounts,
          now: utcNow,
        ))
          card,
    ];
    return List<Card>.unmodifiable(_baseOrder(filtered));
  }

  /// Собирает очередь сессии: фильтры → разминка → интерливинг → перемешивание
  /// → лимит; [seed] фиксирует перемешивание (тесты/воспроизводимость).
  ///
  /// При лимите минут карточки не режутся: бюджет времени попадает в
  /// [SessionPlan.timeBudget].
  static List<Card> build({
    required Iterable<Card> cards,
    required SessionConfig config,
    required Map<String, int> failureCounts,
    required DateTime now,
    int? seed,
  }) {
    final List<Card> selected = select(
      cards: cards,
      config: config,
      failureCounts: failureCounts,
      now: now,
    );
    if (selected.isEmpty) return const <Card>[];

    List<Card> rest = selected;
    List<Card> warmup = const <Card>[];
    if (config.warmup) {
      final List<Card> learned = <Card>[
        for (final Card card in rest)
          if (card.state == CardState.review) card,
      ]..sort(_compareWarmup);
      final int count = learned.length < warmupSize
          ? learned.length
          : warmupSize;
      warmup = learned.sublist(0, count);
      final Set<String> warmCards = <String>{
        for (final Card card in warmup) card.id,
      };
      rest = <Card>[
        for (final Card card in rest)
          if (!warmCards.contains(card.id)) card,
      ];
    }

    if (config.shuffle) {
      rest = _shuffle(rest, seed ?? now.microsecondsSinceEpoch);
    }
    // Интерливинг после перемешивания: иначе случайный порядок снова смешал бы
    // колоды и чередование (A7.19) перестало бы работать.
    if (config.interleave) rest = _interleave(rest);

    final List<Card> ordered = <Card>[...warmup, ...rest];
    final int? cap = config.limit.isMinutes ? null : config.limit.value;
    final List<Card> limited = cap == null || ordered.length <= cap
        ? ordered
        : ordered.sublist(0, cap);
    return List<Card>.unmodifiable(limited);
  }

  /// План сессии: очередь и бюджет времени из лимита минут.
  static SessionPlan plan({
    required Iterable<Card> cards,
    required SessionConfig config,
    required Map<String, int> failureCounts,
    required DateTime now,
    int? seed,
  }) {
    return SessionPlan(
      cards: build(
        cards: cards,
        config: config,
        failureCounts: failureCounts,
        now: now,
        seed: seed,
      ),
      timeBudget: config.limit.timeBudget,
      mode: config.mode,
    );
  }

  static bool _matches(
    Card card, {
    required SessionConfig config,
    required Set<String> decks,
    required Map<String, int> failureCounts,
    required DateTime now,
  }) {
    if (!decks.contains(card.deckId)) return false;
    if (card.suspended) return false;
    final DateTime? buried = card.buriedUntil;
    if (buried != null && buried.toUtc().isAfter(now)) return false;
    if (config.tags.isNotEmpty && !card.tags.any(config.tags.contains)) {
      return false;
    }
    if (config.cardTypes.isNotEmpty &&
        !config.cardTypes.contains(card.cardType)) {
      return false;
    }
    if (config.states.isNotEmpty) {
      bool matchesAny = false;
      for (final SessionStateFilter filter in config.states) {
        if (_matchesState(card, filter, failureCounts)) {
          matchesAny = true;
          break;
        }
      }
      if (!matchesAny) return false;
    }
    return true;
  }

  static bool _matchesState(
    Card card,
    SessionStateFilter filter,
    Map<String, int> failureCounts,
  ) {
    return switch (filter) {
      SessionStateFilter.newCards => card.state == CardState.newCard,
      SessionStateFilter.inProgress =>
        card.state == CardState.learning || card.state == CardState.relearning,
      SessionStateFilter.review => card.state == CardState.review,
      SessionStateFilter.leeches =>
        (failureCounts[card.id] ?? 0) >= leechFailureThreshold,
    };
  }

  /// Базовый порядок ADR-008: карточки с `due` — по `due` ASC, затем новые —
  /// по `createdAt` ASC; тай-брек везде `id` ASC (детерминизм тестов).
  static List<Card> _baseOrder(List<Card> cards) {
    final List<Card> scheduled =
        <Card>[
          for (final Card card in cards)
            if (card.due != null) card,
        ]..sort((Card a, Card b) {
          final int byDue = a.due!.compareTo(b.due!);
          return byDue != 0 ? byDue : a.id.compareTo(b.id);
        });
    final List<Card> unscheduled =
        <Card>[
          for (final Card card in cards)
            if (card.due == null) card,
        ]..sort((Card a, Card b) {
          final int byCreated = a.createdAt.compareTo(b.createdAt);
          return byCreated != 0 ? byCreated : a.id.compareTo(b.id);
        });
    return <Card>[...scheduled, ...unscheduled];
  }

  /// Разминка: выученные карточки с максимальной FSRS-стабильностью; битый
  /// `fsrs_json` не роняет сборку (карточка считается «не лёгкой»).
  static int _compareWarmup(Card a, Card b) {
    final int byStability = _stabilityOf(b).compareTo(_stabilityOf(a));
    if (byStability != 0) return byStability;
    final DateTime? dueA = a.due;
    final DateTime? dueB = b.due;
    if (dueA != null && dueB != null) {
      final int byDue = dueA.compareTo(dueB);
      if (byDue != 0) return byDue;
    } else if (dueA != null) {
      return -1;
    } else if (dueB != null) {
      return 1;
    }
    return a.id.compareTo(b.id);
  }

  static double _stabilityOf(Card card) {
    final String? raw = card.fsrsJson;
    if (raw == null) return 0;
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return 0;
      final Object? stability = decoded['stability'];
      return stability is num ? stability.toDouble() : 0;
    } catch (_) {
      // Битый fsrs_json — карточка не считается лёгкой (ADR-018 §2).
      return 0;
    }
  }

  /// Round-robin по колодам (≈50/50, A7.19): порядок колод — по первому
  /// появлению в базовом порядке, внутри колоды порядок сохраняется.
  static List<Card> _interleave(List<Card> cards) {
    final Map<String, List<Card>> byDeck = <String, List<Card>>{};
    for (final Card card in cards) {
      byDeck.putIfAbsent(card.deckId, () => <Card>[]).add(card);
    }
    if (byDeck.length < 2) return cards;
    final List<List<Card>> queues = byDeck.values.toList(growable: false);
    final List<Card> result = <Card>[];
    for (int round = 0; ; round++) {
      bool added = false;
      for (final List<Card> queue in queues) {
        if (round < queue.length) {
          result.add(queue[round]);
          added = true;
        }
      }
      if (!added) break;
    }
    return result;
  }

  /// Fisher–Yates с `Random(seed)` — детерминированный порядок при заданном
  /// seed (тесты) и случайный в production (seed из времени).
  static List<Card> _shuffle(List<Card> cards, int seed) {
    final List<Card> result = List<Card>.of(cards);
    final Random random = Random(seed);
    for (int index = result.length - 1; index > 0; index--) {
      final int swap = random.nextInt(index + 1);
      final Card temp = result[index];
      result[index] = result[swap];
      result[swap] = temp;
    }
    return result;
  }
}
