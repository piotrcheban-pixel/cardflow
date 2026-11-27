import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/api/generation/cards_batch_engine.dart';
import 'package:cardflow/api/generation/content_model.dart';
import 'package:cardflow/api/generation/content_model_builder.dart';
import 'package:cardflow/api/generation/generation_v3_facade.dart';
import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/generation/allocation.dart';
import 'package:cardflow/domain/generation/cards_batch.dart';
import 'package:cardflow/domain/generation/generated_card.dart';
import 'package:cardflow/domain/generation/generation_ledger.dart';
import 'package:cardflow/domain/generation/generation_provider.dart';
import 'package:cardflow/domain/generation/generation_result.dart';
import 'package:cardflow/domain/generation/knowledge_map.dart';
import 'package:cardflow/domain/generation/model_profile.dart';
import 'package:cardflow/domain/generation/ports.dart';
import 'package:cardflow/domain/generation/provider_account.dart';
import 'package:cardflow/domain/generation/provider_protocol.dart';
import 'package:cardflow/domain/generation/replenish_stage.dart';
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

  /// Материал: 12 блоков, каждый — отдельная единица знания.
  String material() => <String>[
    for (var index = 0; index < 12; index++)
      'Утверждение $index: момент силы равен произведению силы на плечо.',
  ].join('\n');

  /// Understanding без сети: блок → единица с якорем на этот блок.
  Future<KnowledgeMap> understand(Document document) async {
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
    return KnowledgeMap(documentId: document.fileName, units: units);
  }

  GenerationV3Facade facade({
    required _FakeLlmPort port,
    required _FakeDeck deck,
    UnderstandingStage? understanding,
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
      importer: deck.importRun,
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
}

/// Фейковый `LlmPort`: карточки строятся по партиям плана, без сети.
class _FakeLlmPort implements LlmPort {
  _FakeLlmPort({required this.cardsFor, this.overrideCard, this.onCall});

  final void Function()? onCall;

  final List<AllocatedCard> Function(CardsBatch batch) cardsFor;
  final GeneratedCard? Function(GeneratedCard card)? overrideCard;

  @override
  Future<GenerationResult> generate(
    CardsBatch batch, {
    required ProviderAccount account,
    int? maxOutputTokens,
  }) async {
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
