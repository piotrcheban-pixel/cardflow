import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/transfer/media_store.dart';
import 'package:cardflow/domain/generation/generation_card_store.dart';
import 'package:cardflow/domain/generation/generation_run.dart';
import 'package:cardflow/domain/text/document_format.dart';
import 'package:cardflow/domain/text/parsed_document.dart';
import 'package:cardflow/ui/state/app_providers.dart';

import '../helpers/fake_http_adapter.dart';
import '../helpers/generation_fakes.dart';
import '../helpers/settings_fakes.dart';

/// Красная фаза 7.19 (группа A, дефект D1/D2): если поиск не дал результата,
/// карточка остаётся **без** изображения; декоративная заглушка не создаётся и
/// не сохраняется как медиа.
///
/// Тест на production-проводке: `app_providers` → пайплайн → импорт в drift-БД.
/// Ответ модели — совместимый формат v5/v8 (`image_query`): локальная схема
/// обязана принимать его и после перехода на `gen-ru-v9`.
void main() {
  late AppDatabase database;
  late ProviderContainer container;
  late FakeHttpAdapter httpAdapter;
  late Directory mediaDirectory;
  late FakeCardImageFinder finder;

  Map<String, Object?> payload() => <String, Object?>{
    'choices': <Object?>[
      <String, Object?>{
        'message': <String, Object?>{
          'role': 'assistant',
          'content': jsonEncode(<String, Object?>{
            'cards': <Object?>[
              <String, Object?>{
                'front': 'В чём сущность метода конечных разностей?',
                'back': 'В замене непрерывного процесса дискретной сеткой.',
                'hint': null,
                'tags': <Object?>['теплопроводность'],
                'card_type': 'basic',
                'source_excerpt': null,
                'source_file': null,
                'image_id': null,
                'image_query': 'finite difference method grid diagram',
              },
            ],
            'source_exhausted': true,
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
    mediaDirectory = Directory.systemTemp.createTempSync('cardflow_red_7_19_');
    httpAdapter = FakeHttpAdapter(
      (RequestOptions options) => jsonResponse(payload()),
    );
    finder = FakeCardImageFinder();
    container = ProviderContainer(
      overrides: <Override>[
        appDatabaseProvider.overrideWithValue(database),
        effectiveAppSettingsProvider.overrideWithValue(
          legacyGenerationSettings(),
        ),
        mediaStoreProvider.overrideWithValue(MediaStore(mediaDirectory)),
        generationDioProvider.overrideWithValue(dioWithAdapter(httpAdapter)),
        apiKeyStoreProvider.overrideWithValue(
          FakeApiKeyStore(<String, String>{'openai': 'test-key-openai'}),
        ),
        generationSettingsStoreProvider.overrideWithValue(
          FakeGenerationSettingsStore(),
        ),
        cardImageFinderProvider.overrideWithValue(finder),
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

  test(
    'поиск не дал результата: карточка без изображения, заглушек нет',
    () async {
      const String text =
          'Метод конечных разностей заменяет непрерывный процесс сеткой.';
      final GenerationRunResult result = await container
          .read(generationRunnerProvider)
          .run(
            GenerationRunRequest(
              documents: <ParsedDocument>[
                ParsedDocument(
                  format: DocumentFormat.txt,
                  fileName: 'лекция.txt',
                  text: text,
                  sections: <ParsedSection>[
                    ParsedSection(start: 0, end: text.length),
                  ],
                ),
              ],
              account: testProviderAccount(
                presetId: 'openai',
                modelId: 'gpt-4o-mini',
              ),
              deckName: 'Теплопроводность',
              requestedCards: 1,
            ),
          );

      expect(result.cards, hasLength(1));
      expect(finder.queries, <String>[
        'finite difference method grid diagram',
      ], reason: 'внешний поиск выполняется по запросу модели');

      final GenerationImportResult imported = await container
          .read(generationCardStoreProvider)
          .importGeneratedCards(
            deckId: null,
            deckName: 'Теплопроводность',
            cards: result.cards,
            jobId: result.jobId,
            now: DateTime.utc(2026, 11, 21, 12),
          );
      expect(imported.importedCards, 1);

      final List<MediaRow> media = await database.select(database.media).get();
      expect(
        media,
        isEmpty,
        reason: 'ненайденная картинка не должна подменяться нарисованным PNG',
      );
      expect(
        mediaDirectory
            .listSync(recursive: true)
            .whereType<File>()
            .where((File file) => !file.path.endsWith('.meta.json')),
        isEmpty,
        reason: 'в MediaStore не должно появиться файлов-заглушек',
      );
    },
  );
}
