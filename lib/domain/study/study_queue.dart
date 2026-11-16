/// Порядок карточек в режимах Тест/Ввод/Верно-Неверно (итерация 7.15).
///
/// Сначала карточки, которые пора изучать (due и новые — в порядке Классики),
/// затем карточки с `due` в будущем (они проходятся как тренировка). Карточки
/// `suspended` и отложенные (`buriedUntil > now`) исключены.
library;

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/review/review_queue.dart';
import 'package:cardflow/domain/study/study_fsrs_policy.dart';

/// Собирает очередь нового режима изучения.
List<Card> buildStudyQueue(List<Card> cards, {required DateTime now}) {
  final DateTime utcNow = now.toUtc();
  final List<Card> eligible = cards
      .where((Card card) {
        if (card.suspended) return false;
        final DateTime? buried = card.buriedUntil;
        return buried == null || !buried.isAfter(utcNow);
      })
      .toList(growable: false);

  final List<Card> due = ReviewQueue.build(eligible, now: utcNow);
  final Set<String> dueIds = <String>{for (final Card card in due) card.id};
  final List<Card> future =
      eligible
          .where((Card card) => !dueIds.contains(card.id))
          .toList(growable: false)
        ..sort((Card a, Card b) {
          final DateTime? left = a.due;
          final DateTime? right = b.due;
          if (left == null && right == null) return a.id.compareTo(b.id);
          if (left == null) return 1;
          if (right == null) return -1;
          final int byDue = left.compareTo(right);
          return byDue != 0 ? byDue : a.id.compareTo(b.id);
        });

  return List<Card>.unmodifiable(<Card>[...due, ...future]);
}

/// Карточки очереди, для которых режим вправе писать FSRS.
List<Card> fsrsCardsOf(List<Card> queue, {required DateTime now}) {
  return <Card>[
    for (final Card card in queue)
      if (isDueForStudy(card, now)) card,
  ];
}
