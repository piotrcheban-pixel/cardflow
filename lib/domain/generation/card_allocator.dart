/// Card Allocator: распределение заказа по разделам по смысловой насыщенности
/// (ADR-040 §5).
///
/// Детерминированный water-filling: `weight = meaningfulTokens^0.8 × density`,
/// `capacity = ceil(meaningfulWords / 40 × density)`, метод наибольших остатков
/// с ограничением ёмкостью; `Σ = min(requested, Σcapacity)`. Служебные разделы
/// получают 0. Домен не зависит от Flutter.
library;

import 'package:cardflow/domain/generation/input_planner.dart' show SectionKind;
export 'package:cardflow/domain/generation/input_planner.dart' show SectionKind;

/// Раздел для распределения карточек.
final class AllocationSection {
  /// Создаёт раздел распределения.
  const AllocationSection({
    required this.id,
    this.title = '',
    this.weight = 1,
    this.capacity,
    this.kind = SectionKind.content,
    this.meaningfulTokens = 0,
    this.density = 1,
  }) : assert(id != ''),
       assert(weight >= 0),
       assert(capacity == null || capacity >= 0);

  /// Стабильный id раздела.
  final String id;

  /// Заголовок (для совпадений с пожеланиями).
  final String title;

  /// Вес раздела (`meaningfulTokens^0.8 × density`, с поправкой на пожелания).
  final double weight;

  /// Мягкая ёмкость (сколько разных фактов можно извлечь); `null` — без предела.
  final int? capacity;

  /// Служебный или содержательный раздел.
  final SectionKind kind;

  /// Значимые токены раздела.
  final int meaningfulTokens;

  /// Насыщенность `[0.5, 1.5]` (0 у служебных).
  final double density;
}

/// Результат распределения карточек по разделам.
final class CardAllocation {
  /// Создаёт распределение.
  CardAllocation({
    required Map<String, int> planned,
    required this.requested,
    required this.achievable,
    required this.belowRequested,
  }) : planned = Map<String, int>.unmodifiable(planned);

  /// Карточки по разделам (`id → число`), без отрицательных значений.
  final Map<String, int> planned;

  /// Заказ пользователя (`null` — «авто»).
  final int? requested;

  /// Сумма распределённых карточек.
  final int achievable;

  /// true, если материала не хватает на заказ.
  final bool belowRequested;

  /// Карточки, выделенные разделу (0, если раздела нет).
  int forSection(String id) => planned[id] ?? 0;

  /// Сумма распределённых карточек.
  int get total => achievable;

  /// Разделы, получившие хотя бы одну карточку, в порядке передачи.
  List<String> get sectionsWithCards => List<String>.unmodifiable(<String>[
    for (final MapEntry<String, int> entry in planned.entries)
      if (entry.value > 0) entry.key,
  ]);

  @override
  String toString() =>
      'CardAllocation(total: $achievable, requested: ${requested ?? 'auto'}, '
      'below: $belowRequested)';
}

/// Распределяет заказ карточек между разделами.
final class CardAllocator {
  /// Создаёт распределитель.
  const CardAllocator();

  /// Распределяет [requestedCards] между [sections].
  ///
  /// `requestedCards == null` — «авто»: каждый раздел получает свою ёмкость.
  CardAllocation allocate({
    required List<AllocationSection> sections,
    int? requestedCards,
  }) {
    // RED-фаза итерации 7.18: контракт зафиксирован, алгоритм — следующий шаг.
    return CardAllocation(
      planned: <String, int>{for (final AllocationSection s in sections) s.id: 0},
      requested: requestedCards,
      achievable: 0,
      belowRequested: false,
    );
  }
}
