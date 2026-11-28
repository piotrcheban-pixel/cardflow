import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/domain/generation/blind_sample.dart';
import 'package:cardflow/domain/generation/generation_path.dart';

/// Срез 17, часть 1: слепая человеческая выборка из **сохранённых** карточек.
///
/// 30 случайных v3 и 30 случайных legacy с решающих ячеек, случайный порядок,
/// без пути и без id в файле выборки; ключ «номер → путь» — отдельно, его
/// открывают после заполнения. Новых прогонов нет — только сохранённое.
void main() {
  List<BlindSourceCard> cardsOf(
    GenerationPath path,
    String cellId,
    String label,
    int count,
  ) => <BlindSourceCard>[
    for (int index = 0; index < count; index++)
      BlindSourceCard(
        cellId: cellId,
        path: path,
        front: 'Вопрос $label $count #$index',
        back: 'Ответ $label $count #$index',
      ),
  ];

  test('30 + 30 в случайном порядке, номера подряд, путь не течёт', () {
    final BlindSample sample = buildBlindSample(
      cards: <BlindSourceCard>[
        ...cardsOf(GenerationPath.v3, 'textbook-v3-80', 'А', 34),
        ...cardsOf(GenerationPath.legacy, 'textbook-legacy-80', 'Б', 35),
      ],
      seed: 17,
    );

    expect(sample.measured, isTrue);
    expect(sample.entries, hasLength(60));
    expect(
      sample.entries.map((BlindEntry entry) => entry.number),
      List<int>.generate(60, (int index) => index + 1),
    );
    expect(sample.v3Sampled, 30);
    expect(sample.legacySampled, 30);
    expect(sample.key, hasLength(60));
    // В выборке нет ни пути, ни id источника — только тексты и номер.
    for (final BlindEntry entry in sample.entries) {
      expect(entry.front, isNotEmpty);
      expect(entry.back, isNotEmpty);
      expect(entry.front.contains('v3'), isFalse);
      expect(entry.front.contains('legacy'), isFalse);
    }
  });

  test(
    'ключ совпадает по номерам с выборкой и называет карточку источника',
    () {
      final BlindSample sample = buildBlindSample(
        cards: <BlindSourceCard>[
          ...cardsOf(GenerationPath.v3, 'article-v3-80', 'А', 30),
          ...cardsOf(GenerationPath.legacy, 'article-legacy-80', 'Б', 30),
        ],
        seed: 3,
      );

      expect(
        sample.key.map((BlindKeyEntry entry) => entry.number),
        sample.entries.map((BlindEntry entry) => entry.number),
      );
      for (final BlindKeyEntry entry in sample.key) {
        expect(entry.cellId, isNotEmpty);
        expect(entry.path, anyOf(GenerationPath.v3, GenerationPath.legacy));
      }
      expect(
        sample.key.where(
          (BlindKeyEntry entry) => entry.path == GenerationPath.v3,
        ),
        hasLength(30),
      );
      expect(
        sample.key.where(
          (BlindKeyEntry entry) => entry.path == GenerationPath.legacy,
        ),
        hasLength(30),
      );
    },
  );

  test('одна и та же карточка не попадает в выборку дважды', () {
    final BlindSample sample = buildBlindSample(
      cards: <BlindSourceCard>[
        ...cardsOf(GenerationPath.v3, 'textbook-v3-150', 'А', 30),
        ...cardsOf(GenerationPath.legacy, 'textbook-legacy-150', 'Б', 30),
      ],
      seed: 11,
    );
    final Set<String> seen = <String>{};
    for (final BlindKeyEntry entry in sample.key) {
      expect(
        seen.add('${entry.cellId}#${entry.cardIndex}'),
        isTrue,
        reason: 'повтор источника в выборке',
      );
    }
  });

  test(
    'порядок детерминирован seed-ом и не совпадает с порядком источника',
    () {
      final List<BlindSourceCard> cards = <BlindSourceCard>[
        ...cardsOf(GenerationPath.v3, 'textbook-v3-300', 'А', 32),
        ...cardsOf(GenerationPath.legacy, 'textbook-legacy-300', 'Б', 32),
      ];
      final BlindSample first = buildBlindSample(cards: cards, seed: 17);
      final BlindSample second = buildBlindSample(cards: cards, seed: 17);
      expect(
        first.entries.map((BlindEntry entry) => entry.front).toList(),
        second.entries.map((BlindEntry entry) => entry.front).toList(),
      );
      final List<String> sourceFronts = <String>[
        for (final BlindSourceCard card in cards) card.front,
      ];
      expect(
        first.entries.take(10).map((BlindEntry entry) => entry.front).toList(),
        isNot(equals(sourceFronts.take(10).toList())),
        reason: 'порядок перемешан, иначе цель слепоты не выполнена',
      );
    },
  );

  test('меньше 30 у пути — все, что есть, и недобор числом', () {
    final BlindSample sample = buildBlindSample(
      cards: <BlindSourceCard>[
        ...cardsOf(GenerationPath.v3, 'article-v3-80', 'А', 13),
        ...cardsOf(GenerationPath.legacy, 'article-legacy-80', 'Б', 17),
      ],
      seed: 5,
    );
    expect(sample.measured, isTrue);
    expect(sample.entries, hasLength(30));
    expect(sample.v3Sampled, 13);
    expect(sample.legacySampled, 17);
    expect(sample.shortfall, 30);
  });

  test(
    'нет сохранённых карточек → not_measured с причиной, а не пустой файл',
    () {
      final BlindSample sample = buildBlindSample(
        cards: const <BlindSourceCard>[],
        seed: 17,
      );
      expect(sample.measured, isFalse);
      expect(sample.entries, isEmpty);
      expect(sample.key, isEmpty);
      expect(sample.notMeasuredReason, isNotNull);
      expect(sample.notMeasuredReason, contains('сохранённых карточек'));
    },
  );
}
