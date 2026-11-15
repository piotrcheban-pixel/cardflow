// Приёмочный смоук итерации 7.11 на реальном Windows-процессе.
//
// Проверяет сквозной сценарий owner-note на боевом графе: файловая drift-БД,
// MediaStore, настоящий поиск картинки (Wikimedia-разбор + fake HTTP), импорт
// карточки, экран колоды, исчерпанный дневной лимит и режим «Тренировка».
//
// Запуск (Windows-хост, в CI не входит):
//   fvm flutter test integration_test/session_smoke_windows_test.dart -d windows
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:material_ui/material_ui.dart' hide Card;
import 'package:path/path.dart' as p;

import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/db/database_opener.dart';
import 'package:cardflow/data/db/epoch.dart';
import 'package:cardflow/data/transfer/media_store.dart';
import 'package:cardflow/domain/generation/generation_card_store.dart';
import 'package:cardflow/domain/generation/generation_run.dart';
import 'package:cardflow/domain/text/parsed_document.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/app.dart';
import 'package:cardflow/ui/review/practice_session_screen.dart';
import 'package:cardflow/ui/state/app_providers.dart';

import '../test/helpers/fake_http_adapter.dart';
import '../test/helpers/generation_fakes.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Windows: карточка с картинкой → колода → лимит → тренировка → картинка',
    (WidgetTester tester) async {
      final Directory base = Directory.systemTemp.createTempSync(
        'cardflow_smoke_',
      );
      final AppDatabase database = await openAppDatabase(baseDirectory: base);
      final MediaStore mediaStore = MediaStore(
        Directory(p.join(base.path, appDataDirectoryName)),
      );
      addTearDown(() async {
        await database.close();
        if (base.existsSync()) base.deleteSync(recursive: true);
      });

      // Настоящий PNG 1×1: Image.memory декодирует его без ошибок.
      final Uint8List png = base64Decode(
        'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
        '+A8AAQUBAScY42YAAAAASUVORK5CYII=',
      );
      final FakeHttpAdapter httpAdapter = FakeHttpAdapter((options) {
        final String path = options.uri.path;
        if (path.endsWith('/w/api.php')) {
          return jsonResponse(<String, Object?>{
            'batchcomplete': '',
            'query': <String, Object?>{
              'pages': <String, Object?>{
                'page-1': <String, Object?>{
                  'pageid': 1,
                  'ns': 6,
                  'title': 'File:Московский Кремль.jpg',
                  'index': 1,
                  'imageinfo': <Object?>[
                    <String, Object?>{
                      'url': 'https://example.test/kremlin.png',
                      'thumburl': 'https://example.test/thumb/kremlin.png',
                      'mime': 'image/png',
                      'extmetadata': <String, Object?>{
                        'LicenseShortName': <String, Object?>{
                          'value': 'CC BY-SA 4.0',
                        },
                      },
                    },
                  ],
                },
              },
            },
          });
        }
        if (options.uri.host == 'example.test') {
          return bytesResponse(png, contentType: 'image/png');
        }
        return jsonResponse(<String, Object?>{
          'choices': <Object?>[
            <String, Object?>{
              'message': <String, Object?>{
                'role': 'assistant',
                'content': jsonEncode(<String, Object?>{
                  'cards': <Object?>[
                    <String, Object?>{
                      'front': 'Что изображено на картинке?',
                      'back': 'Московский Кремль.',
                      'hint': null,
                      'tags': <Object?>['история'],
                      'card_type': 'basic',
                      'source_excerpt': null,
                      'source_file': null,
                      'image_query': 'Московский Кремль',
                    },
                    <String, Object?>{
                      'front': 'В каком году основан Кремль?',
                      'back': 'В 1156 году.',
                      'hint': null,
                      'tags': <Object?>['история'],
                      'card_type': 'basic',
                      'source_excerpt': null,
                      'source_file': null,
                      'image_query': null,
                    },
                  ],
                }),
              },
              'finish_reason': 'stop',
            },
          ],
          'usage': <String, Object?>{'total_tokens': 42},
        });
      });

      final List<Override> overrides = <Override>[
        appDatabaseProvider.overrideWithValue(database),
        mediaStoreProvider.overrideWithValue(mediaStore),
        generationDioProvider.overrideWithValue(dioWithAdapter(httpAdapter)),
        apiKeyStoreProvider.overrideWithValue(
          FakeApiKeyStore(<String, String>{'openai': 'sk-smoke'}),
        ),
        generationSettingsStoreProvider.overrideWithValue(
          FakeGenerationSettingsStore(),
        ),
      ];
      final ProviderContainer container = ProviderContainer(
        overrides: overrides,
      );
      addTearDown(container.dispose);

      // 1. Генерация на production-графе: модель → image_query → Wikimedia
      //    (разбор ответа и скачивание) → карточка с байтами.
      final GenerationRunResult generated = await container
          .read(generationRunnerProvider)
          .run(
            GenerationRunRequest(
              documents: const <ParsedDocument>[],
              account: testProviderAccount(
                presetId: 'openai',
                modelId: 'gpt-4o-mini',
              ),
              deckName: 'Смоук Windows',
              wishes: 'Московский Кремль',
            ),
          );
      expect(generated.cards, hasLength(2));
      expect(generated.cards.first.image, isNotNull);
      expect(generated.cards.first.image!.bytes, png);

      // 2. Импорт в реальную файловую БД + MediaStore.
      final GenerationImportResult imported = await container
          .read(generationCardStoreProvider)
          .importGeneratedCards(
            deckId: null,
            deckName: 'Смоук Windows',
            cards: generated.cards,
            jobId: generated.jobId,
            now: DateTime.now(),
          );
      expect(imported.importedCards, 2);

      final List<CardRow> cardRows = await (database.select(
        database.cards,
      )..where((table) => table.deckId.equals(imported.deckId))).get();
      final CardRow imageCard = cardRows.firstWhere(
        (CardRow row) => row.mediaJson != '[]',
      );
      expect(imageCard.fsrsJson, isNotNull);
      expect(imageCard.due, isNotNull);
      final MediaRow mediaRow = await (database.select(
        database.media,
      )..where((table) => table.cardId.equals(imageCard.id))).getSingle();
      final File mediaFile = File(
        p.join(base.path, appDataDirectoryName, mediaRow.path),
      );
      expect(
        mediaFile.existsSync(),
        isTrue,
        reason: 'файл иллюстрации записан на диск',
      );
      expect(mediaFile.readAsBytesSync(), png);

      // 3. Дневной лимит новых исчерпан: 20 «новых» оценок за сегодня.
      final DateTime reviewTime = DateTime.now();
      for (var index = 0; index < 20; index++) {
        await database
            .into(database.reviewLogs)
            .insert(
              ReviewLogsCompanion.insert(
                id: 'smoke-log-$index',
                cardId: 'smoke-card-$index',
                rating: 3,
                reviewedAt: toEpochMs(reviewTime),
                mode: 'classic',
                actualDays: const Value<double?>(null),
              ),
            );
      }

      // 4. Приложение на той же БД: колода → лимит → тренировка.
      await tester.pumpWidget(
        ProviderScope(overrides: overrides, child: const CardFlowApp()),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.text('Смоук Windows'));
      await tester.pumpAndSettle();

      final AppLocalizations l10n = AppLocalizations.of(
        tester.element(find.byType(Scaffold).first),
      );

      // Классика: лимит исчерпан — сообщение о лимите, без пустой сессии.
      await tester.tap(find.text(l10n.reviewStartSession));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.reviewModeClassic));
      await tester.pumpAndSettle();
      expect(find.text(l10n.reviewStartEmptyLimitedMessage), findsOneWidget);

      // Снекбар живёт 4 с и перекрывает нижнюю панель оценок: даём ему уйти.
      await tester.pump(const Duration(seconds: 5));
      await tester.pumpAndSettle();

      // Тренировка: карточки доступны, картинка на карточке отрисована.
      await tester.tap(find.text(l10n.reviewStartSession));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.reviewModePractice));
      await tester.pumpAndSettle();

      expect(find.byType(PracticeSessionScreen), findsOneWidget);
      expect(find.text('Что изображено на картинке?'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('card-content-image')),
        findsOneWidget,
        reason: 'иллюстрация импортированной карточки видна в сессии',
      );

      // Ответ раскрывается и оценка тренировки пишется в журнал.
      await tester.tap(find.byKey(const ValueKey<String>('practice-card')));
      await tester.pumpAndSettle();
      expect(find.text('Московский Кремль.'), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey<String>('review-rating-good')),
      );
      await tester.pumpAndSettle();
      expect(find.text('В каком году основан Кремль?'), findsOneWidget);

      final List<ReviewLogRow> practiceLogs = await (database.select(
        database.reviewLogs,
      )..where((table) => table.mode.equals('practice'))).get();
      expect(practiceLogs, hasLength(1));
      expect(practiceLogs.single.rating, 3);

      final CardRow afterRating = await (database.select(
        database.cards,
      )..where((table) => table.id.equals(imageCard.id))).getSingle();
      expect(afterRating.state, 'new', reason: 'тренировка не меняет FSRS');
      expect(afterRating.due, imageCard.due);
      expect(afterRating.fsrsJson, imageCard.fsrsJson);
    },
    timeout: const Timeout(Duration(minutes: 5)),
  );
}
