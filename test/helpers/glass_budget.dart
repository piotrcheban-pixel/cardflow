import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// Бюджет стекла (REDESIGN-SPEC §4.4, §11): одновременно на экране не больше
/// двух групп `BackdropFilter` (+1 модальная). Тест каждого экрана зовёт
/// [expectGlassBudget]; компоненты стекла — тоже (одиночный `NcGlass` = 1).

/// Сколько фильтров и групп стекла сейчас в дереве.
@immutable
class NcGlassBudget {
  /// Создаёт снимок бюджета.
  const NcGlassBudget({
    required this.filters,
    required this.groups,
    required this.ungrouped,
  });

  /// Всего `BackdropFilter` (размытие — самая дорогая часть).
  final int filters;

  /// Различные группы `BackdropGroup`, к которым относятся фильтры.
  final int groups;

  /// Фильтры без `BackdropGroup` (каждый считается отдельной группой).
  final int ungrouped;

  /// Итоговое число групп: общие `BackdropGroup` + одиночные фильтры.
  int get totalGroups => groups + ungrouped;

  @override
  String toString() =>
      'NcGlassBudget(filters: $filters, groups: $groups, '
      'ungrouped: $ungrouped)';
}

/// Считает фильтры стекла и их группы в текущем дереве.
NcGlassBudget measureGlassBudget(WidgetTester tester) {
  final Finder filters = find.byType(BackdropFilter);
  final Set<BackdropKey> groups = <BackdropKey>{};
  var ungrouped = 0;
  var filtersCount = 0;
  for (final Element element in filters.evaluate()) {
    filtersCount++;
    final BackdropGroup? group = element
        .findAncestorWidgetOfExactType<BackdropGroup>();
    if (group == null) {
      ungrouped++;
    } else {
      groups.add(group.backdropKey);
    }
  }
  return NcGlassBudget(
    filters: filtersCount,
    groups: groups.length,
    ungrouped: ungrouped,
  );
}

/// Проверяет бюджет стекла: не больше [maxGroups] групп на экран.
///
/// [maxGroups] — общий лимит; экран с открытым модальным слоем передаёт 3
/// (§4.4: «+1 модальная»).
void expectGlassBudget(WidgetTester tester, {int maxGroups = 2}) {
  final NcGlassBudget budget = measureGlassBudget(tester);
  expect(
    budget.totalGroups,
    lessThanOrEqualTo(maxGroups),
    reason:
        'Бюджет стекла превышен (${budget.totalGroups} > $maxGroups): '
        'подробности — $budget',
  );
}

/// Стекло вообще не должно появляться (например, повышенный контраст).
void expectNoGlass(WidgetTester tester) {
  expect(
    find.byType(BackdropFilter),
    findsNothing,
    reason: 'Стекло запрещено на этом экране/в этом состоянии (§4.3–4.4)',
  );
}
