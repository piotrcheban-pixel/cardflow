import 'package:flutter/services.dart';
import 'package:material_ui/material_ui.dart';

/// Единый обработчик `Esc` на уровне приложения (находка N3 аудита 1.0).
///
/// `Esc` на Windows означает «системный назад»: закрывает текущий диалог,
/// лист, меню или полноэкранный маршрут ровно так же, как кнопка «назад», и
/// проходит через `PopScope` экрана. Раньше `Esc` не работал ни на одном
/// экране — клавиатурный пользователь не мог выйти из сессии или генерации.
///
/// Обработчик ставится **над** `Navigator`, поэтому получает клавишу раньше
/// виджетов маршрута: диалог/лист закрывается `maybePop`, а `PopScope` сессии
/// открывает свой диалог подтверждения, а не теряет прогресс.
///
/// `Esc` не перехватывается, если закрывать нечего (`canPop == false`): на
/// корневой ветке оболочки клавиша остаётся свободной для будущих сценариев.
class EscapeToBack extends StatefulWidget {
  /// Оборачивает приложение.
  const EscapeToBack({required this.child, this.navigatorKey, super.key});

  /// Дерево приложения (обычно `Navigator`).
  final Widget child;

  /// Ключ навигатора приложения; нужен, потому что виджет стоит выше него.
  final GlobalKey<NavigatorState>? navigatorKey;

  @override
  State<EscapeToBack> createState() => _EscapeToBackState();
}

class _EscapeToBackState extends State<EscapeToBack> {
  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_handleKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_handleKey);
    super.dispose();
  }

  bool _handleKey(KeyEvent event) {
    if (event is! KeyDownEvent) return false;
    if (event.logicalKey != LogicalKeyboardKey.escape) return false;
    final NavigatorState? navigator =
        widget.navigatorKey?.currentState ?? Navigator.maybeOf(context);
    if (navigator == null || !navigator.canPop()) return false;
    navigator.maybePop();
    return true;
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
