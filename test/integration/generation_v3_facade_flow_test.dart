import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/api/generation/cards_batch_engine.dart';
import 'package:cardflow/api/generation/content_model.dart';
import 'package:cardflow/api/generation/content_model_builder.dart';
import 'package:cardflow/api/generation/generation_v3_facade.dart';
import 'package:cardflow/api/generation/understanding_service.dart';
import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/generation/allocation.dart';
import 'package:cardflow/domain/generation/card_reason_code.dart';
import 'package:cardflow/domain/generation/cards_batch.dart';
import 'package:cardflow/domain/generation/completion_verdict.dart';
import 'package:cardflow/domain/generation/dedup_mark.dart';
import 'package:cardflow/domain/generation/dedup_report.dart';
import 'package:cardflow/domain/generation/generated_card.dart';
import 'package:cardflow/domain/generation/generation_job.dart';
import 'package:cardflow/domain/generation/generation_ledger.dart';
import 'package:cardflow/domain/generation/generation_report.dart';
import 'package:cardflow/domain/generation/generation_provider.dart';
import 'package:cardflow/domain/generation/generation_result.dart';
import 'package:cardflow/domain/generation/knowledge_map.dart';
import 'package:cardflow/domain/generation/metrics_collector.dart';
import 'package:cardflow/domain/generation/model_profile.dart';
import 'package:cardflow/domain/generation/ports.dart';
import 'package:cardflow/domain/generation/provider_account.dart';
import 'package:cardflow/domain/generation/provider_protocol.dart';
import 'package:cardflow/domain/generation/replenish_stage.dart';
import 'package:cardflow/domain/generation/validation/semantic_matcher.dart';
import 'package:cardflow/domain/text/document_format.dart';
import 'package:cardflow/domain/text/parsed_document.dart';

/// Сквозные тесты фасада v3 (TASK «Срез 10», п. 7): от файла до импорта в
/// колоду и `GenerationReport`, без сети — фейковый `LlmPort`.
void main() {
  const ModelProfile profile = ModelProfile(
    id: 'fake-model',
    provider: 'fake',
    contextWindow: 128000,
    maxOutputTokens: 8192,
    supportsJsonSchema: true,
    supportsVision: false,
    concurrency: 1,
  );

  const ProviderAccount account = ProviderAccount(
    id: 'fake-account',
    label: 'Фейк',
    protocol: ProviderProtocol.openai,
    baseUrl: 'https://example.invalid',
    modelId: 'fake-model',
  );

  ParsedDocument docOf(String text) => ParsedDocument(
    format: DocumentFormat.txt,
    fileName: 'лекция.txt',
    text: text,
    sections: <ParsedSection>[ParsedSection(start: 0, end: text.length)],
  );

  /// Материал: [count] блоков, каждый — отдельная единица знания.
  String materialOf(int count) => <String>[
    for (var index = 0; index < count; index++)
      'Утверждение $index: момент силы равен произведению силы на плечо.',
  ].join('\n');

  /// Материал среза 9–13: 12 блоков.
  String material() => materialOf(12);

  /// Understanding без сети: блок → единица с якорем на этот блок.
  Future<UnderstandingResult> understand(Document document) async {
    final List<KnowledgeUnit> units = <KnowledgeUnit>[];
    final List<Block> blocks = document.contentBlocks.toList();
    for (var index = 0; index < blocks.length; index++) {
      final Block block = blocks[index];
      units.add(
        KnowledgeUnit(
          id: 'ku:$index',
          sectionId: block.sectionId,
          topic: 'тема $index',
          kind: KnowledgeUnitKind.definition,
          statement: block.text,
          anchors: <KnowledgeAnchor>[
            KnowledgeAnchor(blockId: block.id, quote: block.text),
          ],
          salience: 0.9,
        ),
      );
    }
    return UnderstandingResult(
      map: KnowledgeMap(documentId: document.fileName, units: units),
      usage: const TokenUsage(promptTokens: 120, completionTokens: 80),
    );
  }

  GenerationV3Facade facade({
    required _FakeLlmPort port,
    required _FakeDeck deck,
    UnderstandingStage? understanding,
    DeckCardsLoader? deckCards,
    DedupMarkSink? dedupMarks,
    RunImporter? importer,
  }) {
    return GenerationV3Facade(
      engine: CardsBatchEngine(
        port: port,
        account: account,
        promptVersion: 'gen-cards-v3',
      ),
      replenish: ReplenishStage(
        port: port,
        account: account,
        clock: _FixedClock(DateTime.utc(2026, 11, 28, 12)),
        outputTokensPerCard: 80,
      ),
      profile: profile,
      understanding: understanding,
      sink: deck,
      importer: importer ?? deck.importRun,
      deckCards: deckCards,
      dedupMarks: dedupMarks,
      promptVersions: const <String, String>{
        'generating': 'gen-cards-v3',
        'replenishing': 'gen-cards-v3',
      },
    );
  }

  test('happy-path «40 из 40»: от файла до колоды и отчёта', () async {
    final Document document = ContentModelBuilder().build(docOf(material()));
    final _FakeLlmPort port = _FakeLlmPort(
      cardsFor: (CardsBatch batch) => batch.cards,
    );
    final _FakeDeck deck = _FakeDeck();

    final GenerationV3Run run = await facade(
      port: port,
      deck: deck,
      understanding: understand,
    ).run(runId: 'run-40', requestedCards: 40, document: document);

    expect(run.report.requested, 40);
    expect(run.report.accepted, 40);
    expect(run.report.isComplete, isTrue, reason: 'заказ закрыт полностью');
    expect(run.report.shortfallReasons, isEmpty);
    expect(run.blockedCards, isEmpty);
    expect(deck.written, 40, reason: 'журнал запуска пишется по ходу');
    expect(run.imported, 40, reason: 'importRun импортировал всё');
    expect(run.report.guards, isNotNull);
    expect(run.report.guards!.maxPasses, ReplenishPolicy.defaultMaxPasses);
    expect(run.report.guards!.wallClock, const Duration(minutes: 10));
  });

  test('partial «12 из 40 exhausted_material»: долг виден числом', () async {
    final Document document = ContentModelBuilder().build(docOf(material()));
    // Модель отдаёт только основную карточку единицы: добор не двигает долг.
    final _FakeLlmPort port = _FakeLlmPort(
      cardsFor: (CardsBatch batch) => <AllocatedCard>[
        for (final AllocatedCard card in batch.cards)
          if (card.angle == null) card,
      ],
    );
    final _FakeDeck deck = _FakeDeck();

    final GenerationV3Run run = await facade(
      port: port,
      deck: deck,
      understanding: understand,
    ).run(runId: 'run-12', requestedCards: 40, document: document);

    expect(run.report.requested, 40);
    expect(run.report.accepted, 12);
    expect(run.report.reason, ReplenishStopReason.exhaustedMaterial);
    expect(run.report.shortfallReasons[ShortfallKind.exhaustedMaterial], 28);
    expect(run.report.isComplete, isFalse);
    expect(run.imported, 12);
  });

  test('300 при 47 единицах: planned 188, exhausted_material, partial, добора '
      'нет', () async {
    // Регресс S12: план повторял слоты и прогон выглядел как полный успех.
    // 47 единиц × 4 различимых слота = 188; 112 слотов заказа не существует.
    final Document document = ContentModelBuilder().build(
      docOf(materialOf(47)),
    );
    final _FakeLlmPort port = _FakeLlmPort(
      cardsFor: (CardsBatch batch) => batch.cards,
    );
    final _FakeDeck deck = _FakeDeck();

    final GenerationV3Run run = await facade(
      port: port,
      deck: deck,
      understanding: understand,
    ).run(runId: 'run-188', requestedCards: 300, document: document);

    expect(
      CompletionVerdict.fromReport(run.report).jobStatus,
      GenerationJobStatus.partial,
      reason: 'ready при 188/300 — не done',
    );
    expect(run.plan.requested, 300, reason: 'заказ не подменяется ёмкостью');
    expect(run.plan.plannedCards, 188);
    expect(run.plan.capacity, 188);
    expect(run.plan.materialLimited, isTrue);
    expect(run.report.accepted, 188);
    expect(run.report.reason, ReplenishStopReason.exhaustedMaterial);
    expect(run.report.materialCapacity, 188);
    expect(run.report.shortfallReasons[ShortfallKind.exhaustedMaterial], 112);
    expect(run.report.isComplete, isFalse);
    expect(run.report.passes, 0, reason: 'добор не запускался: слотов нет');
    expect(
      port.calls,
      run.plan.batches.length,
      reason: 'после первого прохода модель не звали ни разу',
    );
    final Set<String> slots = <String>{
      for (final AllocatedCard card in run.plan.cards)
        '${card.unitId}\u0000${card.angle?.wireName ?? 'primary'}',
    };
    expect(slots, hasLength(188));
    expect(deck.written, 188);
  });

  test('blocked-карточка не попадает в колоду, но не исчезает', () async {
    final Document document = ContentModelBuilder().build(docOf(material()));
    // Первый ответ модели содержит карточку не на языке колоды; добор её
    // заменяет — в колоду не должно попасть ни одной английской карточки.
    var firstCall = true;
    final _FakeLlmPort port = _FakeLlmPort(
      cardsFor: (CardsBatch batch) => batch.cards,
      overrideCard: (GeneratedCard card) {
        if (!firstCall) return null;
        return card.unitId == 'ku:0' && card.angle == null
            ? GeneratedCard(
                front: 'What is the moment of force?',
                back: 'Force times lever arm.',
                cardType: card.cardType,
                unitId: card.unitId,
                quoteRef: card.quoteRef,
              )
            : null;
      },
      onCall: () => firstCall = false,
    );
    final _FakeDeck deck = _FakeDeck();

    final GenerationV3Run run = await facade(
      port: port,
      deck: deck,
      understanding: understand,
    ).run(runId: 'run-blocked', requestedCards: 40, document: document);

    expect(run.blockedCards, hasLength(1));
    expect(run.blockedCards.single.front, contains('moment of force'));
    expect(
      deck.accepted.where(
        (GeneratedCard card) => card.front.contains('moment of force'),
      ),
      isEmpty,
      reason: 'blocked-карточка в колоду не попала',
    );
    expect(run.report.accepted, 40, reason: 'добор заменил блокированную');
    expect(run.imported, 40);
    expect(run.report.invalid, 1, reason: 'одна карточка отброшена проверкой');
  });

  test(
    'prompt-only: единица темы без якорей — карточки «без источника»',
    () async {
      final _FakeLlmPort port = _FakeLlmPort(
        cardsFor: (CardsBatch batch) => batch.cards,
      );
      final _FakeDeck deck = _FakeDeck();

      final GenerationV3Run run = await facade(
        port: port,
        deck: deck,
      ).run(runId: 'run-prompt', requestedCards: 3, theme: 'Закон Архимеда');

      expect(run.map.units.single.kind, KnowledgeUnitKind.topic);
      expect(run.map.units.single.hasAnchors, isFalse);
      expect(run.map.unanchoredUnitIds, <String>{'ku:prompt#0'});
      expect(run.report.accepted, 3);
      expect(deck.written, 3);
    },
  );

  test('гейт добора: quoteOutOfRange не увеличивает accepted, слот открыт, '
      'вердикт не done', () async {
    final Document document = ContentModelBuilder().build(
      docOf('Момент силы равен произведению силы на плечо.'),
    );
    // Модель всегда возвращает карточку с цитатой вне материала: гейт
    // блокирует её и в первом проходе, и в доборе.
    final _FakeLlmPort port = _FakeLlmPort(
      cardsFor: (CardsBatch batch) => batch.cards,
      overrideCard: (GeneratedCard card) => GeneratedCard(
        front: card.front,
        back: card.back,
        cardType: card.cardType,
        unitId: card.unitId,
        quoteRef: 'цитата, которой нет в материале',
      ),
    );
    final _FakeDeck deck = _FakeDeck();

    final GenerationV3Run run = await facade(
      port: port,
      deck: deck,
      understanding: understand,
    ).run(runId: 'run-gate', requestedCards: 1, document: document);

    expect(
      run.report.accepted,
      0,
      reason: 'accepted растёт только после гейта',
    );
    expect(run.acceptedCards, isEmpty);
    expect(deck.written, 0, reason: 'в журнал запуска блокированное не идёт');
    expect(deck.accepted, isEmpty);
    expect(run.report.unfilledSlots, 1, reason: 'слот остался открытым');
    expect(run.report.isComplete, isFalse);
    expect(
      run.blockedCards,
      hasLength(2),
      reason: 'две попытки — две блокировки',
    );
    final CompletionVerdict verdict = CompletionVerdict.fromReport(run.report);
    expect(verdict.isDone, isFalse);
    expect(verdict.outcome, CompletionOutcome.partial);
  });

  test(
    'две попытки на слот: третьего запроса нет, причина — validation_rejects',
    () async {
      final Document document = ContentModelBuilder().build(
        docOf(
          <String>[
            'Момент силы равен произведению силы на плечо.',
            'Импульс тела равен произведению массы на скорость.',
          ].join('\n'),
        ),
      );
      final _FakeLlmPort port = _FakeLlmPort(
        cardsFor: (CardsBatch batch) => batch.cards,
        overrideCard: (GeneratedCard card) => card.unitId == 'ku:0'
            ? GeneratedCard(
                front: card.front,
                back: card.back,
                cardType: card.cardType,
                unitId: card.unitId,
                quoteRef: 'нет такой цитаты',
              )
            : null,
      );
      final _FakeDeck deck = _FakeDeck();

      final GenerationV3Run run = await facade(
        port: port,
        deck: deck,
        understanding: understand,
      ).run(runId: 'run-attempts', requestedCards: 2, document: document);

      expect(ReplenishPolicy.defaultMaxAttemptsPerSlot, 2);
      expect(
        port.calls,
        2,
        reason:
            'первый проход и одна повторная попытка: третьей блокировки нет',
      );
      expect(run.report.accepted, 1, reason: 'второй слот принят');
      expect(run.report.unfilledSlots, 1);
      expect(run.report.reason, ReplenishStopReason.validationRejects);
      expect(run.report.shortfallReasons[ShortfallKind.validationRejects], 1);
      expect(deck.accepted.single.unitId, 'ku:1');
    },
  );

  test('Dedup в фасаде: 3 известные пары помечены своими уровнями, не удалены', () async {
    // Фикстура: 8 единиц = 6 карточек, образующих 3 пары на разных уровнях
    // каскада, и 2 «ловушки» без пары. Тексты подобраны так, чтобы пары
    // срабатывали именно на своих уровнях (см. `semantic_matcher_test`).
    final Map<String, ({String front, String back})> texts =
        <String, ({String front, String back})>{
          'ku:0': (
            front: 'Что такое импульс тела?',
            back: 'Произведение массы тела на его скорость.',
          ),
          // exact: тот же текст байт в байт.
          'ku:1': (
            front: 'Что такое импульс тела?',
            back: 'Произведение массы тела на его скорость.',
          ),
          'ku:2': (front: 'Что такое сила?', back: 'Мера взаимодействия тел.'),
          // normalized: регистр и пунктуация не различаются.
          'ku:3': (front: 'что такое сила', back: 'МЕРА взаимодействия тел'),
          'ku:4': (
            front: 'Как связаны работа и перемещение?',
            back: 'Работа равна произведению силы на перемещение.',
          ),
          // semantic: почти-дубль (добавлено слово), Жаккар ≥ 0.7.
          'ku:5': (
            front: 'Как связаны работа и перемещение тела?',
            back: 'Работа равна произведению силы на перемещение.',
          ),
          'ku:6': (
            front: 'Чем отличается масса от веса?',
            back: 'Масса — мера инертности, вес — сила тяжести.',
          ),
          'ku:7': (
            front: 'Что такое молярная масса?',
            back: 'Масса одного моля вещества.',
          ),
        };
    final Document document = ContentModelBuilder().build(
      docOf(
        <String>[
          for (var index = 0; index < 8; index++)
            'Утверждение $index: момент силы равен произведению силы на плечо.',
        ].join('\n'),
      ),
    );
    final _FakeLlmPort port = _FakeLlmPort(
      cardsFor: (CardsBatch batch) => batch.cards,
      overrideCard: (GeneratedCard card) {
        final ({String front, String back})? text = texts[card.unitId];
        if (text == null) return null;
        return GeneratedCard(
          front: text.front,
          back: text.back,
          cardType: card.cardType,
          unitId: card.unitId,
          quoteRef: card.quoteRef,
        );
      },
    );
    final _FakeDeck deck = _FakeDeck();
    final List<DedupMark> marks = <DedupMark>[];

    final GenerationV3Run run = await facade(
      port: port,
      deck: deck,
      understanding: understand,
      dedupMarks: (String runId, List<DedupMark> written) async {
        marks.addAll(written);
      },
    ).run(runId: 'run-dedup', requestedCards: 8, document: document);

    // Все три пары — на своих уровнях; счётчик отчёта разложен по уровням.
    final DedupReport dedup = run.dedup!;
    expect(dedup.countOf(DedupLevel.exact), 1);
    expect(dedup.countOf(DedupLevel.normalized), 1);
    expect(dedup.countOf(DedupLevel.semantic), 1);
    expect(run.report.duplicatesByLevel[DedupLevel.exact], 1);
    expect(run.report.duplicatesByLevel[DedupLevel.semantic], 1);
    expect(
      run.report.duplicatesByLevel.values.fold<int>(
        0,
        (int sum, int value) => sum + value,
      ),
      3,
    );

    // Дубль не удалён: все 8 карточек приняты, помечены 6 из них.
    expect(run.acceptedCards, hasLength(8), reason: 'ни одна не удалена');
    expect(deck.written, 8, reason: 'в журнал прогона записаны все');
    expect(run.report.accepted, 8);
    expect(run.report.duplicateMarked, 6);
    for (final GeneratedCard card in run.acceptedCards) {
      final bool paired = <String>{
        'ku:0',
        'ku:1',
        'ku:2',
        'ku:3',
        'ku:4',
        'ku:5',
      }.contains(card.unitId);
      expect(
        card.issues.contains(CardIssueCode.possibleDuplicate),
        paired,
        reason: 'пометка «возможный дубль» у ${card.unitId}',
      );
      expect(
        card.gateReasons.contains(CardReasonCode.possibleDuplicate),
        paired,
        reason: 'код пометки для отчёта у ${card.unitId}',
      );
    }

    // duplicateRate — доля произведённых, а не принятых, и непустая.
    final CollectedMetrics metrics = const MetricsCollector().collect(
      run.report,
    );
    expect(metrics.generated, 8);
    expect(metrics.duplicateRate, closeTo(6 / 8, 1e-9));
    expect(metrics.duplicatesByLevel[DedupLevel.semantic], 1);
    expect(metrics.cleanRate, closeTo(2 / 8, 1e-9));

    // Пометки ушли в журнал: 4 уникальных хеша (у exact-пары он один —
    // одинаковое содержимое хранится одной строкой черновика).
    expect(marks, hasLength(4));
    expect(
      marks.where((DedupMark mark) => mark.level == DedupLevel.semantic),
      hasLength(2),
    );
    expect(
      marks
          .where((DedupMark mark) => mark.level == DedupLevel.exact)
          .single
          .isIdenticalContent,
      isTrue,
      reason: 'точный дубль внутри прогона — то же содержимое',
    );
  });

  test('Dedup: пара «уже в колоде» ловится до импорта', () async {
    final Document document = ContentModelBuilder().build(
      docOf('Момент силы равен произведению силы на плечо.'),
    );
    const String inDeckFront = 'Что такое импульс тела?';
    const String inDeckBack = 'Произведение массы тела на его скорость.';
    final _FakeLlmPort port = _FakeLlmPort(
      cardsFor: (CardsBatch batch) => batch.cards,
      overrideCard: (GeneratedCard card) => GeneratedCard(
        front: inDeckFront,
        back: inDeckBack,
        cardType: card.cardType,
        unitId: card.unitId,
        quoteRef: card.quoteRef,
      ),
    );
    final _FakeDeck deck = _FakeDeck();
    final List<String> events = <String>[];
    final List<DedupMark> marks = <DedupMark>[];

    final GenerationV3Run run =
        await facade(
          port: port,
          deck: deck,
          understanding: understand,
          // Колода — источник пар «уже в колоде»; читается до импорта нового.
          deckCards: (String deckId) async => <DedupCard>[
            const DedupCard(
              id: 'deck-card-1',
              front: inDeckFront,
              back: inDeckBack,
            ),
          ],
          dedupMarks: (String runId, List<DedupMark> written) async {
            events.add('dedup');
            marks.addAll(written);
          },
          importer: (String runId) async {
            events.add('import');
            return deck.accepted.length;
          },
        ).run(
          runId: 'run-deck',
          requestedCards: 1,
          document: document,
          targetDeckId: 'deck-42',
        );

    // Пара «новое ↔ уже в колоде» есть в отчёте, импорт не теряет пометку.
    expect(
      run.dedup!.pairs.any((DedupPair pair) => pair.leftId == 'deck-card-1'),
      isTrue,
      reason: 'карточка колоды — левая сторона пары',
    );
    expect(
      marks.map((DedupMark mark) => mark.duplicateOf),
      contains(DedupMark.deckKey('deck-card-1')),
    );
    expect(run.report.duplicateMarked, 1);
    expect(
      run.acceptedCards.single.issues,
      contains(CardIssueCode.possibleDuplicate),
      reason: 'предпросмотр видит «возможный дубль»',
    );
    expect(deck.written, 1, reason: 'помеченная карточка не удалена');
    // Порядок этапов: Dedup до импорта (пометка не «после факта»).
    expect(events, <String>['dedup', 'import']);
  });

  test('скан без текстового слоя: отчёт с причиной, а не падение', () async {
    final Document empty = Document.empty(fileName: 'скан.pdf');
    final _FakeLlmPort port = _FakeLlmPort(
      cardsFor: (CardsBatch batch) => batch.cards,
    );
    final _FakeDeck deck = _FakeDeck();

    final GenerationV3Run run = await facade(
      port: port,
      deck: deck,
      understanding: (Document document) async =>
          UnderstandingResult(map: KnowledgeMap(documentId: document.fileName)),
    ).run(runId: 'run-scan', requestedCards: 3, document: empty);

    expect(run.report.requested, 3);
    expect(run.report.accepted, 0);
    expect(run.report.unfilledSlots, 3);
    expect(run.report.understandingFailures, contains(kNoTextLayerCode));
    expect(run.report.isComplete, isFalse);
    expect(port.calls, 0, reason: 'модель не зовём: понимать нечего');
    expect(deck.written, 0);
  });
}

/// Фейковый `LlmPort`: карточки строятся по партиям плана, без сети.
class _FakeLlmPort implements LlmPort {
  _FakeLlmPort({required this.cardsFor, this.overrideCard, this.onCall});

  final void Function()? onCall;

  final List<AllocatedCard> Function(CardsBatch batch) cardsFor;
  final GeneratedCard? Function(GeneratedCard card)? overrideCard;

  /// Сколько вызовов модели сделал порт (для теста попыток на слот).
  int calls = 0;

  @override
  Future<GenerationResult> generate(
    CardsBatch batch, {
    required ProviderAccount account,
    int? maxOutputTokens,
  }) async {
    calls++;
    final Map<String, KnowledgeUnit> units = <String, KnowledgeUnit>{
      for (final KnowledgeUnit unit in batch.units) unit.id: unit,
    };
    final List<GeneratedCard> cards = <GeneratedCard>[];
    for (final AllocatedCard planned in cardsFor(batch)) {
      final KnowledgeUnit? unit = units[planned.unitId];
      if (unit == null) continue;
      final GeneratedCard card = GeneratedCard(
        front:
            'Вопрос партии ${batch.index}, карточка '
            '${planned.angle?.wireName ?? 'primary'}',
        back: unit.statement,
        cardType: CardType.basic,
        unitId: unit.id,
        angle: planned.angle?.wireName,
        quoteRef: unit.anchors.isEmpty ? null : unit.anchors.first.quote,
      );
      cards.add(overrideCard?.call(card) ?? card);
    }
    onCall?.call();
    return GenerationResult(
      provider: GenerationProvider.openai,
      model: 'fake-model',
      promptVersion: 'gen-cards-v3',
      cards: cards,
      usage: const TokenUsage(promptTokens: 100, completionTokens: 50),
    );
  }
}

/// Журнал запуска + колода-фейк: писалка (`CardSink`) и импорт в одном лице.
class _FakeDeck implements CardSink {
  final List<GeneratedCard> accepted = <GeneratedCard>[];

  /// Сколько карточек записано в журнал запуска.
  int get written => accepted.length;

  @override
  Future<void> save(GeneratedCard card, {required int batchIndex}) async {
    accepted.add(card);
  }

  /// Импорт идемпотентен: колода получает ровно записанное в журнал.
  Future<int> importRun(String runId) async => accepted.length;
}

/// Часы этапа добора.
class _FixedClock implements Clock {
  _FixedClock(this._now);

  final DateTime _now;

  @override
  DateTime now() => _now;
}
