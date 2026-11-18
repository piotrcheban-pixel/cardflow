import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';

import 'package:cardflow/api/parsers/pdf_parser.dart';
import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/transfer/media_store.dart';
import 'package:cardflow/domain/generation/document_image.dart';
import 'package:cardflow/domain/generation/generation_card_store.dart';
import 'package:cardflow/domain/generation/generation_job.dart';
import 'package:cardflow/domain/generation/generation_run.dart';
import 'package:cardflow/domain/text/parsed_document.dart';
import 'package:cardflow/ui/state/app_providers.dart';

import '../helpers/fake_http_adapter.dart';
import '../helpers/generation_fakes.dart';
import '../unit/api/parsers/fixtures/document_fixtures.dart';

/// Сквозной путь «PDF → изображение → модель → карточка → MediaStore»
/// (итерация L76, ADR-037) на production-проводке:
/// реальный `PdfParser` (PDFium) → `GenerationPipeline` → `CardGenerationService`
/// → fake HTTP (модель «видит» изображение) → `image_id` → импорт в drift-БД →
/// файл в `MediaStore`.
void main() {
  late AppDatabase database;
  late Directory mediaDirectory;
  late ProviderContainer container;
  late FakeHttpAdapter httpAdapter;
  late List<Object?> sentBodies;

  setUpAll(() async {
    await pdfrxInitialize();
  });

  setUp(() {
    database = AppDatabase.inMemory();
    mediaDirectory = Directory.systemTemp.createTempSync('cardflow_pdf_img_');
    sentBodies = <Object?>[];
    httpAdapter = FakeHttpAdapter((options) {
      sentBodies.add(options.data);
      return jsonResponse(<String, Object?>{
        'choices': <Object?>[
          <String, Object?>{
            'message': <String, Object?>{
              'role': 'assistant',
              'content': jsonEncode(<String, Object?>{
                'cards': <Object?>[
                  <String, Object?>{
                    'front': 'Какая схема изображена на рисунке из PDF?',
                    'back': 'Схема рамы с диагоналями.',
                    'hint': null,
                    'tags': <Object?>['фермы'],
                    'card_type': 'basic',
                    'source_excerpt': null,
                    'source_file': 'лекция.pdf',
                    'image_id': 'img1',
                    'image': <String, Object?>{
                      'query': 'truss frame diagram',
                      'fallback_query': 'truss',
                      'kind': 'diagram',
                    },
                  },
                ],
              }),
            },
            'finish_reason': 'stop',
          },
        ],
        'usage': <String, Object?>{'total_tokens': 30},
      });
    });
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

  test('PDF-схема доходит до модели как изображение, карточка пишет её в MediaStore', () async {
    final ParsedDocument document = await const PdfParser().parse(
      buildPdfWithEmbeddedImage(
        imageBytes: diagramJpeg(),
        text:
            'Structural analysis lecture page with a truss scheme '
            'described in enough detail for the parser.',
      ),
      fileName: 'лекция.pdf',
    );
    expect(document.images, hasLength(1));
    final DocumentImage image = document.images.single;
    expect(image.page, 1);

    final GenerationRunResult result = await container
        .read(generationRunnerProvider)
        .run(
          GenerationRunRequest(
            documents: <ParsedDocument>[document],
            account: testProviderAccount(presetId: 'openai', modelId: 'gpt-4o'),
            deckName: 'Фермы',
          ),
        );

    expect(result.cards, hasLength(1));
    expect(result.cards.single.imageId, 'img1');
    expect(result.cards.single.image, isNotNull);
    expect(result.cards.single.image!.bytes, image.bytes);

    // Модель увидела изображение: в теле запроса есть image-part с base64
    // PNG и подпись каталога с id и страницей.
    expect(sentBodies, hasLength(1));
    final Object? rawBody = sentBodies.single;
    final Map<String, Object?> body = rawBody is String
        ? jsonDecode(rawBody) as Map<String, Object?>
        : jsonDecode(jsonEncode(rawBody)) as Map<String, Object?>;
    final List<Object?> messages = body['messages']! as List<Object?>;
    final Map<String, Object?> user = messages.last as Map<String, Object?>;
    final List<Object?> content = user['content']! as List<Object?>;
    final Iterable<Map<String, Object?>> parts = content
        .whereType<Map<String, Object?>>();
    expect(
      parts.any((Map<String, Object?> part) => part['type'] == 'image_url'),
      isTrue,
      reason: 'image-part не попал в запрос к модели',
    );
    expect(
      parts.any(
        (Map<String, Object?> part) =>
            (part['text'] as String?)?.contains('img1 |') ?? false,
      ),
      isTrue,
      reason: 'Подпись каталога не приложена к части изображения',
    );
    expect(
      parts.any(
        (Map<String, Object?> part) =>
            (part['text'] as String?)?.contains('стр. 1') ?? false,
      ),
      isTrue,
    );

    final GenerationImportResult imported = await container
        .read(generationCardStoreProvider)
        .importGeneratedCards(
          deckId: null,
          deckName: 'Фермы',
          cards: result.cards,
          jobId: result.jobId,
          now: DateTime.now(),
        );
    expect(imported.importedCards, 1);

    final CardRow row = (await database.select(database.cards).get()).single;
    final List<Object?> mediaIds = jsonDecode(row.mediaJson) as List<Object?>;
    expect(mediaIds, hasLength(1));

    final MediaRow media = (await database.select(database.media).get()).single;
    final File file = File(
      '${mediaDirectory.path}${Platform.pathSeparator}${media.path}',
    );
    expect(file.existsSync(), isTrue, reason: 'Файл не сохранён в MediaStore');
    expect(await file.readAsBytes(), image.bytes);

    final GenerationJob job = (await container
        .read(generationJobRepositoryProvider)
        .jobById(result.jobId))!;
    expect(job.status, GenerationJobStatus.done);
    expect(job.promptVersion, 'gen-ru-v7');
  });
}
