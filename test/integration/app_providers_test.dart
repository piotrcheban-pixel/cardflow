import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/data/cards/drift_card_media_repository.dart';
import 'package:cardflow/data/cards/drift_card_repository.dart';
import 'package:cardflow/data/cards/file_picker_image_gateway.dart';
import 'package:cardflow/data/cards/media_garbage_collector.dart';
import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/decks/drift_deck_repository.dart';
import 'package:cardflow/data/generation/drift_generation_card_store.dart';
import 'package:cardflow/data/generation/drift_generation_job_repository.dart';
import 'package:cardflow/data/generation/drift_generation_settings_store.dart';
import 'package:cardflow/data/review/drift_review_repository.dart';
import 'package:cardflow/data/transfer/drift_deck_transfer_service.dart';
import 'package:cardflow/data/transfer/file_picker_gateway.dart';
import 'package:cardflow/data/transfer/media_store.dart';
import 'package:cardflow/data/transfer/zip_deck_archive_codec.dart';
import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/decks/deck_query.dart';
import 'package:cardflow/domain/generation/openai_compatible_settings.dart';
import 'package:cardflow/domain/scheduling/scheduler.dart';
import 'package:cardflow/domain/transfer/deck_archive.dart';
import 'package:cardflow/ui/state/app_providers.dart';

/// Интеграционный тест: граф провайдеров `app_providers.dart` на реальной
/// in-memory БД drift и реальном MediaStore (без фейков и без плагинов).
///
/// Доказывает, что продовая сборка зависимостей в `main.dart` корректна:
/// `appDatabaseProvider`/`mediaStoreProvider` переопределяются, остальные
/// провайдеры создают рабочие реализации.
void main() {
  late AppDatabase database;
  late Directory mediaDirectory;
  late ProviderContainer container;

  setUp(() {
    database = AppDatabase.inMemory();
    mediaDirectory = Directory.systemTemp.createTempSync('cardflow_media_');
    container = ProviderContainer(
      overrides: <Override>[
        appDatabaseProvider.overrideWithValue(database),
        mediaStoreProvider.overrideWithValue(MediaStore(mediaDirectory)),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    await database.close();
    if (mediaDirectory.existsSync()) {
      mediaDirectory.deleteSync(recursive: true);
    }
  });

  test('граф провайдеров собирается на реальных реализациях', () {
    expect(container.read(deckRepositoryProvider), isA<DriftDeckRepository>());
    expect(container.read(cardRepositoryProvider), isA<DriftCardRepository>());
    expect(
      (container.read(
        cardRepositoryProvider,
      ) as DriftCardRepository).mediaStore,
      same(container.read(mediaStoreProvider)),
    );
    expect(
      container.read(cardMediaRepositoryProvider),
      isA<DriftCardMediaRepository>(),
    );
    expect(container.read(imageGatewayProvider), isA<FilePickerImageGateway>());
    expect(
      container.read(mediaGarbageCollectorProvider),
      isA<MediaGarbageCollector>(),
    );
    expect(
      container.read(reviewRepositoryProvider),
      isA<DriftReviewRepository>(),
    );
    expect(container.read(schedulerProvider), isA<FsrsScheduler>());
    expect(
      container.read(deckArchiveCodecProvider),
      isA<ZipDeckArchiveCodec>(),
    );
    expect(
      container.read(deckTransferServiceProvider),
      isA<DriftDeckTransferService>(),
    );
    expect(container.read(fileGatewayProvider), isA<FilePickerGateway>());
    expect(container.read(mediaStoreProvider), isA<MediaStore>());
    expect(
      container.read(generationSettingsStoreProvider),
      isA<DriftGenerationSettingsStore>(),
    );
    expect(
      container.read(generationJobRepositoryProvider),
      isA<DriftGenerationJobRepository>(),
    );
    expect(
      container.read(generationCardStoreProvider),
      isA<DriftGenerationCardStore>(),
    );
    expect(container.read(documentGatewayProvider), isNotNull);
    expect(container.read(generationRunnerProvider), isNotNull);
    expect(container.read(fileParsingServiceProvider), isNotNull);
  });

  test(
    'настройки OpenAI-совместимого сервера идут через реальную БД',
    () async {
      final store = container.read(generationSettingsStoreProvider);
      await store.writeOpenAiCompatible(
        const OpenAiCompatibleSettings(
          baseUrl: 'http://localhost:1234/v1',
          model: 'lm-studio-model',
        ),
      );

      final fromGraph = await container
          .read(generationSettingsStoreProvider)
          .readOpenAiCompatible();
      expect(fromGraph.baseUrl, 'http://localhost:1234/v1');
      expect(fromGraph.model, 'lm-studio-model');
      expect(await database.select(database.appSettings).get(), hasLength(1));
    },
  );

  test(
    'колода, созданная через репозиторий из провайдера, видна в потоке',
    () async {
      final repository = container.read(deckRepositoryProvider);
      final deck = await repository.createDeck(name: '  Испанский  ');

      expect(deck.name, 'Испанский');
      final summaries = await repository
          .watchSummaries(query: const DeckQuery())
          .first;
      expect(summaries.map((summary) => summary.deck.id), <String>[deck.id]);
      expect(summaries.single.totalCards, 0);

      await repository.archiveDeck(deck.id);
      final visible = await repository
          .watchSummaries(query: const DeckQuery())
          .first;
      expect(visible, isEmpty);
      final withArchived = await repository
          .watchSummaries(query: const DeckQuery(includeArchived: true))
          .first;
      expect(withArchived.single.deck.isArchived, isTrue);
    },
  );

  test(
    'production-проводка: удаление колоды чистит media-строки и файлы (M5)',
    () async {
      final codec = container.read(deckArchiveCodecProvider);
      final service = container.read(deckTransferServiceProvider);
      final bytes = Uint8List.fromList(<int>[1, 2, 3]);

      final card = Card(
        id: 'card-1',
        deckId: 'deck-1',
        front: 'Вопрос',
        back: 'Ответ',
        cardType: CardType.basic,
        tags: const <String>[],
        mediaIds: const <String>['media-1'],
        state: CardState.newCard,
        createdAt: DateTime.utc(2026, 11, 12, 10),
        updatedAt: DateTime.utc(2026, 11, 12, 10),
      );
      final archive = DeckArchive(
        formatVersion: deckArchiveFormatVersion,
        exportedAt: DateTime.utc(2026, 11, 12, 12),
        deck: ArchiveDeck(
          id: 'deck-1',
          name: 'С медиа',
          settings: const <String, Object?>{},
          createdAt: DateTime.utc(2026, 11, 12, 10),
          updatedAt: DateTime.utc(2026, 11, 12, 10),
        ),
        cards: <Card>[card],
        media: <ArchiveMedia>[
          ArchiveMedia(
            id: 'media-1',
            cardId: 'card-1',
            path: 'media/media-1.png',
            mimeType: 'image/png',
            bytes: bytes,
          ),
        ],
      );

      final ImportResult imported = await service.importZip(
        codec.encode(archive),
      );
      final mediaRows = await database.select(database.media).get();
      expect(mediaRows, hasLength(1));

      final store = container.read(mediaStoreProvider);
      expect(await store.readMedia(mediaRows.single.path), bytes);

      // Проводка провайдера: репозиторий получает MediaStore из графа.
      final repository = container.read(deckRepositoryProvider);
      expect(repository, isA<DriftDeckRepository>());
      expect((repository as DriftDeckRepository).mediaStore, same(store));

      await repository.deleteDeck(imported.deckId);
      expect(await database.select(database.media).get(), isEmpty);
      expect(await database.select(database.cards).get(), isEmpty);
      expect(await store.readMedia(mediaRows.single.path), isNull);
    },
  );
}
