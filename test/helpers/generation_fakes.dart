import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'package:cardflow/api/generation/generation_caller.dart';
import 'package:cardflow/api/generation/generation_cancellation.dart';
import 'package:cardflow/api/generation/generation_pipeline.dart';
import 'package:cardflow/api/http/generation_http_client.dart';
import 'package:cardflow/api/providers/generation_provider_adapter.dart';
import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/generation/api_key_store.dart';
import 'package:cardflow/domain/generation/card_image_finder.dart';
import 'package:cardflow/domain/generation/document_gateway.dart';
import 'package:cardflow/domain/generation/generated_card.dart';
import 'package:cardflow/domain/generation/generated_card_image.dart';
import 'package:cardflow/domain/generation/generation_attachment.dart';
import 'package:cardflow/domain/generation/generation_card_store.dart';
import 'package:cardflow/domain/generation/generation_error.dart';
import 'package:cardflow/domain/generation/generation_job.dart';
import 'package:cardflow/domain/generation/generation_provider.dart';
import 'package:cardflow/domain/generation/generation_request.dart';
import 'package:cardflow/domain/generation/generation_result.dart';
import 'package:cardflow/domain/generation/generation_run.dart';
import 'package:cardflow/domain/generation/generation_settings_store.dart';
import 'package:cardflow/domain/generation/openai_compatible_settings.dart';
import 'package:cardflow/domain/generation/provider_account.dart';
import 'package:cardflow/domain/generation/provider_accounts_store.dart';
import 'package:cardflow/domain/generation/provider_preset.dart';
import 'package:cardflow/domain/generation/provider_protocol.dart';

/// In-memory хранилище ключей API для тестов (без платформы).
///
/// Ключ адресуется id аккаунта провайдера (`ProviderAccount.id`, ADR-020);
/// начальные ключи для legacy-проверок задаются теми же строками, что раньше
/// были wire-именами (`openai`, `gemini`, `anthropic`, `openai_compatible`).
class FakeApiKeyStore implements ApiKeyStore {
  /// Создаёт хранилище; [keys] — начальные ключи.
  FakeApiKeyStore([Map<String, String>? keys])
    : _keys = <String, String>{...?keys};

  final Map<String, String> _keys;

  /// Сколько раз читали ключ.
  int readCalls = 0;

  /// Сколько раз писали ключ.
  int writeCalls = 0;

  /// Сколько раз удаляли ключ.
  int deleteCalls = 0;

  /// Текущее содержимое хранилища (открыто для проверок в тестах).
  Map<String, String> get keys => _keys;

  /// Если задано — `read` бросает эту ошибку (проверка error-состояния UI).
  Object? readError;

  /// Если `true` — `write` «успешен», но значение не сохраняется
  /// (проверка read-back и сообщения об ошибке хранилища).
  bool dropWrites = false;

  @override
  Future<String?> read(String providerId) async {
    readCalls++;
    if (readError != null) throw readError!;
    return _keys[providerId];
  }

  @override
  Future<void> write(String providerId, String apiKey) async {
    writeCalls++;
    if (dropWrites) return;
    _keys[providerId] = apiKey;
  }

  @override
  Future<void> delete(String providerId) async {
    deleteCalls++;
    _keys.remove(providerId);
  }
}

/// In-memory хранилище провайдеров генерации (ADR-020).
class FakeProviderAccountsStore implements ProviderAccountsStore {
  /// Создаёт хранилище с начальным списком [accounts].
  FakeProviderAccountsStore([ProviderAccounts? accounts])
    : accounts = accounts ?? ProviderAccounts.empty;

  /// Текущий список.
  ProviderAccounts accounts;

  /// Сколько раз читали.
  int readCalls = 0;

  /// Сколько раз писали.
  int writeCalls = 0;

  /// Если `true` — запись бросает исключение.
  bool failWrites = false;

  @override
  Future<ProviderAccounts> read() async {
    readCalls++;
    return accounts;
  }

  @override
  Future<void> write(ProviderAccounts value) async {
    writeCalls++;
    if (failWrites) throw StateError('Запись провайдеров недоступна (тест)');
    accounts = value;
  }
}

/// Аккаунт из каталога для тестов (по умолчанию DeepSeek).
ProviderAccount testProviderAccount({
  String presetId = 'deepseek',
  String? id,
  String? modelId,
}) {
  final ProviderPreset preset = providerPresetById(presetId)!;
  return ProviderAccount.fromPreset(
    preset,
    id: id ?? preset.id,
    modelId: modelId,
  );
}

/// Пользовательский аккаунт для тестов.
ProviderAccount testCustomProviderAccount({
  String id = 'custom',
  String label = 'Свой сервер',
  String baseUrl = 'http://localhost:1234/v1',
  String modelId = 'qwen2.5',
  bool supportsVision = false,
}) {
  return ProviderAccount(
    id: id,
    label: label,
    protocol: ProviderProtocol.openaiCompletions,
    baseUrl: baseUrl,
    modelId: modelId,
    supportsVision: supportsVision,
  );
}

/// In-memory хранилище настроек OpenAI-совместимого сервера для тестов.
class FakeGenerationSettingsStore implements GenerationSettingsStore {
  /// Создаёт хранилище; [settings] — начальные настройки.
  FakeGenerationSettingsStore([OpenAiCompatibleSettings? settings])
    : _settings = settings ?? const OpenAiCompatibleSettings();

  OpenAiCompatibleSettings _settings;

  /// Сколько раз читали настройки.
  int readCalls = 0;

  /// Сколько раз писали настройки.
  int writeCalls = 0;

  /// Текущие настройки.
  OpenAiCompatibleSettings get settings => _settings;

  @override
  Future<OpenAiCompatibleSettings> readOpenAiCompatible() async {
    readCalls++;
    return _settings;
  }

  @override
  Future<void> writeOpenAiCompatible(OpenAiCompatibleSettings settings) async {
    writeCalls++;
    _settings = settings;
  }
}

/// Аргументы, с которыми фейковый адаптер строил запрос.
class RecordedBuildArgs {
  /// Создаёт запись аргументов.
  RecordedBuildArgs({
    required this.apiKey,
    required this.model,
    required this.systemPrompt,
    required this.userContent,
    required this.maxOutputTokens,
    this.baseUrl,
    this.strictSchema = true,
    this.sendMaxTokens = true,
    this.images = const <GenerationAttachment>[],
  });

  /// Переданный ключ.
  final String apiKey;

  /// Переданная модель.
  final String model;

  /// Переданный системный промпт.
  final String systemPrompt;

  /// Переданное пользовательское сообщение.
  final String userContent;

  /// Переданный лимит ответа.
  final int maxOutputTokens;

  /// Переданный базовый адрес OpenAI-совместимого сервера.
  final String? baseUrl;

  /// Переданный флаг strict-схемы.
  final bool strictSchema;

  /// Переданный флаг `max_tokens` (ADR-021).
  final bool sendMaxTokens;

  /// Переданные вложения (итерация 7.8).
  final List<GenerationAttachment> images;
}

/// Фейковый адаптер провайдера: запоминает аргументы и отдаёт заданный ответ.
class FakeProviderAdapter implements GenerationProviderAdapter {
  /// Создаёт адаптер.
  FakeProviderAdapter({
    this.provider = GenerationProvider.openai,
    this.cardsJson = '{"cards":[]}',
    this.usage = const TokenUsage(),
    this.error,
    this.request,
  });

  @override
  final GenerationProvider provider;

  /// JSON-строка ответа модели.
  final String cardsJson;

  /// Расход токенов в ответе.
  final TokenUsage usage;

  /// Если задано — `parseResponse` бросит это исключение.
  final Object? error;

  /// Если задано — `buildRequest` вернёт этот запрос.
  final ProviderRequest? request;

  /// Последние аргументы `buildRequest`.
  RecordedBuildArgs? buildArgs;

  /// Сколько раз строили запрос.
  int buildCalls = 0;

  /// Сколько раз разбирали ответ.
  int parseCalls = 0;

  @override
  ProviderRequest buildRequest({
    required String apiKey,
    required String model,
    required String systemPrompt,
    required String userContent,
    required int maxOutputTokens,
    String? baseUrl,
    bool strictSchema = true,
    bool sendMaxTokens = true,
    List<GenerationAttachment> images = const <GenerationAttachment>[],
  }) {
    buildCalls++;
    buildArgs = RecordedBuildArgs(
      apiKey: apiKey,
      model: model,
      systemPrompt: systemPrompt,
      userContent: userContent,
      maxOutputTokens: maxOutputTokens,
      baseUrl: baseUrl,
      strictSchema: strictSchema,
      sendMaxTokens: sendMaxTokens,
      images: images,
    );
    return request ??
        ProviderRequest(
          uri: Uri.parse('https://provider.test/v1/generate'),
          headers: <String, String>{'x-test-key': apiKey},
          body: <String, Object?>{'model': model},
        );
  }

  @override
  ProviderRawResponse parseResponse(Map<String, Object?> json) {
    parseCalls++;
    final failure = error;
    if (failure != null) throw failure;
    return ProviderRawResponse(cardsJson: cardsJson, usage: usage);
  }
}

/// Фейковый HTTP-транспорт: запоминает запросы и отдаёт заданный JSON/ошибку.
class FakeGenerationTransport implements GenerationTransport {
  /// Создаёт транспорт.
  FakeGenerationTransport({
    this.response,
    this.error,
    this.callsBeforeResponse = 0,
    List<Object?>? errorsBeforeResponse,
  }) : _pendingErrors = <Object?>[...?errorsBeforeResponse];

  /// JSON-ответ по умолчанию.
  final Map<String, Object?>? response;

  /// Если задано — будут брошено это исключение.
  final Object? error;

  /// Сколько первых вызовов «падать» (для проверки, что сервис не ретраит сам).
  final int callsBeforeResponse;

  /// Ошибки первых вызовов по порядку (для проверки fallback в сервисе).
  final List<Object?> _pendingErrors;

  /// Все отправленные запросы.
  final List<ProviderRequest> requests = <ProviderRequest>[];

  /// Число вызовов транспорта.
  int calls = 0;

  @override
  Future<Map<String, Object?>> postJson(
    ProviderRequest request, {
    CancelToken? cancelToken,
  }) async {
    calls++;
    requests.add(request);
    if (_pendingErrors.isNotEmpty) {
      throw _pendingErrors.removeAt(0)!;
    }
    if (calls <= callsBeforeResponse) {
      throw const FormatException('fake transient failure');
    }
    final failure = error;
    if (failure != null) throw failure;
    return response ?? <String, Object?>{};
  }
}

/// Создаёт сгенерированную карточку-фикстуру.
GeneratedCard makeGeneratedCard({
  String front = 'Что такое FSRS?',
  String back = 'Алгоритм интервального повторения.',
  CardType cardType = CardType.basic,
  List<String> tags = const <String>['fsrs'],
  String? sourceExcerpt,
  List<CardIssueCode> issues = const <CardIssueCode>[],
  String? imageQuery,
  GeneratedCardImage? image,
  bool isOcclusion = false,
  String? occlusionJson,
}) {
  return GeneratedCard(
    front: front,
    back: back,
    cardType: cardType,
    tags: tags,
    sourceExcerpt: sourceExcerpt,
    issues: issues,
    imageQuery: imageQuery,
    image: image,
    isOcclusion: isOcclusion,
    occlusionJson: occlusionJson,
  );
}

/// Фейковый поиск картинок: ответы по запросу, журнал и ошибка.
class FakeCardImageFinder implements CardImageFinder {
  /// Создаёт фейк с ответами [byQuery].
  FakeCardImageFinder({Map<String, GeneratedCardImage?>? byQuery})
    : byQuery = <String, GeneratedCardImage?>{...?byQuery};

  /// Ответы по запросу; отсутствующий запрос → `null`.
  final Map<String, GeneratedCardImage?> byQuery;

  /// Все запросы в порядке вызовов.
  final List<String> queries = <String>[];

  /// Если задано — `findImage` бросает это исключение.
  Object? error;

  @override
  Future<GeneratedCardImage?> findImage(String query) async {
    queries.add(query);
    if (error != null) throw error!;
    return byQuery[query];
  }
}

/// Картинка-фикстура (JPEG-сигнатура).
GeneratedCardImage makeCardImage({
  String query = 'photosynthesis diagram',
  List<int> bytes = const <int>[0xFF, 0xD8, 0xFF, 1, 2, 3],
  AttachmentMediaType mediaType = AttachmentMediaType.jpeg,
}) {
  return GeneratedCardImage(
    bytes: Uint8List.fromList(bytes),
    mediaType: mediaType,
    query: query,
    sourceUrl: 'https://example.test/image.jpg',
  );
}

/// Фейковый вызов модели: очередь результатов/ошибок, журнал запросов.
class FakeGenerationCaller implements GenerationCaller {
  /// Создаёт фейк; [responses] — `GenerationResult` или `GenerationException`.
  FakeGenerationCaller({List<Object>? responses})
    : _responses = <Object>[...?responses];

  final List<Object> _responses;

  /// Все запросы в порядке вызовов.
  final List<GenerationRequest> requests = <GenerationRequest>[];

  /// Если задано — вызывается вместо очереди (для проверки отмены/прогресса).
  Future<GenerationResult> Function(GenerationRequest request, int call)?
  onGenerate;

  /// Сколько раз вызывали модель.
  int get calls => requests.length;

  @override
  Future<GenerationResult> generate(
    GenerationRequest request, {
    CancelToken? cancelToken,
  }) async {
    requests.add(request);
    final handler = onGenerate;
    if (handler != null) {
      return handler(request, requests.length);
    }
    if (_responses.isEmpty) {
      throw StateError('FakeGenerationCaller: нет запланированного ответа');
    }
    final Object response = _responses.removeAt(0);
    if (response is GenerationException) {
      throw response;
    }
    return response as GenerationResult;
  }
}

/// Фейковое хранилище заданий: in-memory, журнал сохранений.
class FakeGenerationJobRepository implements GenerationJobRepository {
  final Map<String, GenerationJob> _jobs = <String, GenerationJob>{};

  /// Все сохранённые версии заданий в порядке записи.
  final List<GenerationJob> saved = <GenerationJob>[];

  @override
  Future<void> save(GenerationJob job) async {
    saved.add(job);
    _jobs[job.id] = job;
  }

  @override
  Future<GenerationJob?> jobById(String id) async => _jobs[id];
}

/// Фейковое хранилище карточек: хеши существующих и импорт с дедупликацией.
class FakeGenerationCardStore implements GenerationCardStore {
  /// Создаёт фейк с существующими хешами [existingByDeck].
  FakeGenerationCardStore({
    Map<String, Set<String>>? existingByDeck,
    this.importResult,
  }) : _existingByDeck = <String, Set<String>>{...?existingByDeck};

  final Map<String, Set<String>> _existingByDeck;

  /// Результат импорта; по умолчанию — первая карточка списка.
  final GenerationImportResult? importResult;

  /// Карточки, переданные в импорт.
  final List<List<GeneratedCard>> importedCards = <List<GeneratedCard>>[];

  /// Параметры последнего импорта.
  String? lastDeckId;
  String? lastDeckName;
  String? lastJobId;

  /// Если задано — `existingContentHashes` бросает эту ошибку.
  Object? existingError;

  @override
  Future<Set<String>> existingContentHashes(String deckId) async {
    if (existingError != null) throw existingError!;
    return <String>{...?_existingByDeck[deckId]};
  }

  @override
  Future<GenerationImportResult> importGeneratedCards({
    required String? deckId,
    required String deckName,
    required List<GeneratedCard> cards,
    required String jobId,
    required DateTime now,
  }) async {
    importedCards.add(List<GeneratedCard>.of(cards));
    lastDeckId = deckId;
    lastDeckName = deckName;
    lastJobId = jobId;
    return importResult ??
        GenerationImportResult(
          deckId: deckId ?? 'new-deck',
          importedCards: cards.length,
          skippedDuplicates: 0,
        );
  }
}

/// Фейковый пайплайн для widget-тестов экрана генерации/предпросмотра.
class FakeGenerationRunner implements GenerationRunner {
  /// Результат `run`; `null` — бросается [error].
  GenerationRunResult? result;

  /// Результат `retryFailed`; по умолчанию — [result].
  GenerationRunResult? retryResult;

  /// Ошибка вместо результата.
  Object? error;

  /// Если задан — `run` ждёт завершения этого completer (проверка прогресса).
  Completer<GenerationRunResult>? pending;

  /// Сколько раз вызывали `run`.
  int runCalls = 0;

  /// Сколько раз вызывали `retryFailed`.
  int retryCalls = 0;

  /// Последний запрос.
  GenerationRunRequest? lastRequest;

  /// Последний колбэк прогресса.
  GenerationProgressCallback? lastProgress;

  /// Последняя отмена.
  GenerationCancellation? lastCancellation;

  /// Последний предыдущий результат для retry.
  GenerationRunResult? lastPrevious;

  @override
  Future<GenerationRunResult> run(
    GenerationRunRequest request, {
    GenerationProgressCallback? onProgress,
    GenerationCancellation? cancellation,
  }) async {
    runCalls++;
    lastRequest = request;
    lastProgress = onProgress;
    lastCancellation = cancellation;
    final failure = error;
    if (failure != null) throw failure;
    final waiting = pending;
    if (waiting != null) return waiting.future;
    return result!;
  }

  @override
  Future<GenerationRunResult> retryFailed(
    GenerationRunRequest request,
    GenerationRunResult previous, {
    GenerationProgressCallback? onProgress,
    GenerationCancellation? cancellation,
  }) async {
    retryCalls++;
    lastRequest = request;
    lastPrevious = previous;
    lastProgress = onProgress;
    lastCancellation = cancellation;
    final failure = error;
    if (failure != null) throw failure;
    return retryResult ?? result!;
  }
}

/// Фейковый шлюз документов: заданные файлы/байты и журнал вызовов.
class FakeDocumentGateway implements DocumentGateway {
  /// Файлы, которые вернёт пикер.
  List<PickedDocument> picked = <PickedDocument>[];

  /// Байты по пути; по умолчанию — UTF-8 текст «Материал лекции».
  final Map<String, Uint8List> bytesByPath = <String, Uint8List>{};

  /// Ошибка пикера.
  Object? pickError;

  /// Ошибка чтения.
  Object? readError;

  /// Сколько раз открывали пикер.
  int pickCalls = 0;

  /// Сколько раз читали файл.
  int readCalls = 0;

  /// Если задан — `readDocument` ждёт его завершения (проверка parsing-статуса).
  Completer<Uint8List>? readCompleter;

  @override
  int get maxFileBytes => 25 * 1024 * 1024;

  @override
  Future<List<PickedDocument>> pickDocuments() async {
    pickCalls++;
    if (pickError != null) throw pickError!;
    return List<PickedDocument>.of(picked);
  }

  @override
  Future<Uint8List> readDocument(PickedDocument document) async {
    readCalls++;
    if (readError != null) throw readError!;
    final waiting = readCompleter;
    if (waiting != null) return waiting.future;
    return bytesByPath[document.path] ??
        Uint8List.fromList('Материал лекции'.codeUnits);
  }
}
