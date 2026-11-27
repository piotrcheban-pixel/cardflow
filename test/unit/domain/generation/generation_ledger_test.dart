import 'dart:math';

import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/domain/generation/generation_chunker.dart';
import 'package:cardflow/domain/generation/generation_ledger.dart';
import 'package:cardflow/domain/generation/generation_plan.dart';

import '../../../helpers/generation_plan_fakes.dart';

/// Срез 2 (TASK.txt): бухгалтерия прогона — запрошено / произведено /
/// отброшено валидацией / дублей / принято / долг по партиям и суммарно,
/// класс недобора. DoD: property «Σ бюджетов == requested на случайных планах»,
/// «ledger после сбоя батча сохраняет принятое».
void main() {
  /// План, у которого лимиты фрагментов равны [budgets].
  GenerationPlan planWithBudgets(List<int> budgets) {
    final int requested = budgets.fold(0, (int sum, int size) => sum + size);
    final List<GenerationChunk> chunks = <GenerationChunk>[
      for (var index = 0; index < budgets.length; index++)
        GenerationChunk(
          index: index + 1,
          materialsText: 'материал ${index + 1}',
          sourceFiles: const <String>[],
          limit: budgets[index],
        ),
    ];
    return testPlanFromChunks(chunks, requestedCards: requested);
  }

  /// Случайное разбиение [total] на [parts] положительных частей.
  List<int> randomSplit(int total, int parts, Random random) {
    expect(parts, inInclusiveRange(1, total));
    final List<int> partsOut = <int>[];
    var left = total;
    for (var index = 0; index < parts - 1; index++) {
      final int maxTake = left - (parts - 1 - index);
      final int take = 1 + random.nextInt(maxTake);
      partsOut.add(take);
      left -= take;
    }
    partsOut.add(left);
    return partsOut;
  }

  group('ShortfallKind', () {
    test('wire-имена классов недобора — как в TASK.txt', () {
      expect(ShortfallKind.values.length, 5);
      expect(
        ShortfallKind.values
            .map((ShortfallKind kind) => kind.wireName)
            .toList(),
        <String>[
          'exhausted_material',
          'provider_error',
          'truncated',
          'validation_rejects',
          'cancelled',
        ],
      );
    });

    test('fromWire разбирает класс недобора и бросает FormatException', () {
      expect(ShortfallKind.fromWire('truncated'), ShortfallKind.truncated);
      expect(
        () => ShortfallKind.fromWire('unknown_kind'),
        throwsFormatException,
      );
    });
  });

  group('GenerationBatchLedger', () {
    test('партия без событий: долг равен бюджету, класса недобора ещё нет', () {
      const batch = GenerationBatchLedger.budget(batchIndex: 0, requested: 5);
      expect(batch.batchIndex, 0);
      expect(batch.requested, 5);
      expect(batch.generated, 0);
      expect(batch.invalid, 0);
      expect(batch.duplicates, 0);
      expect(batch.accepted, 0);
      expect(batch.remaining, 5);
      expect(batch.hasDebt, isTrue);
      expect(batch.cause, isNull);
      expect(
        batch.shortfall,
        isNull,
        reason: 'событий не было — причина неизвестна',
      );
    });

    test('принятое = произведено − валидация − дубли; долг уменьшается', () {
      const GenerationBatchLedger batch = GenerationBatchLedger.budget(
        batchIndex: 2,
        requested: 6,
      );
      final GenerationBatchLedger filled = batch.record(
        generated: 5,
        invalid: 1,
        duplicates: 1,
      );
      expect(filled.batchIndex, 2);
      expect(filled.generated, 5);
      expect(filled.invalid, 1);
      expect(filled.duplicates, 1);
      expect(filled.accepted, 3);
      expect(filled.remaining, 3);
      expect(filled.shortfall, ShortfallKind.validationRejects);

      final GenerationBatchLedger more = filled.record(
        generated: 3,
        duplicates: 1,
      );
      expect(more.generated, 8);
      expect(more.accepted, 5);
      expect(more.remaining, 1);
    });

    test('переполнение партии: принято больше бюджета, долга нет', () {
      final GenerationBatchLedger batch = const GenerationBatchLedger.budget(
        batchIndex: 0,
        requested: 2,
      ).record(generated: 5);
      expect(batch.accepted, 5);
      expect(batch.remaining, 0);
      expect(batch.hasDebt, isFalse);
      expect(batch.shortfall, isNull);
    });

    test('явная причина важнее выведенной из чисел', () {
      final GenerationBatchLedger batch = const GenerationBatchLedger.budget(
        batchIndex: 0,
        requested: 4,
      ).record(generated: 3, invalid: 1);
      expect(
        batch.shortfall,
        ShortfallKind.validationRejects,
        reason: 'выведено из invalid',
      );
      expect(
        batch.withCause(ShortfallKind.truncated).shortfall,
        ShortfallKind.truncated,
      );
      expect(
        batch.withCause(ShortfallKind.providerError).shortfall,
        ShortfallKind.providerError,
      );
      expect(
        batch.withCause(ShortfallKind.cancelled).shortfall,
        ShortfallKind.cancelled,
      );
    });

    test('короткая, но без ошибок партия — материал исчерпан', () {
      final GenerationBatchLedger batch = const GenerationBatchLedger.budget(
        batchIndex: 0,
        requested: 5,
      ).record(generated: 2);
      expect(batch.remaining, 3);
      expect(batch.shortfall, ShortfallKind.exhaustedMaterial);
      expect(
        batch.withCause(ShortfallKind.exhaustedMaterial).shortfall,
        ShortfallKind.exhaustedMaterial,
      );
    });

    test('нарушения инвариантов — AssertionError', () {
      expect(
        () => GenerationBatchLedger(batchIndex: 0, requested: -1),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => GenerationBatchLedger(
          batchIndex: 0,
          requested: 3,
          generated: 1,
          invalid: 1,
          duplicates: 1,
        ),
        throwsA(isA<AssertionError>()),
        reason: 'валидация и дубли не могут вместе превысить произведённое',
      );
      expect(
        () => const GenerationBatchLedger.budget(
          batchIndex: 0,
          requested: 3,
        ).record(generated: -1),
        throwsA(isA<AssertionError>()),
      );
    });

    test('toString содержит числа партии', () {
      final GenerationBatchLedger batch = const GenerationBatchLedger.budget(
        batchIndex: 1,
        requested: 4,
      ).record(generated: 2, invalid: 1);
      final String text = batch.toString();
      expect(text, contains('партия 1'));
      expect(text, contains('2/4'));
      expect(text, contains('принято 1'));
    });
  });

  group('GenerationLedger', () {
    test('пустой журнал: запрошено 0, долга нет, класса нет', () {
      final GenerationLedger ledger = GenerationLedger.empty();
      expect(ledger.batches, isEmpty);
      expect(ledger.requested, 0);
      expect(ledger.generated, 0);
      expect(ledger.invalid, 0);
      expect(ledger.duplicates, 0);
      expect(ledger.accepted, 0);
      expect(ledger.remaining, 0);
      expect(ledger.hasDebt, isFalse);
      expect(ledger.shortfall, isNull);
      expect(ledger.batch(0), isNull);
      expect(ledger.toString(), contains('партий 0'));
    });

    test(
      'fromBudgets: requested — сумма бюджетов, партии нумеруются по порядку',
      () {
        final GenerationLedger ledger = GenerationLedger.fromBudgets(
          const <int>[4, 6, 0],
        );
        expect(ledger.batches.length, 3);
        expect(
          ledger.batches
              .map((GenerationBatchLedger batch) => batch.batchIndex)
              .toList(),
          <int>[0, 1, 2],
        );
        expect(
          ledger.batches
              .map((GenerationBatchLedger batch) => batch.requested)
              .toList(),
          <int>[4, 6, 0],
        );
        expect(ledger.requested, 10);
        expect(ledger.remaining, 10);
        expect(ledger.batch(1)?.requested, 6);
        expect(ledger.batch(3), isNull);
      },
    );

    test('события партий суммируются в итоги', () {
      var ledger = GenerationLedger.fromBudgets(const <int>[5, 5]);
      ledger = ledger.record(0, generated: 4, invalid: 1);
      ledger = ledger.record(1, generated: 3, duplicates: 1);
      expect(ledger.batch(0)?.accepted, 3);
      expect(ledger.batch(1)?.accepted, 2);
      expect(ledger.generated, 7);
      expect(ledger.invalid, 1);
      expect(ledger.duplicates, 1);
      expect(ledger.accepted, 5);
      expect(ledger.remaining, 5);
      expect(ledger.shortfall, ShortfallKind.validationRejects);
    });

    test('DoD: после сбоя батча принятое сохраняется', () {
      var ledger = GenerationLedger.fromBudgets(const <int>[6, 6]);
      ledger = ledger.record(0, generated: 4, invalid: 1);
      expect(ledger.accepted, 3);

      // Вторая партия упала у провайдера: принятое первой партии не теряется.
      ledger = ledger.markCause(1, ShortfallKind.providerError);
      expect(ledger.batch(0)?.accepted, 3);
      expect(ledger.accepted, 3);
      expect(ledger.batch(1)?.accepted, 0);
      expect(ledger.batch(1)?.remaining, 6);
      expect(ledger.remaining, 9);
      expect(ledger.hasDebt, isTrue);
      expect(ledger.shortfall, ShortfallKind.providerError);

      // Повторная запись упавшей партии не стирает принятое в другой.
      ledger = ledger.replace(
        ledger.batch(1)!.withCause(ShortfallKind.truncated),
      );
      expect(ledger.batch(0)?.accepted, 3);
      expect(ledger.batch(1)?.shortfall, ShortfallKind.truncated);
    });

    test('приоритет класса недобора прогона', () {
      GenerationLedger ledgerWith(List<ShortfallKind?> kinds) {
        var ledger = GenerationLedger.fromBudgets(
          List<int>.filled(kinds.length, 4),
        );
        for (var index = 0; index < kinds.length; index++) {
          final ShortfallKind? kind = kinds[index];
          if (kind != null) ledger = ledger.markCause(index, kind);
        }
        return ledger;
      }

      expect(
        ledgerWith(<ShortfallKind?>[
          ShortfallKind.providerError,
          ShortfallKind.cancelled,
        ]).shortfall,
        ShortfallKind.cancelled,
      );
      expect(
        ledgerWith(<ShortfallKind?>[
          ShortfallKind.truncated,
          ShortfallKind.providerError,
        ]).shortfall,
        ShortfallKind.providerError,
      );
      expect(
        ledgerWith(<ShortfallKind?>[
          ShortfallKind.exhaustedMaterial,
          ShortfallKind.truncated,
        ]).shortfall,
        ShortfallKind.truncated,
      );
      expect(
        ledgerWith(<ShortfallKind?>[
          ShortfallKind.validationRejects,
          ShortfallKind.exhaustedMaterial,
        ]).shortfall,
        ShortfallKind.exhaustedMaterial,
      );
      expect(
        ledgerWith(<ShortfallKind?>[ShortfallKind.validationRejects]).shortfall,
        ShortfallKind.validationRejects,
      );
    });

    test('долга нет — класса недобора нет даже при отброшенных карточках', () {
      var ledger = GenerationLedger.fromBudgets(const <int>[3]);
      ledger = ledger.record(0, generated: 5, invalid: 1, duplicates: 1);
      expect(ledger.accepted, 3);
      expect(ledger.remaining, 0);
      expect(ledger.hasDebt, isFalse);
      expect(ledger.shortfall, isNull);
    });

    test('replace и record проверяют номер партии', () {
      final GenerationLedger ledger = GenerationLedger.fromBudgets(const <int>[
        2,
      ]);
      expect(
        () => ledger.replace(
          const GenerationBatchLedger(batchIndex: 1, requested: 1),
        ),
        throwsArgumentError,
      );
      expect(() => ledger.record(3, generated: 1), throwsArgumentError);
      expect(
        () => ledger.markCause(9, ShortfallKind.cancelled),
        throwsArgumentError,
      );
    });

    test('партии журнала неизменяемы и нумеруются без пропусков', () {
      final GenerationLedger ledger = GenerationLedger.fromBudgets(const <int>[
        1,
        2,
      ]);
      expect(
        () => ledger.batches.add(
          const GenerationBatchLedger(batchIndex: 2, requested: 1),
        ),
        throwsUnsupportedError,
      );
      expect(
        () => GenerationLedger(
          batches: const <GenerationBatchLedger>[
            GenerationBatchLedger(batchIndex: 1, requested: 2),
          ],
        ),
        throwsA(isA<AssertionError>()),
      );
      expect(
        () => GenerationLedger.fromBudgets(const <int>[-1]),
        throwsA(isA<AssertionError>()),
      );
    });

    test('fromPlan: бюджеты партий — лимиты фрагментов плана', () {
      final GenerationPlan plan = planWithBudgets(const <int>[3, 7]);
      final GenerationLedger ledger = GenerationLedger.fromPlan(plan);
      expect(ledger.requested, 10);
      expect(ledger.requested, plan.requestedCards);
      expect(
        ledger.batches
            .map((GenerationBatchLedger batch) => batch.requested)
            .toList(),
        <int>[3, 7],
      );
    });

    test('toString показывает принято/запрошено и долг', () {
      var ledger = GenerationLedger.fromBudgets(const <int>[4, 4]);
      ledger = ledger.record(0, generated: 3);
      final String text = ledger.toString();
      expect(text, contains('принято 3/8'));
      expect(text, contains('долг 5'));
    });
  });

  group('DoD: property-тесты', () {
    test('сумма бюджетов партий == requested на случайных планах', () {
      final Random random = Random(20261127);
      for (var iteration = 0; iteration < 200; iteration++) {
        final int requested = 1 + random.nextInt(300);
        final int parts = 1 + random.nextInt(min(requested, 9));
        final List<int> budgets = randomSplit(requested, parts, random);

        // Свойство генератора: части положительны и складываются в заказ.
        expect(budgets.length, parts);
        expect(budgets.every((int size) => size > 0), isTrue);
        expect(budgets.fold(0, (int sum, int size) => sum + size), requested);

        final GenerationPlan plan = planWithBudgets(budgets);
        final GenerationLedger ledger = GenerationLedger.fromPlan(plan);
        expect(ledger.requested, requested);
        expect(ledger.requested, plan.requestedCards);
        expect(
          ledger.batches
              .map((GenerationBatchLedger batch) => batch.requested)
              .toList(),
          budgets,
        );
        expect(ledger.remaining, requested);
      }
    });

    test('случайные события не нарушают бухгалтерию журнала', () {
      final Random random = Random(7);
      for (var iteration = 0; iteration < 200; iteration++) {
        final List<int> budgets = <int>[
          1 + random.nextInt(20),
          1 + random.nextInt(20),
        ];
        var ledger = GenerationLedger.fromBudgets(budgets);
        for (var step = 0; step < 6; step++) {
          final int index = random.nextInt(ledger.batches.length);
          final int generated = random.nextInt(7);
          final int invalid = generated == 0
              ? 0
              : random.nextInt(generated + 1);
          final int duplicates = generated == invalid
              ? 0
              : random.nextInt(generated - invalid + 1);
          ledger = ledger.record(
            index,
            generated: generated,
            invalid: invalid,
            duplicates: duplicates,
          );
        }

        int sumRequested = 0;
        int sumGenerated = 0;
        int sumInvalid = 0;
        int sumDuplicates = 0;
        for (final GenerationBatchLedger batch in ledger.batches) {
          sumRequested += batch.requested;
          sumGenerated += batch.generated;
          sumInvalid += batch.invalid;
          sumDuplicates += batch.duplicates;
          expect(batch.invalid + batch.duplicates <= batch.generated, isTrue);
          expect(
            batch.accepted,
            batch.generated - batch.invalid - batch.duplicates,
          );
          expect(batch.remaining, max(0, batch.requested - batch.accepted));
          if (batch.shortfall != null) {
            expect(batch.hasDebt, isTrue);
          }
        }
        expect(ledger.requested, sumRequested);
        expect(ledger.generated, sumGenerated);
        expect(ledger.invalid, sumInvalid);
        expect(ledger.duplicates, sumDuplicates);
        expect(ledger.accepted, sumGenerated - sumInvalid - sumDuplicates);
        expect(ledger.remaining, max(0, sumRequested - ledger.accepted));
        if (ledger.shortfall != null) {
          expect(ledger.hasDebt, isTrue);
        }
      }
    });
  });
}
