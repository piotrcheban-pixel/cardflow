import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/api/generation/generation_plan_builder.dart';
import 'package:cardflow/domain/generation/content_unit.dart';
import 'package:cardflow/domain/generation/generation_chunk_planner.dart';
import 'package:cardflow/domain/generation/generation_plan.dart';
import 'package:cardflow/domain/generation/model_capabilities.dart';
import 'package:cardflow/domain/generation/prompt_only_planner.dart';
import 'package:cardflow/domain/generation/prompt_only_request.dart';
import 'package:cardflow/domain/text/document_format.dart';
import 'package:cardflow/domain/text/parsed_document.dart';

/// TASK 03, раздел 7: распределение карточек 1…1000 (prompt-only и материалы).
void main() {
  const GenerationOverheadTokens overhead = GenerationOverheadTokens(
    systemPromptTokens: 7000,
    schemaTokens: 400,
    wrapperTokens: 60,
  );

  ModelCapabilities caps({int context = 128000, int? maxOutput}) {
    return ModelCapabilities(
      contextWindowTokens: context,
      contextSource: CapabilitySource.officialCatalog,
      maxOutputTokens: maxOutput,
    );
  }

  ParsedDocument documentOf(
    List<String> sections, {
    String name = 'материал.txt',
  }) {
    final StringBuffer buffer = StringBuffer();
    final List<ParsedSection> parsed = <ParsedSection>[];
    for (var index = 0; index < sections.length; index++) {
      if (index > 0) buffer.write('\n\n');
      final int start = buffer.length;
      buffer.write(sections[index]);
      parsed.add(ParsedSection(start: start, end: buffer.length));
    }
    return ParsedDocument(
      format: DocumentFormat.txt,
      fileName: name,
      text: buffer.toString(),
      sections: parsed,
    );
  }

  String paragraph(int index, {int chars = 1000}) {
    final StringBuffer buffer = StringBuffer('Тема $index. ');
    var word = 0;
    while (buffer.length < chars) {
      buffer.write('слово${word++} ');
    }
    return buffer.toString();
  }

  group('prompt-only 1…1000', () {
    for (final int count in <int>[1, 2, 5, 10, 20, 50, 100, 200, 500, 1000]) {
      test('$count карточек: сумма лимитов = заказ, запросы по бюджету', () {
        final GenerationPlan plan = const PromptOnlyPlanner().plan(
          request: PromptOnlyRequest(
            prompt: 'Фотосинтез: определения, реакции, роль пигментов',
            requestedCards: count,
          ),
          capabilities: caps(),
          overhead: overhead,
        );
        expect(plan.validity.isInvalid, isFalse);
        expect(plan.requestedCards, count);
        expect(plan.plannedCards, count);
        expect(plan.chunks, isNotEmpty);
        final int expectedChunks = ((count - 1) ~/ 7) + 1;
        expect(plan.chunks.length, expectedChunks);
        for (final PlannedChunk chunk in plan.chunks) {
          expect(chunk.limit, greaterThanOrEqualTo(1));
          expect(chunk.limit, lessThanOrEqualTo(7));
          expect(chunk.materialsText, isEmpty);
          expect(chunk.units, isEmpty);
          expect(chunk.imageParts, isEmpty);
        }
        if (count > 7) {
          expect(
            plan.estimate.continuationReserveTokens,
            greaterThan(0),
            reason: 'несколько запросов получают сводку продолжения',
          );
        }
        expect(
          plan.validity.warnings,
          contains(PlanWarningCode.unknownCapabilities),
        );
      });
    }

    test('int.max заказ: invalid tooManyChunks, заказ не подменён', () {
      final GenerationPlan plan = const PromptOnlyPlanner().plan(
        request: const PromptOnlyRequest(
          prompt: 'Тема',
          requestedCards: 9223372036854775807,
        ),
        capabilities: caps(),
        overhead: overhead,
      );
      expect(plan.validity.isInvalid, isTrue);
      expect(plan.validity.reason, PlanInvalidReason.tooManyChunks);
      expect(plan.chunks, isEmpty);
    });
  });

  group('материалы 1…1000', () {
    const GenerationPlanBuilder builder = GenerationPlanBuilder();

    GenerationPlan planFor({
      required int requestedCards,
      required int sections,
      int context = 128000,
      int? maxOutput,
    }) {
      final ParsedDocument document = documentOf(<String>[
        for (var index = 0; index < sections; index++) paragraph(index),
      ]);
      return builder.build(
        documents: <ParsedDocument>[document],
        capabilities: caps(context: context, maxOutput: maxOutput),
        wishes: 'Нужно $requestedCards карточек',
        requestedCards: requestedCards,
      );
    }

    for (final int count in <int>[1, 2, 5, 10, 20]) {
      test('$count карточек: ровно заказ на большом документе', () {
        final GenerationPlan plan = planFor(
          requestedCards: count,
          sections: count == 1 ? 1 : count * 2,
        );
        expect(plan.requestedCards, count);
        expect(plan.plannedCards, count);
        expect(plan.validity.isInvalid, isFalse);
        expect(plan.chunks, isNotEmpty);
        for (final PlannedChunk chunk in plan.chunks) {
          expect(chunk.limit, greaterThanOrEqualTo(1));
        }
      });
    }

    for (final int count in <int>[50, 100, 200, 500, 1000]) {
      test('$count карточек: материала хватает — план не занижает', () {
        final int targetChunks = ((count - 1) ~/ 7) + 1;
        // ~13 000 символов на фрагмент при 7 карточках: мягкая цель не должна
        // обрезать achievableCards (D20).
        final int sections = targetChunks * 13;
        final GenerationPlan plan = planFor(
          requestedCards: count,
          sections: sections,
        );
        expect(plan.requestedCards, count);
        expect(
          plan.plannedCards,
          count,
          reason: 'заказ $count: план обязан использовать доступный материал',
        );
        expect(
          plan.validity.warnings,
          isNot(contains(PlanWarningCode.requestedAbovePlan)),
        );
        expect(plan.chunks.length, greaterThanOrEqualTo(targetChunks));
      });
    }

    test('мало материала: achievable < requested и честная причина', () {
      final GenerationPlan plan = planFor(requestedCards: 100, sections: 1);
      expect(plan.requestedCards, 100);
      expect(plan.plannedCards, lessThan(100));
      expect(
        plan.validity.warnings,
        contains(PlanWarningCode.requestedAbovePlan),
      );
    });

    test('малое окно модели: план невалиден до сети, без клампа', () {
      final GenerationPlan plan = planFor(
        requestedCards: 20,
        sections: 4,
        context: 8000,
      );
      expect(plan.validity.isInvalid, isTrue);
      expect(
        plan.validity.reason,
        anyOf(
          PlanInvalidReason.contextWindowTooSmall,
          PlanInvalidReason.unitTooLarge,
          PlanInvalidReason.tooManyChunks,
        ),
      );
      expect(plan.chunks, isEmpty);
    });

    test('низкий output budget: больше запросов, карточки не теряются', () {
      final GenerationPlan low = planFor(
        requestedCards: 50,
        sections: 80,
        maxOutput: 4096,
      );
      final GenerationPlan high = planFor(
        requestedCards: 50,
        sections: 80,
        maxOutput: 50000,
      );
      expect(low.plannedCards, 50);
      expect(high.plannedCards, 50);
      expect(low.chunks.length, greaterThan(high.chunks.length));
    });

    test('покрытие: ни одна единица текста не потеряна и не задвоена', () {
      final ParsedDocument document = documentOf(<String>[
        for (var index = 0; index < 40; index++) paragraph(index),
      ]);
      final ContentInventory inventory = builder.inventoryOf(
        documents: <ParsedDocument>[document],
      );
      final GenerationPlan plan = builder.build(
        documents: <ParsedDocument>[document],
        capabilities: caps(),
        wishes: '100 карточек',
        requestedCards: 100,
      );
      final GenerationPlanCoverage coverage = GenerationPlanCoverage.check(
        inventory: inventory,
        plan: plan,
      );
      expect(coverage.missingUnits, isEmpty);
      expect(coverage.duplicatedUnits, isEmpty);
      expect(coverage.uncoveredImages, isEmpty);
    });
  });
}
