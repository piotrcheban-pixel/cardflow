import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cardflow/api/images/placeholder_image_generator.dart';
import 'package:cardflow/api/parsers/document_parser.dart';
import 'package:cardflow/api/parsers/file_parsing_service.dart';
import 'package:cardflow/api/parsers/pdf_scan_pages.dart';
import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/decks/deck_summary.dart';
import 'package:cardflow/domain/generation/generated_card.dart';
import 'package:cardflow/domain/generation/generation_attachment.dart';
import 'package:cardflow/domain/generation/generation_error.dart';
import 'package:cardflow/domain/generation/generation_job.dart';
import 'package:cardflow/domain/generation/generation_run.dart';
import 'package:cardflow/domain/generation/document_gateway.dart';
import 'package:cardflow/domain/generation/provider_account.dart';
import 'package:cardflow/domain/text/document_format.dart';
import 'package:cardflow/domain/text/parsed_document.dart';
import 'package:cardflow/domain/text/parser_exception.dart';
import 'package:cardflow/ui/generation/generation_screen.dart';
import 'package:cardflow/ui/state/app_providers.dart';

import '../../helpers/decks_fakes.dart';
import '../../helpers/generation_fakes.dart';
import '../../helpers/pump_app.dart';
import '../../helpers/settings_fakes.dart';

Future<T> inlineIsolate<T>(Future<T> Function() task) => task();

void main() {
  late FakeDocumentGateway gateway;
  late FakeGenerationRunner runner;
  late FakeApiKeyStore keyStore;
  late FakeProviderAccountsStore accountsStore;
  late FakeDeckRepository deckRepository;

  setUp(() {
    gateway = FakeDocumentGateway();
    runner = FakeGenerationRunner();
    keyStore = FakeApiKeyStore(<String, String>{'deepseek': 'sk-deepseek'});
    // Базовый аккаунт тестов — legacy-модель без Vision: сценарии с
    // изображениями проверяют отказ, а Vision-успех задаётся явно (OpenAI).
    // Отдельный тест проверяет актуальную модель по умолчанию (flash).
    accountsStore = FakeProviderAccountsStore(
      ProviderAccounts.empty.withAccount(
        testProviderAccount(modelId: 'deepseek-chat'),
      ),
    );
    deckRepository = FakeDeckRepository();
  });

  List<Override> overrides({FileParsingService? parsingService}) {
    return <Override>[
      documentGatewayProvider.overrideWithValue(gateway),
      fileParsingServiceProvider.overrideWithValue(
        parsingService ?? FileParsingService(isolateRunner: inlineIsolate),
      ),
      generationRunnerProvider.overrideWithValue(runner),
      generationCardStoreProvider.overrideWithValue(FakeGenerationCardStore()),
      apiKeyStoreProvider.overrideWithValue(keyStore),
      providerAccountsStoreProvider.overrideWithValue(accountsStore),
      deckRepositoryProvider.overrideWithValue(deckRepository),
      appSettingsStoreProvider.overrideWithValue(FakeAppSettingsStore()),
    ];
  }

  GenerationRunResult resultWith(List<GeneratedCard> cards) {
    return GenerationRunResult(
      jobId: 'job-1',
      status: GenerationJobStatus.done,
      cards: cards,
      failures: const <GenerationChunkFailure>[],
      tokensUsed: 42,
      estimatedTokens: 100,
      duplicatesRemoved: 0,
      chunkCount: 1,
      cancelled: false,
    );
  }

  Future<void> pumpScreen(
    WidgetTester tester, {
    String? deckId,
    FileParsingService? parsingService,
  }) async {
    await tester.pumpWidget(
      appWithHome(
        overrides: overrides(parsingService: parsingService),
        home: GenerationScreen(deckId: deckId),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> attachTextFile(WidgetTester tester) async {
    gateway.picked = <PickedDocument>[
      const PickedDocument(
        path: '/tmp/лекция.txt',
        name: 'лекция.txt',
        sizeBytes: 30,
      ),
    ];
    gateway.bytesByPath['/tmp/лекция.txt'] = Uint8List.fromList(
      utf8.encode('Материал лекции'),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('generation-attach-zone')),
    );
    await tester.pumpAndSettle();
  }

  Future<void> attachImageFile(WidgetTester tester) async {
    gateway.picked = <PickedDocument>[
      const PickedDocument(
        path: '/tmp/схема.png',
        name: 'схема.png',
        sizeBytes: 16,
      ),
    ];
    gateway.bytesByPath['/tmp/схема.png'] = Uint8List.fromList(<int>[
      0x89,
      0x50,
      0x4E,
      0x47,
      0x0D,
      0x0A,
      0x1A,
      0x0A,
      0,
      0,
    ]);
    await tester.tap(
      find.byKey(const ValueKey<String>('generation-attach-zone')),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('основной провайдер из настроек предвыбирается, модель — его', (
    tester,
  ) async {
    accountsStore.accounts = ProviderAccounts.empty
        .withAccount(testProviderAccount(presetId: 'deepseek'))
        .withAccount(testProviderAccount(presetId: 'groq'))
        .withActive('groq');
    keyStore.keys['groq'] = 'sk-groq';
    await pumpScreen(tester);

    final Finder chip = find.byKey(
      const ValueKey<String>('generation-provider-groq'),
    );
    await tester.scrollUntilVisible(
      chip,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(tester.widget<ChoiceChip>(chip).selected, isTrue);

    final Finder modelField = find.byKey(
      const ValueKey<String>('generation-model-groq'),
    );
    await tester.scrollUntilVisible(
      modelField,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(
      tester.widget<DropdownButtonFormField<String>>(modelField).initialValue,
      'llama-3.3-70b-versatile',
    );
  });

  testWidgets('рендер: заголовок, зона прикрепления, пожелания, кнопка', (
    tester,
  ) async {
    await pumpScreen(tester);
    final l10n = l10nOf(tester);
    expect(find.text(l10n.generationTitle), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('generation-attach-zone')),
      findsOneWidget,
    );
    expect(find.text(l10n.generationAttachHint), findsOneWidget);
    expect(find.text(l10n.generationWishesLabel), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('generation-start')),
      findsOneWidget,
    );
    expect(find.text(l10n.generationFilesEmpty), findsOneWidget);
  });

  testWidgets('пикер: файл разобран, статус и оценка токенов', (tester) async {
    await pumpScreen(tester);
    await attachTextFile(tester);
    final l10n = l10nOf(tester);
    expect(gateway.pickCalls, 1);
    expect(gateway.readCalls, 1);
    expect(
      find.byKey(const ValueKey<String>('generation-file-tile-0')),
      findsOneWidget,
    );
    expect(find.text('лекция.txt'), findsOneWidget);
    expect(find.text(l10n.generationFileParsed), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('generation-estimate')),
      findsOneWidget,
    );
    expect(find.textContaining('Примерно'), findsOneWidget);
    final start = tester.widget<FilledButton>(
      find.byKey(const ValueKey<String>('generation-start')),
    );
    expect(start.onPressed, isNotNull);
  });

  // Итерация 7.14: колода видна сразу, картинки догружаются, UI обновляется.
  testWidgets('живые карточки и картинки во время генерации', (tester) async {
    final placeholder = const PlaceholderImageGenerator().generate(
      seed: 'live-card',
    );
    final GeneratedCard card = GeneratedCard(
      front: 'Какой тип моста состоит из треугольных ячеек?',
      back: 'Ферменный мост.',
      cardType: CardType.basic,
      image: placeholder,
    );
    runner.pending = Completer<GenerationRunResult>();
    runner.result = resultWith(<GeneratedCard>[card]);
    await pumpScreen(tester);
    await attachTextFile(tester);

    await tester.tap(find.byKey(const ValueKey<String>('generation-start')));
    await tester.pump();

    final l10n = l10nOf(tester);
    runner.lastProgress!(
      GenerationProgress(
        phase: GenerationProgressPhase.receiving,
        chunkIndex: 1,
        chunkCount: 1,
        cards: <GeneratedCard>[card],
        imagesPending: true,
      ),
    );
    await tester.pump();

    expect(
      find.byKey(const ValueKey<String>('generation-live-cards')),
      findsOneWidget,
    );
    expect(find.text(l10n.generationLiveCardsTitle(1)), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('generation-live-pending')),
      findsOneWidget,
      reason: 'показываем, что картинки ещё догружаются',
    );
    expect(find.byKey(const ValueKey<String>('card-image')), findsOneWidget);

    runner.pending!.complete(runner.result!);
    await tester.pumpAndSettle();
  });

  testWidgets('файл можно убрать', (tester) async {
    await pumpScreen(tester);
    await attachTextFile(tester);
    await tester.tap(
      find.byKey(const ValueKey<String>('generation-file-remove-0')),
    );
    await tester.pumpAndSettle();
    final l10n = l10nOf(tester);
    expect(find.text(l10n.generationFilesEmpty), findsOneWidget);
  });

  testWidgets('ошибка файла показывается строкой ARB и не блокирует экран', (
    tester,
  ) async {
    gateway.picked = <PickedDocument>[
      const PickedDocument(
        path: '/tmp/старый.doc',
        name: 'старый.doc',
        sizeBytes: 10,
      ),
    ];
    await pumpScreen(tester);
    await tester.tap(
      find.byKey(const ValueKey<String>('generation-attach-zone')),
    );
    await tester.pumpAndSettle();
    final l10n = l10nOf(tester);
    expect(find.text(l10n.parserErrorUnsupportedFormat), findsOneWidget);
  });

  testWidgets('старт без файлов и без темы — кнопка неактивна, подсказка ARB', (
    tester,
  ) async {
    await pumpScreen(tester);
    final l10n = l10nOf(tester);
    final FilledButton button = tester.widget<FilledButton>(
      find.byKey(const ValueKey<String>('generation-start')),
    );
    expect(
      button.onPressed,
      isNull,
      reason: 'нечего генерировать (fix-gen Д1)',
    );
    expect(
      find.byKey(const ValueKey<String>('generation-start-hint')),
      findsOneWidget,
    );
    expect(find.text(l10n.generationTopicRequired), findsOneWidget);
    expect(runner.runCalls, 0);
  });

  // Итерация 7.10, ADR-024: тема без файлов — валидный вход генерации.
  testWidgets('старт только с темой (без файлов) — prompt-only запрос', (
    tester,
  ) async {
    await pumpScreen(tester);
    runner.result = resultWith(<GeneratedCard>[
      const GeneratedCard(
        front: 'Что такое фотосинтез?',
        back: 'Процесс синтеза органики на свету.',
        cardType: CardType.basic,
      ),
    ]);
    final Finder wishes = find.byKey(
      const ValueKey<String>('generation-wishes'),
    );
    await tester.scrollUntilVisible(
      wishes,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(wishes, 'Фотосинтез');
    await tester.pump();
    expect(
      find.byKey(const ValueKey<String>('generation-estimate')),
      findsOneWidget,
      reason: 'для prompt-only тоже показываем оценку токенов',
    );

    await tester.tap(find.byKey(const ValueKey<String>('generation-start')));
    await tester.pumpAndSettle();

    final l10n = l10nOf(tester);
    expect(runner.runCalls, 1);
    expect(runner.lastRequest!.documents, isEmpty);
    expect(runner.lastRequest!.images, isEmpty);
    expect(runner.lastRequest!.wishes, 'Фотосинтез');
    // fix-gen Д1: имя колоды по умолчанию берётся из темы пожелания.
    expect(runner.lastRequest!.deckName, 'Фотосинтез');
    expect(find.text(l10n.generationPreviewTitle), findsOneWidget);
  });

  testWidgets('старт: запрос с документами и именем колоды из файла', (
    tester,
  ) async {
    await pumpScreen(tester);
    await attachTextFile(tester);
    runner.result = resultWith(<GeneratedCard>[
      const GeneratedCard(
        front: 'Вопрос',
        back: 'Ответ',
        cardType: CardType.basic,
      ),
    ]);
    await tester.tap(find.byKey(const ValueKey<String>('generation-start')));
    await tester.pumpAndSettle();

    expect(runner.runCalls, 1);
    expect(runner.lastRequest, isNotNull);
    expect(runner.lastRequest!.documents, hasLength(1));
    expect(runner.lastRequest!.documents.single.fileName, 'лекция.txt');
    expect(runner.lastRequest!.deckName, 'лекция');
    expect(runner.lastRequest!.targetDeckId, isNull);
    expect(runner.lastRequest!.account.id, 'deepseek');
    expect(runner.lastRequest!.account.baseUrl, 'https://api.deepseek.com');
    expect(runner.lastRequest!.account.modelId, 'deepseek-chat');
    final l10n = l10nOf(tester);
    expect(find.text(l10n.generationPreviewTitle), findsOneWidget);
  });

  testWidgets('нет ключа: баннер и переход в настройки', (tester) async {
    keyStore = FakeApiKeyStore();
    await pumpScreen(tester);
    final l10n = l10nOf(tester);
    expect(find.text(l10n.generationKeyMissing), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('generation-key-banner')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('generation-open-settings')),
      findsOneWidget,
    );
  });

  testWidgets('провайдеры не настроены: баннер «Сервер не настроен»', (
    tester,
  ) async {
    accountsStore = FakeProviderAccountsStore();
    await pumpScreen(tester);
    final l10n = l10nOf(tester);
    expect(
      find.byKey(const ValueKey<String>('generation-provider-banner')),
      findsOneWidget,
    );
    expect(
      find.text(l10n.generationErrorProviderNotConfigured),
      findsOneWidget,
    );

    await attachTextFile(tester);
    await tester.tap(find.byKey(const ValueKey<String>('generation-start')));
    await tester.pumpAndSettle();
    expect(runner.runCalls, 0);
    expect(find.text(l10n.generationErrorProviderNotConfigured), findsWidgets);
  });

  testWidgets('прогресс и отмена: текст фрагмента и отмена токена', (
    tester,
  ) async {
    await pumpScreen(tester);
    await attachTextFile(tester);
    runner.pending = Completer<GenerationRunResult>();
    await tester.tap(find.byKey(const ValueKey<String>('generation-start')));
    await tester.pump();

    runner.lastProgress!(
      const GenerationProgress(
        phase: GenerationProgressPhase.sending,
        chunkIndex: 1,
        chunkCount: 3,
      ),
    );
    await tester.pump();
    final l10n = l10nOf(tester);
    expect(find.text(l10n.generationProgressSending(1, 3)), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('generation-cancel')),
      findsOneWidget,
    );

    await tester.tap(find.byKey(const ValueKey<String>('generation-cancel')));
    await tester.pump();
    expect(runner.lastCancellation, isNotNull);
    expect(runner.lastCancellation!.isCancelled, isTrue);

    runner.pending!.complete(
      const GenerationRunResult(
        jobId: 'job-1',
        status: GenerationJobStatus.cancelled,
        cards: <GeneratedCard>[],
        failures: <GenerationChunkFailure>[],
        tokensUsed: 0,
        estimatedTokens: 10,
        duplicatesRemoved: 0,
        chunkCount: 0,
        cancelled: true,
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text(l10n.generationCancelled), findsOneWidget);
  });

  testWidgets('ошибка генерации — строка ARB без сырых деталей', (
    tester,
  ) async {
    await pumpScreen(tester);
    await attachTextFile(tester);
    runner.error = const GenerationException(
      GenerationErrorCode.invalidApiKey,
      details: 'raw-provider-detail',
    );
    await tester.tap(find.byKey(const ValueKey<String>('generation-start')));
    await tester.pumpAndSettle();
    final l10n = l10nOf(tester);
    expect(find.text(l10n.generationErrorInvalidApiKey), findsOneWidget);
    expect(find.textContaining('raw-provider-detail'), findsNothing);
  });

  testWidgets('целевая колода: имя показывается, поле имени скрыто', (
    tester,
  ) async {
    deckRepository = FakeDeckRepository(
      summaries: <DeckSummary>[
        makeSummary(id: 'deck-1', name: 'Моя колода', totalCards: 5),
      ],
    );
    await pumpScreen(tester, deckId: 'deck-1');
    final l10n = l10nOf(tester);
    expect(find.text(l10n.generationTargetDeck('Моя колода')), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('generation-deck-name')),
      findsNothing,
    );
  });

  testWidgets('все фрагменты упали: предпросмотр с ошибками и повтором', (
    tester,
  ) async {
    await pumpScreen(tester);
    await attachTextFile(tester);
    runner.result = GenerationRunResult(
      jobId: 'job-1',
      status: GenerationJobStatus.error,
      cards: const <GeneratedCard>[],
      failures: <GenerationChunkFailure>[
        GenerationChunkFailure(
          chunkIndex: 1,
          code: GenerationErrorCode.network,
          materialsText: 'материал',
          limit: 20,
        ),
      ],
      tokensUsed: 0,
      estimatedTokens: 10,
      duplicatesRemoved: 0,
      chunkCount: 1,
      cancelled: false,
    );
    await tester.tap(find.byKey(const ValueKey<String>('generation-start')));
    await tester.pumpAndSettle();

    final l10n = l10nOf(tester);
    expect(find.text(l10n.generationPreviewTitle), findsOneWidget);
    expect(find.text(l10n.generationFailuresTitle), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('generation-preview-retry-failed')),
      findsOneWidget,
    );
    expect(find.text(l10n.generationErrorEmptyResponse), findsNothing);
  });

  testWidgets('все карточки — дубли: сообщение о дублях, не пустой ответ', (
    tester,
  ) async {
    await pumpScreen(tester);
    await attachTextFile(tester);
    runner.result = const GenerationRunResult(
      jobId: 'job-1',
      status: GenerationJobStatus.done,
      cards: <GeneratedCard>[],
      failures: <GenerationChunkFailure>[],
      tokensUsed: 10,
      estimatedTokens: 10,
      duplicatesRemoved: 2,
      chunkCount: 1,
      cancelled: false,
    );
    await tester.tap(find.byKey(const ValueKey<String>('generation-start')));
    await tester.pumpAndSettle();

    final l10n = l10nOf(tester);
    expect(find.text(l10n.generationDuplicatesRemoved(2)), findsOneWidget);
    expect(find.text(l10n.generationErrorEmptyResponse), findsNothing);
    expect(find.text(l10n.generationPreviewTitle), findsNothing);
  });

  testWidgets(
    'модель вернула валидный пустой массив: понятное сообщение о материалах',
    (tester) async {
      await pumpScreen(tester);
      await attachTextFile(tester);
      // status=done + ноль карточек: модель ответила по схеме пустым списком
      // (пустой бланк/скан в материалах), это не пустой ответ провайдера.
      runner.result = resultWith(const <GeneratedCard>[]);
      await tester.tap(find.byKey(const ValueKey<String>('generation-start')));
      await tester.pumpAndSettle();

      final l10n = l10nOf(tester);
      expect(find.text(l10n.generationNoCardsFound), findsOneWidget);
      expect(find.text(l10n.generationErrorEmptyResponse), findsNothing);
      expect(find.text(l10n.generationPreviewTitle), findsNothing);
    },
  );

  testWidgets('пока файл парсится, кнопка генерации недоступна', (
    tester,
  ) async {
    gateway.readCompleter = Completer<Uint8List>();
    gateway.picked = <PickedDocument>[
      const PickedDocument(
        path: '/tmp/лекция.txt',
        name: 'лекция.txt',
        sizeBytes: 30,
      ),
    ];
    await pumpScreen(tester);
    await tester.tap(
      find.byKey(const ValueKey<String>('generation-attach-zone')),
    );
    await tester.pump();

    FilledButton start = tester.widget<FilledButton>(
      find.byKey(const ValueKey<String>('generation-start')),
    );
    expect(start.onPressed, isNull);

    gateway.readCompleter!.complete(
      Uint8List.fromList(utf8.encode('Материал лекции')),
    );
    await tester.pumpAndSettle();
    start = tester.widget<FilledButton>(
      find.byKey(const ValueKey<String>('generation-start')),
    );
    expect(start.onPressed, isNotNull);
  });

  testWidgets('ошибка чтения ключей: сообщение ARB и повтор', (tester) async {
    keyStore.readError = StateError('secure storage down');
    await pumpScreen(tester);
    final l10n = l10nOf(tester);
    expect(find.text(l10n.settingsLoadError), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('generation-config-retry')),
      findsOneWidget,
    );

    keyStore.readError = null;
    await tester.tap(
      find.byKey(const ValueKey<String>('generation-config-retry')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('generation-attach-zone')),
      findsOneWidget,
    );
  });

  testWidgets('системный Back во время генерации отменяет запрос', (
    tester,
  ) async {
    await pumpScreen(tester);
    await attachTextFile(tester);
    runner.pending = Completer<GenerationRunResult>();
    await tester.tap(find.byKey(const ValueKey<String>('generation-start')));
    await tester.pump();

    await tester.binding.handlePopRoute();
    await tester.pump();
    expect(runner.lastCancellation, isNotNull);
    expect(runner.lastCancellation!.isCancelled, isTrue);

    runner.pending!.complete(
      const GenerationRunResult(
        jobId: 'job-1',
        status: GenerationJobStatus.cancelled,
        cards: <GeneratedCard>[],
        failures: <GenerationChunkFailure>[],
        tokensUsed: 0,
        estimatedTokens: 10,
        duplicatesRemoved: 0,
        chunkCount: 0,
        cancelled: true,
      ),
    );
    await tester.pumpAndSettle();
  });

  testWidgets('картинка: статус «Изображение», модель без Vision — ошибка', (
    tester,
  ) async {
    await pumpScreen(tester);
    await attachImageFile(tester);
    final l10n = l10nOf(tester);
    expect(find.text(l10n.generationFileImage), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('generation-start')));
    await tester.pumpAndSettle();
    expect(runner.runCalls, 0);
    expect(find.text(l10n.generationErrorVisionUnsupported), findsOneWidget);
  });

  testWidgets('картинка + модель Vision: уходит в GenerationRunRequest', (
    tester,
  ) async {
    accountsStore.accounts = ProviderAccounts.empty.withAccount(
      testProviderAccount(presetId: 'openai', modelId: 'gpt-4o'),
    );
    keyStore.keys['openai'] = 'sk-openai';
    await pumpScreen(tester);
    await attachImageFile(tester);
    runner.result = resultWith(<GeneratedCard>[
      const GeneratedCard(
        front: 'Вопрос',
        back: 'Ответ',
        cardType: CardType.basic,
      ),
    ]);

    await tester.tap(find.byKey(const ValueKey<String>('generation-start')));
    await tester.pumpAndSettle();

    expect(runner.runCalls, 1);
    expect(runner.lastRequest!.images, hasLength(1));
    expect(runner.lastRequest!.images.single.fileName, 'схема.png');
    expect(runner.lastRequest!.documents, isEmpty);
    expect(runner.lastRequest!.deckName, 'схема');
  });

  testWidgets('PDF-скан: статус, без Vision — понятная ошибка', (tester) async {
    gateway.picked = <PickedDocument>[
      const PickedDocument(
        path: '/tmp/скан.pdf',
        name: 'скан.pdf',
        sizeBytes: 8,
      ),
    ];
    gateway.bytesByPath['/tmp/скан.pdf'] = Uint8List.fromList(<int>[
      0x25,
      0x50,
      0x44,
      0x46,
      0x2D,
      0x31,
      0x2E,
      0x37,
    ]);
    await pumpScreen(
      tester,
      parsingService: FileParsingService(
        parsers: <DocumentParser>[const _ScannedPdfParser()],
        isolateRunner: inlineIsolate,
        pdfScanPages: _FakePdfScanRenderer(error: StateError('PDFium')),
      ),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('generation-attach-zone')),
    );
    await tester.pumpAndSettle();
    final l10n = l10nOf(tester);
    expect(find.text(l10n.generationFileScannedPdf), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('generation-start')));
    await tester.pumpAndSettle();
    expect(runner.runCalls, 0);
    expect(
      find.text(l10n.generationErrorFileWithoutTextAndVision),
      findsOneWidget,
    );
  });

  group('PDF-скан → PNG-страницы (итерация 7.9)', () {
    Future<void> attachScan(
      WidgetTester tester, {
      String name = 'скан.pdf',
      int pageCount = 3,
    }) async {
      gateway.picked = <PickedDocument>[
        PickedDocument(path: '/tmp/$name', name: name, sizeBytes: 8),
      ];
      gateway.bytesByPath['/tmp/$name'] = Uint8List.fromList(<int>[
        0x25,
        0x50,
        0x44,
        0x46,
        0x2D,
        0x31,
        0x2E,
        0x37,
      ]);
      await pumpScreen(
        tester,
        parsingService: FileParsingService(
          parsers: <DocumentParser>[const _ShortTextPdfParser()],
          isolateRunner: inlineIsolate,
          pdfScanPages: _FakePdfScanRenderer(pageCount: pageCount),
        ),
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('generation-attach-zone')),
      );
      await tester.pumpAndSettle();
    }

    testWidgets('Vision: страницы уходят одним запросом как PNG', (
      tester,
    ) async {
      accountsStore.accounts = ProviderAccounts.empty.withAccount(
        testProviderAccount(presetId: 'openai', modelId: 'gpt-4o'),
      );
      keyStore.keys['openai'] = 'sk-openai';
      await attachScan(tester);
      final l10n = l10nOf(tester);
      expect(find.text(l10n.generationFilePdfPages), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey<String>('generation-start')));
      await tester.pumpAndSettle();

      expect(runner.runCalls, 1);
      final attachments = runner.lastRequest!.images;
      expect(attachments, hasLength(3));
      expect(attachments.map((attachment) => attachment.pageNumber), <int>[
        1,
        2,
        3,
      ]);
      expect(
        attachments.map((attachment) => attachment.groupKey).toSet(),
        <String>{'/tmp/скан.pdf'},
        reason: 'Страницы одного PDF — один фрагмент запроса',
      );
      for (final attachment in attachments) {
        expect(attachment.mediaType, AttachmentMediaType.png);
        expect(
          hasValidAttachmentSignature(
            AttachmentMediaType.png,
            attachment.bytes,
          ),
          isTrue,
        );
        expect(attachment.isPdfPage, isTrue);
        expect(attachment.fileName, 'скан.pdf');
      }
      expect(runner.lastRequest!.documents, isEmpty);
    });

    testWidgets('без Vision — понятная ошибка и запрос не отправлен', (
      tester,
    ) async {
      accountsStore.accounts = ProviderAccounts.empty.withAccount(
        testProviderAccount(modelId: 'deepseek-chat'),
      );
      keyStore.keys['deepseek'] = 'sk-deepseek';
      await attachScan(tester);
      final l10n = l10nOf(tester);

      await tester.tap(find.byKey(const ValueKey<String>('generation-start')));
      await tester.pumpAndSettle();

      expect(runner.runCalls, 0);
      expect(
        find.text(l10n.generationErrorPdfScanVisionRequired),
        findsOneWidget,
      );
    });

    testWidgets('рендер не удался — fallback на PDF и понятная ошибка', (
      tester,
    ) async {
      gateway.picked = <PickedDocument>[
        const PickedDocument(
          path: '/tmp/битый.pdf',
          name: 'битый.pdf',
          sizeBytes: 8,
        ),
      ];
      gateway.bytesByPath['/tmp/битый.pdf'] = Uint8List.fromList(<int>[
        0x25,
        0x50,
        0x44,
        0x46,
        0x2D,
        0x31,
        0x2E,
        0x37,
      ]);
      await pumpScreen(
        tester,
        parsingService: FileParsingService(
          parsers: <DocumentParser>[const _ShortTextPdfParser()],
          isolateRunner: inlineIsolate,
          pdfScanPages: _FakePdfScanRenderer(error: StateError('PDFium')),
        ),
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('generation-attach-zone')),
      );
      await tester.pumpAndSettle();
      final l10n = l10nOf(tester);

      expect(find.text(l10n.generationFileScannedPdf), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey<String>('generation-start')));
      await tester.pumpAndSettle();
      expect(runner.runCalls, 0);
      expect(
        find.text(l10n.generationErrorFileWithoutTextAndVision),
        findsOneWidget,
      );
    });
  });

  // TASK 03, L132: числовое поле количества карточек и предпросмотр плана.
  testWidgets('числовое поле карточек передаёт requestedCards в запрос', (
    tester,
  ) async {
    runner.result = resultWith(<GeneratedCard>[
      const GeneratedCard(
        front: 'Вопрос',
        back: 'Ответ',
        cardType: CardType.basic,
      ),
    ]);
    await pumpScreen(tester);
    await attachTextFile(tester);
    final Finder countField = find.byKey(
      const ValueKey<String>('generation-cards-count'),
    );
    await tester.scrollUntilVisible(
      countField,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(countField, '37');
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey<String>('generation-start')));
    await tester.pumpAndSettle();

    expect(runner.runCalls, 1);
    expect(runner.lastRequest!.requestedCards, 37);
  });

  testWidgets('числовое поле: ноль — ошибка валидации, запуска нет', (
    tester,
  ) async {
    await pumpScreen(tester);
    await attachTextFile(tester);
    final Finder countField = find.byKey(
      const ValueKey<String>('generation-cards-count'),
    );
    await tester.scrollUntilVisible(
      countField,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(countField, '0');
    await tester.pump();
    final l10n = l10nOf(tester);
    expect(find.text(l10n.generationCardsCountInvalid), findsOneWidget);
    expect(runner.runCalls, 0);
  });

  testWidgets('предпросмотр плана показывает недостижимый заказ', (
    tester,
  ) async {
    await pumpScreen(tester);
    await attachTextFile(tester);
    final Finder countField = find.byKey(
      const ValueKey<String>('generation-cards-count'),
    );
    await tester.scrollUntilVisible(
      countField,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.enterText(countField, '1000');
    await tester.pump();
    final Finder preview = find.byKey(
      const ValueKey<String>('generation-plan-preview'),
    );
    await tester.scrollUntilVisible(
      preview,
      -300,
      scrollable: find.byType(Scrollable).first,
    );
    expect(preview, findsOneWidget);
    expect(find.textContaining('запрошено — 1000'), findsOneWidget);
    expect(find.textContaining('достижимо —'), findsOneWidget);
    expect(find.textContaining('Запрошено 1000 карточек'), findsOneWidget);
  });
}

/// Парсер PDF, который всегда сообщает «скан» (проводка UI, итерация 7.8).
class _ScannedPdfParser implements DocumentParser {
  const _ScannedPdfParser();

  @override
  DocumentFormat get format => DocumentFormat.pdf;

  @override
  Future<ParsedDocument> parse(
    Uint8List bytes, {
    required String fileName,
  }) async {
    throw const ParserException(
      ParserErrorCode.scannedPdf,
      details: 'тестовый скан',
    );
  }
}

/// PDF, из которого извлёкся почти пустой текст (< 50 символов).
class _ShortTextPdfParser implements DocumentParser {
  const _ShortTextPdfParser();

  @override
  DocumentFormat get format => DocumentFormat.pdf;

  @override
  Future<ParsedDocument> parse(
    Uint8List bytes, {
    required String fileName,
  }) async {
    const String text = '1';
    return ParsedDocument(
      format: DocumentFormat.pdf,
      fileName: fileName,
      text: text,
      sections: const <ParsedSection>[ParsedSection(start: 0, end: 1)],
    );
  }
}

/// Фейковый разбор PDF-скана для widget-тестов экрана генерации (ADR-037).
class _FakePdfScanRenderer extends PdfScanPageExtractor {
  _FakePdfScanRenderer({this.pageCount = 3, this.error});

  final int pageCount;
  final Object? error;

  static final Uint8List _png = Uint8List.fromList(<int>[
    0x89,
    0x50,
    0x4E,
    0x47,
    0x0D,
    0x0A,
    0x1A,
    0x0A,
    0,
    0,
    0,
  ]);

  @override
  Future<PdfScanDocument> extract(
    Uint8List bytes, {
    required String fileName,
    int? maxPages,
  }) async {
    if (error != null) throw error!;
    return PdfScanDocument(
      fileName: fileName,
      pages: <PdfScanPage>[
        for (var index = 0; index < pageCount; index++)
          PdfScanPage(
            pageNumber: index + 1,
            pngBytes: _png,
            width: 2,
            height: 2,
          ),
      ],
    );
  }
}
