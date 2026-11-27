import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/generation/generated_card.dart';
import 'package:cardflow/domain/generation/generation_ledger.dart';
import 'package:cardflow/domain/generation/generation_provider.dart';
import 'package:cardflow/domain/generation/generation_request.dart';
import 'package:cardflow/domain/generation/generation_result.dart';
import 'package:cardflow/domain/generation/generation_run.dart';
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

  test('LlmPort отдаёт GenerationResult и номер партии', () async {
    final _StubLlmPort port = _StubLlmPort();
    final GenerationRequest request = GenerationRequest(
      account: account,
      materialsText: 'материал',
      limit: 3,
    );
    final GenerationResult result = await port.generate(request, batchIndex: 1);
    expect(port.calls, <int>[1]);
    expect(result.cards.single.front, 'Q1');
    expect(result.provider, GenerationProvider.openaiCompatible);
    expect(result.model, 'test-model');
  });
}

class _FixedClock implements Clock {
  _FixedClock(this.value);

  final DateTime value;

  @override
  DateTime now() => value;
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

  @override
  Future<GenerationResult> generate(
    GenerationRequest request, {
    required int batchIndex,
  }) async {
    calls.add(batchIndex);
    return GenerationResult(
      provider: GenerationProvider.openaiCompatible,
      model: request.account.modelId,
      promptVersion: 'test',
      cards: <GeneratedCard>[
        GeneratedCard(
          front: 'Q$batchIndex',
          back: 'A',
          cardType: CardType.basic,
        ),
      ],
      usage: const TokenUsage(),
    );
  }
}
