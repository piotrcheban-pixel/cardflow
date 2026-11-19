import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/api/generation/card_generation_service.dart';
import 'package:cardflow/api/generation/generation_diagnostics.dart';
import 'package:cardflow/api/generation/generation_pipeline.dart';
import 'package:cardflow/api/generation/system_prompt.dart';
import 'package:cardflow/api/http/generation_http_client.dart';
import 'package:cardflow/api/http/retry_policy.dart';
import 'package:cardflow/api/images/composite_card_image_finder.dart';
import 'package:cardflow/api/images/image_provider.dart';
import 'package:cardflow/api/images/image_search_service.dart';
import 'package:cardflow/api/images/openverse_image_provider.dart';
import 'package:cardflow/api/images/wikimedia_image_provider.dart';
import 'package:cardflow/api/images/wikipedia_image_provider.dart';
import 'package:cardflow/api/parsers/docx_parser.dart';
import 'package:cardflow/api/parsers/pdf_scan_renderer.dart';
import 'package:cardflow/api/providers/openai_compatible_adapter.dart';
import 'package:cardflow/domain/generation/card_image_finder.dart';
import 'package:cardflow/domain/generation/generated_card.dart';
import 'package:cardflow/domain/generation/generation_attachment.dart';
import 'package:cardflow/domain/generation/generation_job.dart';
import 'package:cardflow/domain/generation/generation_provider.dart';
import 'package:cardflow/domain/generation/generation_request.dart';
import 'package:cardflow/domain/generation/generation_run.dart';
import 'package:cardflow/domain/generation/provider_account.dart';
import 'package:cardflow/domain/generation/provider_protocol.dart';
import 'package:cardflow/domain/text/parsed_document.dart';

import 'support/live_test_config.dart';

import '../helpers/generation_fakes.dart';
import '../unit/api/parsers/fixtures/document_fixtures.dart';

/// Live-проверка OpenAI-совместимого адаптера на реальном DeepSeek (ADR-013).
///
/// Запуск — только при наличии ключа в окружении (иначе skip):
///   set DEEPSEEK_API_KEY=...            (значение не выводить в терминал)
///   fvm flutter test test/live --tags live
/// Необязательно: DEEPSEEK_BASE_URL (по умолчанию `https://api.deepseek.com`),
/// DEEPSEEK_MODEL (по умолчанию `deepseek-flash` — актуальный id каталога).
void main() {
  final Map<String, String> env = Platform.environment;
  final String? apiKey = _envValue(env, 'DEEPSEEK_API_KEY');
  final String baseUrl =
      _envValue(env, 'DEEPSEEK_BASE_URL') ?? 'https://api.deepseek.com';
  final String model = _envValue(env, 'DEEPSEEK_MODEL') ?? 'deepseek-flash';
  // TASK 04: без явного CARDFLOW_LIVE_TESTS=1 файл не делает запросов.
  final String? liveSkip = liveDetailedTestsSkipReason(
    apiKey: apiKey,
    keyVariable: 'DEEPSEEK_API_KEY',
    environment: env,
  );

  test(
    'реальный вызов DeepSeek через OpenAI-compatible: один запрос, '
    'карточки по канонической схеме A8.4',
    () async {
      final Dio dio = Dio();
      addTearDown(() => dio.close(force: true));

      final service = CardGenerationService(
        adapters: <OpenAiCompatibleAdapter>[const OpenAiCompatibleAdapter()],
        apiKeyStore: FakeApiKeyStore(<String, String>{'deepseek': apiKey!}),
        httpClient: GenerationHttpClient(
          dio: dio,
          retryPolicy: RetryPolicy(),
          delay: (Duration _) async {},
        ),
        maxOutputTokens: 4096,
      );

      final result = await service.generate(
        GenerationRequest(
          account: ProviderAccount(
            id: 'deepseek',
            label: 'DeepSeek',
            presetId: 'deepseek',
            protocol: ProviderProtocol.openaiCompletions,
            baseUrl: baseUrl,
            modelId: model,
            contextTokens: 128000,
            requiresApiKey: true,
          ),
          materialsText:
              'FSRS — алгоритм интервального повторения. Он прогнозирует '
              'вероятность вспоминания карточки и выбирает дату следующего '
              'повторения. CardFlow использует FSRS для планирования.',
          limit: 3,
        ),
      );

      // Успешный ответ доказывает: живой endpoint, разбор ответа, локальная
      // валидация схемы A8.4 и контентные правила пройдены.
      expect(result.provider, GenerationProvider.openaiCompatible);
      expect(result.model, model);
      expect(result.promptVersion, systemPromptVersion);
      expect(result.cards, isNotEmpty);
      expect(result.cards.length, lessThanOrEqualTo(3));
      for (final card in result.cards) {
        expect(card.front.trim(), isNotEmpty);
      }
      // ignore: avoid_print — evidence в логе прогона без ключа/материалов.
      print(
        'LIVE DeepSeek OK: model=$model, cards=${result.cards.length}, '
        'tokens=${result.usage.totalTokens}',
      );
    },
    skip: liveSkip,
    timeout: const Timeout(Duration(minutes: 2)),
    tags: <String>['live'],
  );

  test(
    'живой DeepSeek отклоняет strict response_format → fallback с max_tokens '
    '(ADR-021)',
    () async {
      // Запоминаем только метаданные запросов: ключ, тела и ответ модели в
      // лог не попадают (AGENTS: тела генерации не логируются).
      final List<Map<String, Object?>> bodies = <Map<String, Object?>>[];
      final List<int?> statuses = <int?>[];
      final Dio dio = Dio();
      addTearDown(() => dio.close(force: true));
      dio.interceptors.add(
        InterceptorsWrapper(
          onRequest: (RequestOptions options, RequestInterceptorHandler next) {
            final data = options.data;
            if (data is String) {
              final decoded = jsonDecode(data);
              if (decoded is Map<String, Object?>) bodies.add(decoded);
            }
            next.next(options);
          },
          onResponse:
              (Response<dynamic> response, ResponseInterceptorHandler next) {
                statuses.add(response.statusCode);
                next.next(response);
              },
          onError: (DioException error, ErrorInterceptorHandler next) {
            statuses.add(error.response?.statusCode);
            next.next(error);
          },
        ),
      );

      final service = CardGenerationService(
        adapters: <OpenAiCompatibleAdapter>[const OpenAiCompatibleAdapter()],
        apiKeyStore: FakeApiKeyStore(<String, String>{'deepseek': apiKey!}),
        httpClient: GenerationHttpClient(
          dio: dio,
          retryPolicy: RetryPolicy(),
          delay: (Duration _) async {},
        ),
        maxOutputTokens: 8192,
      );

      final result = await service.generate(
        GenerationRequest(
          account: ProviderAccount(
            id: 'deepseek',
            label: 'DeepSeek',
            presetId: 'deepseek',
            protocol: ProviderProtocol.openaiCompletions,
            baseUrl: baseUrl,
            modelId: model,
            contextTokens: 128000,
            requiresApiKey: true,
          ),
          materialsText:
              'Минералы делятся на классы по химическому составу. Кварц — '
              'минерал класса оксидов, твердость 7, блеск стеклянный.',
          limit: 2,
        ),
      );

      expect(result.cards, isNotEmpty);
      expect(
        bodies,
        hasLength(2),
        reason: 'strict-запрос отклонён, затем fallback',
      );
      expect(statuses, <int?>[400, 200]);
      final strictFormat = bodies.first['response_format'];
      expect(strictFormat, isA<Map<String, Object?>>());
      expect(bodies.first['max_tokens'], 8192);
      expect(bodies.last.containsKey('response_format'), isFalse);
      expect(bodies.last['max_tokens'], 8192);
      // ignore: avoid_print — evidence без ключа, тел и ответа модели.
      print(
        'LIVE DeepSeek fallback: strict=${statuses.first}, '
        'tolerant=${statuses.last}, max_tokens=${bodies.last['max_tokens']}, '
        'cards=${result.cards.length}',
      );
    },
    skip: liveSkip,
    timeout: const Timeout(Duration(minutes: 2)),
    tags: <String>['live'],
  );

  // Итерация 7.10, ADR-024: генерация по теме без файлов и проверка того, что
  // модель возвращает image_query по правилу 14 промпта `gen-ru-v4`.
  test(
    'живой DeepSeek: prompt-only без файлов и выбор картинки (gen-ru-v7)',
    () async {
      final List<String> diagnostics = <String>[];
      final Dio dio = Dio();
      addTearDown(() => dio.close(force: true));

      final service = CardGenerationService(
        adapters: <OpenAiCompatibleAdapter>[const OpenAiCompatibleAdapter()],
        apiKeyStore: FakeApiKeyStore(<String, String>{'deepseek': apiKey!}),
        httpClient: GenerationHttpClient(
          dio: dio,
          retryPolicy: RetryPolicy(),
          delay: (Duration _) async {},
        ),
        maxOutputTokens: 8192,
        diagnostics: GenerationDiagnostics(
          enabled: true,
          sink: diagnostics.add,
        ),
      );

      final result = await service.generate(
        GenerationRequest(
          account: ProviderAccount(
            id: 'deepseek',
            label: 'DeepSeek',
            presetId: 'deepseek',
            protocol: ProviderProtocol.openaiCompletions,
            baseUrl: baseUrl,
            modelId: model,
            contextTokens: 128000,
            requiresApiKey: true,
          ),
          materialsText: '',
          wishes: 'Животные Африки: слон, жираф и лев. 3 карточки',
          limit: 3,
        ),
      );

      expect(result.cards, isNotEmpty);
      expect(result.promptVersion, systemPromptVersion);
      final int withQuery = result.cards
          .where((card) => (card.imageQuery ?? '').isNotEmpty)
          .length;
      final int withAbstractQuery = result.cards
          .where(
            (card) => card.issues.contains(CardIssueCode.abstractImageQuery),
          )
          .length;
      final int malformed = result.cards
          .where((card) => card.issues.contains(CardIssueCode.latexBroken))
          .length;
      // ignore: avoid_print — evidence: сырой ответ модели (диагностика ADR-024),
      // чтобы видеть `image_query` при разборе owner-note (итерация fix-gen).
      for (final String line in diagnostics) {
        // ignore: avoid_print
        print(line);
      }
      // ignore: avoid_print — evidence без ключа и тел ответа.
      print(
        'LIVE DeepSeek prompt-only: cards=${result.cards.length}, '
        'image_query=$withQuery, abstract_query=$withAbstractQuery, '
        'latex_broken=$malformed, prompt=${result.promptVersion}, '
        'tokens=${result.usage.totalTokens}, '
        'rejected=${result.rejectedCards}',
      );
      expect(
        withQuery,
        greaterThan(0),
        reason: 'промпт v5 требует image_query для конкретных объектов',
      );
      expect(diagnostics, isNotEmpty);
      // С v6 модель отвечает объектом image; ответ v5 с image_query тоже
      // допустим — live-проверка смотрит только на наличие выбора картинки.
      expect(
        diagnostics.single.contains('image_query') ||
            diagnostics.single.contains('"image"'),
        isTrue,
        reason: 'в ответе нет ни image_query (v5), ни image (v6+)',
      );
    },
    skip: liveSkip,
    timeout: const Timeout(Duration(minutes: 2)),
    tags: <String>['live'],
  );
  // Итерация 7.12 (ADR-028): production-пайплайн с живым DeepSeek и живым
  // поиском картинок — карточки должны прийти с иллюстрациями.
  test(
    'живой DeepSeek → image_query → реальный поиск → карточки с картинками',
    () async {
      final List<String> diagnostics = <String>[];
      final Dio dio = Dio();
      addTearDown(() => dio.close(force: true));
      final GenerationDiagnostics diag = GenerationDiagnostics(
        enabled: true,
        sink: diagnostics.add,
      );
      final service = CardGenerationService(
        adapters: <OpenAiCompatibleAdapter>[const OpenAiCompatibleAdapter()],
        apiKeyStore: FakeApiKeyStore(<String, String>{'deepseek': apiKey!}),
        httpClient: GenerationHttpClient(
          dio: dio,
          retryPolicy: RetryPolicy(),
          delay: (Duration _) async {},
        ),
        maxOutputTokens: 8192,
        diagnostics: diag,
      );
      final pipeline = GenerationPipeline(
        caller: service,
        jobRepository: FakeGenerationJobRepository(),
        cardStore: FakeGenerationCardStore(),
        imageFinder: CompositeCardImageFinder(<CardImageFinder>[
          ImageSearchService(
            dio: dio,
            providers: <ImageProvider>[WikimediaImageProvider(dio: dio)],
            diagnostics: diag,
          ),
          ImageSearchService(
            dio: dio,
            providers: <ImageProvider>[WikipediaImageProvider(dio: dio)],
            diagnostics: diag,
          ),
          ImageSearchService(
            dio: dio,
            providers: <ImageProvider>[OpenverseImageProvider(dio: dio)],
            diagnostics: diag,
          ),
        ]),
        imageSearchBudget: const Duration(seconds: 90),
        diagnostics: diag,
      );

      final GenerationRunResult result = await pipeline.run(
        GenerationRunRequest(
          documents: const <ParsedDocument>[],
          account: ProviderAccount(
            id: 'deepseek',
            label: 'DeepSeek',
            presetId: 'deepseek',
            protocol: ProviderProtocol.openaiCompletions,
            baseUrl: baseUrl,
            modelId: model,
            contextTokens: 16000,
            requiresApiKey: true,
          ),
          deckName: 'Живые картинки',
          wishes: 'Животные Африки: слон, жираф и лев. 3 карточки',
        ),
      );

      // ignore: avoid_print — evidence: итог и причины до проверок.
      for (final String line in diagnostics) {
        // ignore: avoid_print
        print(line);
      }
      // ignore: avoid_print — evidence без ключа.
      print(
        'LIVE image pipeline status=${result.status.name}, '
        'cards=${result.cards.length}, '
        'failures=${result.failures.map((failure) => failure.code.name).toList()}, '
        'model=$model',
      );
      expect(result.status, GenerationJobStatus.done);
      expect(result.cards, isNotEmpty);
      final int withImage = result.cards
          .where((card) => card.image != null)
          .length;
      // ignore: avoid_print — evidence без ключа и тел ответа.
      print(
        'LIVE image pipeline: cards=${result.cards.length}, '
        'with_image=$withImage, model=$model',
      );
      for (final GeneratedCard card in result.cards) {
        // ignore: avoid_print
        print(
          'LIVE card: image_query=${card.imageQuery}, '
          'image=${card.image == null ? 'null' : '${card.image!.bytes.length} Б '
                    '${card.image!.mediaType.name}'}, '
          'issues=${card.issues.map((issue) => issue.name).toList()}',
        );
      }
      expect(
        withImage,
        greaterThan(0),
        reason: 'живой поиск должен приложить хотя бы одну картинку',
      );
    },
    skip: liveSkip,
    timeout: const Timeout(Duration(minutes: 5)),
    tags: <String>['live'],
  );

  // Итерация 7.11 (owner-note): страницы PDF-скана отправляются реальной
  // Vision-модели как image parts и дают карточки.
  test(
    'живой DeepSeek: страницы PDF-скана как image parts (7.11)',
    () async {
      // Фикстура `buildPdfPages` пишет страницы в Latin-1, поэтому текст
      // страниц латинский: для Vision важен сам PNG-скан, а не алфавит.
      final Uint8List pdf = buildPdfPages(<String>[
        'Ivan the Terrible ruled from 1533 to 1584.',
        'The Time of Troubles began after the Rurik dynasty ended.',
        'In 1613 the Zemsky Sobor elected Mikhail Romanov as tsar.',
      ]);
      final List<Uint8List> pages = await const PdfScanRenderer(
        maxPages: 3,
        maxWidth: 1000,
      ).render(pdf);
      expect(pages, hasLength(3));

      final List<GenerationAttachment> attachments = <GenerationAttachment>[
        for (var index = 0; index < pages.length; index++)
          GenerationAttachment(
            fileName: 'скан.pdf',
            mediaType: AttachmentMediaType.png,
            bytes: pages[index],
            pageNumber: index + 1,
            groupKey: '/tmp/скан.pdf',
          ),
      ];

      final Dio dio = Dio();
      addTearDown(() => dio.close(force: true));
      final service = CardGenerationService(
        adapters: <OpenAiCompatibleAdapter>[const OpenAiCompatibleAdapter()],
        apiKeyStore: FakeApiKeyStore(<String, String>{'deepseek': apiKey!}),
        httpClient: GenerationHttpClient(
          dio: dio,
          retryPolicy: RetryPolicy(),
          delay: (Duration _) async {},
        ),
        maxOutputTokens: 8192,
      );

      final result = await service.generate(
        GenerationRequest(
          account: ProviderAccount(
            id: 'deepseek',
            label: 'DeepSeek',
            presetId: 'deepseek',
            protocol: ProviderProtocol.openaiCompletions,
            baseUrl: baseUrl,
            modelId: model,
            contextTokens: 128000,
            requiresApiKey: true,
            supportsVision: true,
          ),
          materialsText: '',
          wishes: 'Сделай 2 карточки по содержанию скана',
          limit: 2,
          images: attachments,
        ),
      );

      expect(result.cards, isNotEmpty);
      // ignore: avoid_print — evidence без ключа и тел ответа.
      print(
        'LIVE DeepSeek scan OK: pages=${pages.length}, '
        'cards=${result.cards.length}, tokens=${result.usage.totalTokens}',
      );
    },
    skip: liveSkip,
    timeout: const Timeout(Duration(minutes: 3)),
    tags: <String>['live'],
  );

  // Итерация fix-gen (Д5): автоматическая оценка качества по теме без файлов.
  test(
    'живой DeepSeek: тема «Статика: аксиомы, связи, плоские фермы», '
    '20 карточек, доля пометок качества',
    () async {
      final Dio dio = Dio();
      addTearDown(() => dio.close(force: true));
      final service = CardGenerationService(
        adapters: <OpenAiCompatibleAdapter>[const OpenAiCompatibleAdapter()],
        apiKeyStore: FakeApiKeyStore(<String, String>{'deepseek': apiKey!}),
        httpClient: GenerationHttpClient(
          dio: dio,
          retryPolicy: RetryPolicy(),
          delay: (Duration _) async {},
        ),
        maxOutputTokens: 8192,
      );

      final result = await service.generate(
        GenerationRequest(
          account: ProviderAccount(
            id: 'deepseek',
            label: 'DeepSeek',
            presetId: 'deepseek',
            protocol: ProviderProtocol.openaiCompletions,
            baseUrl: baseUrl,
            modelId: model,
            contextTokens: 16000,
            requiresApiKey: true,
          ),
          materialsText: '',
          wishes:
              'Статика: аксиомы, связи, плоские фермы. Сделай 20 карточек, '
              'с уровнем сложности вуза',
          limit: 20,
        ),
        cancelToken: null,
      );

      expect(result.cards, isNotEmpty);
      expect(result.cards.length, lessThanOrEqualTo(20));
      final Map<String, int> byIssue = <String, int>{};
      for (final GeneratedCard card in result.cards) {
        expect(card.front.trim(), isNotEmpty);
        for (final CardIssueCode issue in card.issues) {
          byIssue[issue.name] = (byIssue[issue.name] ?? 0) + 1;
        }
      }
      final int marked = result.cards.where((card) => card.hasIssues).length;
      final double share = marked / result.cards.length;
      // ignore: avoid_print — evidence без ключа и тел ответа (fix-gen Д5).
      print(
        'LIVE statics quality: cards=${result.cards.length}, '
        'prompt=${result.promptVersion}, rejected=${result.rejectedCards}, '
        'tokens=${result.usage.totalTokens}, marked=$marked '
        '(${(share * 100).toStringAsFixed(1)} %), issues=$byIssue',
      );
      for (final GeneratedCard card in result.cards.take(10)) {
        // ignore: avoid_print
        print(
          'LIVE statics card: front="${card.front}" | '
          'back="${card.back}" | image_id=${card.imageId}, '
          'image_query=${card.imageQuery}, '
          'issues=${card.issues.map((issue) => issue.name).toList()}',
        );
      }
      expect(result.promptVersion, 'gen-ru-v7');
    },
    skip: liveSkip,
    timeout: const Timeout(Duration(minutes: 5)),
    tags: <String>['live'],
  );

  // Итерация fix-gen (Д3): DOCX с рисунком → каталог <images> → карточки
  // с иллюстрацией из файла (приоритет над внешним поиском).
  test(
    'живой DeepSeek: DOCX с формулами и рисунком → image_id из файла',
    () async {
      final Uint8List docx = buildDocxWithImage(
        paragraphs: <String>[
          'Статика. Аксиома о равновесии двух сил.',
          'Две силы, приложенные к твёрдому телу, уравновешены, если равны '
              'по модулю и направлены вдоль одной прямой в противоположные '
              'стороны.',
          'Плоская ферма геометрически неизменяема при s = 2n - 3.',
        ],
        imageBytes: pngFixture(seed: 21),
        caption: 'Рис. 1. Тело под действием двух сил',
      );
      final ParsedDocument parsed = await const DocxParser().parse(
        docx,
        fileName: 'статика-fixgen.docx',
      );
      expect(parsed.images, isNotEmpty);

      final Dio dio = Dio();
      addTearDown(() => dio.close(force: true));
      final List<String> diagnostics = <String>[];
      final GenerationDiagnostics diag = GenerationDiagnostics(
        enabled: true,
        sink: diagnostics.add,
      );
      final service = CardGenerationService(
        adapters: <OpenAiCompatibleAdapter>[const OpenAiCompatibleAdapter()],
        apiKeyStore: FakeApiKeyStore(<String, String>{'deepseek': apiKey!}),
        httpClient: GenerationHttpClient(
          dio: dio,
          retryPolicy: RetryPolicy(),
          delay: (Duration _) async {},
        ),
        maxOutputTokens: 8192,
        diagnostics: diag,
      );
      final pipeline = GenerationPipeline(
        caller: service,
        jobRepository: FakeGenerationJobRepository(),
        cardStore: FakeGenerationCardStore(),
        imageFinder: null,
        diagnostics: diag,
      );

      final GenerationRunResult result = await pipeline.run(
        GenerationRunRequest(
          documents: <ParsedDocument>[parsed],
          account: ProviderAccount(
            id: 'deepseek',
            label: 'DeepSeek',
            presetId: 'deepseek',
            protocol: ProviderProtocol.openaiCompletions,
            baseUrl: baseUrl,
            modelId: model,
            contextTokens: 16000,
            requiresApiKey: true,
          ),
          deckName: 'Статика fix-gen',
          wishes: 'Акцент на аксиомах и фермах',
        ),
      );

      final int withImage = result.cards
          .where((card) => card.image != null)
          .length;
      final int withImageId = result.cards
          .where((card) => (card.imageId ?? '').isNotEmpty)
          .length;
      // ignore: avoid_print — evidence без ключа и тел ответа.
      print(
        'LIVE docx images: images=${parsed.images.length}, '
        'status=${result.status.name}, cards=${result.cards.length}, '
        'image_id=$withImageId, with_image=$withImage, '
        'tokens=${result.tokensUsed}',
      );
      expect(result.cards, isNotEmpty);
      expect(result.cards.length, lessThanOrEqualTo(20));
    },
    skip: liveSkip,
    timeout: const Timeout(Duration(minutes: 5)),
    tags: <String>['live'],
  );
}

/// Непустое (после trim) значение переменной окружения или null.
String? _envValue(Map<String, String> env, String name) {
  final value = env[name]?.trim();
  if (value == null || value.isEmpty) return null;
  return value;
}
