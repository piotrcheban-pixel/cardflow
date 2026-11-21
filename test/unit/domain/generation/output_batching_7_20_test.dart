import 'package:cardflow/domain/generation/card_allocator.dart';
import 'package:cardflow/domain/generation/generation_planning_config.dart';
import 'package:cardflow/domain/generation/input_planner.dart';
import 'package:cardflow/domain/generation/model_limits.dart';
import 'package:cardflow/domain/generation/output_batch_planner.dart';
import 'package:flutter_test/flutter_test.dart';

/// Итерация 7.20: партии ограничены вместимостью **одного** ответа, сумма
/// партий равна заказу.
///
/// Вместимость задаётся бюджетом вывода запроса: `cardsFor(maxTokens)` при
/// `tokensPerCard = 300`, `outputFill = 0.85`, `schemaOverhead = 200`
/// (`GenerationPlanningConfig`). Пустой запрос к модели здесь не выполняется.
void main() {
  const GenerationPlanningConfig config = GenerationPlanningConfig();

  ModelLimits limits({int maxOutput = 200000}) => ModelLimits(
    contextTokens: Sourced<int>(
      1000000,
      source: CapabilitySource.officialCatalog,
    ),
    contextSemantics: ContextSemantics.totalInputPlusOutput,
    maxOutputTokens: Sourced<int>(
      maxOutput,
      source: CapabilitySource.officialCatalog,
    ),
  );

  /// План входа с заданным резервом вывода (одна «документная» часть).
  InputPlan inputWith({
    required int maxTokens,
    int sections = 4,
    bool promptOnly = false,
  }) => const InputPlanner().plan(
    sections: promptOnly
        ? const <InputSection>[]
        : <InputSection>[
            for (var index = 0; index < sections; index++)
              InputSection(
                id: 's$index',
                shortId: 's$index',
                title: 'Раздел $index',
                tokens: 300,
                text: 'Текст раздела $index.',
              ),
          ],
    limits: limits(),
    fixedTokens: 1000,
    desiredOutputTokens: maxTokens,
  );

  CardAllocation allocationOf(int total) => CardAllocation(
    planned: <String, int>{'s0': total},
    requested: total,
    achievable: total,
    belowRequested: false,
    estimatedCapacity: total,
  );

  List<PlannedBatch> batchesFor({
    required int requested,
    required int maxTokens,
    int? maxCardsPerRequest,
    int reasoningReserveTokens = 0,
    GenerationPlanningConfig planning = config,
  }) => OutputBatchPlanner(config: planning).plan(
    input: inputWith(maxTokens: maxTokens),
    allocation: allocationOf(requested),
    maxTokensPerBatch: maxTokens,
    maxCardsPerRequest: maxCardsPerRequest,
    reasoningReserveTokens: reasoningReserveTokens,
  );

  List<int> sizes(List<PlannedBatch> batches) =>
      batches.map((PlannedBatch batch) => batch.limit).toList();

  int total(List<PlannedBatch> batches) =>
      batches.fold<int>(0, (int sum, PlannedBatch b) => sum + b.limit);

  group('обязательные примеры задания 7.20 §3', () {
    test('заказ 40, вместимость 16 → 3 партии, сумма 40', () {
      // cardsFor(6000) = floor((6000 × 0.85 − 200) / 300) = 16.
      final List<PlannedBatch> batches = batchesFor(
        requested: 40,
        maxTokens: 6000,
      );
      expect(batches, hasLength(3));
      expect(sizes(batches), <int>[16, 16, 8]);
      expect(total(batches), 40);
      for (final PlannedBatch batch in batches) {
        expect(batch.limit, lessThanOrEqualTo(16));
        expect(batch.limit, greaterThanOrEqualTo(1));
      }
    });

    test('заказ 100, вместимость 12 → 9 партий (12×8 + 4)', () {
      // cardsFor(4600) = floor((4600 × 0.85 − 200) / 300) = 12.
      final List<PlannedBatch> batches = batchesFor(
        requested: 100,
        maxTokens: 4600,
      );
      expect(batches, hasLength(9));
      expect(sizes(batches), <int>[12, 12, 12, 12, 12, 12, 12, 12, 4]);
      expect(total(batches), 100);
      expect(
        batches.every((PlannedBatch batch) => batch.limit <= 12),
        isTrue,
        reason: 'ни одна партия не превышает вместимость одного ответа',
      );
    });

    test('заказ 200, вместимость 20 → 10 партий по 20', () {
      // cardsFor(7400) = floor((7400 × 0.85 − 200) / 300) = 20.
      final List<PlannedBatch> batches = batchesFor(
        requested: 200,
        maxTokens: 7400,
      );
      expect(batches, hasLength(10));
      expect(sizes(batches), List<int>.filled(10, 20));
      expect(total(batches), 200);
    });

    test('заказ 1 и вместимость 16 → ровно один запрос', () {
      final List<PlannedBatch> batches = batchesFor(
        requested: 1,
        maxTokens: 6000,
      );
      expect(batches, hasLength(1));
      expect(sizes(batches), <int>[1]);
    });

    test('заказ 16 и вместимость 16 → ровно один запрос', () {
      final List<PlannedBatch> batches = batchesFor(
        requested: 16,
        maxTokens: 6000,
      );
      expect(batches, hasLength(1));
      expect(sizes(batches), <int>[16]);
    });

    test('заказ 17 и вместимость 16 → 2 запроса (16 + 1)', () {
      final List<PlannedBatch> batches = batchesFor(
        requested: 17,
        maxTokens: 6000,
      );
      expect(batches, hasLength(2));
      expect(sizes(batches), <int>[16, 1]);
      expect(total(batches), 17);
    });
  });

  group('свойства партий', () {
    for (final int requested in <int>[1, 5, 10, 20, 40, 50, 100, 200, 500]) {
      for (final int maxTokens in <int>[2500, 4600, 6000, 7400, 12000]) {
        test('заказ $requested при бюджете $maxTokens: сумма, минимум, '
            'максимум и отсутствие лишнего запроса', () {
          final List<PlannedBatch> batches = batchesFor(
            requested: requested,
            maxTokens: maxTokens,
          );
          final int perBatch = const OutputBatchPlanner().cardsPerBatch(
            inputWith(maxTokens: maxTokens).maxTokens,
          );
          expect(perBatch, greaterThanOrEqualTo(1));
          expect(total(batches), requested);
          expect(
            batches.length,
            (requested + perBatch - 1) ~/ perBatch,
            reason: 'число партий — ⌈заказ / вместимость⌉, без лишних запросов',
          );
          for (final PlannedBatch batch in batches) {
            expect(batch.limit, greaterThanOrEqualTo(1));
            expect(batch.limit, lessThanOrEqualTo(perBatch));
          }
          expect(
            batches.every((PlannedBatch batch) => batch.partCount == 1),
            isTrue,
            reason: 'партии не дробят вход',
          );
        });
      }
    }

    test('максимально допустимый заказ: 512 партий по 16 = 8192 карточки', () {
      final List<PlannedBatch> batches = batchesFor(
        requested: 8192,
        maxTokens: 6000,
      );
      expect(batches, hasLength(512));
      expect(total(batches), 8192);
    });

    test('заказ ровно кратен вместимости → нет лишней партии', () {
      for (final int multiplier in <int>[1, 2, 3, 8]) {
        final List<PlannedBatch> batches = batchesFor(
          requested: 12 * multiplier,
          maxTokens: 4600,
        );
        expect(batches, hasLength(multiplier));
        expect(total(batches), 12 * multiplier);
      }
    });

    test(
      'batchSizesFor: карточки не теряются при недостаточном числе партий',
      () {
        // Ревью 7.20 (R1): если число партий меньше ⌈total / cap⌉, размеры
        // поднимаются до минимально нужного — сумма остаётся равной заказу.
        expect(OutputBatchPlanner.batchSizesFor(10, 2, 3), <int>[
          3,
          3,
          3,
          1,
        ], reason: 'две партии по 3 не вмещают 10 карточек — нужно четыре');
        expect(
          OutputBatchPlanner.batchSizesFor(
            10,
            2,
            3,
          ).fold<int>(0, (int sum, int value) => sum + value),
          10,
        );
        // Больше партий, чем нужно по бюджету (раскладка изображений): сумма
        // сохраняется, каждая партия не больше вместимости.
        for (final int count in <int>[5, 7, 12]) {
          final List<int> sizes = OutputBatchPlanner.batchSizesFor(
            23,
            count,
            5,
          );
          expect(sizes.length, count);
          expect(sizes.fold<int>(0, (int sum, int value) => sum + value), 23);
          expect(sizes.every((int size) => size >= 1 && size <= 5), isTrue);
        }
      },
    );
  });

  group('изменение бюджета меняет партии, но не заказ', () {
    test('maxOutputTokens 2000…64000: сумма одна, партий больше/меньше', () {
      for (final int requested in <int>[40, 100, 200]) {
        final List<int> totals = <int>[];
        final List<int> counts = <int>[];
        for (final int maxTokens in <int>[2500, 4600, 6000, 7400, 12000]) {
          final List<PlannedBatch> batches = batchesFor(
            requested: requested,
            maxTokens: maxTokens,
          );
          totals.add(total(batches));
          counts.add(batches.length);
        }
        expect(totals.toSet(), <int>{
          requested,
        }, reason: 'заказ $requested не зависит от бюджета ответа');
        expect(
          counts.toSet().length,
          greaterThan(1),
          reason: 'бюджет ответа меняет только число партий',
        );
      }
    });

    test('reasoningReserveTokens: партий больше, заказ тот же', () {
      final List<PlannedBatch> without = batchesFor(
        requested: 100,
        maxTokens: 12000,
      );
      final List<PlannedBatch> withReserve = batchesFor(
        requested: 100,
        maxTokens: 12000,
        reasoningReserveTokens: 4000,
      );
      final int perBatchWithReserve = const OutputBatchPlanner().cardsPerBatch(
        12000,
        reasoningReserveTokens: 4000,
      );
      expect(perBatchWithReserve, 22);
      expect(total(withReserve), 100);
      expect(total(without), 100);
      expect(withReserve.length, greaterThan(without.length));
      expect(
        withReserve.every(
          (PlannedBatch batch) => batch.limit <= perBatchWithReserve,
        ),
        isTrue,
        reason: 'резерв рассуждения уменьшает партию, но не заказ',
      );
    });

    test('batchCardsCeiling: потолок партии, не потолок заказа', () {
      final List<PlannedBatch> wide = batchesFor(
        requested: 100,
        maxTokens: 12000,
      );
      final List<PlannedBatch> narrow = batchesFor(
        requested: 100,
        maxTokens: 12000,
        planning: config.copyWith(batchCardsCeiling: 10, minBatchCards: 5),
      );
      expect(total(wide), 100);
      expect(total(narrow), 100);
      expect(narrow.length, greaterThan(wide.length));
      expect(narrow.every((PlannedBatch batch) => batch.limit <= 10), isTrue);
    });

    test('maxCardsPerRequest ограничивает партию, но не заказ', () {
      final List<PlannedBatch> batches = batchesFor(
        requested: 100,
        maxTokens: 12000,
        maxCardsPerRequest: 4,
      );
      expect(total(batches), 100);
      expect(batches.every((PlannedBatch batch) => batch.limit <= 4), isTrue);
      expect(batches, hasLength(25));
    });
  });

  group('prompt-only: та же арифметика партий', () {
    test('заказ 40, бюджет 7 карточек на ответ → 6 партий, сумма 40', () {
      final InputPlan plan = inputWith(maxTokens: 6000, promptOnly: true);
      final List<PlannedBatch> batches = OutputBatchPlanner().plan(
        input: plan,
        allocation: allocationOf(0),
        maxTokensPerBatch: plan.maxTokens,
        promptOnlyRequestedCards: 40,
        maxCardsPerRequest: 7,
      );
      expect(batches, hasLength(6));
      expect(total(batches), 40);
      expect(batches.first.partIndex, -1);
      expect(batches.first.partCount, 0);
    });
  });
}
