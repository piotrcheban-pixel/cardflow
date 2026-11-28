import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/api/generation/cards_batch_engine.dart';
import 'package:cardflow/api/http/retry_policy.dart';
import 'package:cardflow/api/prompts/cards_prompt.dart';
import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/generation/allocation.dart';
import 'package:cardflow/domain/generation/cards_batch.dart';
import 'package:cardflow/domain/generation/generated_card.dart';
import 'package:cardflow/domain/generation/generation_result.dart';
import 'package:cardflow/domain/generation/knowledge_map.dart';
import 'package:cardflow/domain/generation/model_profile.dart';
import 'package:cardflow/domain/generation/ports.dart';
import 'package:cardflow/domain/generation/provider_account.dart';
import 'package:cardflow/domain/generation/provider_protocol.dart';
import 'package:cardflow/domain/generation/run_card_context.dart';

/// DoD среза 17B, часть 1 (TASK): в запрос этапа Generation попадает контекст
/// «уже создано» — краткие утверждения принятых карточек **прогона** и занятые
/// `unit_id`, а не только принятое текущего батча.
///
/// Тест не подменяет модель: тот же `CardsBatchEngine`, тот же сборщик
/// пользовательского сообщения (`buildCardsUserContent`), что уходит в
/// провайдера. Проверяется только проводка контекста и предел его роста.
void main() {
  const ModelProfile profile = ModelProfile(
    id: 'deepseek-chat',
    provider: 'deepseek',
    contextWindow: 128000,
    maxOutputTokens: 8192,
    supportsJsonSchema: true,
    supportsVision: false,
    concurrency: 1,
  );

  const ProviderAccount account = ProviderAccount(
    id: 'account-1',
    label: 'DeepSeek',
    protocol: ProviderProtocol.openaiCompletions,
    baseUrl: 'https://api.deepseek.test/v1',
    modelId: 'deepseek-chat',
  );

  group('контекст «уже создано» в запросе Generation', () {
    test(
      'шестой запрос несёт утверждения пяти принятых карточек прогона',
      () async {
        final AllocationPlan plan = _sixBatchPlan(profile);
        final _RecordingPort port = _RecordingPort();
        final CardsBatchEngine engine = CardsBatchEngine(
          port: port,
          account: account,
          retryPolicy: RetryPolicy(jitter: () => 0.0),
        );

        final CardsBatchRun run = await engine.run(plan);

        expect(run.accepted, 6);
        expect(port.calls, hasLength(6));

        final String first = buildCardsUserContent(port.calls.first);
        final String sixth = buildCardsUserContent(port.calls.last);

        // Диагноз среза 17B: до правки запрос видел только единицы своей
        // партии, и утверждения уже принятого прогона в него не попадали.
        expect(
          sixth,
          contains('<already_created>'),
          reason: 'шестой запрос обязан нести контекст «уже создано»',
        );
        for (final int index in <int>[0, 1, 2, 3, 4]) {
          expect(
            sixth,
            contains('Утверждение единицы U$index о моменте силы.'),
            reason: 'принятое карточки U$index должно попасть в шестой запрос',
          );
        }
        expect(
          '<statement '.allMatches(sixth).length,
          5,
          reason: 'в контексте ровно пять утверждений — по принятой карточке',
        );
        expect(
          sixth,
          contains('<taken units="U0 U1 U2 U3 U4"/>'),
          reason: 'занятые unit_id перечислены отдельно от утверждений',
        );
        // Первый запрос прогона ничего не «уже создал»: блока нет.
        expect(first, isNot(contains('<already_created>')));
      },
    );

    test('в контекст не попадает принятое чужого содержимого: только unit_id '
        'и утверждение, без ответа и подсказок', () async {
      final AllocationPlan plan = _sixBatchPlan(profile);
      final _RecordingPort port = _RecordingPort();
      final CardsBatchEngine engine = CardsBatchEngine(
        port: port,
        account: account,
        retryPolicy: RetryPolicy(jitter: () => 0.0),
      );

      await engine.run(plan);

      final String sixth = buildCardsUserContent(port.calls.last);
      // Утверждение единицы — то, что модель должна не повторять; ответ
      // (back) и вопрос (front) чужих карточек в контексте не нужны.
      expect(sixth, contains('<already_created>'));
      expect(
        'Ответ U0'.allMatches(sixth).length,
        0,
        reason: 'ответ принятых карточек в контекст не входит',
      );
      expect(
        'Вопрос U0'.allMatches(sixth).length,
        0,
        reason: 'вопрос принятых карточек в контекст не входит',
      );
    });

    test('две карточки одной единицы не дублируют утверждение в контексте', () async {
      final Map<String, int> counts = <String, int>{'U0': 2, 'U1': 1};
      final List<KnowledgeUnit> units = <KnowledgeUnit>[
        _unit('U0'),
        _unit('U1'),
      ];
      final List<AllocatedCard> cards = <AllocatedCard>[
        const AllocatedCard(unitId: 'U0'),
        const AllocatedCard(unitId: 'U0', angle: AllocationAngle.cloze),
        const AllocatedCard(unitId: 'U1'),
      ];
      final AllocationPlan plan = AllocationPlan(
        requested: cards.length,
        profile: profile,
        units: <UnitBudget>[
          for (final KnowledgeUnit unit in units)
            UnitBudget(unit: unit, cards: counts[unit.id]!),
        ],
        cards: cards,
        batches: <AllocationBatch>[
          AllocationBatch(
            index: 0,
            profile: profile,
            cards: <AllocatedCard>[cards[0], cards[2]],
            inputTokens: 100,
            outputTokens: 200,
          ),
          AllocationBatch(
            index: 1,
            profile: profile,
            cards: <AllocatedCard>[cards[1]],
            inputTokens: 100,
            outputTokens: 100,
          ),
        ],
      );
      final _RecordingPort port = _RecordingPort();
      final CardsBatchEngine engine = CardsBatchEngine(
        port: port,
        account: account,
        retryPolicy: RetryPolicy(jitter: () => 0.0),
      );

      final CardsBatchRun run = await engine.run(plan);

      expect(run.accepted, 3);
      final String second = buildCardsUserContent(port.calls[1]);
      // У единицы U0 приняты две карточки (primary и cloze), но утверждение в
      // контексте одно: строки `<statement …>` — по единицам, не по карточкам.
      expect('<statement '.allMatches(second).length, 2);
      expect(
        second,
        contains(
          '<statement unit_id="U0">Утверждение единицы U0 о моменте силы.'
          '</statement>',
        ),
      );
      expect(second, contains('<taken units="U0 U1"/>'));
    });
  });

  group('предел роста контекста (усечение по числу, а не по байтам)', () {
    test('200 принятых единиц дают тот же запрос, что 50: рост обрезан', () {
      final CardsBatch batch = _batchWith(runContext: _context(count: 50));
      final String payload50 = buildCardsUserContent(batch);
      final String payload200 = buildCardsUserContent(
        _batchWith(runContext: _context(count: 200)),
      );

      expect(
        payload200,
        payload50,
        reason: 'за пределами лимита payload не растёт: обрезка по числу',
      );
      expect(
        '<statement '.allMatches(payload200).length,
        kRunContextMaxStatements,
      );
      final RegExpMatch? taken = RegExp(r'<taken units="([^"]*)"/>')
          .firstMatch(payload200);
      expect(taken, isNotNull);
      expect(
        taken!.group(1)!.split(' ').where((String id) => id.isNotEmpty).length,
        kRunContextMaxTakenUnits,
      );
    });

    test(
      'длинное утверждение обрезается по символам, а не тянет весь текст',
      () {
        final String longStatement = 'А' * (kRunContextStatementMaxChars + 80);
        final CardsBatch batch = _batchWith(
          runContext: RunCardContext(
            statements: <CreatedStatement>[
              CreatedStatement(unitId: 'U0', statement: longStatement),
            ],
            takenUnitIds: const <String>['U0'],
          ),
        );

        final String payload = buildCardsUserContent(batch);

        expect(payload, contains('…</statement>'));
        expect(
          payload,
          contains('А' * kRunContextStatementMaxChars),
          reason: 'начало утверждения остаётся',
        );
        expect(
          payload.contains('А' * (kRunContextStatementMaxChars + 1)),
          isFalse,
          reason: 'длиннее предела утверждение не попадает целиком',
        );
      },
    );

    test('утверждения разделов текущей партии идут первыми при усечении', () {
      // 25 утверждений: пять последних — раздел «фокус» партии.
      final RunCardContext context = RunCardContext(
        statements: <CreatedStatement>[
          for (var index = 0; index < 20; index++)
            CreatedStatement(
              unitId: 'F$index',
              statement: 'Чужой раздел $index',
              sectionId: 'doc:другой.md#1',
            ),
          for (var index = 0; index < 5; index++)
            CreatedStatement(
              unitId: 'U$index',
              statement: 'Свой раздел $index',
              sectionId: 'doc:материал.md#0',
            ),
        ],
        takenUnitIds: <String>[
          for (var index = 0; index < 20; index++) 'F$index',
          for (var index = 0; index < 5; index++) 'U$index',
        ],
      );
      final String payload = buildCardsUserContent(
        _batchWith(runContext: context),
      );

      expect(
        '<statement '.allMatches(payload).length,
        kRunContextMaxStatements,
      );
      // Все пять «своих» утверждений попали в запрос, хотя приняты последними.
      for (var index = 0; index < 5; index++) {
        expect(payload, contains('Свой раздел $index'));
      }
      expect(payload, isNot(contains('Свой раздел 5')));
      // И первыми в блоке идут именно они.
      final int firstForeign = payload.indexOf('Чужой раздел 0');
      final int lastOwn = payload.lastIndexOf('Свой раздел 4');
      expect(
        firstForeign,
        greaterThan(payload.indexOf('Свой раздел 0')),
        reason: 'приоритет — у разделов партии',
      );
      expect(lastOwn, lessThan(firstForeign));
    });
  });
}

/// Контекст из [count] утверждений и единиц (для проверки усечения).
RunCardContext _context({required int count}) => RunCardContext(
  statements: <CreatedStatement>[
    for (var index = 0; index < count; index++)
      CreatedStatement(
        unitId: 'U$index',
        statement: 'Утверждение единицы U$index.',
        sectionId: 'doc:материал.md#0',
      ),
  ],
  takenUnitIds: <String>[for (var index = 0; index < count; index++) 'U$index'],
);

/// Партия с заданным контекстом прогона (по одной карточке единиц A и B).
CardsBatch _batchWith({required RunCardContext runContext}) => CardsBatch(
  index: 1,
  units: <KnowledgeUnit>[_unit('A'), _unit('B')],
  cards: const <AllocatedCard>[
    AllocatedCard(unitId: 'A'),
    AllocatedCard(unitId: 'B'),
  ],
  runContext: runContext,
);

/// План из шести партий по одной карточке: каждый запрос — новая единица.
AllocationPlan _sixBatchPlan(ModelProfile profile) {
  final List<KnowledgeUnit> units = <KnowledgeUnit>[
    for (var index = 0; index < 6; index++) _unit('U$index'),
  ];
  final List<AllocatedCard> cards = <AllocatedCard>[
    for (final KnowledgeUnit unit in units) AllocatedCard(unitId: unit.id),
  ];
  return AllocationPlan(
    requested: cards.length,
    profile: profile,
    units: <UnitBudget>[
      for (final KnowledgeUnit unit in units) UnitBudget(unit: unit, cards: 1),
    ],
    cards: cards,
    batches: <AllocationBatch>[
      for (var index = 0; index < cards.length; index++)
        AllocationBatch(
          index: index,
          profile: profile,
          cards: <AllocatedCard>[cards[index]],
          inputTokens: 100,
          outputTokens: 100,
        ),
    ],
  );
}

KnowledgeUnit _unit(String id) => KnowledgeUnit(
  id: id,
  sectionId: 'doc:материал.md#0',
  topic: 'момент силы',
  kind: KnowledgeUnitKind.definition,
  statement: 'Утверждение единицы $id о моменте силы.',
  anchors: <KnowledgeAnchor>[
    KnowledgeAnchor(
      blockId: 'doc:материал.md#0#0',
      quote: 'Цитата материала $id о моменте силы.',
    ),
  ],
  salience: 1,
);

/// Порт, который отвечает на партию ровно её карточками и записывает запросы.
class _RecordingPort implements LlmPort {
  final List<CardsBatch> calls = <CardsBatch>[];

  @override
  Future<GenerationResult> generate(
    CardsBatch batch, {
    required ProviderAccount account,
    int? maxOutputTokens,
  }) async {
    calls.add(batch);
    final List<GeneratedCard> cards = <GeneratedCard>[];
    for (final AllocatedCard planned in batch.cards) {
      final KnowledgeUnit unit = batch.unit(planned.unitId)!;
      cards.add(
        GeneratedCard(
          front: 'Вопрос ${unit.id}',
          back: 'Ответ ${unit.id}',
          cardType: CardType.basic,
          unitId: unit.id,
          angle: planned.angle?.wireName,
          quoteRef: unit.anchors.first.quote,
        ),
      );
    }
    return GenerationResult(
      provider: account.protocol.adapterProvider,
      model: account.modelId,
      promptVersion: cardsPromptVersion,
      cards: cards,
      usage: const TokenUsage(
        promptTokens: 10,
        completionTokens: 5,
        totalTokens: 15,
      ),
    );
  }
}
