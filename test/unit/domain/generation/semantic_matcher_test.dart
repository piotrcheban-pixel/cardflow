import 'dart:convert';
import 'dart:io';

import 'package:cardflow/domain/generation/dedup_report.dart';
import 'package:cardflow/domain/generation/validation/semantic_matcher.dart';
import 'package:flutter_test/flutter_test.dart';

/// Контракт каскада дедупликации (TASK «Срез 6», ADR-050 §3.4).
///
/// Каскад: точный ключ → нормализованный ключ → шинглы + Жаккар; эмбеддинги —
/// за необязательным интерфейсом. Дубль **помечается парой**, а не удаляется:
/// `match` возвращает отчёт, список карточек не меняется.
void main() {
  test('точный дубль: уровень exact, similarity 1, пара, а не удаление', () {
    final List<DedupCard> cards = <DedupCard>[
      const DedupCard(
        id: 'a',
        front: 'Что такое энтропия?',
        back: 'Мера рассеяния энергии.',
      ),
      const DedupCard(
        id: 'b',
        front: 'Что такое энтропия?',
        back: 'Мера рассеяния энергии.',
      ),
      const DedupCard(
        id: 'c',
        front: 'Что такое энтальпия?',
        back: 'Полная энергия системы.',
      ),
    ];

    final DedupReport report = const SemanticMatcher().match(cards);

    expect(report.pairs, hasLength(1));
    final DedupPair pair = report.pairs.single;
    expect(pair.leftId, 'a');
    expect(pair.rightId, 'b');
    expect(pair.level, DedupLevel.exact);
    expect(pair.similarity, 1.0);
    expect(cards, hasLength(3), reason: 'дубль не удаляется из списка');
    expect(report.duplicateIds, <String>{'a', 'b'});
  });

  test('нормализованный дубль: регистр, ё, пунктуация, пробелы', () {
    final List<DedupCard> cards = <DedupCard>[
      const DedupCard(
        id: 'a',
        front: 'Ёмкость — отношение заряда к напряжению.',
        back: 'Измеряется в фарадах.',
      ),
      const DedupCard(
        id: 'b',
        front: 'емкость   -   отношение заряда к напряжению',
        back: 'измеряется в фарадах',
      ),
    ];

    final DedupReport report = const SemanticMatcher().match(cards);

    expect(report.pairs.single.level, DedupLevel.normalized);
    expect(report.pairs.single.similarity, 1.0);
    expect(report.countOf(DedupLevel.exact), 0);
  });

  test('почти-дубль: уровень semantic с коэффициентом Жаккара', () {
    final List<DedupCard> cards = <DedupCard>[
      const DedupCard(
        id: 'a',
        front: 'Что такое энтропия в термодинамике?',
        back:
            'Мера необратимого рассеяния энергии, равная отношению теплоты '
            'к температуре.',
      ),
      const DedupCard(
        id: 'b',
        front: 'Что такое энтропия в термодинамике?',
        back:
            'Мера необратимого рассеяния энергии, равная отношению теплоты '
            'к самой температуре.',
      ),
    ];

    final DedupReport report = const SemanticMatcher().match(cards);

    expect(report.pairs.single.level, DedupLevel.semantic);
    expect(report.pairs.single.similarity, greaterThan(0.7));
    expect(report.pairs.single.similarity, lessThan(1.0));
  });

  test('разные карточки не дубли: отчёт пуст', () {
    final List<DedupCard> cards = <DedupCard>[
      const DedupCard(
        id: 'a',
        front: 'Кто сформулировал закон всемирного тяготения?',
        back: 'Исаак Ньютон.',
      ),
      const DedupCard(
        id: 'b',
        front: 'Сколько струн у классической гитары?',
        back: 'Шесть.',
      ),
    ];

    expect(
      const SemanticMatcher().match(cards).pairs,
      isEmpty,
    );
  });

  test('каскад не понижает уровень: exact важнее semantic', () {
    final List<DedupCard> cards = <DedupCard>[
      const DedupCard(id: 'a', front: 'Вопрос?', back: 'Ответ.'),
      const DedupCard(id: 'b', front: 'Вопрос?', back: 'Ответ.'),
      const DedupCard(id: 'c', front: 'Вопрос?', back: 'Ответ!'),
    ];

    final DedupReport report = const SemanticMatcher().match(cards);

    expect(report.levelOf('b'), DedupLevel.exact);
    expect(report.pairs.first.level, DedupLevel.exact);
    // Третий отличается только пунктуацией — нормализованный уровень.
    expect(report.levelOf('c'), DedupLevel.normalized);
    expect(report.countOf(DedupLevel.exact), 1);
    expect(report.countOf(DedupLevel.normalized), 2);
  });

  test('сверка с колодой: существующая карточка — левая сторона пары', () {
    final DedupReport report = const SemanticMatcher().match(
      <DedupCard>[
        const DedupCard(
          id: 'new',
          front: 'Что такое энтропия?',
          back: 'Мера рассеяния энергии.',
        ),
      ],
      existing: <DedupCard>[
        const DedupCard(
          id: 'deck-1',
          front: 'Что такое энтропия?',
          back: 'Мера рассеяния энергии.',
        ),
      ],
    );

    expect(report.pairs.single.leftId, 'deck-1');
    expect(report.pairs.single.rightId, 'new');
    expect(report.pairs.single.level, DedupLevel.exact);
    expect(report.duplicateIds, <String>{'deck-1', 'new'});
  });

  test('эмбеддинги необязательны: без интерфейса пары нет, с ним — есть', () {
    final List<DedupCard> cards = <DedupCard>[
      const DedupCard(
        id: 'a',
        front: 'Почему небо голубое?',
        back: 'Рэлеевское рассеяние света.',
      ),
      const DedupCard(
        id: 'b',
        front: 'Отчего днём небосвод синий?',
        back: 'Свет рассеивается на молекулах воздуха.',
      ),
    ];

    expect(const SemanticMatcher().match(cards).pairs, isEmpty);

    final DedupReport withEmbeddings = const SemanticMatcher(
      embeddingProvider: _ConstantEmbeddings(),
    ).match(cards);

    expect(withEmbeddings.pairs.single.level, DedupLevel.embeddings);
    expect(withEmbeddings.pairs.single.similarity, 1.0);
  });

  test('провайдер без вектора (null) не даёт пары', () {
    final DedupReport report = const SemanticMatcher(
      embeddingProvider: _NullEmbeddings(),
    ).match(<DedupCard>[
      const DedupCard(id: 'a', front: 'Вопрос один?', back: 'Ответ один.'),
      const DedupCard(id: 'b', front: 'Вопрос два?', back: 'Ответ два.'),
    ]);

    expect(report.pairs, isEmpty);
  });

  test('повторные id карточек — ArgumentError (пара неоднозначна)', () {
    expect(
      () => const SemanticMatcher().match(<DedupCard>[
        const DedupCard(id: 'a', front: 'Вопрос?', back: 'Ответ.'),
        const DedupCard(id: 'a', front: 'Вопрос?', back: 'Ответ.'),
      ]),
      throwsArgumentError,
    );
  });

  test('матч детерминирован: один отчёт на один вход', () {
    final List<DedupCard> cards = <DedupCard>[
      const DedupCard(id: 'a', front: 'Вопрос?', back: 'Ответ.'),
      const DedupCard(id: 'b', front: 'Вопрос?', back: 'Ответ.'),
      const DedupCard(id: 'c', front: 'Вопрос?', back: 'Ответ!'),
    ];
    const SemanticMatcher matcher = SemanticMatcher();

    expect(matcher.match(cards).pairs, matcher.match(cards).pairs);
  });

  group('нормализация и метрики', () {
    test('normalizeForDedup: регистр, ё, пунктуация, пробелы', () {
      expect(
        SemanticMatcher.normalizeForDedup('  Ёмкость — «отношение»!  '),
        'емкость отношение',
      );
      expect(SemanticMatcher.normalizeForDedup('а, б; в.'), 'а б в');
    });

    test('шинглы и Жаккар: одинаковый текст — 1, разные — 0', () {
      final Set<String> left = SemanticMatcher.shinglesOf('энтропия мера');
      final Set<String> same = SemanticMatcher.shinglesOf('энтропия мера');
      final Set<String> disjoint = SemanticMatcher.shinglesOf('гитара струна');

      expect(SemanticMatcher.jaccard(left, same), 1.0);
      expect(SemanticMatcher.jaccard(left, disjoint), lessThan(0.2));
      expect(SemanticMatcher.jaccard(left, const <String>{}), 0.0);
      expect(SemanticMatcher.jaccard(const <String>{}, const <String>{}), 1.0);
    });

    test('косинус векторов: одинаковые — 1, ортогональные — 0', () {
      expect(
        SemanticMatcher.cosineSimilarity(
          const <double>[1, 2, 3],
          const <double>[1, 2, 3],
        ),
        1.0,
      );
      expect(
        SemanticMatcher.cosineSimilarity(
          const <double>[1, 0],
          const <double>[0, 1],
        ),
        0.0,
      );
      expect(
        SemanticMatcher.cosineSimilarity(const <double>[], const <double>[]),
        0.0,
        reason: 'пустые векторы сравнивать нечем',
      );
    });
  });

  test('фикстура: все известные пары ловятся, ложных нет', () {
    final _Fixture fixture = _Fixture.load(
      'test/fixtures/validation/duplicate_pairs.json',
    );
    final SemanticMatcher matcher = SemanticMatcher(
      similarityThreshold: fixture.similarityThreshold,
    );

    final DedupReport report = matcher.match(fixture.cards);

    final Set<String> actual = <String>{
      for (final DedupPair pair in report.pairs)
        '${pair.leftId}|${pair.rightId}|${pair.level.wireName}',
    };
    final Set<String> expected = <String>{
      for (final _FixturePair pair in fixture.expectedPairs)
        '${pair.left}|${pair.right}|${pair.level}',
    };

    expect(actual, expected);
    expect(report.pairs, hasLength(fixture.expectedPairs.length));
    for (final String id in fixture.expectedDistinct) {
      expect(
        report.isDuplicate(id),
        isFalse,
        reason: 'ложное срабатывание на карточке $id',
      );
    }
    expect(fixture.cards, hasLength(8), reason: 'фикстура не теряет карточки');
  });
}

/// Фикстура дедупа: карточки, ожидаемые пары и «ловушки» ложных срабатываний.
class _Fixture {
  const _Fixture({
    required this.similarityThreshold,
    required this.cards,
    required this.expectedPairs,
    required this.expectedDistinct,
  });

  factory _Fixture.load(String path) {
    final Map<String, Object?> json =
        jsonDecode(File(path).readAsStringSync()) as Map<String, Object?>;
    final List<Object?> rawCards = json['cards']! as List<Object?>;
    final List<Object?> rawPairs = json['expectedPairs']! as List<Object?>;
    final List<Object?> rawDistinct = json['expectedDistinct']! as List<Object?>;
    final List<DedupCard> cards = <DedupCard>[];
    for (final Object? raw in rawCards) {
      final Map<String, Object?> map = raw! as Map<String, Object?>;
      cards.add(
        DedupCard(
          id: map['id']! as String,
          front: map['front']! as String,
          back: map['back']! as String,
        ),
      );
    }
    final List<_FixturePair> expectedPairs = <_FixturePair>[];
    for (final Object? raw in rawPairs) {
      final Map<String, Object?> map = raw! as Map<String, Object?>;
      expectedPairs.add(
        _FixturePair(
          left: map['left']! as String,
          right: map['right']! as String,
          level: map['level']! as String,
        ),
      );
    }
    return _Fixture(
      similarityThreshold: (json['similarityThreshold']! as num).toDouble(),
      cards: cards,
      expectedPairs: expectedPairs,
      expectedDistinct: <String>[
        for (final Object? raw in rawDistinct) raw! as String,
      ],
    );
  }

  final double similarityThreshold;
  final List<DedupCard> cards;
  final List<_FixturePair> expectedPairs;
  final List<String> expectedDistinct;
}

/// Ожидаемая пара фикстуры.
class _FixturePair {
  const _FixturePair({
    required this.left,
    required this.right,
    required this.level,
  });

  final String left;
  final String right;
  final String level;
}

/// Провайдер, который считает все тексты одним и тем же вектором.
class _ConstantEmbeddings implements TextEmbeddingProvider {
  const _ConstantEmbeddings();

  @override
  List<double>? embed(String text) => const <double>[1, 0, 0];
}

/// Провайдер без векторов: эмбеддинги недоступны.
class _NullEmbeddings implements TextEmbeddingProvider {
  const _NullEmbeddings();

  @override
  List<double>? embed(String text) => null;
}
