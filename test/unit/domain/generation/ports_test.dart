import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/generation/allocation.dart';
import 'package:cardflow/domain/generation/cards_batch.dart';
import 'package:cardflow/domain/generation/generated_card.dart';
import 'package:cardflow/domain/generation/generation_ledger.dart';
import 'package:cardflow/domain/generation/generation_provider.dart';
import 'package:cardflow/domain/generation/generation_result.dart';
import 'package:cardflow/domain/generation/generation_run.dart';
import 'package:cardflow/domain/generation/knowledge_map.dart';
import 'package:cardflow/domain/generation/ports.dart';
import 'package:cardflow/domain/generation/provider_account.dart';
import 'package:cardflow/domain/generation/provider_protocol.dart';

/// Срез 2 (TASK.txt): порты этапов прогона. Контракт должен быть реализуем
/// без Dio, drift и UI — это проверяют фейки ниже (ADR-050, ARCH §2).
void main() {
  const ProviderAccount account = ProviderAccount(
    id: 'test-account',
    label: 'Тест',
    protocol: ProviderProtocol.openaiCompletions,
    baseUrl: 'https://example.test/v1',
    modelId: 'test-model',
  );

  test('Clock: время инжектируется, а не берётся из DateTime.now', () {
    final Clock clock = _FixedClock(DateTime.utc(2026, 11, 27, 12));
    expect(clock.now(), DateTime.utc(2026, 11, 27, 12));
  });

  test('CancellationSignal: этап видит отмену, не зная про Dio', () {
    final _FakeCancellation cancellation = _FakeCancellation();
    expect(cancellation.isCancelled, isFalse);
    cancellation.cancel();
    expect(cancellation.isCancelled, isTrue);
  });

  test('ProgressSink получает этап и журнал прогона', () {
    final _RecordingProgressSink sink = _RecordingProgressSink();
    sink.report(
      GenerationStage.generating,
      GenerationLedger.fromBudgets(const <int>[2]),
    );
    expect(sink.reports, <(GenerationStage, int)>[
      (GenerationStage.generating, 0),
    ]);
  });

  test('CardSink принимает карточку вместе с номером партии', () async {
    final _RecordingCardSink sink = _RecordingCardSink();
    const GeneratedCard card = GeneratedCard(
      front: 'Вопрос',
      back: 'Ответ',
      cardType: CardType.basic,
    );
    await sink.save(card, batchIndex: 3);
    expect(sink.saved, <String>['3:Вопрос']);
  });

  test('KnowledgeMapCache читает и пишет карту по документу и хешу', () async {
    final _MemoryKnowledgeMapCache cache = _MemoryKnowledgeMapCache();
    expect(await cache.read(documentId: 'doc-1', contentHash: 'hash'), isNull);
    await cache.write(
      documentId: 'doc-1',
      contentHash: 'hash',
      map: 'карта знаний',
    );
    expect(
      await cache.read(documentId: 'doc-1', contentHash: 'hash'),
      'карта знаний',
    );
    expect(await cache.read(documentId: 'doc-2', contentHash: 'hash'), isNull);
  });

  test(
    'LlmPort принимает партию единиц и аккаунт, отдаёт GenerationResult',
    () async {
      final _StubLlmPort port = _StubLlmPort();
      final CardsBatch batch = _batch();
      final GenerationResult result = await port.generate(
        batch,
        account: account,
      );
      expect(port.calls, <int>[0]);
      expect(port.lastUnitIds, <String>['ku:doc#0']);
      expect(result.cards.single.front, 'Q0');
      expect(result.provider, GenerationProvider.openaiCompatible);
      expect(result.model, 'test-model');
    },
  );
}

CardsBatch _batch() => CardsBatch(
  index: 0,
  units: <KnowledgeUnit>[_unit()],
  cards: const <AllocatedCard>[AllocatedCard(unitId: 'ku:doc#0')],
);

KnowledgeUnit _unit() => KnowledgeUnit(
  id: 'ku:doc#0',
  sectionId: 'doc:файл.md#0',
  topic: 'тема',
  kind: KnowledgeUnitKind.definition,
  statement: 'Моментом силы называют произведение силы на плечо.',
  anchors: const <KnowledgeAnchor>[
    KnowledgeAnchor(blockId: 'doc:файл.md#0#0', quote: 'Момент силы — …'),
  ],
);

class _FixedClock implements Clock {
  _FixedClock(this.value);

  final DateTime value;

  @override
  DateTime now() => value;
}

class _FakeCancellation implements CancellationSignal {
  bool _cancelled = false;

  @override
  bool get isCancelled => _cancelled;

  void cancel() => _cancelled = true;
}

class _RecordingProgressSink implements ProgressSink {
  final List<(GenerationStage, int)> reports = <(GenerationStage, int)>[];

  @override
  void report(GenerationStage stage, GenerationLedger ledger) {
    reports.add((stage, ledger.accepted));
  }
}

class _RecordingCardSink implements CardSink {
  final List<String> saved = <String>[];

  @override
  Future<void> save(GeneratedCard card, {required int batchIndex}) async {
    saved.add('$batchIndex:${card.front}');
  }
}

class _MemoryKnowledgeMapCache implements KnowledgeMapCache<String> {
  final Map<String, String> _store = <String, String>{};

  @override
  Future<String?> read({
    required String documentId,
    required String contentHash,
  }) async => _store[_key(documentId, contentHash)];

  @override
  Future<void> write({
    required String documentId,
    required String contentHash,
    required String map,
  }) async {
    _store[_key(documentId, contentHash)] = map;
  }

  String _key(String documentId, String contentHash) =>
      '$documentId#$contentHash';
}

class _StubLlmPort implements LlmPort {
  final List<int> calls = <int>[];
  List<String> lastUnitIds = const <String>[];

  @override
  Future<GenerationResult> generate(
    CardsBatch batch, {
    required ProviderAccount account,
    int? maxOutputTokens,
  }) async {
    calls.add(batch.index);
    lastUnitIds = <String>[for (final unit in batch.units) unit.id];
    return GenerationResult(
      provider: GenerationProvider.openaiCompatible,
      model: account.modelId,
      promptVersion: 'test',
      cards: <GeneratedCard>[
        GeneratedCard(
          front: 'Q${batch.index}',
          back: 'A',
          cardType: CardType.basic,
        ),
      ],
      usage: const TokenUsage(),
    );
  }
}
