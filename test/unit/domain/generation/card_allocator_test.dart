import 'package:cardflow/domain/generation/card_allocator.dart';
import 'package:flutter_test/flutter_test.dart';

/// §5.2 задания 7.18: распределение карточек между разделами.
void main() {
  const CardAllocator allocator = CardAllocator();

  AllocationSection section(
    String id, {
    double weight = 1,
    int? capacity,
    SectionKind kind = SectionKind.content,
  }) => AllocationSection(
    id: id,
    weight: weight,
    capacity: capacity,
    kind: kind,
  );

  List<AllocationSection> five({
    List<double> weights = const <double>[1, 3, 2, 3, 1],
    List<int?> capacities = const <int?>[null, null, null, null, null],
  }) => <AllocationSection>[
    for (var index = 0; index < 5; index++)
      section('s$index', weight: weights[index], capacity: capacities[index]),
  ];

  List<int> values(CardAllocation allocation) => <int>[
    for (final AllocationSection s in five())
      allocation.forSection(s.id),
  ];

  group('§5.2 распределение', () {
    test('веса 1:3:2:3:1, ёмкость ∞, заказ 50 → 5/15/10/15/5', () {
      final CardAllocation allocation = allocator.allocate(
        sections: five(),
        requestedCards: 50,
      );
      expect(allocation.achievable, 50);
      expect(allocation.belowRequested, isFalse);
      expect(values(allocation), <int>[5, 15, 10, 15, 5]);
    });

    test('те же веса, ёмкость первого 3 → 3/16/10/16/5', () {
      final CardAllocation allocation = allocator.allocate(
        sections: five(
          capacities: const <int?>[3, 20, 20, 20, 20],
        ),
        requestedCards: 50,
      );
      expect(allocation.achievable, 50);
      expect(
        values(allocation),
        <int>[3, 16, 10, 16, 5],
        reason: 'остаток после фиксации ёмкости перераспределяется по весам',
      );
    });

    test('ёмкости 3/6/5/6/2, заказ 50 → achievable 22, предупреждение', () {
      final CardAllocation allocation = allocator.allocate(
        sections: five(
          capacities: const <int?>[3, 6, 5, 6, 2],
        ),
        requestedCards: 50,
      );
      expect(allocation.achievable, 22);
      expect(allocation.belowRequested, isTrue);
      expect(values(allocation), <int>[3, 6, 5, 6, 2]);
    });

    test('служебный раздел → 0, маленький насыщенный не теряется', () {
      final CardAllocation allocation = allocator.allocate(
        sections: <AllocationSection>[
          section('toc', weight: 100, kind: SectionKind.service),
          section('refs', weight: 100, kind: SectionKind.service),
          section('big', weight: 100, capacity: 100),
          section('small', weight: 0.5, capacity: 2),
        ],
        requestedCards: 10,
      );
      expect(allocation.forSection('toc'), 0);
      expect(allocation.forSection('refs'), 0);
      expect(allocation.forSection('big'), greaterThan(0));
      expect(
        allocation.forSection('small'),
        greaterThanOrEqualTo(1),
        reason: 'при заказе ≥ числа значимых разделов каждому минимум 1',
      );
      expect(allocation.achievable, 10);
    });
  });

  group('§5.2 свойства', () {
    for (final int requested in <int>[1, 5, 10, 50, 100]) {
      test('заказ $requested: сумма, неотрицательность, детерминизм', () {
        final List<AllocationSection> sections = five(
          capacities: const <int?>[3, 20, 20, 20, 20],
        );
        final CardAllocation first = allocator.allocate(
          sections: sections,
          requestedCards: requested,
        );
        final CardAllocation second = allocator.allocate(
          sections: sections,
          requestedCards: requested,
        );
        expect(
          first.achievable,
          requested < 63 ? requested : 63,
          reason: 'Σ = min(requested, Σcapacity)',
        );
        expect(first.planned, second.planned, reason: 'детерминизм');
        for (final int value in first.planned.values) {
          expect(value, greaterThanOrEqualTo(0));
        }
      });
    }

    test('заказ больше ёмкостей → сумма равна сумме ёмкостей', () {
      final List<AllocationSection> sections = five(
        capacities: const <int?>[3, 6, 5, 6, 2],
      );
      final CardAllocation allocation = allocator.allocate(
        sections: sections,
        requestedCards: 1000000,
      );
      expect(allocation.achievable, 22);
      expect(allocation.belowRequested, isTrue);
    });

    test('«авто» (null) → каждый раздел получает ёмкость', () {
      final CardAllocation allocation = allocator.allocate(
        sections: five(capacities: const <int?>[3, 6, 5, 6, 2]),
      );
      expect(allocation.achievable, 22);
      expect(values(allocation), <int>[3, 6, 5, 6, 2]);
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

    test('пустой список разделов → пустое распределение', () {
      final CardAllocation allocation = allocator.allocate(
        sections: const <AllocationSection>[],
        requestedCards: 10,
      );
      expect(allocation.achievable, 0);
      expect(allocation.planned, isEmpty);
    });
  });
}
