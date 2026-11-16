import 'package:material_ui/material_ui.dart';

/// Состояние «прокрутка вниз → компактный хром» для `NcFab` и `NcTopBar`
/// (REDESIGN-SPEC §8, §9.2).
///
/// Оборачивает прокручиваемую область, слушает `ScrollNotification` и
/// сообщает вниз, что контент уехал вниз ([collapsed]) или вернулся к началу.
/// Сами компоненты не знают о `ScrollController` экрана.
class NcScrollCollapseScope extends StatefulWidget {
  /// Оборачивает прокручиваемую область.
  const NcScrollCollapseScope({super.key, required this.child});

  /// Прокручиваемая область (обычно `CustomScrollView`/`ListView`).
  final Widget child;

  @override
  State<NcScrollCollapseScope> createState() => _NcScrollCollapseScopeState();
}

class _NcScrollCollapseScopeState extends State<NcScrollCollapseScope> {
  bool _collapsed = false;

  bool _onNotification(ScrollNotification notification) {
    if (notification.depth != 0) return false;
    if (notification is ScrollUpdateNotification) {
      final double delta = notification.scrollDelta ?? 0;
      final bool next = notification.metrics.pixels > 8
          ? (delta > 0.5 ? true : (delta < -0.5 ? false : _collapsed))
          : false;
      if (next != _collapsed) setState(() => _collapsed = next);
    } else if (notification is ScrollEndNotification &&
        notification.metrics.pixels <= 8 &&
        _collapsed) {
      setState(() => _collapsed = false);
    }
    return false;
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollNotification>(
        onNotification: _onNotification,
        child: _NcScrollCollapseState(
          collapsed: _collapsed,
          child: widget.child,
        ),
      );
}

class _NcScrollCollapseState extends InheritedWidget {
  const _NcScrollCollapseState({required this.collapsed, required super.child});

  final bool collapsed;

  @override
  bool updateShouldNotify(_NcScrollCollapseState oldWidget) =>
      oldWidget.collapsed != collapsed;
}

/// Читает состояние прокрутки из ближайшего [NcScrollCollapseScope].
abstract final class NcScrollCollapse {
  /// Свёрнут ли хром (false без scope).
  static bool of(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<_NcScrollCollapseState>()
          ?.collapsed ??
      false;
}
