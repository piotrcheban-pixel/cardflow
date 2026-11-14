import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/generation/drift_generation_card_store.dart';
import 'package:cardflow/data/generation/drift_generation_job_repository.dart';
import 'package:cardflow/domain/generation/generation_job.dart';
import 'package:cardflow/domain/generation/generation_provider.dart';
import 'package:cardflow/domain/generation/generation_run.dart';
import 'package:cardflow/domain/text/document_format.dart';
import 'package:cardflow/domain/text/parsed_document.dart';
import 'package:cardflow/ui/state/app_providers.dart';

import '../helpers/fake_http_adapter.dart';
import '../helpers/generation_fakes.dart';

/// Интеграционный срез 3c на production-проводке (урок H1 итерации 2):
/// `app_providers` → `GenerationPipeline` → `CardGenerationService` → fake HTTP →
/// валидация A8.4 → `generation_jobs` (реальная drift-БД) → импорт карточек.
void main() {
  late AppDatabase database;
  late ProviderContainer container;
  late FakeHttpAdapter httpAdapter;

  Map<String, Object?> cardJson() => <String, Object?>{
    'front': 'Что такое FSRS?',
    'back': 'Алгоритм интервального повторения.',
    'hint': null,
    'tags': <Object?>['fsrs'],
    'card_type': 'basic',
    'source_excerpt': null,
    'source_file': 'лекция.txt',
  };

  Map<String, Object?> openAiPayload() => <String, Object?>{
    'choices': <Object?>[
      <String, Object?>{
        'message': <String, Object?>{
          'role': 'assistant',
          'content': jsonEncode(<String, Object?>{
            'cards': <Object?>[cardJson()],
          }),
        },
        'finish_reason': 'stop',
      },
    ],
    'usage': <String, Object?>{
      'prompt_tokens': 10,
      'completion_tokens': 20,
      'total_tokens': 30,
    },
  };

  setUp(() {
    database = AppDatabase.inMemory();
    httpAdapter = FakeHttpAdapter((options) => jsonResponse(openAiPayload()));
    container = ProviderContainer(
      overrides: <Override>[
        appDatabaseProvider.overrideWithValue(database),
        generationDioProvider.overrideWithValue(dioWithAdapter(httpAdapter)),
        apiKeyStoreProvider.overrideWithValue(
          FakeApiKeyStore(<GenerationProvider, String>{
            GenerationProvider.openai: 'test-key-openai',
          }),
        ),
        generationSettingsStoreProvider.overrideWithValue(
          FakeGenerationSettingsStore(),
        ),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await database.close();
  });

  ParsedDocument document() {
    const String text = 'Материал лекции про FSRS и интервальное повторение.';
    return ParsedDocument(
      format: DocumentFormat.txt,
      fileName: 'лекция.txt',
      text: text,
      sections: <ParsedSection>[ParsedSection(start: 0, end: text.length)],
    );
  }

  GenerationRunRequest request({String? targetDeckId}) {
    return GenerationRunRequest(
      documents: <ParsedDocument>[document()],
      provider: GenerationProvider.openai,
      modelId: 'gpt-4o-mini',
      deckName: 'Сгенерированная колода',
      targetDeckId: targetDeckId,
    );
  }

  test(
    'production-граф: генерация → job done в БД → импорт в новую колоду',
    () async {
      final result = await container
          .read(generationRunnerProvider)
          .run(request());

      expect(result.status, GenerationJobStatus.done);
      expect(result.cards, hasLength(1));
      expect(result.tokensUsed, 30);
      expect(result.duplicatesRemoved, 0);
      expect(httpAdapter.requests, hasLength(1));

      final GenerationJob job = (await container
          .read(generationJobRepositoryProvider)
          .jobById(result.jobId))!;
      expect(job.status, GenerationJobStatus.done);
      expect(job.provider, 'openai');
      expect(job.model, 'gpt-4o-mini');
      expect(job.tokensUsed, 30);
      expect(job.cardsCount, 1);
      expect(job.chunkCount, 1);
      expect(job.files, <String>['лекция.txt']);
      expect(job.promptVersion, 'gen-ru-v2');

      final imported = await container
          .read(generationCardStoreProvider)
          .importGeneratedCards(
            deckId: null,
            deckName: 'Сгенерированная колода',
            cards: result.cards,
            jobId: result.jobId,
            now: DateTime.utc(2026, 11, 14, 10),
          );
      expect(imported.importedCards, 1);
      expect(imported.skippedDuplicates, 0);

      final deckRows = await database.select(database.decks).get();
      expect(deckRows, hasLength(1));
      expect(deckRows.single.id, imported.deckId);
      final cardRows = await database.select(database.cards).get();
      expect(cardRows, hasLength(1));
      expect(cardRows.single.front, 'Что такое FSRS?');
      expect(cardRows.single.deckId, imported.deckId);

      final importedJob = (await container
          .read(generationJobRepositoryProvider)
          .jobById(result.jobId))!;
      expect(importedJob.resultDeckId, imported.deckId);
      expect(importedJob.cardsCount, 1);
    },
  );

  test(
    'повторная генерация в ту же колоду отсеивает существующую карточку',
    () async {
      final first = await container
          .read(generationRunnerProvider)
          .run(request());
      final imported = await container
          .read(generationCardStoreProvider)
          .importGeneratedCards(
            deckId: null,
            deckName: 'Колода',
            cards: first.cards,
            jobId: first.jobId,
            now: DateTime.utc(2026),
          );

      final second = await container
          .read(generationRunnerProvider)
          .run(request(targetDeckId: imported.deckId));

      expect(second.cards, isEmpty);
      expect(second.duplicatesRemoved, 1);
      final secondJob = (await container
          .read(generationJobRepositoryProvider)
          .jobById(second.jobId))!;
      expect(secondJob.status, GenerationJobStatus.done);
      expect(secondJob.cardsCount, 0);
      expect(httpAdapter.requests, hasLength(2));
    },
  );

  test('production-граф собирает реальные реализации генерации', () {
    expect(
      container.read(generationJobRepositoryProvider),
      isA<DriftGenerationJobRepository>(),
    );
    expect(
      container.read(generationCardStoreProvider),
      isA<DriftGenerationCardStore>(),
    );
    expect(container.read(documentGatewayProvider), isNotNull);
  });
}
