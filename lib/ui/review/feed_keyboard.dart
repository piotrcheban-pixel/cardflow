import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

/// Клавиатура режима «Лента» (ADR-044).
///
/// Раскладка свободного просмотра:
///
/// * `↓`, `PageDown`, `→` — следующая карточка;
/// * `↑`, `PageUp`, `←` — предыдущая;
/// * `Home` / `End` — первая / последняя;
/// * `Space` / `Enter` — раскрыть/скрыть ответ;
/// * `Esc` — выход (диалог подтверждения открывает экран).
///
/// Функция без состояния: экран передаёт обработчики и получает
/// [KeyEventResult], поэтому раскладка тестируется без дерева виджетов.
/// В отличие от классики, здесь **нет** клавиш `1`–`4`: в ленте нет оценок.
KeyEventResult handleFeedSessionKey({
  required KeyEvent event,
  required VoidCallback onNext,
  required VoidCallback onPrevious,
  required VoidCallback onReveal,
  required VoidCallback onFirst,
  required VoidCallback onLast,
  required VoidCallback onClose,
}) {
  if (event is! KeyDownEvent) return KeyEventResult.ignored;
  final LogicalKeyboardKey key = event.logicalKey;
  if (key == LogicalKeyboardKey.arrowDown ||
      key == LogicalKeyboardKey.pageDown ||
      key == LogicalKeyboardKey.arrowRight) {
    onNext();
    return KeyEventResult.handled;
  }
  if (key == LogicalKeyboardKey.arrowUp ||
      key == LogicalKeyboardKey.pageUp ||
      key == LogicalKeyboardKey.arrowLeft) {
    onPrevious();
    return KeyEventResult.handled;
  }
  if (key == LogicalKeyboardKey.home) {
    onFirst();
    return KeyEventResult.handled;
  }
  if (key == LogicalKeyboardKey.end) {
    onLast();
    return KeyEventResult.handled;
  }
  if (key == LogicalKeyboardKey.space ||
      key == LogicalKeyboardKey.enter ||
      key == LogicalKeyboardKey.numpadEnter) {
    onReveal();
    return KeyEventResult.handled;
  }
  if (key == LogicalKeyboardKey.escape) {
    onClose();
    return KeyEventResult.handled;
  }
  return KeyEventResult.ignored;
}
