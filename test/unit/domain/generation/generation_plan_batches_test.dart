import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/api/generation/generation_plan_builder.dart';
import 'package:cardflow/domain/generation/content_token_estimator.dart';
import 'package:cardflow/domain/generation/document_image.dart';
import 'package:cardflow/domain/generation/generation_attachment.dart';
import 'package:cardflow/domain/generation/generation_chunk_planner.dart';
import 'package:cardflow/domain/generation/generation_plan.dart';
import 'package:cardflow/domain/generation/input_planner.dart';
import 'package:cardflow/domain/generation/model_capabilities.dart';
import 'package:cardflow/domain/generation/sourced.dart' show ContextSemantics;
import 'package:cardflow/domain/text/document_format.dart';
import 'package:cardflow/domain/text/parsed_document.dart';

/// ADR-040: whole-document-first, партии и ограничения на уровне `GenerationPlan`.
///
/// Тексты считаются 1 символ = 1 токен ([_CharEstimator]), чтобы задать объём
/// материалов в токенах напрямую.
void main() {
  const GenerationOverheadTokens overhead = GenerationOverheadTokens(
    systemPromptTokens: 2500,
    schemaTokens: 300,
    wrapperTokens: 200,
  );

  GenerationPlanBuilder builder() =>
      GenerationChunkPlanner(estimator: const _CharEstimator()).let(
        (GenerationChunkPlanner planner) =>
            GenerationPlanBuilder(planner: planner),
      );

  ModelCapabilities caps({
    int? context = 128000,
    int? maxInput,
    int? maxOutput,
    ContextSemantics semantics = ContextSemantics.totalInputPlusOutput,
    int? maxRequestBytes,
    bool vision = false,
  }) => ModelCapabilities(
    contextWindowTokens: context,
    maxInputTokens: maxInput,
    contextSemantics: semantics,
    contextSource: context == null
        ? CapabilitySource.unknown
        : CapabilitySource.officialCatalog,
    maxOutputTokens: maxOutput,
    maxRequestBytes: maxRequestBytes,
    supportsVision: vision,
  );

  String filler(int chars, {int word = 6}) {
    final StringBuffer buffer = StringBuffer();
    var index = 0;
    while (buffer.length < chars) {
      buffer.write('слово${index++} ');
    }
    return buffer.toString();
  }

  ParsedDocument docOf(
    List<String> sections, {
    String name = 'd.txt',
    List<DocumentImage> images = const <DocumentImage>[],
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
      images: images,
    );
  }

  ParsedDocument sectionsOf(int count, int tokensEach) => docOf(<String>[
    // Ровно tokensEach символов (оценщик 1:1), чтобы объём материала был точным.
    for (var index = 0; index < count; index++)
      filler(tokensEach).substring(0, tokensEach),
  ]);

  GenerationPlan build(
    ParsedDocument document, {
    required ModelCapabilities capabilities,
    int? requestedCards,
    List<GenerationAttachment> attachments = const <GenerationAttachment>[],
    int? outlineTokens,
  }) => builder().build(
    documents: <ParsedDocument>[document],
    capabilities: capabilities,
    requestedCards: requestedCards,
    attachments: attachments,
    overhead: GenerationOverheadTokens(
      systemPromptTokens: overhead.systemPromptTokens,
      schemaTokens: overhead.schemaTokens,
      wrapperTokens: overhead.wrapperTokens,
      outlineTokens: outlineTokens ?? 0,
    ),
  );

  group('T2–T3: весь документ и партии', () {
    test('T2: 50 карточек, output 8192 → whole, партии 17/17/16', () {
      final GenerationPlan plan = build(
        sectionsOf(400, 100),
        capabilities: caps(maxOutput: 8192),
        requestedCards: 50,
      );
      expect(plan.validity.isInvalid, isFalse);
      expect(plan.inputStrategy, InputStrategy.wholeDocument);
      expect(plan.partCount, 1);
      expect(
        plan.plannedInputTokens,
        47300,
        reason: 'ceil((3000 + 40000) × 1.1); заголовки разделов входят в текст',
      );
      expect(plan.outputReserveTokens, 8192);
      expect(plan.chunks.map((PlannedChunk c) => c.limit).toList(), <int>[
        17,
        17,
        16,
      ]);
      expect(plan.achievableCards, 50);
    });

    test('T3: inputOnly, output 5530 → whole, партии 15,15,14×5', () {
      final GenerationPlan plan = build(
        sectionsOf(500, 200),
        capabilities: caps(
          context: 500000,
          maxInput: 500000,
          maxOutput: 5530,
          semantics: ContextSemantics.inputOnly,
        ),
        requestedCards: 100,
      );
      expect(plan.inputStrategy, InputStrategy.wholeDocument);
      expect(plan.partCount, 1);
      expect(plan.outputReserveTokens, 5530);
      expect(plan.chunks.map((PlannedChunk c) => c.limit).toList(), <int>[
        15,
        15,
        14,
        14,
        14,
        14,
        14,
      ]);
    });

    test('T7: 64000/32000, D=50000 → резерв уменьшен до 5700, вход цел', () {
      final GenerationPlan plan = build(
        sectionsOf(100, 500),
        capabilities: caps(context: 64000, maxOutput: 32000),
        requestedCards: 100,
      );
      expect(plan.inputStrategy, InputStrategy.wholeDocument);
      expect(plan.plannedInputTokens, 58300);
      expect(plan.outputReserveTokens, 5700);
      expect(plan.chunks.map((PlannedChunk c) => c.limit).toList(), <int>[
        15,
        15,
        14,
        14,
        14,
        14,
        14,
      ]);
    });
  });

  group('T4–T8: дробление', () {
    test('T4: D=300000 → 3 части; разбиение от заказа не зависит', () {
      final ParsedDocument document = sectionsOf(300, 1000);
      final List<GenerationPlan> plans = <int>[10, 50, 100]
          .map(
            (int requested) => build(
              document,
              capabilities: caps(context: 128000, maxOutput: 8192),
              requestedCards: requested,
              outlineTokens: 1500,
            ),
          )
          .toList();
      for (final GenerationPlan plan in plans) {
        expect(plan.inputStrategy, InputStrategy.fragmented);
        expect(plan.partCount, 3);
        expect(
          plan.materialBudgetPerPart,
          104416,
          reason: 'floor((128000 − 8192)/1.1) − 4500',
        );
      }
      List<String> partIds(GenerationPlan plan) => <String>[
        for (final InputPart part in plan.parts)
          part.sections.map((InputSection s) => s.promptId).join('+'),
      ];
      expect(partIds(plans[0]), partIds(plans[1]));
      expect(partIds(plans[1]), partIds(plans[2]));
      expect(plans[0].achievableCards, isNot(plans[2].achievableCards));
    });

    test('T8: 64000/32000, D=56000 → room < tokensFor(5) → 2 части', () {
      final GenerationPlan plan = build(
        sectionsOf(112, 500),
        capabilities: caps(context: 64000, maxOutput: 32000),
        requestedCards: 10,
      );
      expect(plan.inputStrategy, InputStrategy.fragmented);
      expect(plan.partCount, 2);
      expect(plan.materialBudgetPerPart, 42133);
    });

    test('части сохраняют порядок и покрытие', () {
      final GenerationPlan plan = build(
        sectionsOf(120, 500),
        capabilities: caps(context: 8000, maxOutput: 2000),
        requestedCards: 20,
      );
      expect(plan.validity.isInvalid, isFalse);
      expect(plan.inputStrategy, InputStrategy.fragmented);
      final List<int> order = <int>[
        for (final InputPart part in plan.parts)
          for (final InputSection section in part.sections)
            int.parse(section.promptId.substring(1)),
      ];
      expect(order, List<int>.generate(order.length, (int i) => i + 1));
      final Set<String> ids = <String>{
        for (final PlannedChunk chunk in plan.chunks)
          for (final UnitSpan span in chunk.units) span.unitId,
      };
      expect(ids.length, greaterThan(0));
    });
  });

  group('изображения и байтовое ограничение', () {
    test('T5: по токенам помещается, по байтам — одна картинка в запросе', () {
      final Uint8List big = Uint8List(13 * 1024 * 1024);
      final Uint8List other = Uint8List(13 * 1024 * 1024)..[0] = 1;
      final ParsedDocument document = docOf(
        <String>['Раздел с схемами. ${filler(400)}'],
        images: <DocumentImage>[
          DocumentImage(
            fileName: 'd.txt',
            bytes: big,
            mediaType: AttachmentMediaType.png,
            sectionIndex: 0,
            order: 0,
            caption: 'Схема 1',
          ),
          DocumentImage(
            fileName: 'd.txt',
            bytes: other,
            mediaType: AttachmentMediaType.png,
            sectionIndex: 0,
            order: 1,
            caption: 'Схема 2',
          ),
        ],
      );
      final GenerationPlan plan = build(
        document,
        capabilities: caps(
          maxOutput: 8192,
          maxRequestBytes: 20 * 1024 * 1024,
          vision: true,
        ),
        requestedCards: 20,
      );
      expect(plan.inputStrategy, InputStrategy.wholeDocument);
      expect(plan.images.length, 2);
      expect(plan.images.where((PlannedImage i) => i.sentToModel).length, 1);
      expect(
        plan.images
            .where(
              (PlannedImage i) =>
                  i.status == ImageParticipationStatus.omittedPayload,
            )
            .length,
        1,
      );
      expect(plan.validity.warnings, contains(PlanWarningCode.payloadLimited));
    });
  });

  group('заказ и achievable', () {
    for (final int count in <int>[1, 5, 10, 20]) {
      test('$count карточек: ровно заказ при достаточном материале', () {
        final GenerationPlan plan = build(
          sectionsOf(60, 200),
          capabilities: caps(),
          requestedCards: count,
        );
        expect(plan.requestedCards, count);
        expect(plan.achievableCards, count);
        for (final PlannedChunk chunk in plan.chunks) {
          expect(chunk.limit, greaterThanOrEqualTo(1));
        }
      });
    }

    test('мало материала: achievable < заказа и причина видна', () {
      final GenerationPlan plan = build(
        docOf(<String>['Короткий раздел. Это определение и число 42.']),
        capabilities: caps(),
        requestedCards: 100,
      );
      expect(plan.achievableCards, lessThan(100));
      expect(
        plan.validity.warnings,
        contains(PlanWarningCode.requestedAbovePlan),
      );
    });

    test('весь заказ помещается в один ответ — ровно один запрос', () {
      final GenerationPlan plan = build(
        sectionsOf(10, 200),
        capabilities: caps(maxOutput: 8192),
        requestedCards: 10,
      );
      expect(plan.chunks, hasLength(1));
      expect(plan.chunks.single.limit, 10);
    });

    test('focus в whole-режиме: все разделы с карточками покрыты', () {
      final GenerationPlan plan = build(
        sectionsOf(12, 300),
        capabilities: caps(maxOutput: 2000),
        requestedCards: 24,
      );
      expect(plan.inputStrategy, InputStrategy.wholeDocument);
      expect(plan.chunks.length, greaterThan(1));
      final Set<String> focus = <String>{
        for (final PlannedChunk chunk in plan.chunks) ...chunk.focusSectionIds,
      };
      final Set<String> planned = <String>{
        for (final InputSection section in plan.parts.single.sections)
          if ((plan.allocation?.forSection(section.id) ?? 0) > 0)
            section.promptId,
      };
      expect(focus, planned);
    });
  });
}

extension<T> on T {
  R let<R>(R Function(T value) block) => block(this);
}

/// Оценщик 1 символ = 1 токен (объём материалов задаётся длиной текста).
class _CharEstimator implements ContentTokenEstimator {
  const _CharEstimator();

  @override
  String get version => 'test_char/1';

  @override
  double get charsPerToken => 1;

  @override
  int estimateText(String text) => text.runes.length;

  @override
  ImageTokenEstimate estimateImage({
    int? width,
    int? height,
    required int bytes,
    ImageTokenModel? model,
  }) => const ImageTokenEstimate(
    tokens: 100,
    source: ImageTokenSource.byteHeuristic,
    isAssumption: true,
  );
}
