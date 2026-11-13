// Проба интервалов FSRS для отчёта итерации 2 (SPEC A7.2, ADR-004).
//
// Печатает прогноз интервалов Again/Hard/Good/Easy для карточки в каждом
// состоянии (new / learning / review / relearning) при конфигурации по
// умолчанию: desiredRetention 0.9, шаги 1/10 мин, relearning 10 мин, fuzzing
// выключен. Это доказательство того, что прогноз детерминирован и различается
// по состояниям, а не «тесты зелёные».
//
// Запуск: fvm dart run tool/fsrs_intervals_probe.dart
import 'dart:io';

import 'package:cardflow/domain/scheduling/scheduler.dart';

String describe(Duration d) {
  final int seconds = d.inSeconds;
  if (seconds % Duration.secondsPerDay == 0) {
    return '${d.inDays} д';
  }
  if (seconds % Duration.secondsPerHour == 0) {
    return '${d.inHours} ч';
  }
  if (seconds % Duration.secondsPerMinute == 0) {
    return '${d.inMinutes} мин';
  }
  return '${d.inMinutes} мин ${d.inSeconds % Duration.secondsPerMinute} с';
}

void main() {
  final scheduler = FsrsScheduler();
  final base = DateTime.utc(2026, 11, 13, 12);

  // Состояния строятся той же операцией планировщика, что и в приложении.
  final newCard = SchedulingCard.newCard(cardId: 'probe', now: base);
  final learning = scheduler.review(newCard, Rating.good, now: base).card;
  final review = scheduler.review(newCard, Rating.easy, now: base).card;
  final relearning = scheduler
      .review(review, Rating.again, now: review.due)
      .card;

  final rows = <(String, DateTime, SchedulingCard)>[
    ('new', base, newCard),
    ('learning (step 1)', learning.due, learning),
    ('review', review.due, review),
    ('relearning (step 0)', relearning.due, relearning),
  ];

  stdout.writeln(
    'Состояние            | Again        | Hard         | Good         | Easy',
  );
  stdout.writeln(
    '---------------------+--------------+--------------+--------------+--------------',
  );
  for (final (String name, DateTime at, SchedulingCard card) in rows) {
    final Map<Rating, Duration> preview = scheduler.previewIntervals(
      card,
      now: at,
    );
    final List<String> cells = <String>[
      for (final Rating rating in Rating.values) describe(preview[rating]!),
    ];
    stdout.writeln(
      '${name.padRight(20)}| ${cells[0].padRight(13)}| ${cells[1].padRight(13)}| '
      '${cells[2].padRight(13)}| ${cells[3].padRight(13)}',
    );
  }

  stdout.writeln('');
  stdout.writeln(
    'Карточка review: stability=${review.stability!.toStringAsFixed(3)}, '
    'difficulty=${review.difficulty!.toStringAsFixed(3)}, '
    'due через ${describe(review.due.difference(base))} после Easy.',
  );
  stdout.writeln(
    'Карточка learning: step=${learning.step}, '
    'stability=${learning.stability!.toStringAsFixed(3)}.',
  );
  stdout.writeln(
    'Карточка relearning: step=${relearning.step}, '
    'stability=${relearning.stability!.toStringAsFixed(3)}.',
  );
}
