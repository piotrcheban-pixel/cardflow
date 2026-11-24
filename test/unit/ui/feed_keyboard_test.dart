import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/ui/review/feed_keyboard.dart';

/// Раскладка клавиатуры ленты (ADR-044): навигация и раскрытие без оценок.
void main() {
  KeyEvent down(LogicalKeyboardKey key) => KeyDownEvent(
    physicalKey: PhysicalKeyboardKey.arrowDown,
    logicalKey: key,
    timeStamp: Duration.zero,
  );

  KeyEventResult run(
    LogicalKeyboardKey key, {
    required void Function(String action) onAction,
  }) {
    return handleFeedSessionKey(
      event: down(key),
      onNext: () => onAction('next'),
      onPrevious: () => onAction('previous'),
      onReveal: () => onAction('reveal'),
      onFirst: () => onAction('first'),
      onLast: () => onAction('last'),
      onClose: () => onAction('close'),
    );
  }

  test('вниз/PageDown/вправо — следующая, вверх/PageUp/влево — предыдущая', () {
    final List<String> actions = <String>[];
    for (final LogicalKeyboardKey key in <LogicalKeyboardKey>[
      LogicalKeyboardKey.arrowDown,
      LogicalKeyboardKey.pageDown,
      LogicalKeyboardKey.arrowRight,
    ]) {
      actions.clear();
      expect(run(key, onAction: actions.add), KeyEventResult.handled);
      expect(actions, <String>['next'], reason: '$key');
    }
    for (final LogicalKeyboardKey key in <LogicalKeyboardKey>[
      LogicalKeyboardKey.arrowUp,
      LogicalKeyboardKey.pageUp,
      LogicalKeyboardKey.arrowLeft,
    ]) {
      actions.clear();
      expect(run(key, onAction: actions.add), KeyEventResult.handled);
      expect(actions, <String>['previous'], reason: '$key');
    }
  });

  test('Home/End/пробел/Enter/Esc', () {
    final List<String> actions = <String>[];
    expect(
      run(LogicalKeyboardKey.home, onAction: actions.add),
      KeyEventResult.handled,
    );
    expect(
      run(LogicalKeyboardKey.end, onAction: actions.add),
      KeyEventResult.handled,
    );
    expect(
      run(LogicalKeyboardKey.space, onAction: actions.add),
      KeyEventResult.handled,
    );
    expect(
      run(LogicalKeyboardKey.enter, onAction: actions.add),
      KeyEventResult.handled,
    );
    expect(
      run(LogicalKeyboardKey.escape, onAction: actions.add),
      KeyEventResult.handled,
    );
    expect(actions, <String>['first', 'last', 'reveal', 'reveal', 'close']);
  });

  test('цифры 1–4 в ленте ничего не делают: оценок здесь нет', () {
    final List<String> actions = <String>[];
    for (final LogicalKeyboardKey key in <LogicalKeyboardKey>[
      LogicalKeyboardKey.digit1,
      LogicalKeyboardKey.digit2,
      LogicalKeyboardKey.digit3,
      LogicalKeyboardKey.digit4,
    ]) {
      expect(run(key, onAction: actions.add), KeyEventResult.ignored);
    }
    expect(actions, isEmpty);
  });
}
