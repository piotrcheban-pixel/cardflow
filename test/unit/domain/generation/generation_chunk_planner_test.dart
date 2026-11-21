import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/api/generation/generation_plan_builder.dart';
import 'package:cardflow/domain/generation/content_token_estimator.dart';
import 'package:cardflow/domain/generation/content_unit.dart';
import 'package:cardflow/domain/generation/document_image.dart';
import 'package:cardflow/domain/generation/generation_attachment.dart';
import 'package:cardflow/domain/generation/generation_chunk_planner.dart';
import 'package:cardflow/domain/generation/generation_plan.dart';
import 'package:cardflow/domain/generation/generation_planning_config.dart';
import 'package:cardflow/domain/generation/input_planner.dart';
import 'package:cardflow/domain/generation/model_capabilities.dart';
import 'package:cardflow/domain/text/document_format.dart';
import 'package:cardflow/domain/text/parsed_document.dart';

/// Планировщик итерации 7.18 (ADR-040): стратегия входа, распределение,
/// партии, покрытие и предохранители.
void main() {
  const GenerationPlanBuilder builder = GenerationPlanBuilder();
  const GenerationOverheadTokens overhead = GenerationOverheadTokens(
    systemPromptTokens: 1000,
    schemaTokens: 200,
    wrapperTokens: 100,
    taskTailTokens: 30,
  );

  ModelCapabilities caps({
    int? context = 128000,
    int? maxOutput,
    int? maxCards,
    bool vision = false,
  }) => ModelCapabilities(
    contextWindowTokens: context,
    contextSource: context == null
        ? CapabilitySource.unknown
        : CapabilitySource.officialCatalog,
    maxOutputTokens: maxOutput,
    maxCardsPerRequest: maxCards,
    supportsVision: vision,
  );

  ParsedDocument docOf(
    String fileName,
    List<String> sections, {
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
      fileName: fileName,
      text: buffer.toString(),
      sections: parsed,
      images: images,
    );
  }

  String words(int count) => List<String>.filled(count, 'слово').join(' ');

  GenerationPlan planFor(
    List<ParsedDocument> documents, {
    ModelCapabilities? capabilities,
    int? requestedCards,
    GenerationChunkPlannerConfig config = const GenerationChunkPlannerConfig(),
  }) =>
      GenerationChunkPlanner(
        config: config,
        estimator: const _MultiplierEstimator(1),
      ).plan(
        inventory: builder.inventoryOf(documents: documents),
        capabilities: capabilities ?? caps(),
        overhead: overhead,
        requestedCards: requestedCards,
      );

  List<String> partIds(GenerationPlan plan) => <String>[
    for (final InputPart part in plan.parts)
      part.sections.map((InputSection s) => s.promptId).join('+'),
  ];

  group('валидность и предохранители', () {
    test('пустой инвентарь — пустой валидный план', () {
      final GenerationPlan plan = planFor(const <ParsedDocument>[]);
      expect(plan.chunks, isEmpty);
      expect(plan.validity.isValid, isTrue);
      expect(plan.isExecutable, isFalse);
      expect(plan.inputStrategy, InputStrategy.promptOnly);
    });

    test('крошечное окно: план невалиден до сети', () {
      final GenerationPlan plan = planFor(<ParsedDocument>[
        docOf('big.txt', <String>[
          for (var index = 0; index < 40; index++)
            'Раздел $index. ${words(400)}',
        ]),
      ], capabilities: caps(context: 1500));
      expect(plan.validity.isInvalid, isTrue);
      expect(
        plan.validity.reason,
        anyOf(
          PlanInvalidReason.contextWindowTooSmall,
          PlanInvalidReason.tooManyChunks,
          PlanInvalidReason.unitTooLarge,
        ),
      );
      expect(plan.chunks, isEmpty);
    });

    test('раздел больше бюджета части — unitTooLarge', () {
      final GenerationPlan plan = planFor(<ParsedDocument>[
        docOf('one.txt', <String>[words(4000)]),
      ], capabilities: caps(context: 9000, maxOutput: 2000));
      expect(plan.validity.isInvalid, isTrue);
      expect(plan.validity.reason, PlanInvalidReason.unitTooLarge);
    });

    test('вложения без Vision — невыполнимый план, а не тишина', () {
      final GenerationPlan plan =
          GenerationChunkPlanner(estimator: const _MultiplierEstimator(1)).plan(
            inventory: builder.inventoryOf(
              documents: const <ParsedDocument>[],
              attachments: <GenerationAttachment>[
                GenerationAttachment(
                  fileName: 'scan.pdf',
                  mediaType: AttachmentMediaType.png,
                  bytes: Uint8List.fromList(<int>[1, 2, 3, 4]),
                  pageNumber: 1,
                  groupKey: 'scan.pdf',
                ),
              ],
            ),
            capabilities: caps(),
            overhead: overhead,
          );
      expect(plan.validity.isInvalid, isTrue);
      expect(plan.validity.reason, PlanInvalidReason.imagesWithoutVision);
    });

    test('предохранитель maxChunks ограничивает число частей', () {
      final GenerationPlan plan = planFor(
        <ParsedDocument>[
          docOf('many.txt', <String>[
            for (var index = 0; index < 60; index++)
              'Раздел $index. ${words(300)}',
          ]),
        ],
        capabilities: caps(context: 6000, maxOutput: 1500),
        config: const GenerationChunkPlannerConfig(maxChunks: 3),
      );
      expect(plan.validity.isInvalid, isTrue);
      expect(plan.validity.reason, PlanInvalidReason.tooManyChunks);
    });

    test('карта покрытия: каждая единица ровно один раз на часть', () {
      final ParsedDocument document = docOf('cover.txt', <String>[
        'Первый абзац.\n\nВторой абзац.',
        'Третий раздел. ${words(80)}',
      ]);
      final GenerationPlan plan = planFor(<ParsedDocument>[
        document,
      ], requestedCards: 5);
      final ContentInventory inventory = builder.inventoryOf(
        documents: <ParsedDocument>[document],
      );
      final GenerationPlanCoverage coverage = GenerationPlanCoverage.check(
        inventory: inventory,
        plan: plan,
      );
      expect(coverage.isComplete, isTrue, reason: '$coverage');
    });
  });

  group('стратегия входа', () {
    test('документ помещается целиком — wholeDocument, один источник', () {
      final GenerationPlan plan = planFor(<ParsedDocument>[
        docOf('small.txt', <String>['Раздел 1. ${words(100)}', 'Раздел 2.']),
      ], requestedCards: 10);
      expect(plan.inputStrategy, InputStrategy.wholeDocument);
      expect(plan.partCount, 1);
      expect(plan.chunks, isNotEmpty);
      expect(plan.parts.single.materialsText, contains('## [s1]'));
      expect(plan.parts.single.materialsText, startsWith('Файл: small.txt'));
    });

    test('документ не помещается — минимальное число частей, порядок цел', () {
      final GenerationPlan plan = planFor(
        <ParsedDocument>[
          docOf('big.txt', <String>[
            for (var index = 0; index < 30; index++)
              'Раздел $index. ${words(300)}',
          ]),
        ],
        capabilities: caps(context: 6000, maxOutput: 1500),
        requestedCards: 10,
      );
      expect(plan.validity.isInvalid, isFalse);
      expect(plan.inputStrategy, InputStrategy.fragmented);
      expect(plan.partCount, greaterThan(1));
      final List<String> sections = <String>[
        for (final InputPart part in plan.parts)
          for (final InputSection section in part.sections) section.promptId,
      ];
      final List<int> numbers = <int>[
        for (final String id in sections) int.parse(id.substring(1)),
      ];
      expect(numbers, List<int>.generate(numbers.length, (int i) => i + 1));
    });

    test('разбиение входа не зависит от числа карточек', () {
      final List<ParsedDocument> documents = <ParsedDocument>[
        docOf('stable.txt', <String>[
          for (var index = 0; index < 24; index++)
            'Раздел $index. ${words(400)}',
        ]),
      ];
      final List<GenerationPlan> plans = <int>[10, 50, 100]
          .map(
            (int requested) => planFor(
              documents,
              capabilities: caps(context: 20000, maxOutput: 2000),
              requestedCards: requested,
            ),
          )
          .toList();
      expect(plans[0].partCount, plans[1].partCount);
      expect(plans[1].partCount, plans[2].partCount);
      expect(partIds(plans[0]), partIds(plans[1]));
      expect(partIds(plans[1]), partIds(plans[2]));
      expect(
        plans[0].chunks.map((PlannedChunk c) => c.limit).toList(),
        isNot(plans[2].chunks.map((PlannedChunk c) => c.limit).toList()),
      );
    });

    test('неизвестное окно — допущение и честное предупреждение', () {
      final GenerationPlan plan = planFor(
        <ParsedDocument>[
          docOf('u.txt', <String>['Раздел. ${words(200)}']),
        ],
        capabilities: caps(context: null),
        requestedCards: 5,
      );
      expect(plan.validity.isValid, isTrue);
      expect(
        plan.validity.warnings,
        contains(PlanWarningCode.contextUnconfirmed),
      );
      expect(plan.budget.contextWindowTokens, isNull);
      expect(plan.parts.single.materialsText, isNotEmpty);
    });
  });

  group('распределение и партии', () {
    test('заказ 5 — сумма лимитов 5 и каждый ≥ 1', () {
      final GenerationPlan plan = planFor(<ParsedDocument>[
        docOf('a.txt', <String>[
          for (var index = 0; index < 3; index++)
            'Раздел $index. ${words(400)}',
        ]),
      ], requestedCards: 5);
      expect(plan.chunks, isNotEmpty);
      expect(plan.plannedCards, 5);
      for (final PlannedChunk chunk in plan.chunks) {
        expect(chunk.limit, greaterThanOrEqualTo(1));
      }
    });

    test('большой заказ: партии ограничены cardsFor(maxTokens)', () {
      const GenerationPlanningConfig config = GenerationPlanningConfig();
      final GenerationPlan plan = planFor(
        <ParsedDocument>[
          docOf('big.txt', <String>[
            for (var index = 0; index < 40; index++)
              'Раздел $index. ${words(200)}',
          ]),
        ],
        capabilities: caps(maxOutput: 8192),
        requestedCards: 100,
      );
      final int perBatch = config.cardsFor(plan.outputReserveTokens!);
      final int cap = perBatch < config.batchCardsCeiling
          ? perBatch
          : config.batchCardsCeiling;
      for (final PlannedChunk chunk in plan.chunks) {
        expect(chunk.limit, lessThanOrEqualTo(cap));
      }
      expect(
        plan.chunks.fold<int>(0, (int sum, PlannedChunk c) => sum + c.limit),
        100,
      );
    });

    test(
      'мало материала: заказ сохранён, причина материала отдельно (7.20)',
      () {
        final GenerationPlan plan = planFor(<ParsedDocument>[
          docOf('tiny.txt', <String>['Короткий раздел.']),
        ], requestedCards: 100);
        // 7.20: мягкая ёмкость больше не режет заказ (было plannedCards < 100).
        expect(plan.plannedCards, 100);
        expect(
          plan.validity.warnings,
          contains(PlanWarningCode.materialCapacityBelowRequested),
        );
        expect(
          plan.validity.warnings,
          isNot(contains(PlanWarningCode.requestedAbovePlan)),
        );
      },
    );

    test('maxCardsPerRequest ограничивает размер партии', () {
      final GenerationPlan plan = planFor(
        <ParsedDocument>[
          docOf('cards.txt', <String>[
            for (var index = 0; index < 10; index++)
              'Раздел $index. ${words(100)}',
          ]),
        ],
        capabilities: caps(maxCards: 4),
        requestedCards: 40,
      );
      for (final PlannedChunk chunk in plan.chunks) {
        expect(chunk.limit, lessThanOrEqualTo(4));
      }
    });

    test('whole-режим: focus покрывает разделы с карточками', () {
      final GenerationPlan plan = planFor(
        <ParsedDocument>[
          docOf('focus.txt', <String>[
            for (var index = 0; index < 8; index++)
              'Раздел $index. ${words(120)}',
          ]),
        ],
        capabilities: caps(maxOutput: 2000),
        requestedCards: 20,
      );
      expect(plan.inputStrategy, InputStrategy.wholeDocument);
      expect(plan.chunks.length, greaterThan(1));
      final Set<String> focus = <String>{
        for (final PlannedChunk chunk in plan.chunks) ...chunk.focusSectionIds,
      };
      final Set<String> expected = <String>{
        for (final InputSection section in plan.parts.single.sections)
          if ((plan.allocation?.forSection(section.id) ?? 0) > 0)
            section.promptId,
      };
      expect(focus, expected);
      for (final PlannedChunk chunk in plan.chunks) {
        expect(chunk.focusSectionIds, isNotEmpty);
        expect(chunk.materialsText, plan.parts.single.materialsText);
      }
    });
  });

  group('prompt-only через тот же планировщик', () {
    test('тема без файлов: prompt-only чанки через allowPromptOnly', () {
      final GenerationPlan plan =
          GenerationChunkPlanner(estimator: const _MultiplierEstimator(1)).plan(
            inventory: builder.inventoryOf(documents: const <ParsedDocument>[]),
            capabilities: caps(),
            overhead: overhead,
            requestedCards: 40,
            wishes: 'Тема: оптика',
            allowPromptOnly: true,
          );
      expect(plan.mode, GenerationMode.promptOnly);
      expect(plan.chunks, isNotEmpty);
      for (final PlannedChunk chunk in plan.chunks) {
        expect(chunk.isPromptOnly, isTrue);
        expect(chunk.materialsText, isEmpty);
      }
      expect(plan.plannedCards, 40);
    });

    test('без темы пустой инвентарь — пустой план, не ошибка', () {
      final GenerationPlan plan =
          GenerationChunkPlanner(estimator: const _MultiplierEstimator(1)).plan(
            inventory: builder.inventoryOf(documents: const <ParsedDocument>[]),
            capabilities: caps(),
            overhead: overhead,
            allowPromptOnly: true,
          );
      expect(plan.chunks, isEmpty);
      expect(plan.validity.isValid, isTrue);
    });
  });

  group('сообщение и стабильность', () {
    test('обвязка P видна в трассировке бюджета', () {
      final GenerationPlan plan = planFor(<ParsedDocument>[
        docOf('p.txt', <String>['Раздел.']),
      ], requestedCards: 1);
      expect(plan.budget.systemPromptTokens, overhead.systemPromptTokens);
      expect(plan.budget.schemaTokens, overhead.schemaTokens);
      expect(
        plan.budget.fixedOverheadTokens,
        overhead.fixedTokens,
        reason: 'P = промпт + схема + обёртка + хвост task',
      );
    });

    test('оглавление и id разделов стабильны во всех партиях whole', () {
      final GenerationPlan plan = planFor(
        <ParsedDocument>[
          docOf('s.txt', <String>[
            for (var index = 0; index < 6; index++)
              'Раздел $index. ${words(80)}',
          ]),
        ],
        capabilities: caps(maxOutput: 2000),
        requestedCards: 30,
      );
      expect(plan.chunks.length, greaterThan(1));
      final String first = plan.chunks.first.materialsText;
      for (final PlannedChunk chunk in plan.chunks) {
        expect(chunk.materialsText, first);
      }
      expect(first, contains('## [s1]'));
    });

    test('детерминизм: одинаковые входы — одинаковый план', () {
      final List<ParsedDocument> documents = <ParsedDocument>[
        docOf('d.txt', <String>[
          for (var index = 0; index < 12; index++)
            'Раздел $index. ${words(150)}',
        ]),
      ];
      final GenerationPlan first = planFor(documents, requestedCards: 25);
      final GenerationPlan second = planFor(documents, requestedCards: 25);
      expect(first.partCount, second.partCount);
      expect(
        first.chunks.map((PlannedChunk c) => c.limit).toList(),
        second.chunks.map((PlannedChunk c) => c.limit).toList(),
      );
      for (var index = 0; index < first.chunks.length; index++) {
        expect(
          first.chunks[index].materialsText,
          second.chunks[index].materialsText,
        );
      }
    });
  });
}

/// Оценщик-множитель: 1 символ = [perChar] токенов (для планов на малом тексте).
class _MultiplierEstimator implements ContentTokenEstimator {
  const _MultiplierEstimator(this.perChar);

  final int perChar;

  @override
  String get version => 'test_multiplier/1';

  @override
  double get charsPerToken => 1 / perChar;

  @override
  int estimateText(String text) => text.runes.length * perChar;

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
