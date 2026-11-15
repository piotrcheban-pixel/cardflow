import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/generation/drift_generation_card_store.dart';
import 'package:cardflow/data/generation/drift_generation_job_repository.dart';
import 'package:cardflow/data/transfer/media_store.dart';
import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/cards/card_scheduling.dart';
import 'package:cardflow/domain/generation/generation_attachment.dart';
import 'package:cardflow/domain/generation/generated_card.dart';
import 'package:cardflow/domain/generation/generated_card_image.dart';
import 'package:cardflow/domain/generation/generation_card_store.dart';
import 'package:cardflow/domain/generation/generation_error.dart';
import 'package:cardflow/domain/generation/generation_job.dart';
import 'package:cardflow/domain/generation/generation_run.dart';
import 'package:cardflow/domain/review/review_queue.dart';
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
  late Directory mediaDirectory;

  Map<String, Object?> cardJson() => <String, Object?>{
    'front': 'Что такое FSRS?',
    'back': 'Алгоритм интервального повторения.',
    'hint': null,
    'tags': <Object?>['fsrs'],
    'card_type': 'basic',
    'source_excerpt': null,
    'source_file': 'лекция.txt',
    'image_query': null,
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
    mediaDirectory = Directory.systemTemp.createTempSync('cardflow_gen_flow_');
    httpAdapter = FakeHttpAdapter((options) => jsonResponse(openAiPayload()));
    container = ProviderContainer(
      overrides: <Override>[
        appDatabaseProvider.overrideWithValue(database),
        mediaStoreProvider.overrideWithValue(MediaStore(mediaDirectory)),
        generationDioProvider.overrideWithValue(dioWithAdapter(httpAdapter)),
        apiKeyStoreProvider.overrideWithValue(
          FakeApiKeyStore(<String, String>{'openai': 'test-key-openai'}),
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
    if (mediaDirectory.existsSync()) {
      mediaDirectory.deleteSync(recursive: true);
    }
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

  GenerationRunRequest request({
    String? targetDeckId,
    List<GenerationAttachment> images = const <GenerationAttachment>[],
    bool includeDocument = true,
    String presetId = 'openai',
    String modelId = 'gpt-4o-mini',
  }) {
    return GenerationRunRequest(
      documents: includeDocument
          ? <ParsedDocument>[document()]
          : const <ParsedDocument>[],
      images: images,
      account: testProviderAccount(presetId: presetId, modelId: modelId),
      deckName: 'Сгенерированная колода',
      targetDeckId: targetDeckId,
    );
  }

  test(
    'production-граф: occlusion + image_query → поиск, media и маска (7.9)',
    () async {
      final FakeCardImageFinder finder = FakeCardImageFinder(
        byQuery: <String, GeneratedCardImage?>{
          'plant cell diagram': makeCardImage(query: 'plant cell diagram'),
        },
      );
      final FakeHttpAdapter adapter = FakeHttpAdapter(
        (options) => jsonResponse(<String, Object?>{
          'choices': <Object?>[
            <String, Object?>{
              'message': <String, Object?>{
                'role': 'assistant',
                'content': jsonEncode(<String, Object?>{
                  'cards': <Object?>[
                    <String, Object?>{
                      'front': 'Что изображено на схеме?',
                      'back': 'Клетка растения.',
                      'hint': null,
                      'tags': <Object?>['биология'],
                      'card_type': 'occlusion',
                      'source_excerpt': null,
                      'source_file': 'лекция.txt',
                      'image_query': 'plant cell diagram',
                    },
                  ],
                }),
              },
              'finish_reason': 'stop',
            },
          ],
          'usage': <String, Object?>{'total_tokens': 30},
        }),
      );
      final ProviderContainer local = ProviderContainer(
        overrides: <Override>[
          appDatabaseProvider.overrideWithValue(database),
          mediaStoreProvider.overrideWithValue(MediaStore(mediaDirectory)),
          generationDioProvider.overrideWithValue(dioWithAdapter(adapter)),
          apiKeyStoreProvider.overrideWithValue(
            FakeApiKeyStore(<String, String>{'openai': 'test-key-openai'}),
          ),
          generationSettingsStoreProvider.overrideWithValue(
            FakeGenerationSettingsStore(),
          ),
          cardImageFinderProvider.overrideWithValue(finder),
        ],
      );
      addTearDown(local.dispose);

      final GenerationRunResult result = await local
          .read(generationRunnerProvider)
          .run(
            GenerationRunRequest(
              documents: <ParsedDocument>[document()],
              account: testProviderAccount(
                presetId: 'openai',
                modelId: 'gpt-4o',
              ),
              deckName: 'Биология',
            ),
          );

      expect(finder.queries, <String>['plant cell diagram']);
      final GeneratedCard card = result.cards.single;
      expect(card.isOcclusion, isTrue);
      expect(card.image, isNotNull);
      expect(card.occlusionJson, isNotNull);

      final GenerationImportResult imported = await local
          .read(generationCardStoreProvider)
          .importGeneratedCards(
            deckId: null,
            deckName: 'Биология',
            cards: result.cards,
            jobId: result.jobId,
            now: DateTime.now(),
          );
      expect(imported.importedCards, 1);

      final CardRow row = (await database.select(database.cards).get()).single;
      expect(row.cardType, 'basic');
      expect(row.occlusionJson, card.occlusionJson);
      expect(jsonDecode(row.mediaJson), hasLength(1));

      final MediaRow mediaRow =
          (await database.select(database.media).get()).single;
      expect(
        File('${mediaDirectory.path}${Platform.pathSeparator}${mediaRow.path}')
            .existsSync(),
        isTrue,
      );
    },
  );

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
      expect(job.promptVersion, 'gen-ru-v4');

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

  test(
    'аккаунт DeepSeek: сохранённый ключ → запрос на https://api.deepseek.com',
    () async {
      // Ключ пишется в secure-storage-фейк так же, как это делает экран
      // провайдеров (ADR-020): id аккаунта === ключ хранилища.
      await container
          .read(apiKeyStoreProvider)
          .write('deepseek', 'sk-ds-test-key');

      final result = await container
          .read(generationRunnerProvider)
          .run(
            GenerationRunRequest(
              documents: <ParsedDocument>[document()],
              account: testProviderAccount(
                presetId: 'deepseek',
                modelId: 'deepseek-chat',
              ),
              deckName: 'DeepSeek колода',
            ),
          );

      expect(result.status, GenerationJobStatus.done);
      expect(result.cards, hasLength(1));
      expect(httpAdapter.requests, hasLength(1));
      final sent = httpAdapter.requests.single;
      expect(
        sent.uri.toString(),
        'https://api.deepseek.com/chat/completions',
        reason: 'запрос должен уйти на адрес аккаунта DeepSeek',
      );
      expect(sent.headers['Authorization'], 'Bearer sk-ds-test-key');
      final body = jsonDecode(sent.data! as String) as Map<String, Object?>;
      expect(body['model'], 'deepseek-chat');

      final GenerationJob job = (await container
          .read(generationJobRepositoryProvider)
          .jobById(result.jobId))!;
      expect(job.status, GenerationJobStatus.done);
      expect(job.provider, 'deepseek', reason: 'id аккаунта в generation_jobs');
      expect(job.model, 'deepseek-chat');
      expect(job.tokensUsed, 30);
    },
  );

  test('изображение + Vision: production-граф шлёт image_url, job.files хранит файл', () async {
    final GenerationAttachment image = GenerationAttachment(
      fileName: 'схема.png',
      mediaType: AttachmentMediaType.png,
      bytes: Uint8List.fromList(<int>[
        0x89,
        0x50,
        0x4E,
        0x47,
        0x0D,
        0x0A,
        0x1A,
        0x0A,
        1,
        2,
      ]),
    );

    final result = await container
        .read(generationRunnerProvider)
        .run(
          request(
            includeDocument: false,
            images: <GenerationAttachment>[image],
            modelId: 'gpt-4o',
          ),
        );

    expect(result.status, GenerationJobStatus.done);
    expect(result.cards, hasLength(1));
    expect(httpAdapter.requests, hasLength(1));
    final body = jsonDecode(
      httpAdapter.requests.single.data! as String,
    ) as Map<String, Object?>;
    final messages = body['messages']! as List<Object?>;
    final user = messages[1]! as Map<String, Object?>;
    final content = user['content']! as List<Object?>;
    final imagePart = content[1]! as Map<String, Object?>;
    expect(imagePart['type'], 'image_url');
    expect(
      (imagePart['image_url']! as Map<String, Object?>)['url'],
      startsWith('data:image/png;base64,'),
    );

    final job = (await container
        .read(generationJobRepositoryProvider)
        .jobById(result.jobId))!;
    expect(job.files, <String>['схема.png']);
  });

  test('изображение + модель без Vision: ошибка без HTTP-запроса', () async {
    await container
        .read(apiKeyStoreProvider)
        .write('deepseek', 'sk-ds-test-key');
    final GenerationAttachment image = GenerationAttachment(
      fileName: 'схема.png',
      mediaType: AttachmentMediaType.png,
      bytes: Uint8List.fromList(<int>[
        0x89,
        0x50,
        0x4E,
        0x47,
        0x0D,
        0x0A,
        0x1A,
        0x0A,
      ]),
    );

    final result = await container
        .read(generationRunnerProvider)
        .run(
          request(
            includeDocument: false,
            images: <GenerationAttachment>[image],
            presetId: 'deepseek',
            modelId: 'deepseek-chat',
          ),
        );

    expect(result.cards, isEmpty);
    expect(result.failures, hasLength(1));
    expect(result.failures.single.code, GenerationErrorCode.visionUnsupported);
    expect(httpAdapter.requests, isEmpty);
  });

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

  // Итерация 7.10, ADR-024: генерация по теме без единого файла.
  test(
    'production-граф: prompt-only — пустой <materials> и тема в <wishes>',
    () async {
      final FakeHttpAdapter adapter = FakeHttpAdapter(
        (options) => jsonResponse(openAiPayload()),
      );
      final ProviderContainer local = ProviderContainer(
        overrides: <Override>[
          appDatabaseProvider.overrideWithValue(database),
          mediaStoreProvider.overrideWithValue(MediaStore(mediaDirectory)),
          generationDioProvider.overrideWithValue(dioWithAdapter(adapter)),
          apiKeyStoreProvider.overrideWithValue(
            FakeApiKeyStore(<String, String>{'openai': 'test-key-openai'}),
          ),
          generationSettingsStoreProvider.overrideWithValue(
            FakeGenerationSettingsStore(),
          ),
        ],
      );
      addTearDown(local.dispose);

      final GenerationRunResult result = await local
          .read(generationRunnerProvider)
          .run(
            GenerationRunRequest(
              documents: const <ParsedDocument>[],
              account: testProviderAccount(
                presetId: 'openai',
                modelId: 'gpt-4o-mini',
              ),
              deckName: 'Фотосинтез',
              wishes: 'Фотосинтез: световая и темновая фазы',
            ),
          );

      expect(result.status, GenerationJobStatus.done);
      expect(result.cards, hasLength(1));
      expect(adapter.requests, hasLength(1));
      final body = jsonDecode(
        adapter.requests.single.data! as String,
      ) as Map<String, Object?>;
      final messages = body['messages']! as List<Object?>;
      final userContent =
          (messages[1]! as Map<String, Object?>)['content']! as String;
      expect(userContent, contains('<materials>\n</materials>'));
      expect(
        userContent,
        contains('<wishes>\nФотосинтез: световая и темновая фазы\n</wishes>'),
      );

      final GenerationJob job = (await local
          .read(generationJobRepositoryProvider)
          .jobById(result.jobId))!;
      expect(job.status, GenerationJobStatus.done);
      expect(job.files, isEmpty);
      expect(job.promptVersion, 'gen-ru-v4');
      expect(job.cardsCount, 1);
    },
  );

  // Итерация 7.10, ADR-024: поиск картинок — реальный ImageSearchService на
  // production-проводке (fake-Dio вместо сети): image_query → скачивание →
  // карточка с байтами → MediaStore/media при импорте.
  test(
    'production-граф: image_query → ImageSearchService → картинка и media',
    () async {
      final Uint8List jpeg = Uint8List.fromList(<int>[
        0xFF,
        0xD8,
        0xFF,
        0xE0,
        0x00,
        0x10,
        0x4A,
        0x46,
        0x49,
        0x46,
      ]);
      final FakeHttpAdapter adapter = FakeHttpAdapter((options) {
        final String path = options.uri.path;
        if (path.endsWith('/chat/completions')) {
          return jsonResponse(<String, Object?>{
            'choices': <Object?>[
              <String, Object?>{
                'message': <String, Object?>{
                  'role': 'assistant',
                  'content': jsonEncode(<String, Object?>{
                    'cards': <Object?>[
                      <String, Object?>{
                        'front': 'Какая органелла изображена?',
                        'back': 'Хлоропласт.',
                        'hint': null,
                        'tags': <Object?>['биология'],
                        'card_type': 'basic',
                        'source_excerpt': null,
                        'source_file': 'лекция.txt',
                        'image_query': 'chloroplast diagram',
                      },
                    ],
                  }),
                },
                'finish_reason': 'stop',
              },
            ],
            'usage': <String, Object?>{'total_tokens': 30},
          });
        }
        if (path.endsWith('/v1/images/')) {
          return jsonResponse(<String, Object?>{
            'results': <Object?>[
              <String, Object?>{
                'url': 'https://example.test/original.jpg',
                'thumbnail': 'https://api.openverse.org/v1/images/abc/thumb/',
                'license': 'cc0',
                'attribution': '"Chloroplast" is licensed under CC0.',
              },
            ],
          });
        }
        if (path.endsWith('/thumb/')) return bytesResponse(jpeg);
        return bytesResponse(<int>[1, 2, 3], contentType: 'text/plain');
      });
      final ProviderContainer local = ProviderContainer(
        overrides: <Override>[
          appDatabaseProvider.overrideWithValue(database),
          mediaStoreProvider.overrideWithValue(MediaStore(mediaDirectory)),
          generationDioProvider.overrideWithValue(dioWithAdapter(adapter)),
          apiKeyStoreProvider.overrideWithValue(
            FakeApiKeyStore(<String, String>{'openai': 'test-key-openai'}),
          ),
          generationSettingsStoreProvider.overrideWithValue(
            FakeGenerationSettingsStore(),
          ),
        ],
      );
      addTearDown(local.dispose);

      final GenerationRunResult result = await local
          .read(generationRunnerProvider)
          .run(
            GenerationRunRequest(
              documents: <ParsedDocument>[document()],
              account: testProviderAccount(
                presetId: 'openai',
                modelId: 'gpt-4o-mini',
              ),
              deckName: 'Биология',
            ),
          );

      expect(result.cards, hasLength(1));
      final GeneratedCard card = result.cards.single;
      expect(card.imageQuery, 'chloroplast diagram');
      expect(card.image, isNotNull);
      expect(card.image!.bytes, jpeg);
      expect(
        adapter.requests.any(
          (RequestOptions options) =>
              options.method == 'GET' &&
              options.uri.path.endsWith('/v1/images/') &&
              options.uri.queryParameters['q'] == 'chloroplast diagram',
        ),
        isTrue,
        reason: 'ImageSearchService должен быть вызван по image_query',
      );

      await local
          .read(generationCardStoreProvider)
          .importGeneratedCards(
            deckId: null,
            deckName: 'Биология',
            cards: result.cards,
            jobId: result.jobId,
            now: DateTime.now(),
          );
      final CardRow row = (await database.select(database.cards).get()).single;
      expect(jsonDecode(row.mediaJson), hasLength(1));
      final MediaRow mediaRow =
          (await database.select(database.media).get()).single;
      expect(
        File('${mediaDirectory.path}${Platform.pathSeparator}${mediaRow.path}')
            .readAsBytesSync(),
        jpeg,
      );
    },
  );

  // Итерация 7.11 (owner-note): сгенерированная карточка с медиа обязана
  // попасть в очередь повторения сразу после импорта — без оценки.
  test(
    'production-граф: карточка с медиа после импорта входит в ReviewQueue',
    () async {
      final FakeCardImageFinder finder = FakeCardImageFinder(
        byQuery: <String, GeneratedCardImage?>{
          'chloroplast diagram': makeCardImage(query: 'chloroplast diagram'),
        },
      );
      final FakeHttpAdapter adapter = FakeHttpAdapter(
        (options) => jsonResponse(<String, Object?>{
          'choices': <Object?>[
            <String, Object?>{
              'message': <String, Object?>{
                'role': 'assistant',
                'content': jsonEncode(<String, Object?>{
                  'cards': <Object?>[
                    <String, Object?>{
                      'front': 'Какая органелла изображена?',
                      'back': 'Хлоропласт.',
                      'hint': null,
                      'tags': <Object?>['биология'],
                      'card_type': 'basic',
                      'source_excerpt': null,
                      'source_file': 'лекция.txt',
                      'image_query': 'chloroplast diagram',
                    },
                  ],
                }),
              },
              'finish_reason': 'stop',
            },
          ],
          'usage': <String, Object?>{'total_tokens': 30},
        }),
      );
      final ProviderContainer local = ProviderContainer(
        overrides: <Override>[
          appDatabaseProvider.overrideWithValue(database),
          mediaStoreProvider.overrideWithValue(MediaStore(mediaDirectory)),
          generationDioProvider.overrideWithValue(dioWithAdapter(adapter)),
          apiKeyStoreProvider.overrideWithValue(
            FakeApiKeyStore(<String, String>{'openai': 'test-key-openai'}),
          ),
          generationSettingsStoreProvider.overrideWithValue(
            FakeGenerationSettingsStore(),
          ),
          cardImageFinderProvider.overrideWithValue(finder),
        ],
      );
      addTearDown(local.dispose);

      final GenerationRunResult result = await local
          .read(generationRunnerProvider)
          .run(request());
      expect(result.cards.single.image, isNotNull);

      final DateTime now = DateTime.utc(2026, 11, 15, 19, 30);
      final GenerationImportResult imported = await local
          .read(generationCardStoreProvider)
          .importGeneratedCards(
            deckId: null,
            deckName: 'Биология',
            cards: result.cards,
            jobId: result.jobId,
            now: now,
          );

      final List<Card> cards = await local
          .read(cardRepositoryProvider)
          .cardsByDeck(imported.deckId);
      expect(cards, hasLength(1));
      final Card card = cards.single;
      expect(card.state, CardState.newCard);
      expect(card.mediaIds, hasLength(1));
      expect(
        card.due,
        isNotNull,
        reason: 'due новой карточки — момент импорта',
      );
      expect(card.due!.isAfter(now), isFalse, reason: 'due <= now');
      expect(card.fsrsJson, isNotNull, reason: 'fsrs_json инициализирован');
      final scheduling = CardSchedulingMapper.toSchedulingCard(card, now: now);
      expect(scheduling.cardId, card.id);
      expect(scheduling.state, CardState.newCard);

      final List<Card> queue = ReviewQueue.build(cards, now: now);
      expect(queue.map((Card value) => value.id), <String>[
        card.id,
      ], reason: 'новая карточка должна быть в очереди классической сессии');
    },
  );
}
