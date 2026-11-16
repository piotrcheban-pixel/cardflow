import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/study/study_fsrs_policy.dart';
import 'package:cardflow/domain/study/study_mode.dart';
import 'package:cardflow/domain/study/study_queue.dart';

/// Очередь и политика FSRS новых режимов (7.15).
void main() {
  final DateTime now = DateTime.utc(2026, 11, 16, 12);

  Card card(
    String id, {
    CardState state = CardState.newCard,
    DateTime? due,
    bool suspended = false,
    DateTime? buriedUntil,
  }) {
    return Card(
      id: id,
      deckId: 'deck-1',
      front: 'Вопрос $id',
      back: 'Ответ $id',
      cardType: CardType.basic,
      state: state,
      due: due,
      suspended: suspended,
      buriedUntil: buriedUntil,
      createdAt: DateTime.utc(2026, 11, 1),
      updatedAt: DateTime.utc(2026, 11, 1),
    );
  }

  test('очередь: due и новые, затем будущие due', () {
    final queue = buildStudyQueue(<Card>[
      card('new'),
      card(
        'due',
        state: CardState.review,
        due: now.subtract(const Duration(days: 1)),
      ),
      card(
        'future',
        state: CardState.review,
        due: now.add(const Duration(days: 2)),
      ),
      card('suspended', suspended: true),
      card('buried', buriedUntil: now.add(const Duration(hours: 1))),
    ], now: now);
    expect(queue.map((Card c) => c.id), <String>['due', 'new', 'future']);
  });

  test('политика: новая и просроченная — FSRS, будущая — тренировка', () {
    expect(
      isDueForStudy(card('new'), now),
      isTrue,
      reason: 'первая оценка создаёт расписание',
    );
    expect(
      isDueForStudy(card('due', state: CardState.review, due: now), now),
      isTrue,
    );
    expect(
      isDueForStudy(
        card(
          'future',
          state: CardState.review,
          due: now.add(const Duration(days: 1)),
        ),
        now,
      ),
      isFalse,
    );
  });

  test('shouldWriteFsrs учитывает поддержку режима', () {
    final future = card(
      'future',
      state: CardState.review,
      due: now.add(const Duration(days: 1)),
    );
    final due = card('due', state: CardState.review, due: now);
    expect(shouldWriteFsrs(future, now, modeSupportsFsrs: true), isFalse);
    expect(shouldWriteFsrs(due, now, modeSupportsFsrs: true), isTrue);
    expect(
      shouldWriteFsrs(due, now, modeSupportsFsrs: false),
      isFalse,
      reason: 'Тренировка/Пары не пишут FSRS',
    );
  });

  test('StudyMode: wire-значения и политика', () {
    expect(StudyMode.test.wireName, 'test');
    expect(StudyMode.typing.wireName, 'typing');
    expect(StudyMode.match.wireName, 'match');
    expect(StudyMode.trueFalse.wireName, 'true_false');
    expect(StudyMode.match.canWriteFsrs, isFalse);
    expect(StudyMode.match.writesReviewLog, isFalse);
    expect(StudyMode.practice.canWriteFsrs, isFalse);
    expect(StudyMode.test.canWriteFsrs, isTrue);
    expect(StudyMode.typing.canWriteFsrs, isTrue);
    expect(StudyMode.trueFalse.canWriteFsrs, isTrue);
    expect(StudyMode.tryParse('true_false'), StudyMode.trueFalse);
    expect(StudyMode.tryParse('unknown'), isNull);
  });
}
