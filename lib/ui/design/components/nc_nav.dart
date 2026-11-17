import 'package:material_ui/material_ui.dart';

/// Навигация Nocturne (REDESIGN-SPEC §8, §9.1): док на телефоне, рейл на
/// планшете, расширенный сайдбар на ПК.
///
/// Компоненты не знают о `GoRouter`: индексы и обработчик приходят от
/// оболочки (`AppShell`), ключи пунктов — контракт экранных тестов.

/// Пункт навигации.
@immutable
class NcNavItem {
  /// Создаёт пункт.
  const NcNavItem({
    required this.key,
    required this.icon,
    required this.selectedIcon,
    required this.label,
  });

  /// Ключ пункта (`shell-nav-*`, контракт REDESIGN-SPEC §9.1).
  final Key key;

  /// Иконка в покое.
  final IconData icon;

  /// Залитая иконка активного пункта.
  final IconData selectedIcon;

  /// Подпись (ARB).
  final String label;
}

/// Телефонный док (`< 600 px`): парящая pill-капсула со тремя пунктами.
class NcNavDock extends StatelessWidget {
  /// Создаёт док.
  const NcNavDock({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    this.semanticLabel,
  });

  /// Пункты.
  final List<NcNavItem> items;

  /// Активный пункт.
  final int selectedIndex;

  /// Выбор пункта.
  final ValueChanged<int> onSelected;

  /// Текст семантики панели.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// Планшетный рейл (`600–1023 px`): 80 px слева на стекле.
class NcNavRail extends StatelessWidget {
  /// Создаёт рейл.
  const NcNavRail({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    this.semanticLabel,
  });

  /// Пункты.
  final List<NcNavItem> items;

  /// Активный пункт.
  final int selectedIndex;

  /// Выбор пункта.
  final ValueChanged<int> onSelected;

  /// Текст семантики панели.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}

/// ПК-сайдбар (`≥ 1024 px`): 248 px, логотип и название, пункты строками.
class NcNavSidebar extends StatelessWidget {
  /// Создаёт сайдбар.
  const NcNavSidebar({
    super.key,
    required this.items,
    required this.selectedIndex,
    required this.onSelected,
    required this.appName,
    this.semanticLabel,
  });

  /// Пункты.
  final List<NcNavItem> items;

  /// Активный пункт.
  final int selectedIndex;

  /// Выбор пункта.
  final ValueChanged<int> onSelected;

  /// Название приложения (Literata `titleL`).
  final String appName;

  /// Текст семантики панели.
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) => const SizedBox.shrink();
}
