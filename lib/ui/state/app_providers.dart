import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import 'package:cardflow/api/generation/api_key_verifier.dart';
import 'package:cardflow/api/generation/card_generation_service.dart';
import 'package:cardflow/api/generation/generation_diagnostics.dart';
import 'package:cardflow/api/generation/generation_pipeline.dart';
import 'package:cardflow/api/generation/generation_v3_path.dart';
import 'package:cardflow/api/generation/request_token_counter.dart';
import 'package:cardflow/api/http/generation_http_client.dart';
import 'package:cardflow/api/http/redacting_log_interceptor.dart';
import 'package:cardflow/api/http/retry_policy.dart';
import 'package:cardflow/api/images/image_api_keys.dart';
import 'package:cardflow/api/images/image_providers.dart';
import 'package:cardflow/api/images/image_search_service.dart';
import 'package:cardflow/api/models/model_capability_service.dart';
import 'package:cardflow/api/providers/generation_adapters.dart';
import 'package:cardflow/api/parsers/file_parsing_service.dart';
import 'package:cardflow/api/parsers/parser_diagnostics.dart';
import 'package:cardflow/data/cards/card_image_refresher.dart';
import 'package:cardflow/data/cards/drift_card_media_repository.dart';
import 'package:cardflow/data/study/drift_match_best_store.dart';
import 'package:cardflow/data/cards/drift_card_repository.dart';
import 'package:cardflow/data/cards/file_picker_image_gateway.dart';
import 'package:cardflow/data/cards/media_garbage_collector.dart';
import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/decks/drift_deck_repository.dart';
import 'package:cardflow/data/generation/drift_generation_card_store.dart';
import 'package:cardflow/data/generation/drift_generation_job_repository.dart';
import 'package:cardflow/data/generation/drift_generation_run_store.dart';
import 'package:cardflow/data/generation/drift_generation_settings_store.dart';
import 'package:cardflow/data/generation/drift_knowledge_map_cache.dart';
import 'package:cardflow/domain/generation/generation_path.dart';
import 'package:cardflow/domain/generation/model_capability_cache.dart';
import 'package:cardflow/domain/generation/token_calibration.dart';
import 'package:cardflow/data/generation/drift_model_capability_cache.dart';
import 'package:cardflow/data/generation/drift_token_calibration_store.dart';
import 'package:cardflow/data/generation/drift_provider_accounts_store.dart';
import 'package:cardflow/data/generation/file_picker_document_gateway.dart';
import 'package:cardflow/data/review/drift_review_repository.dart';
import 'package:cardflow/data/review/drift_leech_repository.dart';
import 'package:cardflow/data/review/drift_daily_usage_repository.dart';
import 'package:cardflow/data/review/drift_practice_repository.dart';
import 'package:cardflow/data/security/secure_api_key_store.dart';
import 'package:cardflow/data/session/drift_session_preset_repository.dart';
import 'package:cardflow/data/settings/drift_app_settings_store.dart';
import 'package:cardflow/data/statistics/drift_statistics_repository.dart';
import 'package:cardflow/data/transfer/drift_deck_transfer_service.dart';
import 'package:cardflow/data/transfer/file_picker_gateway.dart';
import 'package:cardflow/data/transfer/media_store.dart';
import 'package:cardflow/data/transfer/zip_deck_archive_codec.dart';
import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/cards/card_media.dart';
import 'package:cardflow/domain/cards/card_media_repository.dart';
import 'package:cardflow/domain/cards/card_repository.dart';
import 'package:cardflow/domain/decks/deck_repository.dart';
import 'package:cardflow/domain/generation/api_key_store.dart';
import 'package:cardflow/domain/generation/card_image_finder.dart';
import 'package:cardflow/domain/generation/document_gateway.dart';
import 'package:cardflow/domain/generation/generation_card_store.dart';
import 'package:cardflow/domain/generation/generation_job.dart';
import 'package:cardflow/domain/generation/generation_settings_store.dart';
import 'package:cardflow/domain/generation/provider_account.dart';
import 'package:cardflow/domain/generation/provider_accounts_store.dart';
import 'package:cardflow/domain/generation/validation/semantic_matcher.dart';
import 'package:cardflow/domain/review/daily_usage_repository.dart';
import 'package:cardflow/domain/review/practice_repository.dart';
import 'package:cardflow/domain/review/review_repository.dart';
import 'package:cardflow/domain/scheduling/scheduler.dart';
import 'package:cardflow/domain/study/match_best_store.dart';
import 'package:cardflow/domain/session/leech_repository.dart';
import 'package:cardflow/domain/session/session_preset_repository.dart';
import 'package:cardflow/domain/settings/app_settings.dart';
import 'package:cardflow/domain/settings/app_settings_store.dart';
import 'package:cardflow/domain/statistics/statistics.dart';
import 'package:cardflow/domain/statistics/statistics_repository.dart';
import 'package:cardflow/ui/state/settings_diagnostics.dart';
import 'package:cardflow/domain/transfer/archive_codec.dart';
import 'package:cardflow/domain/transfer/deck_transfer_service.dart';
import 'package:cardflow/domain/transfer/file_gateway.dart';
import 'package:cardflow/ui/settings/external_link_launcher.dart';

/// Адаптеры провайдеров для сервиса генерации (SPEC A8.2, ADR-013).
///
/// Список живёт в `lib/api/providers/generation_adapters.dart`: тот же набор
/// используют live-испытания, поэтому тест проверяет production-адаптеры.
export 'package:cardflow/api/providers/generation_adapters.dart'
    show generationAdapters;

/// Провайдеры приложения (ADR-002: Riverpod 3 без кодогенерации).
///
/// Здесь собирается граф зависимостей data-слоя. Платформенные вещи,
/// которые нельзя создать без `WidgetsFlutterBinding` (`AppDatabase`,
/// `MediaStore`), передаются через `ProviderScope(overrides: …)` в `main.dart`.
/// В widget-тестах провайдеры подменяются фейками.

/// БД приложения; в `main.dart` переопределяется реальным открытым экземпляром.
final appDatabaseProvider = Provider<AppDatabase>((ref) {
  throw UnimplementedError('appDatabaseProvider должен быть переопределён');
});

/// Репозиторий колод.
///
/// MediaStore передаётся, чтобы удаление колоды чистило и файлы медиа
/// (fix-итерация по ревью M5), а не только строки БД.
final deckRepositoryProvider = Provider<DeckRepository>((ref) {
  return DriftDeckRepository(
    ref.watch(appDatabaseProvider),
    mediaStore: ref.watch(mediaStoreProvider),
  );
});

/// Репозиторий карточек.
final cardRepositoryProvider = Provider<CardRepository>((ref) {
  return DriftCardRepository(
    ref.watch(appDatabaseProvider),
    mediaStore: ref.watch(mediaStoreProvider),
  );
});

/// Чтение изображений карточек в сессиях (без drift в UI).
final cardMediaRepositoryProvider = Provider<CardMediaRepository>((ref) {
  return DriftCardMediaRepository(
    ref.watch(appDatabaseProvider),
    ref.watch(mediaStoreProvider),
  );
});

/// Системный выбор изображения для Image Occlusion.
final imageGatewayProvider = Provider<CardImageGateway>((ref) {
  return const FilePickerImageGateway();
});

/// Очистка сирот медиа при старте приложения.
final mediaGarbageCollectorProvider = Provider<MediaGarbageCollector>((ref) {
  return MediaGarbageCollector(
    ref.watch(appDatabaseProvider),
    ref.watch(mediaStoreProvider),
  );
});

/// Запись повторений (review_logs + due/fsrs_json в одной транзакции).
final reviewRepositoryProvider = Provider<ReviewRepository>((ref) {
  return DriftReviewRepository(ref.watch(appDatabaseProvider));
});

/// Запись оценок тренировки (review_logs.mode = 'practice', ADR-025).
final practiceRepositoryProvider = Provider<PracticeRepository>((ref) {
  return DriftPracticeRepository(ref.watch(appDatabaseProvider));
});

/// Счётчики провалов для фильтра «Пиявки» конструктора (ADR-018).
final leechRepositoryProvider = Provider<LeechRepository>((ref) {
  return DriftLeechRepository(ref.watch(appDatabaseProvider));
});

/// Дневной расход лимитов из `review_logs` (A6.6, ADR-019 §8).
final dailyUsageRepositoryProvider = Provider<DailyUsageRepository>((ref) {
  return DriftDailyUsageRepository(ref.watch(appDatabaseProvider));
});

/// Пресеты конструктора сессии (`session_presets`, ADR-018).
final sessionPresetRepositoryProvider = Provider<SessionPresetRepository>((
  ref,
) {
  return DriftSessionPresetRepository(ref.watch(appDatabaseProvider));
});

/// Планировщик FSRS: retention и шаги обучения — из настроек (A6.6, ADR-019).
final schedulerProvider = Provider<Scheduler>((ref) {
  final AppSettings settings = ref.watch(effectiveAppSettingsProvider);
  return FsrsScheduler(
    desiredRetention: settings.desiredRetention,
    learningSteps: settings.learningSteps,
  );
});

/// Кодек `.zip`-архива колоды.
final deckArchiveCodecProvider = Provider<DeckArchiveCodec>((ref) {
  return const ZipDeckArchiveCodec();
});

/// Хранилище медиа; в `main.dart` переопределяется каталогом приложения.
final mediaStoreProvider = Provider<MediaStore>((ref) {
  throw UnimplementedError('mediaStoreProvider должен быть переопределён');
});

/// Сервис импорта/экспорта колод.
final deckTransferServiceProvider = Provider<DeckTransferService>((ref) {
  return DriftDeckTransferService(
    appDatabase: ref.watch(appDatabaseProvider),
    codec: ref.watch(deckArchiveCodecProvider),
    mediaStore: ref.watch(mediaStoreProvider),
  );
});

/// Файловый шлюз (системный пикер/сохранение `.zip`).
final fileGatewayProvider = Provider<FileGateway>((ref) {
  return FilePickerGateway();
});

/// Хранилище ключей API (только `flutter_secure_storage`).
final apiKeyStoreProvider = Provider<ApiKeyStore>((ref) {
  return SecureApiKeyStore(FlutterSecureKeyValueStore());
});

/// Хранилище настроек OpenAI-совместимого сервера (`app_settings`, ADR-013).
final generationSettingsStoreProvider = Provider<GenerationSettingsStore>((
  ref,
) {
  return DriftGenerationSettingsStore(ref.watch(appDatabaseProvider));
});

/// Хранилище пользовательских настроек (`app_settings`, ADR-019).
final appSettingsStoreProvider = Provider<AppSettingsStore>((ref) {
  return DriftAppSettingsStore(ref.watch(appDatabaseProvider));
});

/// Debug-диагностика записи настроек (owner-note 1.0.1).
///
/// В release-сборке методы — no-op; в debug причина падения (тип исключения,
/// текст drift/SQLite, первые кадры стека) идёт в консоль `flutter run`, чтобы
/// «не сохраняется» не оставалось без причины.
final settingsDiagnosticsProvider = Provider<SettingsDiagnostics>((ref) {
  return SettingsDiagnostics(sink: kDebugMode ? debugPrint : null);
});

/// Контроллер настроек: состояние меняется сразу, запись — в store.
///
/// Ошибка записи не «проглатывается»: состояние откатывается к прежнему,
/// исключение уходит в UI (сообщение из ARB), чтобы экран не показывал
/// несохранённые настройки как сохранённые.
class AppSettingsController extends AsyncNotifier<AppSettings> {
  @override
  Future<AppSettings> build() => ref.watch(appSettingsStoreProvider).read();

  /// Применяет [settings] и сохраняет их.
  Future<void> save(AppSettings settings) async {
    final AppSettings? previous = state.value;
    state = AsyncData<AppSettings>(settings);
    try {
      await ref.read(appSettingsStoreProvider).write(settings);
    } on Object catch (error, stackTrace) {
      ref.read(settingsDiagnosticsProvider).saveFailed(error, stackTrace);
      state = previous == null
          ? AsyncError<AppSettings>(error, stackTrace)
          : AsyncData<AppSettings>(previous);
      rethrow;
    }
  }
}

/// Настройки приложения (loading/error/data).
final appSettingsProvider =
    AsyncNotifierProvider<AppSettingsController, AppSettings>(
      AppSettingsController.new,
    );

/// Синхронный снимок настроек для мест, где `await` невозможен.
///
/// До загрузки/при ошибке — значения по умолчанию (ADR-019 §1).
final effectiveAppSettingsProvider = Provider<AppSettings>((ref) {
  return ref.watch(appSettingsProvider).value ?? AppSettings.defaults;
});

/// Проверка подключения провайдера минимальным запросом (A6.6, ADR-020).
final apiKeyVerifierProvider = Provider<ApiKeyVerifier>((ref) {
  return ApiKeyVerifier(
    adapters: generationAdapters,
    apiKeyStore: ref.watch(apiKeyStoreProvider),
    transport: ref.watch(generationHttpClientProvider),
  );
});

/// Хранилище провайдеров (`app_settings`, ключ `generation.providers`).
///
/// [generationSettingsStoreProvider] передаётся только для миграции старых
/// настроек OpenAI-совместимого сервера при первом чтении (ADR-020 §4).
final providerAccountsStoreProvider = Provider<ProviderAccountsStore>((ref) {
  return DriftProviderAccountsStore(
    ref.watch(appDatabaseProvider),
    apiKeyStore: ref.watch(apiKeyStoreProvider),
    legacySettingsStore: ref.watch(generationSettingsStoreProvider),
  );
});

/// Список провайдеров генерации; запись — через [ProviderAccountsController].
class ProviderAccountsController extends AsyncNotifier<ProviderAccounts> {
  @override
  Future<ProviderAccounts> build() =>
      ref.watch(providerAccountsStoreProvider).read();

  /// Сохраняет список; при ошибке записи состояние откатывается.
  Future<void> save(ProviderAccounts accounts) async {
    final ProviderAccounts previous = state.value ?? ProviderAccounts.empty;
    state = AsyncData<ProviderAccounts>(accounts);
    try {
      await ref.read(providerAccountsStoreProvider).write(accounts);
    } on Object {
      state = AsyncData<ProviderAccounts>(previous);
      rethrow;
    }
  }
}

/// Провайдеры генерации (loading/error/data).
final providerAccountsProvider =
    AsyncNotifierProvider<ProviderAccountsController, ProviderAccounts>(
      ProviderAccountsController.new,
    );

/// Синхронный снимок провайдеров для мест, где `await` невозможен.
final effectiveProviderAccountsProvider = Provider<ProviderAccounts>((ref) {
  return ref.watch(providerAccountsProvider).value ?? ProviderAccounts.empty;
});

/// Внешние ссылки (политика приватности) — системный браузер.
final externalLinkLauncherProvider = Provider<ExternalLinkLauncher>((ref) {
  return const UrlLauncherExternalLinkLauncher();
});

/// Статистика обучения (SPEC A6.5, ADR-019 §4).
final statisticsRepositoryProvider = Provider<StatisticsRepository>((ref) {
  return DriftStatisticsRepository(ref.watch(appDatabaseProvider));
});

/// Снимок статистики для экрана A6.5.
final statisticsProvider = FutureProvider.autoDispose<StatisticsSnapshot>((
  ref,
) {
  return ref.watch(statisticsRepositoryProvider).load(now: DateTime.now());
});

/// Токены генерации за последние 7 дней (A6.6, блок API).
final weeklyTokensProvider = FutureProvider.autoDispose<int>((ref) {
  return ref
      .watch(statisticsRepositoryProvider)
      .tokensUsedSince(
        DateTime.now().subtract(
          const Duration(days: StatisticsCalculator.weekDays - 1),
        ),
      );
});

/// Dio для вызовов провайдеров генерации: таймауты и redaction-перехватчик.
///
/// «Щедрые на приём, разумные на соединение» (A8.6): соединение 15 с,
/// отправка 60 с, приём 180 с. Логи — только в debug и без секретов.
final generationDioProvider = Provider<Dio>((ref) {
  final dio = Dio(
    BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      sendTimeout: const Duration(seconds: 60),
      receiveTimeout: const Duration(seconds: 180),
    ),
  );
  if (kDebugMode) {
    dio.interceptors.add(RedactingLogInterceptor(sink: debugPrint));
  }
  ref.onDispose(() => dio.close(force: true));
  return dio;
});

/// Debug-диагностика ответов провайдеров (ADR-024, итерация 7.10).
///
/// В release-сборке методы — no-op; sink инжектируется в тестах. В debug
/// сообщения идут в консоль `flutter run` (`debugPrint`), чтобы сырой ответ
/// модели и итог поиска картинки были видны при разборе (итерация 7.12).
final generationDiagnosticsProvider = Provider<GenerationDiagnostics>((ref) {
  return GenerationDiagnostics(sink: kDebugMode ? debugPrint : null);
});

/// HTTP-клиент генерации (ретраи/backoff, нормализация ошибок).
final generationHttpClientProvider = Provider<GenerationHttpClient>((ref) {
  return GenerationHttpClient(
    dio: ref.watch(generationDioProvider),
    retryPolicy: RetryPolicy(),
    diagnostics: ref.watch(generationDiagnosticsProvider),
  );
});

/// Сервис генерации карточек (адаптеры провайдеров + валидация A8.4).
final cardGenerationServiceProvider = Provider<CardGenerationService>((ref) {
  return CardGenerationService(
    adapters: generationAdapters,
    apiKeyStore: ref.watch(apiKeyStoreProvider),
    httpClient: ref.watch(generationHttpClientProvider),
    diagnostics: ref.watch(generationDiagnosticsProvider),
  );
});

/// Парсинг прикреплённых документов (SPEC A8.3, A8.5 шаг 3).
///
/// PDFium получает каталог кэша из main-изолята (`path_provider`): в фоновом
/// изоляте платформенный канал недоступен, а неявный `HOME` в pdfrx на Android
/// не задан — из-за этого любой PDF показывал «Не удалось прочитать файл»
/// (TASK 04, часть 2).
final fileParsingServiceProvider = Provider<FileParsingService>((ref) {
  return FileParsingService(
    pdfCacheDirectory: () async => (await getTemporaryDirectory()).path,
    diagnostics: ref.watch(parserDiagnosticsProvider),
  );
});

/// Debug-диагностика импорта документов (TASK 04, часть 8).
final parserDiagnosticsProvider = Provider<ParserDiagnostics>((ref) {
  return const ParserDiagnostics();
});

/// Шлюз выбора/чтения документов генерации (A6.8).
final documentGatewayProvider = Provider<DocumentGateway>((ref) {
  return FilePickerDocumentGateway(
    diagnostics: ref.watch(parserDiagnosticsProvider),
  );
});

/// Задания генерации в `generation_jobs` (A5, ADR-015).
final generationJobRepositoryProvider = Provider<GenerationJobRepository>((
  ref,
) {
  return DriftGenerationJobRepository(ref.watch(appDatabaseProvider));
});

/// Импорт сгенерированных карточек в колоду (A8.5 шаги 9–11).
final generationCardStoreProvider = Provider<GenerationCardStore>((ref) {
  return DriftGenerationCardStore(
    ref.watch(appDatabaseProvider),
    mediaStore: ref.watch(mediaStoreProvider),
  );
});

/// Поиск иллюстраций: цепочка провайдеров (ADR-023, ADR-027, ADR-028, 7.14).
///
/// Порядок: Wikimedia Commons (быстро по конкретным запросам) → Wikipedia
/// pageimages (понимает русские словоформы: статья, а не имя файла) →
/// Openverse (CC-резерв) → Pixabay/Pexels, только если ключ задан в
/// `--dart-define`/окружении. Без ключа провайдера в цепочке нет. Бюджет
/// времени ограничивает пайплайн: недоступный источник не задерживает импорт.
final cardImageFinderProvider = Provider<CardImageFinder>((ref) {
  final Dio dio = ref.watch(generationDioProvider);
  final GenerationDiagnostics diagnostics = ref.watch(
    generationDiagnosticsProvider,
  );
  final String? pixabayKey = pixabayApiKeyFromEnvironment();
  final String? pexelsKey = pexelsApiKeyFromEnvironment();
  return ImageSearchService(
    dio: dio,
    diagnostics: diagnostics,
    providers: buildImageProviders(
      dio: dio,
      pixabayApiKey: pixabayKey,
      pexelsApiKey: pexelsKey,
    ),
  );
});

/// Повторный поиск картинки карточки (7.14: «Найти картинку заново»).
final cardImageRefresherProvider = Provider<CardImageRefresher>((ref) {
  return CardImageRefresher(
    database: ref.watch(appDatabaseProvider),
    mediaStore: ref.watch(mediaStoreProvider),
    imageFinder: ref.watch(cardImageFinderProvider),
  );
});

/// Лучшие результаты «Подбора пар» (`app_settings`, 7.16).
final matchBestStoreProvider = Provider<MatchBestStore>((ref) {
  return DriftMatchBestStore(ref.watch(appDatabaseProvider));
});

/// Пайплайн генерации: чанкинг, вызовы, прогресс/отмена, дедупликация.
///
/// Путь выбирает **функция от материала** (TASK «Срез 17», п. 11, ADR-054):
/// `generationPathDecisionProvider` переводит режим настройки (`auto`/`v3`/
/// `legacy`) в решение; `auto` при неопределённом пороге N* честно остаётся на
/// legacy. Выключенный v3 — прежнее поведение без изменений.
final generationRunnerProvider = Provider<GenerationRunner>((ref) {
  final ApiKeyStore keyStore = ref.watch(apiKeyStoreProvider);
  final GenerationPathDecision path = ref.watch(generationPathDecisionProvider);
  return GenerationPipeline(
    caller: ref.watch(cardGenerationServiceProvider),
    // Нативный подсчёт входа: только Anthropic/Gemini (ADR-040 §3.5.1).
    tokenCounter: ProtocolRequestTokenCounter(
      dio: ref.watch(generationDioProvider),
      readApiKey: (String accountId) => keyStore.read(accountId),
    ),
    jobRepository: ref.watch(generationJobRepositoryProvider),
    cardStore: ref.watch(generationCardStoreProvider),
    imageFinder: ref.watch(cardImageFinderProvider),
    diagnostics: ref.watch(generationDiagnosticsProvider),
    capabilityCache: ref.watch(modelCapabilityCacheProvider),
    calibrationStore: ref.watch(tokenCalibrationStoreProvider),
    pipelineV3: path.path == GenerationPath.v3,
    // production-проводка пути v3 (срез 11): фасад включается тем же решением.
    v3Path: ref.watch(generationV3PathProvider),
  );
});

/// Решение о пути генерации по материалу и режиму из настроек (ADR-054).
///
/// Объём материала до первого запроса неизвестен (карты единиц ещё нет),
/// поэтому вызывающий слой передаёт 0 — при неопределённом пороге N* это не
/// влияет на решение; когда порог появится из данных, объём будет передан
/// здесь (L236).
final generationPathDecisionProvider = Provider<GenerationPathDecision>((
  Ref ref,
) {
  final AppSettings settings = ref.watch(effectiveAppSettingsProvider);
  return selectGenerationPath(mode: settings.generationPathMode);
});

/// true — решением выбран путь v3 (для прогресса и экрана генерации).
final generationUsesV3Provider = Provider<bool>((Ref ref) {
  return ref.watch(generationPathDecisionProvider).path == GenerationPath.v3;
});

/// Путь генерации v3: фасад этапов, понимание с HTTP-вызовом и кэшем на БД,
/// добор с гейтом и отчёт прогона (TASK «Срез 11», часть 3).
///
/// Работает только при выборе пути v3 (`GenerationPathDecision`,
/// `generationPathDecisionProvider`); legacy — путь без изменений
/// (`GenerationPipeline.pipelineV3`).
final generationV3PathProvider = Provider<GenerationV3Path>((ref) {
  final AppDatabase database = ref.watch(appDatabaseProvider);
  final GenerationV3PathRunner runner = GenerationV3PathRunner(
    apiKeyStore: ref.watch(apiKeyStoreProvider),
    transport: ref.watch(generationHttpClientProvider),
    runStore: DriftGenerationRunStore(database),
    knowledgeMapCache: DriftKnowledgeMapCache(database),
    // Этап Dedup (срез 13) сверяет принятые карточки с целевой колодой **до**
    // импорта: пара «уже в колоде» помечается, а не обнаруживается после
    // записи. Читаются только id и стороны — байтов и настроек не нужно.
    deckCards: (String deckId) async {
      final List<Card> cards = await DriftCardRepository(database)
          .cardsByDeck(deckId);
      return <DedupCard>[
        for (final Card card in cards)
          DedupCard(id: card.id, front: card.front, back: card.back),
      ];
    },
    importer: (String runId, String? deckId, String deckName) async {
      // MediaStore читается в момент импорта: он не нужен ни Understanding,
      // ни генерации, и не должен строиться при открытии экрана.
      final GenerationImportResult result =
          await DriftGenerationCardStore(
            database,
            mediaStore: ref.read(mediaStoreProvider),
          ).importRunCards(
            runId: runId,
            deckId: deckId,
            deckName: deckName,
            now: DateTime.now(),
          );
      return result.importedCards;
    },
  );
  return runner.run;
});

/// Кэш характеристик модели (`generation.model_capabilities`, ADR-039).
final modelCapabilityCacheProvider = Provider<ModelCapabilityCache>((ref) {
  return DriftModelCapabilityCache(ref.watch(appDatabaseProvider));
});

/// Калибровка `tokensPerCard` (ADR-040 §9).
final tokenCalibrationStoreProvider = Provider<TokenCalibrationStore>((ref) {
  return DriftTokenCalibrationStore(ref.watch(appDatabaseProvider));
});

/// Сервис характеристик: discovery, кэш и «Обновить характеристики».
final modelCapabilityServiceProvider = Provider<ModelCapabilityService>((ref) {
  final ApiKeyStore keyStore = ref.watch(apiKeyStoreProvider);
  return ModelCapabilityService(
    dio: ref.watch(generationDioProvider),
    readApiKey: (String accountId) => keyStore.read(accountId),
    cache: ref.watch(modelCapabilityCacheProvider),
  );
});
