/// Политика FSRS для новых режимов (итерация 7.15, ADR-032).
///
/// Расписание не должно искажаться: оценка пишется в FSRS только для карточек,
/// которые пора повторять. Новая карточка (`state = new`) ещё не планировалась —
/// для неё первая оценка создаёт начальное расписание (как в Классике), поэтому
/// она тоже считается «due».
///
/// Карточка с `due` в будущем в режиме Тест/Ввод/Верно-Неверно работает как
/// тренировка: журнал `review_logs` пишется, `cards.state`/`fsrs_json`/`due` —
/// нет (ADR-025).
library;

import 'package:cardflow/domain/cards/card.dart';

/// Пора ли изучать карточку сейчас (due или новая).
bool isDueForStudy(Card card, DateTime now) {
  if (card.state == CardState.newCard) return true;
  final DateTime? due = card.due;
  return due != null && !due.isAfter(now.toUtc());
}

/// Стоит ли записывать оценку в FSRS для карточки в режиме с поддержкой FSRS.
bool shouldWriteFsrs(
  Card card,
  DateTime now, {
  required bool modeSupportsFsrs,
}) {
  if (!modeSupportsFsrs) return false;
  return isDueForStudy(card, now);
}
