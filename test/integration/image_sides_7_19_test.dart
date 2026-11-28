import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;

import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/transfer/media_store.dart';
import 'package:cardflow/domain/generation/document_image.dart';
import 'package:cardflow/domain/generation/generated_card.dart';
import 'package:cardflow/domain/generation/generation_attachment.dart';
import 'package:cardflow/domain/generation/generation_card_store.dart';
import 'package:cardflow/domain/generation/generation_run.dart';
import 'package:cardflow/domain/text/document_format.dart';
import 'package:cardflow/domain/text/parsed_document.dart';
import 'package:cardflow/ui/state/app_providers.dart';

import '../helpers/fake_http_adapter.dart';
import '../helpers/generation_fakes.dart';
import '../helpers/settings_fakes.dart';

/// Итерация 7.19: изображения по сторонам и запрет синтезированных заглушек
/// на **production-проводке** (`app_providers` → `GenerationPipeline` →
/// `CardGenerationService` → fake HTTP → drift-БД → `MediaStore`).
///
/// Группа A (потеря/подстановка изображений) и приёмка §8 сценариев A и B.
void main() {
  late AppDatabase database;
  late ProviderContainer container;
  late FakeHttpAdapter httpAdapter;
  late Directory mediaDirectory;
  late FakeCardImageFinder finder;

  /// Ответ модели текущего теста: подмена до `run`, без пересоздания Dio.
  late Map<String, Object?> responseCard;

  final Uint8List documentPng = Uint8List.fromList(
    img.encodePng(img.Image(width: 200, height: 150)),
  );

  Map<String, Object?> cardJson({
    List<String> questionIds = const <String>[],
    List<String> answerIds = const <String>[],
    Map<String, Object?>? image,
    String front =
        'Какой формулой рассчитывают фактическую '
        'воздухопроницаемость окна?',
    String back =
        r'$G_{\text{ф}} = A_{\text{ок}} \cdot \Delta P^{0.67} / R_{\text{и}}$',
  }) {
    return <String, Object?>{
      'front': front,
      'back': back,
      'hint': null,
      'tags': <Object?>['воздухопроницаемость'],
      'card_type': 'basic',
      'source_excerpt': null,
      'source_file': 'лекция.pdf',
      'section_id': null,
      'question_image_ids': questionIds,
      'answer_image_ids': answerIds,
      'image': image,
    };
  }

  Map<String, Object?> providerPayload(Map<String, Object?> card) {
    return <String, Object?>{
      'choices': <Object?>[
        <String, Object?>{
          'message': <String, Object?>{
            'role': 'assistant',
            'content': jsonEncode(<String, Object?>{
              'cards': <Object?>[card],
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
  }

  setUp(() {
    database = AppDatabase.inMemory();
    mediaDirectory = Directory.systemTemp.createTempSync('cardflow_7_19_');
    responseCard = cardJson();
    httpAdapter = FakeHttpAdapter(
      (RequestOptions options) => jsonResponse(providerPayload(responseCard)),
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

  ParsedDocument document() {
    const String text =
        'Фактическая воздухопроницаемость окна рассчитывается по формуле '
        'Gф = Aок · ΔP^0.67 / Rи.';
    return ParsedDocument(
      format: DocumentFormat.txt,
      fileName: 'лекция.txt',
      text: text,
      sections: <ParsedSection>[ParsedSection(start: 0, end: text.length)],
    );
  }

  DocumentImage formulaImage() {
    return DocumentImage(
      fileName: 'лекция.pdf',
      bytes: documentPng,
      mediaType: AttachmentMediaType.png,
      caption: 'Формула фактической воздухопроницаемости окна',
      context: 'Gф = Aок · ΔP^0.67 / Rи',
      page: 4,
    );
  }

  GenerationRunRequest request({
    List<DocumentImage> documentImages = const <DocumentImage>[],
  }) {
    return GenerationRunRequest(
      documents: <ParsedDocument>[document()],
      documentImages: documentImages,
      account: testProviderAccount(presetId: 'openai', modelId: 'gpt-4o-mini'),
      deckName: 'Воздухопроницаемость',
      requestedCards: 1,
    );
  }

  Future<GenerationImportResult> runAndImport({
    List<DocumentImage> documentImages = const <DocumentImage>[],
  }) async {
    final GenerationRunResult result = await container
        .read(generationRunnerProvider)
        .run(request(documentImages: documentImages));
    expect(result.cards, hasLength(1), reason: 'ответ v9 разобран целиком');
    return container
        .read(generationCardStoreProvider)
        .importGeneratedCards(
          deckId: null,
          deckName: 'Воздухопроницаемость',
          cards: result.cards,
          jobId: result.jobId,
          now: DateTime.utc(2026, 11, 21, 12),
        );
  }

  test(
    'A1/A2: поиск не дал результата — карточка без изображения, заглушек нет',
    () async {
      responseCard = cardJson(
        image: <String, Object?>{
          'query': 'finite difference method grid diagram',
          'fallback_query': 'finite difference grid',
          'kind': 'diagram',
          'side': 'question',
        },
      );
      finder.byQuery.clear();

      final GenerationImportResult imported = await runAndImport();

      expect(imported.importedCards, 1);
      final List<MediaRow> media = await database.select(database.media).get();
      expect(
        media,
        isEmpty,
        reason: 'заглушка не должна сохраняться как медиа',
      );
      final CardRow row = (await database.select(database.cards).get()).single;
      expect(_sidesOf(row.mediaJson).all, isEmpty);
      expect(
        mediaDirectory
            .listSync(recursive: true)
            .whereType<File>()
            .where((File file) => !file.path.endsWith('.meta.json')),
        isEmpty,
        reason: 'в хранилище не должно появиться нарисованных картинок',
      );
    },
  );

  test(
    'A3/B16: изображение с формулой из документа — только сторона ответа',
    () async {
      responseCard = cardJson(answerIds: <String>['img1']);

      final GenerationImportResult imported = await runAndImport(
        documentImages: <DocumentImage>[formulaImage()],
      );

      final CardRow row = (await database.select(database.cards).get()).single;
      final sides = _sidesOf(row.mediaJson);
      expect(
        sides.question,
        isEmpty,
        reason: 'формула не должна попасть на фронт',
      );
      expect(sides.answer, hasLength(1));

      final MediaRow mediaRow =
          (await database.select(database.media).get()).single;
      expect(mediaRow.id, sides.answer.single);
      expect(mediaRow.mimeType, 'image/png');
      final File file = File(
        '${mediaDirectory.path}${Platform.pathSeparator}${mediaRow.path}',
      );
      expect(file.existsSync(), isTrue);
      expect(file.readAsBytesSync(), documentPng);
      expect(imported.importedCards, 1);
    },
  );

  test('B17: изображение-предмет вопроса — только сторона вопроса', () async {
    responseCard = cardJson(questionIds: <String>['img1']);

    await runAndImport(documentImages: <DocumentImage>[formulaImage()]);

    final CardRow row = (await database.select(database.cards).get()).single;
    final sides = _sidesOf(row.mediaJson);
    expect(sides.question, hasLength(1));
    expect(sides.answer, isEmpty);
  });

  test(
    'B19: неизвестный image id не создаёт медиа и не отбрасывает карточку',
    () async {
      responseCard = cardJson(
        questionIds: <String>['img99'],
        answerIds: <String>['img98'],
      );

      final GenerationRunResult result = await container
          .read(generationRunnerProvider)
          .run(request());
      expect(result.cards, hasLength(1));
      final GeneratedCard card = result.cards.single;
      expect(card.questionImages, isEmpty);
      expect(card.answerImages, isEmpty);
      expect(card.issues, contains(CardIssueCode.imageIdUnknown));

      await container
          .read(generationCardStoreProvider)
          .importGeneratedCards(
            deckId: null,
            deckName: 'Воздухопроницаемость',
            cards: result.cards,
            jobId: result.jobId,
            now: DateTime.utc(2026, 11, 21, 12),
          );
      expect(await database.select(database.media).get(), isEmpty);
    },
  );

  test('A12: повторный запуск не переиспользует медиа предыдущего', () async {
    responseCard = cardJson(answerIds: <String>['img1']);
    final GenerationRunResult first = await container
        .read(generationRunnerProvider)
        .run(request(documentImages: <DocumentImage>[formulaImage()]));
    final GenerationImportResult importedFirst = await container
        .read(generationCardStoreProvider)
        .importGeneratedCards(
          deckId: null,
          deckName: 'Колода 1',
          cards: first.cards,
          jobId: first.jobId,
          now: DateTime.utc(2026, 11, 21, 12),
        );

    final GenerationRunResult second = await container
        .read(generationRunnerProvider)
        .run(request(documentImages: <DocumentImage>[formulaImage()]));
    final GenerationImportResult importedSecond = await container
        .read(generationCardStoreProvider)
        .importGeneratedCards(
          deckId: importedFirst.deckId,
          deckName: 'Колода 1',
          cards: second.cards,
          jobId: second.jobId,
          now: DateTime.utc(2026, 11, 21, 13),
        );

    final List<CardRow> rows = await database.select(database.cards).get();
    expect(rows, hasLength(1), reason: 'повторная карточка — дубликат');
    expect(importedSecond.importedCards, 0);
    expect(importedSecond.skippedDuplicates, 1);
    final sides = _sidesOf(rows.single.mediaJson);
    expect(sides.question, isEmpty);
    expect(sides.answer, hasLength(1));
    expect(
      await database.select(database.media).get(),
      hasLength(1),
      reason: 'повторный запуск не добавляет медиа',
    );
  });
}

({List<String> question, List<String> answer, List<String> all}) _sidesOf(
  String mediaJson,
) {
  final Object? decoded = jsonDecode(mediaJson);
  if (decoded is List) {
    return (
      question: decoded.whereType<String>().toList(),
      answer: const <String>[],
      all: decoded.whereType<String>().toList(),
    );
  }
  final Map<String, Object?> map = (decoded! as Map).cast<String, Object?>();
  final List<String> question = (map['question'] as List? ?? <Object?>[])
      .whereType<String>()
      .toList();
  final List<String> answer = (map['answer'] as List? ?? <Object?>[])
      .whereType<String>()
      .toList();
  return (
    question: question,
    answer: answer,
    all: <String>[...question, ...answer],
  );
}
