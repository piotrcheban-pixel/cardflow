import 'package:cardflow/domain/text/normalization.dart';

/// Поиск/фильтр списка колод (SPEC A6.2, семантика — ADR-007).
enum DeckFilter {
  /// Все активные колоды.
  all,

  /// Колоды, где есть хотя бы одна новая карточка.
  withNewCards,

  /// Колоды, где есть хотя бы одна карточка в процессе изучения.
  inProgress,

  /// Колоды, где есть хотя бы одна просроченная карточка.
  due,
}

/// Параметры выборки списка колод.
///
/// Неизменяемый: UI-слой создаёт новый запрос при вводе поиска/смене чипа.
class DeckQuery {
  /// Создаёт параметры выборки.
  const DeckQuery({
    this.search = '',
    this.filter = DeckFilter.all,
    this.includeArchived = false,
  });

  /// Строка поиска по имени колоды (нормализуется при сравнении).
  final String search;

  /// Активный фильтр.
  final DeckFilter filter;

  /// Показывать ли архивные колоды (в основной список — нет).
  final bool includeArchived;

  /// Нормализованная строка поиска.
  String get normalizedSearch => normalizeForComparison(search);

  /// Признак «поиск не активен».
  bool get isEmptySearch => normalizedSearch.isEmpty;

  /// Копия с заменой полей.
  DeckQuery copyWith({
    String? search,
    DeckFilter? filter,
    bool? includeArchived,
  }) {
    return DeckQuery(
      search: search ?? this.search,
      filter: filter ?? this.filter,
      includeArchived: includeArchived ?? this.includeArchived,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is DeckQuery &&
        other.search == search &&
        other.filter == filter &&
        other.includeArchived == includeArchived;
  }

  @override
  int get hashCode => Object.hash(search, filter, includeArchived);

  @override
  String toString() =>
      'DeckQuery(search: "$search", filter: $filter, '
      'includeArchived: $includeArchived)';
}
