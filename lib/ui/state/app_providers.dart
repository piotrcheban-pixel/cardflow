import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:cardflow/api/generation/card_generation_service.dart';
import 'package:cardflow/api/generation/generation_pipeline.dart';
import 'package:cardflow/api/http/generation_http_client.dart';
import 'package:cardflow/api/http/redacting_log_interceptor.dart';
import 'package:cardflow/api/http/retry_policy.dart';
import 'package:cardflow/api/providers/anthropic_adapter.dart';
import 'package:cardflow/api/providers/gemini_adapter.dart';
import 'package:cardflow/api/providers/openai_adapter.dart';
import 'package:cardflow/api/providers/openai_compatible_adapter.dart';
import 'package:cardflow/api/providers/generation_provider_adapter.dart';
import 'package:cardflow/api/parsers/file_parsing_service.dart';
import 'package:cardflow/data/cards/drift_card_media_repository.dart';
import 'package:cardflow/data/cards/drift_card_repository.dart';
import 'package:cardflow/data/cards/file_picker_image_gateway.dart';
import 'package:cardflow/data/cards/media_garbage_collector.dart';
import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/decks/drift_deck_repository.dart';
import 'package:cardflow/data/generation/drift_generation_card_store.dart';
import 'package:cardflow/data/generation/drift_generation_job_repository.dart';
import 'package:cardflow/data/generation/drift_generation_settings_store.dart';
import 'package:cardflow/data/generation/file_picker_document_gateway.dart';
import 'package:cardflow/data/review/drift_review_repository.dart';
import 'package:cardflow/data/review/drift_leech_repository.dart';
import 'package:cardflow/data/security/secure_api_key_store.dart';
import 'package:cardflow/data/session/drift_session_preset_repository.dart';
import 'package:cardflow/data/transfer/drift_deck_transfer_service.dart';
import 'package:cardflow/data/transfer/file_picker_gateway.dart';
import 'package:cardflow/data/transfer/media_store.dart';
import 'package:cardflow/data/transfer/zip_deck_archive_codec.dart';
import 'package:cardflow/domain/cards/card_media.dart';
import 'package:cardflow/domain/cards/card_media_repository.dart';
import 'package:cardflow/domain/cards/card_repository.dart';
import 'package:cardflow/domain/decks/deck_repository.dart';
import 'package:cardflow/domain/generation/api_key_store.dart';
import 'package:cardflow/domain/generation/document_gateway.dart';
import 'package:cardflow/domain/generation/generation_card_store.dart';
import 'package:cardflow/domain/generation/generation_job.dart';
import 'package:cardflow/domain/generation/generation_settings_store.dart';
import 'package:cardflow/domain/generation/openai_compatible_settings.dart';
import 'package:cardflow/domain/review/review_repository.dart';
import 'package:cardflow/domain/scheduling/scheduler.dart';
import 'package:cardflow/domain/session/leech_repository.dart';
import 'package:cardflow/domain/session/session_preset_repository.dart';
import 'package:cardflow/domain/transfer/archive_codec.dart';
import 'package:cardflow/domain/transfer/deck_transfer_service.dart';
import 'package:cardflow/domain/transfer/file_gateway.dart';

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

/// Счётчики провалов для фильтра «Пиявки» конструктора (ADR-018).
final leechRepositoryProvider = Provider<LeechRepository>((ref) {
  return DriftLeechRepository(ref.watch(appDatabaseProvider));
});

/// Пресеты конструктора сессии (`session_presets`, ADR-018).
final sessionPresetRepositoryProvider = Provider<SessionPresetRepository>((
  ref,
) {
  return DriftSessionPresetRepository(ref.watch(appDatabaseProvider));
});

/// Планировщик FSRS (ADR-004: конфигурация детерминированного прогноза).
final schedulerProvider = Provider<Scheduler>((ref) => FsrsScheduler());

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

/// Текущие настройки OpenAI-совместимого сервера для экрана настроек.
final openAiCompatibleSettingsProvider =
    FutureProvider<OpenAiCompatibleSettings>((ref) {
      return ref.watch(generationSettingsStoreProvider).readOpenAiCompatible();
    });

/// Адаптеры провайдеров для сервиса генерации (SPEC A8.2, ADR-013).
const List<GenerationProviderAdapter> generationAdapters =
    <GenerationProviderAdapter>[
      OpenAiAdapter(),
      GeminiAdapter(),
      AnthropicAdapter(),
      OpenAiCompatibleAdapter(),
    ];

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

/// HTTP-клиент генерации (ретраи/backoff, нормализация ошибок).
final generationHttpClientProvider = Provider<GenerationHttpClient>((ref) {
  return GenerationHttpClient(
    dio: ref.watch(generationDioProvider),
    retryPolicy: RetryPolicy(),
  );
});

/// Сервис генерации карточек (адаптеры провайдеров + валидация A8.4).
final cardGenerationServiceProvider = Provider<CardGenerationService>((ref) {
  return CardGenerationService(
    adapters: generationAdapters,
    apiKeyStore: ref.watch(apiKeyStoreProvider),
    httpClient: ref.watch(generationHttpClientProvider),
    generationSettingsStore: ref.watch(generationSettingsStoreProvider),
  );
});

/// Парсинг прикреплённых документов (SPEC A8.3, A8.5 шаг 3).
final fileParsingServiceProvider = Provider<FileParsingService>((ref) {
  return FileParsingService();
});

/// Шлюз выбора/чтения документов генерации (A6.8).
final documentGatewayProvider = Provider<DocumentGateway>((ref) {
  return const FilePickerDocumentGateway();
});

/// Задания генерации в `generation_jobs` (A5, ADR-015).
final generationJobRepositoryProvider = Provider<GenerationJobRepository>((
  ref,
) {
  return DriftGenerationJobRepository(ref.watch(appDatabaseProvider));
});

/// Импорт сгенерированных карточек в колоду (A8.5 шаги 9–11).
final generationCardStoreProvider = Provider<GenerationCardStore>((ref) {
  return DriftGenerationCardStore(ref.watch(appDatabaseProvider));
});

/// Пайплайн генерации: чанкинг, вызовы, прогресс/отмена, дедупликация.
final generationRunnerProvider = Provider<GenerationRunner>((ref) {
  return GenerationPipeline(
    caller: ref.watch(cardGenerationServiceProvider),
    jobRepository: ref.watch(generationJobRepositoryProvider),
    cardStore: ref.watch(generationCardStoreProvider),
  );
});
