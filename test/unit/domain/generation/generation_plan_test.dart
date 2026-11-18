import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/domain/generation/document_image.dart';
import 'package:cardflow/domain/generation/generation_attachment.dart';
import 'package:cardflow/domain/generation/generation_budget.dart';
import 'package:cardflow/domain/generation/generation_plan.dart';
import 'package:cardflow/domain/generation/generation_pricing.dart';
import 'package:cardflow/domain/generation/model_capabilities.dart';

/// TASK 02A: план генерации, его валидность и оценка (разделы D.8/G.6).
void main() {
  BudgetTrace budgetTrace({int limit = 3}) {
    return GenerationBudget.compute(
      capabilities: const ModelCapabilities(
        contextWindowTokens: 128000,
        contextSource: CapabilitySource.preset,
      ),
      limit: limit,
      systemPromptTokens: 100,
      schemaTokens: 10,
      wrapperTokens: 10,
      catalogTokens: 0,
      imageTokens: 0,
    ).trace;
  }

  GenerationEstimate estimate({
    PricingState pricingState = PricingState.unknown,
    double? inputCost,
    double? outputCost,
    double? totalCost,
    String? currency,
    List<String> unknownFields = const <String>['pricing'],
  }) {
    return GenerationEstimate(
      inputTextTokens: 1000,
      imageTokens: 200,
      fixedPromptTokens: 6000,
      wrapperTokens: 50,
      schemaTokens: 300,
      catalogTokens: 100,
      reservedOutputTokens: 1000,
      expectedOutputTokens: 1000,
      totalTokens: 8650,
      plannedChunks: 1,
      plannedRequests: 1,
      retryAllowanceRequests: 1,
      pricingState: pricingState,
      estimatorVersion: 'test-1',
      inputCost: inputCost,
      outputCost: outputCost,
      totalCost: totalCost,
      currency: currency,
      unknownFields: unknownFields,
      confidence: 0.5,
    );
  }

  DocumentImage image({int bytes = 3, String? caption}) {
    return DocumentImage(
      fileName: 'lecture.docx',
      bytes: Uint8List.fromList(List<int>.filled(bytes, 1)),
      mediaType: AttachmentMediaType.png,
      caption: caption,
      sectionIndex: 0,
    );
  }

  PlannedChunk chunk({
    int index = 1,
    int limit = 3,
    int textTokens = 100,
    int imageTokens = 200,
    List<DocumentImage> imageParts = const <DocumentImage>[],
    List<DocumentImage> catalogOnly = const <DocumentImage>[],
    List<GenerationAttachment> attachments = const <GenerationAttachment>[],
    List<UnitSpan> units = const <UnitSpan>[
      UnitSpan(unitId: 'doc:lecture.docx#0#0', start: 0, end: 10, tokens: 5),
    ],
  }) {
    return PlannedChunk(
      index: index,
      kind: ChunkKind.mixed,
      limit: limit,
      textTokens: textTokens,
      imageTokens: imageTokens,
      bodyBytes: 1024,
      units: units,
      imageParts: imageParts,
      catalogOnly: catalogOnly,
      attachments: attachments,
    );
  }

  GenerationPlan plan({
    List<PlannedChunk>? chunks,
    PlanValidity validity = const PlanValidity.valid(),
    List<OmittedUnit> omitted = const <OmittedUnit>[],
    int requestedCards = 0,
  }) {
    return GenerationPlan(
      validity: validity,
      estimate: estimate(),
      budget: budgetTrace(),
      chunks: chunks ?? <PlannedChunk>[chunk()],
      omitted: omitted,
      requestedCards: requestedCards,
      retryAllowanceRequests: 1,
      unknownFields: const <String>['pricing'],
    );
  }

  group('UnitSpan', () {
    test('хранит id единицы, смещения и токены', () {
      const UnitSpan span = UnitSpan(
        unitId: 'doc:a.docx#0#1',
        start: 5,
        end: 15,
        tokens: 7,
      );
      expect(span.unitId, 'doc:a.docx#0#1');
      expect(span.start, 5);
      expect(span.end, 15);
      expect(span.tokens, 7);
    });
  });

  group('PlannedChunk', () {
    test('итог — сумма токенов, байты image-частей и вложений', () {
      final PlannedChunk planned = chunk(
        imageParts: <DocumentImage>[image(bytes: 3), image(bytes: 4)],
        catalogOnly: <DocumentImage>[image(bytes: 9)],
        attachments: <GenerationAttachment>[
          GenerationAttachment(
            fileName: 'scan.pdf',
            mediaType: AttachmentMediaType.pdf,
            bytes: Uint8List.fromList(<int>[1, 2, 3, 4, 5]),
            pageNumber: 1,
          ),
        ],
      );
      expect(planned.totalTokens, 300);
      expect(planned.imagePartBytes, 12);
      expect(planned.imageParts, hasLength(2));
      expect(planned.catalogOnly, hasLength(1));
      expect(planned.attachments, hasLength(1));
      expect(planned.limit, 3);
      expect(planned.kind, ChunkKind.mixed);
      expect(planned.splitDepth, 0);
    });

    test('пустой фрагмент запрещён (D.4.9)', () {
      expect(
        () => PlannedChunk(
          index: 1,
          kind: ChunkKind.text,
          limit: 1,
          textTokens: 0,
          imageTokens: 0,
          bodyBytes: 0,
        ),
        throwsA(isA<AssertionError>()),
      );
    });

    test('лимит карточек запланированного фрагмента ≥ 1 (D.7.3)', () {
      expect(() => chunk(limit: 0), throwsA(isA<AssertionError>()));
    });
  });

  group('PlanValidity', () {
    test('valid: план можно запускать, предупреждений нет', () {
      const PlanValidity validity = PlanValidity.valid();
      expect(validity.kind, PlanValidityKind.valid);
      expect(validity.isValid, isTrue);
      expect(validity.isInvalid, isFalse);
      expect(validity.hasWarnings, isFalse);
      expect(validity.reason, isNull);
    });

    test('warnings: план запускаем, причины перечислены', () {
      const PlanValidity validity = PlanValidity.warnings(<PlanWarningCode>[
        PlanWarningCode.unknownCapabilities,
        PlanWarningCode.catalogOnlyImages,
      ]);
      expect(validity.kind, PlanValidityKind.warnings);
      expect(validity.isValid, isTrue);
      expect(validity.hasWarnings, isTrue);
      expect(validity.warnings, hasLength(2));
    });

    test('invalid: причина и нехватка бюджета', () {
      const PlanValidity validity = PlanValidity.invalid(
        PlanInvalidReason.contextWindowTooSmall,
        neededTokens: 900,
        availableTokens: 512,
      );
      expect(validity.kind, PlanValidityKind.invalid);
      expect(validity.isValid, isFalse);
      expect(validity.reason, PlanInvalidReason.contextWindowTooSmall);
      expect(validity.neededTokens, 900);
      expect(validity.availableTokens, 512);
    });
  });

  group('GenerationEstimate', () {
    test('неизвестная цена — null и состояние unknown, а не 0', () {
      final GenerationEstimate unknown = estimate();
      expect(unknown.pricingState, PricingState.unknown);
      expect(unknown.inputCost, isNull);
      expect(unknown.outputCost, isNull);
      expect(unknown.totalCost, isNull);
      expect(unknown.currency, isNull);
      expect(unknown.hasKnownCost, isFalse);
      expect(unknown.unknownFields, contains('pricing'));
      expect(unknown.confidence, 0.5);
      expect(unknown.estimatorVersion, 'test-1');
    });

    test('полные цены: стоимость посчитана', () {
      final GenerationEstimate complete = estimate(
        pricingState: PricingState.complete,
        inputCost: 0.001,
        outputCost: 0.002,
        totalCost: 0.003,
        currency: 'USD',
        unknownFields: const <String>[],
      );
      expect(complete.hasKnownCost, isTrue);
      expect(complete.totalCost, 0.003);
      expect(complete.currency, 'USD');
    });

    test('состояние complete без стоимости — ошибка программиста', () {
      expect(
        () => estimate(pricingState: PricingState.complete),
        throwsA(isA<AssertionError>()),
      );
    });

    test('уверенность вне 0..1 — ошибка программиста', () {
      expect(
        () => GenerationEstimate(
          inputTextTokens: 0,
          imageTokens: 0,
          fixedPromptTokens: 0,
          wrapperTokens: 0,
          schemaTokens: 0,
          catalogTokens: 0,
          reservedOutputTokens: 0,
          expectedOutputTokens: 0,
          totalTokens: 0,
          plannedChunks: 0,
          plannedRequests: 0,
          retryAllowanceRequests: 0,
          pricingState: PricingState.unknown,
          estimatorVersion: 'v',
          confidence: 2,
        ),
        throwsA(isA<AssertionError>()),
      );
    });
  });

  group('GenerationPlan', () {
    test('план считает карточки и запросы из фрагментов', () {
      final GenerationPlan generationPlan = plan(
        chunks: <PlannedChunk>[
          chunk(index: 1, limit: 3),
          chunk(index: 2, limit: 2),
        ],
        requestedCards: 5,
      );
      expect(generationPlan.chunks, hasLength(2));
      expect(generationPlan.plannedCards, 5);
      expect(generationPlan.plannedRequests, 2);
      expect(generationPlan.isEmpty, isFalse);
      expect(generationPlan.isExecutable, isTrue);
      expect(generationPlan.hasOmittedUnits, isFalse);
      expect(generationPlan.requestedCards, 5);
      expect(generationPlan.retryAllowanceRequests, 1);
      expect(generationPlan.unknownFields, <String>['pricing']);
    });

    test('отброшенные единицы видны с причиной, а не теряются', () {
      final GenerationPlan generationPlan = plan(
        omitted: <OmittedUnit>[
          const OmittedUnit(
            unitId: 'img:lecture.docx#7',
            reason: OmittedReason.providerImageCap,
            tokens: 900,
            documentId: 'doc:lecture.docx',
          ),
        ],
      );
      expect(generationPlan.hasOmittedUnits, isTrue);
      expect(
        generationPlan.omitted.single.reason,
        OmittedReason.providerImageCap,
      );
      expect(generationPlan.omitted.single.tokens, 900);
    });

    test('невалидный план не исполняется', () {
      final GenerationPlan generationPlan = plan(
        validity: const PlanValidity.invalid(
          PlanInvalidReason.contextWindowTooSmall,
          neededTokens: 2000,
          availableTokens: 700,
        ),
      );
      expect(generationPlan.validity.isInvalid, isTrue);
      expect(generationPlan.isExecutable, isFalse);
    });

    test('план без фрагментов не исполняется даже при valid', () {
      final GenerationPlan generationPlan = plan(chunks: <PlannedChunk>[]);
      expect(generationPlan.isEmpty, isTrue);
      expect(generationPlan.plannedCards, 0);
      expect(generationPlan.isExecutable, isFalse);
    });

    test('списки плана неизменяемы', () {
      final GenerationPlan generationPlan = plan();
      expect(
        () => generationPlan.chunks.add(chunk(index: 2)),
        throwsUnsupportedError,
      );
      expect(
        () => generationPlan.omitted.add(
          const OmittedUnit(
            unitId: 'img:x#0',
            reason: OmittedReason.budget,
            tokens: 1,
          ),
        ),
        throwsUnsupportedError,
      );
    });

    test('toString описывает план, фрагмент, оценку и валидность', () {
      const UnitSpan span = UnitSpan(
        unitId: 'doc:a.docx#0#1',
        start: 0,
        end: 5,
        tokens: 2,
      );
      expect(span.toString(), contains('doc:a.docx#0#1'));

      const OmittedUnit omitted = OmittedUnit(
        unitId: 'img:a.docx#0',
        reason: OmittedReason.payload,
        tokens: 10,
      );
      expect(omitted.toString(), contains('payload'));

      expect(const PlanValidity.valid().toString(), 'PlanValidity.valid');
      expect(
        const PlanValidity.warnings(<PlanWarningCode>[
          PlanWarningCode.unknownCapabilities,
        ]).toString(),
        contains('unknownCapabilities'),
      );
      expect(
        const PlanValidity.invalid(PlanInvalidReason.payloadTooLarge)
            .toString(),
        contains('payloadTooLarge'),
      );

      final PlannedChunk planned = chunk();
      expect(planned.toString(), contains('limit: 3'));

      final GenerationEstimate generationEstimate = estimate();
      expect(generationEstimate.toString(), contains('unknown'));

      final GenerationPlan generationPlan = plan();
      expect(generationPlan.toString(), contains('chunks: 1'));
    });
  });
}
