import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/domain/generation/generation_budget.dart';
import 'package:cardflow/domain/generation/model_capabilities.dart';

/// TASK 02A: бюджет входа и трассировка расчёта (раздел D.1 аудита).
///
/// Регрессия L-16/L-18: никакого клампинга в 2 000 — при нехватке бюджета
/// возвращается отрицательное значение и `isWorkable == false`.
void main() {
  GenerationBudget compute({
    int? contextWindowTokens,
    int? maxInputTokens,
    int? maxOutputTokens,
    int? maxRequestBytes,
    int limit = 3,
    int systemPromptTokens = 0,
    int schemaTokens = 0,
    int wrapperTokens = 0,
    int catalogTokens = 0,
    int imageTokens = 0,
    int imagePartBytes = 0,
    GenerationBudgetConfig config = const GenerationBudgetConfig(),
  }) {
    return GenerationBudget.compute(
      capabilities: ModelCapabilities(
        contextWindowTokens: contextWindowTokens,
        maxInputTokens: maxInputTokens,
        maxOutputTokens: maxOutputTokens,
        maxRequestBytes: maxRequestBytes,
        contextSource: contextWindowTokens == null
            ? CapabilitySource.unknown
            : CapabilitySource.preset,
      ),
      limit: limit,
      systemPromptTokens: systemPromptTokens,
      schemaTokens: schemaTokens,
      wrapperTokens: wrapperTokens,
      catalogTokens: catalogTokens,
      imageTokens: imageTokens,
      imagePartBytes: imagePartBytes,
      config: config,
    );
  }

  group('GenerationBudget: известное окно', () {
    test('формула D.1: окно − вывод − обвязка − запас', () {
      final GenerationBudget budget = compute(
        contextWindowTokens: 128000,
        limit: 5,
        systemPromptTokens: 1000,
        schemaTokens: 200,
        wrapperTokens: 100,
        catalogTokens: 100,
      );
      expect(budget.fixedOverheadTokens, 1400);
      expect(
        budget.expectedOutputTokens,
        5 * kBudgetPerCardOutputTokens + kBudgetJsonEnvelopeTokens,
      );
      expect(budget.reservedOutputTokens, budget.expectedOutputTokens);
      expect(budget.safetyMarginTokens, 6400, reason: '5 % от 128 000');
      expect(
        budget.inputBudget,
        128000 - budget.expectedOutputTokens - 1400 - 6400,
      );
      expect(budget.source, BudgetSource.capabilities);
      expect(budget.hasKnownContextWindow, isTrue);
      expect(budget.isWorkable, isTrue);
      expect(budget.shortfallTokens, 0);
      expect(budget.trace.formula, GenerationBudget.formulaKnownContext);
      expect(budget.trace.contextSource, CapabilitySource.preset);
      expect(budget.trace.outputCapTokens, kBudgetDefaultOutputCapTokens);
      expect(budget.trace.outputCapAssumed, isTrue);
      expect(budget.trace.fixedOverheadTokens, 1400);
      expect(budget.trace.systemPromptTokens, 1000);
      expect(budget.trace.schemaTokens, 200);
      expect(budget.trace.wrapperTokens, 100);
      expect(budget.trace.catalogTokens, 100);
      expect(budget.trace.imageTokens, 0);
      expect(budget.trace.inputBudget, budget.inputBudget);
    });

    test('лимит вывода модели используется вместо допущения', () {
      final GenerationBudget budget = compute(
        contextWindowTokens: 128000,
        maxOutputTokens: 1000,
        limit: 5,
      );
      expect(budget.trace.outputCapTokens, 1000);
      expect(budget.trace.outputCapAssumed, isFalse);
      expect(budget.expectedOutputTokens, 1000);
      expect(budget.inputBudget, 128000 - 1000 - 6400);
    });

    test('минимальный запас 256 применяется на малом окне', () {
      final GenerationBudget budget = compute(
        contextWindowTokens: 2000,
        limit: 0,
      );
      expect(budget.safetyMarginTokens, 256);
      expect(budget.expectedOutputTokens, kBudgetJsonEnvelopeTokens);
      expect(budget.inputBudget, 2000 - kBudgetJsonEnvelopeTokens - 256);
    });

    test('заказ карточек определяет ожидаемый вывод', () {
      final GenerationBudget budget = compute(
        contextWindowTokens: 128000,
        limit: 2,
      );
      expect(
        budget.expectedOutputTokens,
        2 * kBudgetPerCardOutputTokens + kBudgetJsonEnvelopeTokens,
      );
    });
  });

  group('GenerationBudget: нехватка бюджета (регресс moonshot-8k)', () {
    test('окно 8 000 не даёт 2 000 и помечается невыполнимым', () {
      final GenerationBudget budget = compute(
        contextWindowTokens: 8000,
        limit: 3,
        systemPromptTokens: 6566,
        schemaTokens: 500,
        wrapperTokens: 100,
      );
      expect(budget.fixedOverheadTokens, 7166);
      expect(budget.expectedOutputTokens, 3088);
      expect(budget.safetyMarginTokens, 400);
      expect(budget.inputBudget, -2654);
      expect(budget.inputBudget, isNot(kBudgetMinWorkableInputTokens));
      expect(budget.isWorkable, isFalse);
      expect(budget.shortfallTokens, kBudgetMinWorkableInputTokens + 2654);
      expect(budget.trace.inputBudget, -2654);
    });
  });

  group('GenerationBudget: неизвестное окно', () {
    test('консервативное допущение 6000 и вывод 2048, источник assumption', () {
      final GenerationBudget budget = compute(limit: 3);
      expect(budget.contextWindowTokens, isNull);
      expect(budget.inputBudget, kBudgetUnknownContextInputTokens);
      expect(budget.source, BudgetSource.assumption);
      expect(budget.safetyMarginTokens, isNull);
      expect(budget.trace.formula, GenerationBudget.formulaUnknownContext);
      expect(
        budget.trace.outputCapTokens,
        kBudgetUnknownContextOutputCapTokens,
      );
      expect(budget.trace.outputCapAssumed, isTrue);
      expect(budget.isWorkable, isTrue);
      expect(
        budget.unknownFields,
        contains(ModelCapabilities.unknownContextWindow),
      );
    });
  });

  group('GenerationBudget: лимиты провайдера', () {
    test('отдельный входной лимит уменьшает бюджет', () {
      final GenerationBudget budget = compute(
        contextWindowTokens: 128000,
        maxInputTokens: 5000,
        systemPromptTokens: 1400,
      );
      expect(budget.maxInputTokensLimit, 3600);
      expect(budget.inputBudget, 3600);
    });

    test('лимит тела запроса учитывает base64 image-частей', () {
      final GenerationBudget budget = compute(
        contextWindowTokens: 128000,
        maxRequestBytes: 10000,
        imagePartBytes: 3000,
        limit: 1,
      );
      expect(budget.maxRequestBytesLimit, 10000);
      expect(
        budget.inputBudget,
        (10000 - base64EncodedByteLength(3000)) ~/ kBudgetBytesPerTokenBound,
      );
      expect(budget.inputBudget, 1500);
    });

    test('изображения больше лимита тела — бюджет 0, не «всё равно»', () {
      final GenerationBudget budget = compute(
        contextWindowTokens: 128000,
        maxRequestBytes: 1000,
        imagePartBytes: 1000,
        limit: 1,
      );
      expect(base64EncodedByteLength(1000), greaterThan(1000));
      expect(budget.inputBudget, 0);
      expect(budget.isWorkable, isFalse);
    });

    test('base64-длина тела: округление вверх до 4 байт', () {
      expect(base64EncodedByteLength(0), 0);
      expect(base64EncodedByteLength(1), 4);
      expect(base64EncodedByteLength(2), 4);
      expect(base64EncodedByteLength(3), 4);
      expect(base64EncodedByteLength(4), 8);
      expect(base64EncodedByteLength(1000), 1336);
    });
  });

  group('GenerationBudget: конфигурация', () {
    test('значения конфигурации используются в формуле', () {
      const GenerationBudgetConfig config = GenerationBudgetConfig(
        perCardOutputTokens: 100,
        jsonEnvelopeTokens: 0,
        defaultOutputCapTokens: 500,
        minWorkableInputTokens: 1,
        minSafetyMarginTokens: 0,
        safetyMarginFraction: 0,
      );
      final GenerationBudget budget = compute(
        contextWindowTokens: 1000,
        limit: 3,
        config: config,
      );
      expect(budget.expectedOutputTokens, 300);
      expect(budget.safetyMarginTokens, 0);
      expect(budget.inputBudget, 700);
      expect(budget.minWorkableInputTokens, 1);
      expect(budget.isWorkable, isTrue);
    });

    test('отрицательные слагаемые трактуются как 0', () {
      final GenerationBudget budget = compute(
        contextWindowTokens: 128000,
        systemPromptTokens: -100,
        schemaTokens: -1,
      );
      expect(budget.fixedOverheadTokens, 0);
    });

    test('toString бюджета и трассировки — для диагностики', () {
      final GenerationBudget known = compute(contextWindowTokens: 128000);
      expect(known.toString(), contains('context: 128000'));
      expect(known.toString(), contains(BudgetSource.capabilities.name));
      expect(known.trace.toString(), contains('safety'));

      final GenerationBudget unknown = compute();
      expect(unknown.toString(), contains(BudgetSource.assumption.name));
      expect(unknown.trace.toString(), contains('assumption'));
    });
  });
}
