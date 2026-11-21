import 'package:cardflow/domain/generation/card_allocator.dart';
import 'package:flutter_test/flutter_test.dart';

/// Итерация 7.20: мягкая ёмкость материала — предпочтение распределения,
/// а не потолок заказа.
///
/// До 7.20 `CardAllocator.allocate` считал
/// `target = min(requestedCards, Σ capacity)` и возвращал
/// `belowRequested = true`, поэтому заказ 40 при ёмкости 32 превращался в 32, а
/// UI объяснял это «бюджетом модели» (ARB
/// `generationPlanRequestedAboveAchievable`). Бюджет одного ответа к этой
/// арифметике отношения не имеет: ёмкость — эвристика `words/40 × density`
/// (ADR-040 §5).
void main() {
  const CardAllocator allocator = CardAllocator();

  AllocationSection section(
    String id, {
    double weight = 1,
    int? capacity,
    SectionKind kind = SectionKind.content,
  }) =>
      AllocationSection(id: id, weight: weight, capacity: capacity, kind: kind);

  /// Пять содержательных разделов с заданными ёмкостями.
  List<AllocationSection> five({
    List<int?> capacities = const <int?>[8, 8, 8, 8, 8],
  }) => <AllocationSection>[
    for (var index = 0; index < 5; index++)
      section('s$index', capacity: capacities[index]),
  ];

  int sum(CardAllocation allocation) =>
      allocation.planned.values.fold<int>(0, (int a, int b) => a + b);

  group('7.20: заказ не обрезается мягкой ёмкостью', () {
    test('заказ 40 при ёмкости 32 → в плане 40, ёмкость 32 отдельно', () {
      final CardAllocation allocation = allocator.allocate(
        sections: five(capacities: const <int?>[8, 8, 8, 8, 8]),
        requestedCards: 40,
      );
      expect(allocation.achievable, 40);
      expect(sum(allocation), 40);
      expect(allocation.estimatedCapacity, 32);
      expect(allocation.materialLimited, isTrue);
      expect(
        allocation.belowRequested,
        isFalse,
        reason: 'заказ выполним: план запрашивает его партиями',
      );
      expect(
        allocation.planned.values.where((int value) => value > 0).length,
        5,
        reason: 'весь материал участвует в распределении',
      );
    });

    test('заказ 100 при ёмкости 12 → в плане ровно 100', () {
      final CardAllocation allocation = allocator.allocate(
        sections: five(capacities: const <int?>[3, 3, 2, 2, 2]),
        requestedCards: 100,
      );
      expect(sum(allocation), 100);
      expect(allocation.achievable, 100);
      expect(allocation.estimatedCapacity, 12);
      expect(allocation.materialLimited, isTrue);
    });

    test('заказ 200 при ёмкости 20 → в плане ровно 200', () {
      final CardAllocation allocation = allocator.allocate(
        sections: five(capacities: const <int?>[4, 4, 4, 4, 4]),
        requestedCards: 200,
      );
      expect(sum(allocation), 200);
      expect(allocation.estimatedCapacity, 20);
    });

    test('ёмкости хватает → materialLimited ложно, сумма = заказ', () {
      final CardAllocation allocation = allocator.allocate(
        sections: five(),
        requestedCards: 30,
      );
      expect(sum(allocation), 30);
      expect(allocation.estimatedCapacity, 40);
      expect(allocation.materialLimited, isFalse);
      expect(allocation.belowRequested, isFalse);
    });

    test('нехватка ёмкости не уводит карточки в служебные разделы', () {
      final CardAllocation allocation = allocator.allocate(
        sections: <AllocationSection>[
          section('toc', kind: SectionKind.service),
          section('refs', kind: SectionKind.service),
          section('big', capacity: 4),
          section('small', capacity: 2),
        ],
        requestedCards: 40,
      );
      expect(allocation.forSection('toc'), 0);
      expect(allocation.forSection('refs'), 0);
      expect(sum(allocation), 40);
      expect(allocation.forSection('big') + allocation.forSection('small'), 40);
    });

    test('пустой список содержательных разделов → 0 и belowRequested', () {
      final CardAllocation allocation = allocator.allocate(
        sections: <AllocationSection>[
          section('toc', kind: SectionKind.service),
        ],
        requestedCards: 10,
      );
      expect(allocation.achievable, 0);
      expect(allocation.belowRequested, isTrue);
      expect(allocation.estimatedCapacity, 0);
      expect(allocation.materialLimited, isTrue);
    });

    test('«авто» (заказ не задан) по-прежнему равен ёмкости материала', () {
      final CardAllocation allocation = allocator.allocate(
        sections: five(capacities: const <int?>[3, 6, 5, 6, 2]),
      );
      expect(allocation.requested, isNull);
      expect(allocation.achievable, 22);
      expect(allocation.estimatedCapacity, 22);
      expect(allocation.materialLimited, isFalse);
      expect(allocation.belowRequested, isFalse);
    });

    test('раздел без предела: ёмкость неизвестна, materialLimited ложно', () {
      final CardAllocation allocation = allocator.allocate(
        sections: five(capacities: const <int?>[null, null, null, null, null]),
        requestedCards: 500,
      );
      expect(sum(allocation), 500);
      expect(allocation.estimatedCapacity, isNull);
      expect(allocation.materialLimited, isFalse);
    });
  });

  group('7.20: распределение при достаточной ёмкости не изменилось', () {
    test('веса 1:3:2:3:1, ёмкость ∞, заказ 50 → 5/15/10/15/5', () {
      const List<double> weights = <double>[1, 3, 2, 3, 1];
      final List<AllocationSection> sections = <AllocationSection>[
        for (var index = 0; index < weights.length; index++)
          section('s$index', weight: weights[index]),
      ];
      final CardAllocation allocation = allocator.allocate(
        sections: sections,
        requestedCards: 50,
      );
      expect(allocation.achievable, 50);
      expect(allocation.belowRequested, isFalse);
      expect(
        <int>[
          for (final AllocationSection s in sections)
            allocation.forSection(s.id),
        ],
        <int>[5, 15, 10, 15, 5],
        reason: 'при достаточной ёмкости остаётся прежний water-filling',
      );
    });

    test('заказ 1…20 на ёмкости 100 → заказ целиком, сумма точная', () {
      for (final int requested in <int>[1, 5, 10, 20]) {
        final CardAllocation allocation = allocator.allocate(
          sections: five(),
          requestedCards: requested,
        );
        expect(sum(allocation), requested, reason: 'заказ $requested');
        expect(allocation.materialLimited, isFalse);
      }
    });
  });

  group('7.20: свойства распределения', () {
    for (final int requested in <int>[1, 5, 10, 20, 40, 50, 100, 200, 500]) {
      test(
        'заказ $requested: сумма = заказ, неотрицательность, детерминизм',
        () {
          final List<AllocationSection> sections = five(
            capacities: const <int?>[3, 6, 5, 6, 2],
          );
          final CardAllocation first = allocator.allocate(
            sections: sections,
            requestedCards: requested,
          );
          final CardAllocation second = allocator.allocate(
            sections: sections,
            requestedCards: requested,
          );
          expect(first.achievable, requested);
          expect(sum(first), requested);
          expect(first.estimatedCapacity, 22);
          expect(
            first.materialLimited,
            requested > 22,
            reason: 'статус нехватки материала — только по ёмкости',
          );
          expect(first.planned, second.planned, reason: 'детерминизм');
          for (final int value in first.planned.values) {
            expect(value, greaterThanOrEqualTo(0));
          }
        },
      );
    }

    test('заказ 1 000 000: сумма точная, без переполнения', () {
      final CardAllocation allocation = allocator.allocate(
        sections: five(capacities: const <int?>[3, 6, 5, 6, 2]),
        requestedCards: 1000000,
      );
      expect(allocation.achievable, 1000000);
      expect(sum(allocation), 1000000);
    });

    test('невалидный заказ (0 и отрицательный) → ArgumentError', () {
      expect(
        () => allocator.allocate(sections: five(), requestedCards: 0),
        throwsArgumentError,
      );
      expect(
        () => allocator.allocate(sections: five(), requestedCards: -5),
        throwsArgumentError,
      );
    });
  });
}
