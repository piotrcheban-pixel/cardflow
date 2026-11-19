/// План сценариев live-испытаний и их предварительная стоимость
/// (TASK 04, разделы 6–7).
///
/// Здесь одна точка правды для чисел, которые попадают в отчёты и в план
/// TASK 05: сколько запросов ожидается, сколько токенов на запрос и сколько
/// это может стоить. Значения — **оценка сверху** по реальным размерам
/// системного промпта (`gen-ru-v7`, ~16,4 тыс. символов ≈ 6,6 тыс. токенов) и
/// канонической JSON-схемы (~2,2 тыс. токенов), а не по «типовым» числам
/// провайдера. Фактические токены придут в `usage` и будут записаны в
/// `LiveRunRecord`.
library;

import 'dart:math' as math;

import 'live_cost.dart';
import 'live_pricing.dart';
import 'live_test_config.dart';

/// Лимит вывода по умолчанию приложения (`GenerationChunkPlannerConfig`
/// через бюджет плана) — по нему считается число запросов.
const int kLiveOutputCapTokens = 8192;

/// Конверт JSON на запрос (план: `kBudgetJsonEnvelopeTokens`).
const int kLiveJsonEnvelopeTokens = 16;

/// Ожидаемый вывод на одну карточку, токенов (факт: ~200–400 у DeepSeek).
const int kLiveOutputPerCardTokens = 500;

/// Карточек на запрос по лимиту вывода: `(8192 − 16) / 1024`.
int get kLiveCardsPerRequest =>
    (kLiveOutputCapTokens - kLiveJsonEnvelopeTokens) ~/ 1024;

/// Описание одного сценария испытаний.
class LiveScenarioPlan {
  /// Создаёт план.
  const LiveScenarioPlan({
    required this.id,
    required this.title,
    required this.kind,
    required this.requestedCards,
    required this.inputTokensPerRequest,
    required this.outputTokensPerRequest,
    required this.images,
    required this.expectsMultipleRequests,
    this.requiresVision = false,
  });

  /// Машинное имя (`prompt_only_short`, ...).
  final String id;

  /// Человеческое название (Test A…).
  final String title;

  /// Какой флаг сценария включает прогон.
  final LiveScenario kind;

  /// Сколько карточек заказано.
  final int requestedCards;

  /// Ожидаемый вход на запрос (обвязка + материалы/тема + сводка).
  final int inputTokensPerRequest;

  /// Ожидаемый выход на запрос (резерв считается отдельно).
  final int outputTokensPerRequest;

  /// Сколько изображений приложено к запросу.
  final int images;

  /// Ожидается ли более одного запроса (несколько фрагментов).
  final bool expectsMultipleRequests;

  /// Нужна ли модель с Vision.
  final bool requiresVision;

  /// Ожидаемое число запросов по лимиту вывода.
  int get expectedRequests {
    final int cardsPerRequest = math.max(1, kLiveCardsPerRequest);
    return math.max(1, (requestedCards / cardsPerRequest).ceil());
  }

  /// Число токенов входа за весь сценарий.
  int get totalInputTokens => expectedRequests * inputTokensPerRequest;

  /// Число токенов выхода за весь сценарий.
  int get totalOutputTokens => expectedRequests * outputTokensPerRequest;

  /// Предварительная стоимость для конфигурации [config].
  LiveCostEstimate costFor(LiveTestConfig config) {
    return estimateLiveCost(
      provider: config.provider,
      model: config.model,
      requests: expectedRequests,
      inputTokensPerRequest: inputTokensPerRequest,
      outputTokensPerRequest: outputTokensPerRequest,
    );
  }

  /// JSON для отчёта.
  Map<String, Object?> toJson(LiveTestConfig config) => <String, Object?>{
    'id': id,
    'title': title,
    'requestedCards': requestedCards,
    'expectedRequests': expectedRequests,
    'inputTokensPerRequest': inputTokensPerRequest,
    'outputTokensPerRequest': outputTokensPerRequest,
    'images': images,
    'requiresVision': requiresVision,
    'priceVerifiedOn': livePriceFor(config.provider, config.model)?.verifiedOn,
    'cost': costFor(config).toJson(),
  };
}

/// Планы испытаний Test A–E (Test F — локальная симуляция, без оплаты).
///
/// Числа входа (измерены на коде, а не «типовые»):
/// - базовая обвязка запроса ≈ 7,0 тыс. токенов: системный промпт `gen-ru-v7`
///   16 413 символов ≈ 6 566 токенов, каноническая JSON-схема 866 символов ≈
///   347, обёртка `<materials>/<wishes>/<limit>` ≈ 44;
/// - короткая тема + пожелания ≈ 0,1 тыс.;
/// - фрагмент документа Test C ≈ 0,3 тыс. (весь текст), Test D ≈ 1,5–2 тыс.;
/// - сводка продолжения prompt-only ≈ до 1,2 тыс. на запрос после первого;
/// - изображение (Test E) по консервативной оценке ≈ 1,5 тыс. на картинку;
/// - запас 10 % на неточность эвристики (2,5 симв./токен) и разброс моделей.
const List<LiveScenarioPlan> kLiveScenarioPlans = <LiveScenarioPlan>[
  LiveScenarioPlan(
    id: 'prompt_only_short',
    title: 'Test A — короткий prompt-only',
    kind: LiveScenario.promptOnly,
    requestedCards: 3,
    inputTokensPerRequest: 7800,
    outputTokensPerRequest: 1500,
    images: 0,
    expectsMultipleRequests: false,
  ),
  LiveScenarioPlan(
    id: 'prompt_only_many_20',
    title: 'Test B — 20 карточек prompt-only',
    kind: LiveScenario.promptOnlyMany,
    requestedCards: 20,
    inputTokensPerRequest: 9000,
    outputTokensPerRequest: 3500,
    images: 0,
    expectsMultipleRequests: true,
  ),
  LiveScenarioPlan(
    id: 'small_document',
    title: 'Test C — небольшой документ (6 карточек)',
    kind: LiveScenario.smallDocument,
    requestedCards: 6,
    inputTokensPerRequest: 8200,
    outputTokensPerRequest: 3000,
    images: 0,
    expectsMultipleRequests: false,
  ),
  LiveScenarioPlan(
    id: 'big_document_30',
    title: 'Test D — большой документ (30 карточек)',
    kind: LiveScenario.bigDocument,
    requestedCards: 30,
    inputTokensPerRequest: 10000,
    outputTokensPerRequest: 3500,
    images: 0,
    expectsMultipleRequests: true,
  ),
  LiveScenarioPlan(
    id: 'pdf_with_image',
    title: 'Test E — PDF с изображением (Vision)',
    kind: LiveScenario.images,
    requestedCards: 4,
    inputTokensPerRequest: 10200,
    outputTokensPerRequest: 2000,
    images: 1,
    expectsMultipleRequests: false,
    requiresVision: true,
  ),
];

/// План сценария по id или `null`.
LiveScenarioPlan? liveScenarioPlanById(String id) {
  for (final LiveScenarioPlan plan in kLiveScenarioPlans) {
    if (plan.id == id) return plan;
  }
  return null;
}
