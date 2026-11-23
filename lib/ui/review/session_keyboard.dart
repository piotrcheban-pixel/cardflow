import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import 'package:cardflow/domain/scheduling/rating.dart';
import 'package:cardflow/ui/theme/app_tokens.dart';

/// Клавиатура классической сессии и тренировки (SPEC A7.2, A4.4).
///
/// Раскладка:
/// * `Space` / `→` — показать ответ;
/// * `←` — отменить последнюю оценку (если есть что отменять);
/// * `1`–`4` — Again / Hard / Good / Easy;
/// * `↑`/`↓`, `PageUp`/`PageDown`, `Home`/`End` — прокрутка длинного текста
///   карточки (аудит v2, D1: колесо прокручивало, клавиатура — нет).
///
/// Ключевое правило аудита (находка F1): **оценка без раскрытого ответа не
/// принимается**. Клавиша `1`–`4` до раскрытия ничего не пишет в журнал, иначе
/// расписание FSRS строится по ответам, которых пользователь не видел. То же
/// условие проверяет и панель оценок (`enabled && revealed`), а движок сессии
/// остаётся последней линией защиты — `rate` до раскрытия возвращает `false`.
///
/// Функция без состояния: экраны передают свои обработчики и получают
/// [KeyEventResult], поэтому поведение клавиш тестируется без дерева виджетов.
KeyEventResult handleReviewSessionKey({
  required KeyEvent event,
  required bool revealed,
  required bool canUndo,
  required VoidCallback onReveal,
  required ValueChanged<Rating> onRate,
  required VoidCallback onUndo,
  ScrollController? scroll,
}) {
  if (event is! KeyDownEvent) return KeyEventResult.ignored;
  final LogicalKeyboardKey key = event.logicalKey;
  if (_scrollByKey(key, scroll)) return KeyEventResult.handled;
  if (key == LogicalKeyboardKey.space ||
      key == LogicalKeyboardKey.arrowRight ||
      key == LogicalKeyboardKey.enter ||
      key == LogicalKeyboardKey.numpadEnter) {
    if (!revealed) onReveal();
    return KeyEventResult.handled;
  }
  if (key == LogicalKeyboardKey.arrowLeft) {
    if (canUndo) onUndo();
    return KeyEventResult.handled;
  }
  final Rating? rating = switch (key) {
    LogicalKeyboardKey.digit1 || LogicalKeyboardKey.numpad1 => Rating.again,
    LogicalKeyboardKey.digit2 || LogicalKeyboardKey.numpad2 => Rating.hard,
    LogicalKeyboardKey.digit3 || LogicalKeyboardKey.numpad3 => Rating.good,
    LogicalKeyboardKey.digit4 || LogicalKeyboardKey.numpad4 => Rating.easy,
    _ => null,
  };
  if (rating == null) return KeyEventResult.ignored;
  // Клавиша распознана, но без раскрытого ответа оценка не пишется: сначала
  // пользователь должен увидеть ответ (находка F1).
  if (!revealed) return KeyEventResult.handled;
  onRate(rating);
  return KeyEventResult.handled;
}

/// Прокрутка содержимого карточки клавишами; `true` — клавиша обработана.
bool _scrollByKey(LogicalKeyboardKey key, ScrollController? scroll) {
  if (scroll == null || !scroll.hasClients) return false;
  final ScrollPosition position = scroll.position;
  final double page = position.viewportDimension * 0.8;
  final double? target = switch (key) {
    LogicalKeyboardKey.arrowDown => position.pixels + 48,
    LogicalKeyboardKey.arrowUp => position.pixels - 48,
    LogicalKeyboardKey.pageDown => position.pixels + page,
    LogicalKeyboardKey.pageUp => position.pixels - page,
    LogicalKeyboardKey.home => 0,
    LogicalKeyboardKey.end => position.maxScrollExtent,
    _ => null,
  };
  if (target == null) return false;
  unawaited(
    scroll.animateTo(
      target.clamp(0.0, position.maxScrollExtent),
      // Аудит v7 (G9): анимация прокрутки — из общей шкалы токенов, а не
      // литеральные 160 мс.
      duration: AppDurations.base,
      curve: Curves.easeOut,
    ),
  );
  return true;
}
