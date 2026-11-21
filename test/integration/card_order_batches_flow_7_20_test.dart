import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/api/generation/generation_pipeline.dart';
import 'package:cardflow/api/generation/generation_plan_builder.dart';
import 'package:cardflow/api/generation/generation_plan_entry.dart';
import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/generation/card_allocator.dart';
import 'package:cardflow/domain/generation/content_token_estimator.dart';
import 'package:cardflow/domain/generation/generated_card.dart';
import 'package:cardflow/domain/generation/generation_chunk_planner.dart';
import 'package:cardflow/domain/generation/generation_error.dart';
import 'package:cardflow/domain/generation/generation_job.dart';
import 'package:cardflow/domain/generation/generation_plan.dart';
import 'package:cardflow/domain/generation/generation_planning_config.dart';
import 'package:cardflow/domain/generation/generation_provider.dart';
import 'package:cardflow/domain/generation/generation_request.dart';
import 'package:cardflow/domain/generation/generation_result.dart';
import 'package:cardflow/domain/generation/generation_run.dart';
import 'package:cardflow/domain/generation/input_planner.dart';
import 'package:cardflow/domain/generation/model_capabilities.dart';
import 'package:cardflow/domain/generation/model_capability_cache.dart';
import 'package:cardflow/domain/generation/model_limits.dart';
import 'package:cardflow/domain/generation/provider_account.dart';
import 'package:cardflow/domain/generation/provider_protocol.dart';
import 'package:cardflow/domain/text/document_format.dart';
import 'package:cardflow/domain/text/parsed_document.dart';

import '../helpers/generation_fakes.dart';

/// Итерация 7.20: production-путь заказа 40 карточек — несколько
/// последовательных партий, сохранение уже полученного, исчерпание материала и
/// отсутствие дублей при восстановлении. Живых API-запросов нет.
void main() {
  const ContentTokenEstimator estimator = _SizedEstimator();

  /// Плотный блок: 1 карточка мягкой ёмкости на 2 блока (ADR-040 §5).
  const String block =
      r'1. Определение phi — это $a=1$, alpha-beta. 2. Термин называется delta, '
      r'понимается как gamma. 3. Величина является omega, представляет собой '
      r'отношение. - sigma $b=2$ 12, 34, 56, 78. ';

  /// Материал с измеренной мягкой ёмкостью (та же эвристика, что в плане).
  ({ParsedDocument document, int capacity}) materialOf(
    int sections,
    int blocksEach,
  ) {
    final StringBuffer buffer = StringBuffer();
    final List<ParsedSection> parsed = <ParsedSection>[];
    var capacity = 0;
    for (var index = 0; index < sections; index++) {
      if (index > 0) buffer.write('\n\n');
      final int start = buffer.length;
      final String text = List<String>.filled(blocksEach, block).join();
      buffer.write(text);
      parsed.add(ParsedSection(start: start, end: buffer.length));
      capacity += SectionFeatures.of(title: '', text: text).capacity;
    }
    return (
      document: ParsedDocument(
        format: DocumentFormat.txt,
        fileName: 'материал.txt',
        text: buffer.toString(),
        sections: parsed,
      ),
      capacity: capacity,
    );
  }

  /// Материал, которому заведомо хватает ёмкости на [cards] карточек.
  ({ParsedDocument document, int capacity}) materialFor(int cards) {
    var sections = (cards / 2).ceil();
    var blocks = 2;
    while (sections <= 2048) {
      final ({ParsedDocument document, int capacity}) material = materialOf(
        sections,
        blocks,
      );
      if (material.capacity >= cards) return material;
      sections *= 2;
      blocks = (blocks / 2).ceil();
    }
    throw StateError('не удалось собрать материал для $cards карточек');
  }

  /// Сборщик плана с партией не больше [ceiling] карточек.
  GenerationPlanBuilder builder({
    int ceiling = 16,
    GenerationPlanningConfig planning = const GenerationPlanningConfig(),
  }) => GenerationPlanBuilder(
    planner: GenerationChunkPlanner(
      estimator: estimator,
      config: GenerationChunkPlannerConfig(
        planning: planning.copyWith(batchCardsCeiling: ceiling),
      ),
    ),
  );

  late FakeGenerationCaller caller;
  late FakeGenerationJobRepository jobs;
  late FakeGenerationCardStore store;

  GenerationPipeline pipeline({
    GenerationPlanBuilder? planBuilder,
    ModelCapabilityCache? capabilityCache,
  }) {
    caller = FakeGenerationCaller();
    jobs = FakeGenerationJobRepository();
    store = FakeGenerationCardStore();
    return GenerationPipeline(
      caller: caller,
      jobRepository: jobs,
      cardStore: store,
      planBuilder: planBuilder ?? builder(),
      capabilityCache: capabilityCache,
      now: () => DateTime.utc(2026, 11, 21, 12),
      jobIdFactory: () => 'job-7-20',
    );
  }

  GenerationRunRequest requestFor(
    int requestedCards, {
    ParsedDocument? document,
  }) => GenerationRunRequest(
    documents: <ParsedDocument>[
      document ?? materialFor(requestedCards).document,
    ],
    account: testProviderAccount(
      presetId: 'deepseek',
      modelId: 'deepseek-chat',
    ),
    deckName: 'Колода',
    requestedCards: requestedCards,
  );

  /// Словарь для различимых формулировок: карточки одной партии не должны
  /// отсеиваться как почти-дубли (сходство триграмм ≥ 0.85).
  const List<String> vocabulary = <String>[
    'анализ',
    'баланс',
    'вектор',
    'график',
    'давление',
    'ёмкость',
    'жёсткость',
    'закон',
    'импульс',
    'контур',
    'лоток',
    'мощность',
    'напряжение',
    'оптика',
    'поток',
    'радиус',
    'смесь',
    'точка',
    'усилие',
    'фаза',
    'химия',
    'цикл',
    'частота',
    'шум',
    'энергия',
    'ядро',
    'квант',
    'линза',
    'масса',
    'норма',
    'объём',
    'плотность',
    'работа',
    'сила',
    'тепло',
    'угол',
    'форма',
    'центр',
    'частица',
    'яркость',
  ];

  /// Сквозной счётчик карточек: каждая формулировка уникальна, чтобы
  /// почти-дубли (сходство триграмм ≥ 0.85) не отсеивали карточки партий.
  var cardCounter = 0;

  GeneratedCard nextCard() {
    final int index = cardCounter++;
    final List<String> words = <String>[
      vocabulary[index % vocabulary.length],
      vocabulary[(index * 7 + 3) % vocabulary.length],
      vocabulary[(index * 11 + 5) % vocabulary.length],
      vocabulary[(index * 13 + 9) % vocabulary.length],
    ];
    return GeneratedCard(
      front: '${words.join(' ')} — что это?',
      back: 'Ответ: ${words.reversed.join(' ')}.',
      cardType: CardType.basic,
    );
  }

  /// Ответ модели: ровно запрошенное число карточек партии (как у провайдера,
  /// который справился с заданием) и, при необходимости, `source_exhausted`.
  GenerationResult replyFor(
    GenerationRequest request,
    int call, {
    bool sourceExhausted = false,
  }) => GenerationResult(
    provider: GenerationProvider.openai,
    model: 'test',
    promptVersion: 'test',
    cards: <GeneratedCard>[
      for (var index = 0; index < request.limit; index++) nextCard(),
    ],
    usage: TokenUsage(
      promptTokens: 10,
      completionTokens: request.limit * 10,
      totalTokens: 10 + request.limit * 10,
    ),
    sourceExhausted: sourceExhausted,
  );

  test(
    'заказ 40: три последовательные партии, все 40 карточек сохранены',
    () async {
      final GenerationPipeline runner = pipeline();
      caller.onGenerate = (GenerationRequest request, int call) async =>
          replyFor(request, call);
      final GenerationRunResult result = await runner.run(requestFor(40));

      final GenerationPlan plan = result.plan!;
      expect(plan.requestedCards, 40);
      expect(
        plan.plannedCards,
        40,
        reason: 'заказ не ограничен бюджетом ответа',
      );
      expect(plan.chunks, hasLength(3));
      expect(
        plan.chunks.map((PlannedChunk chunk) => chunk.limit).toList(),
        <int>[16, 16, 8],
      );
      expect(caller.calls, 3, reason: 'партии выполняются последовательно');
      expect(
        caller.requests
            .map((GenerationRequest request) => request.limit)
            .toList(),
        <int>[16, 16, 8],
      );
      expect(
        result.cards,
        hasLength(40),
        reason: 'карточки всех партий сохранены',
      );
      expect(
        result.cards.map((GeneratedCard card) => card.front).toSet().length,
        40,
      );
      expect(result.status, GenerationJobStatus.done);
      expect(result.jobId, 'job-7-20');
      expect(jobs.saved.last.cardsCount, 40);
    },
  );

  test('предпросмотр и production строят одинаковое число партий', () async {
    final GenerationPlanBuilder planBuilder = builder();
    final GenerationRunRequest request = requestFor(40);
    final ModelCapabilities capabilities = resolveModelCapabilities(
      request.account,
    );
    final GenerationPlan preview = buildRunPlan(
      builder: planBuilder,
      request: request,
      capabilities: capabilities,
    )!;
    final GenerationPipeline runner = pipeline(planBuilder: planBuilder);
    caller.onGenerate = (GenerationRequest request, int call) async =>
        replyFor(request, call);
    final GenerationRunResult result = await runner.run(request);
    expect(preview.plannedCards, 40);
    expect(preview.chunks.length, result.plan!.chunks.length);
    expect(
      preview.chunks.map((PlannedChunk chunk) => chunk.limit).toList(),
      result.plan!.chunks.map((PlannedChunk chunk) => chunk.limit).toList(),
    );
  });

  test('source_exhausted: оставшиеся партии не отправляются', () async {
    // Один раздел: все партии у него в focus, исчерпание останавливает очередь.
    final ({ParsedDocument document, int capacity}) material = materialFor(80);
    final ParsedDocument single = materialOf(1, 400).document;
    final GenerationPipeline runner = pipeline();
    caller.onGenerate = (GenerationRequest request, int call) async =>
        replyFor(request, call, sourceExhausted: true);
    final GenerationRunResult result = await runner.run(
      requestFor(40, document: single),
    );

    expect(caller.calls, 1, reason: 'после исчерпания новые запросы не нужны');
    expect(
      result.cards,
      hasLength(caller.requests.single.limit),
      reason: 'уже созданное сохранено',
    );
    expect(result.skippedBatches, 2);
    expect(result.exhaustedSectionIds, isNotEmpty);
    expect(
      result.shortfallCards,
      greaterThan(0),
      reason: 'недобор объясняется материалом, а не бюджетом',
    );
    expect(result.plan!.plannedCards, 40, reason: 'план не переписывается');
    expect(material.capacity, greaterThan(0));
  });

  test('сбой партии не теряет карточки предыдущих партий', () async {
    final GenerationPipeline runner = pipeline();
    caller.onGenerate = (GenerationRequest request, int call) async {
      if (call == 2) {
        throw const GenerationException(GenerationErrorCode.network);
      }
      return replyFor(request, call);
    };
    final GenerationRunResult result = await runner.run(requestFor(40));
    expect(caller.calls, 3);
    expect(
      result.cards,
      hasLength(caller.requests.first.limit + caller.requests.last.limit),
      reason: 'карточки удачных партий целы, сбойная партия не выдумана',
    );
    expect(result.failures, hasLength(1));
    expect(result.status, GenerationJobStatus.partial);
  });

  test(
    'recovery дробит только проблемную партию и не дублирует карточки',
    () async {
      final GenerationPipeline runner = pipeline();
      caller.onGenerate = (GenerationRequest request, int call) async {
        if (call == 1) {
          throw const GenerationException(GenerationErrorCode.contextOverflow);
        }
        return replyFor(request, call);
      };
      final GenerationRunResult result = await runner.run(requestFor(40));
      final List<GenerationRequest> succeeded = caller.requests.sublist(1);
      expect(
        succeeded.fold<int>(
          0,
          (int sum, GenerationRequest request) => sum + request.limit,
        ),
        40,
        reason: 'ни одна карточка заказа не потеряна при восстановлении',
      );
      expect(result.cards, hasLength(40));
      expect(
        result.cards.map((GeneratedCard card) => card.front).toSet().length,
        40,
        reason: 'дублей нет',
      );
      expect(result.failures, isEmpty);
    },
  );

  test('fragmented: партии внутри частей, сумма = заказ', () async {
    const ProviderAccount account = ProviderAccount(
      id: 'custom',
      label: 'Свой сервер',
      protocol: ProviderProtocol.openaiCompletions,
      baseUrl: 'http://localhost:1234/v1',
      modelId: 'qwen2.5',
    );
    final ParsedDocument document = materialFor(240).document;
    final GenerationRunRequest request = GenerationRunRequest(
      documents: <ParsedDocument>[document],
      account: account,
      deckName: 'Колода',
      requestedCards: 40,
    );
    // Лимит входа берётся от измеренной обвязки запроса, поэтому материал
    // заведомо не помещается целиком и план честно дробится.
    final GenerationPlan baseline = buildRunPlan(
      builder: builder(ceiling: 40),
      request: request,
      capabilities: resolveModelCapabilities(account),
    )!;
    final int fixedTokens = baseline.budget.fixedOverheadTokens;
    expect(fixedTokens, greaterThan(0));
    final ModelCapabilityRecord record = ModelCapabilityRecord(
      accountId: account.id,
      protocol: account.protocol,
      baseUrl: account.baseUrl,
      model: account.modelId,
      fetchedAt: DateTime.utc(2026, 11, 21),
      limits: ModelLimits(
        contextTokens: Sourced<int>(
          128000,
          source: CapabilitySource.providerApi,
          sourceRef: 'https://provider.test/models',
        ),
        maxInputTokens: Sourced<int>(
          (fixedTokens * 2).ceil(),
          source: CapabilitySource.providerApi,
          sourceRef: 'https://provider.test/models',
        ),
        maxOutputTokens: Sourced<int>(
          2000,
          source: CapabilitySource.providerApi,
          sourceRef: 'https://provider.test/models',
        ),
      ),
    );
    final GenerationPipeline runner = pipeline(
      planBuilder: builder(ceiling: 40),
      capabilityCache: _StaticCapabilityCache(record),
    );
    caller.onGenerate = (GenerationRequest request, int call) async =>
        replyFor(request, call);
    final GenerationRunResult result = await runner.run(request);
    final GenerationPlan plan = result.plan!;
    expect(plan.inputStrategy, InputStrategy.fragmented);
    expect(plan.parts.length, greaterThan(1));
    expect(plan.plannedCards, 40);
    expect(plan.chunks.length, greaterThan(plan.parts.length));
    expect(
      plan.chunks.every((PlannedChunk chunk) => chunk.limit <= 5),
      isTrue,
      reason: 'cardsFor(2000) = 5 — вместимость одного ответа',
    );
    expect(result.cards, hasLength(40));
    expect(
      caller.requests.fold<int>(
        0,
        (int sum, GenerationRequest request) => sum + request.limit,
      ),
      40,
    );
  });
}

/// Кэш характеристик модели с одной записью (production-путь резолвера).
class _StaticCapabilityCache implements ModelCapabilityCache {
  const _StaticCapabilityCache(this.record);

  final ModelCapabilityRecord record;

  @override
  Future<void> invalidateAccount(String accountId) async {}

  @override
  Future<ModelCapabilityRecord?> read({
    required String accountId,
    required ProviderProtocol protocol,
    required String baseUrl,
    required String model,
  }) async => accountId == record.accountId ? record : null;

  @override
  Future<List<ModelCapabilityRecord>> readAll() async =>
      <ModelCapabilityRecord>[record];

  @override
  Future<void> write(ModelCapabilityRecord value) async {}
}

/// Оценщик «6 символов = 1 токен»: объём входа задаётся текстом фикстуры.
class _SizedEstimator implements ContentTokenEstimator {
  const _SizedEstimator();

  @override
  String get version => 'test_sized/1';

  @override
  double get charsPerToken => 6;

  @override
  int estimateText(String text) => (text.runes.length / 6).ceil() + 1;

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
