// Приёмочный смоук итерации 7.12 на реальном Windows-процессе.
//
// Проверяет три owner-note сценария на боевом графе (файловая drift-БД,
// MediaStore, настоящие репозитории и UI):
//   1) Basic-карточка с картинкой без масок создаётся и показывается в сессии;
//   2) карточки, созданные сегодня, доступны при исчерпанном дневном лимите,
//      а вчерашние — через предупреждение «Продолжить без лимита»;
//   3) генерация ИИ с `image_query` (fake HTTP-провайдер + Wikimedia) даёт
//      скачанную картинку в предпросмотре и в media после импорта.
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

import 'package:cardflow/api/images/placeholder_image_generator.dart';
import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/db/database_opener.dart';
import 'package:cardflow/data/db/epoch.dart';
import 'package:cardflow/data/transfer/media_store.dart';
import 'package:cardflow/domain/cards/card_media.dart';
import 'package:cardflow/domain/generation/generation_run.dart';
import 'package:cardflow/domain/text/parsed_document.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/app.dart';
import 'package:cardflow/ui/generation/generation_preview_screen.dart';
import 'package:cardflow/ui/review/review_session_screen.dart';
import 'package:cardflow/ui/state/app_providers.dart';

import '../test/helpers/decks_fakes.dart';
import '../test/helpers/fake_http_adapter.dart';
import '../test/helpers/generation_fakes.dart';
import '../test/helpers/pump_app.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'Windows 7.12: картинка Basic без масок, лимит, генерация с картинками',
    (WidgetTester tester) async {
      final Directory base = Directory.systemTemp.createTempSync(
        'cardflow_smoke_712_',
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
      // 7.14: цепочка картинок отбрасывает изображения < 400 px по короткой
      // стороне, поэтому «настоящая» найденная картинка — валидный PNG 800×450.
      final Uint8List foundPng = const PlaceholderImageGenerator()
          .generate(seed: 'smoke-found-image')
          .bytes;
      final DateTime now = DateTime.now();
      final int epochNow = toEpochMs(now.toUtc());

      // Две колоды: «Мои карточки» (сегодняшняя, из формы) и «Старая колода»
      // (карточка создана месяц назад — дневной лимит для неё действует).
      await database
          .into(database.decks)
          .insert(
            DecksCompanion.insert(
              id: 'deck-today',
              name: 'Мои карточки',
              createdAt: epochNow,
              updatedAt: epochNow,
            ),
          );
      await database
          .into(database.decks)
          .insert(
            DecksCompanion.insert(
              id: 'deck-old',
              name: 'Старая колода',
              createdAt: epochNow - 30 * 86400000,
              updatedAt: epochNow,
            ),
          );
      await database
          .into(database.cards)
          .insert(
            CardsCompanion.insert(
              id: 'old-card',
              deckId: 'deck-old',
              front: 'Вчерашняя карточка',
              back: 'Ответ',
              cardType: 'basic',
              state: 'new',
              createdAt: epochNow - 30 * 86400000,
              updatedAt: epochNow,
            ),
          );
      // Дневной лимит новых израсходован ещё до создания новой карточки.
      for (var index = 0; index < 20; index++) {
        await database
            .into(database.reviewLogs)
            .insert(
              ReviewLogsCompanion.insert(
                id: 'limit-log-$index',
                cardId: 'limit-card-$index',
                rating: 3,
                reviewedAt: toEpochMs(now),
                mode: 'classic',
                actualDays: const Value<double?>(null),
              ),
            );
      }

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
          return bytesResponse(foundPng, contentType: 'image/png');
        }
        return jsonResponse(<String, Object?>{
          'choices': <Object?>[
            <String, Object?>{
              'message': <String, Object?>{
                'role': 'assistant',
                'content': jsonEncode(<String, Object?>{
                  'cards': <Object?>[
                    <String, Object?>{
                      'front': 'Что это?',
                      'back': 'Московский Кремль.',
                      'hint': null,
                      'tags': <Object?>['история'],
                      'card_type': 'basic',
                      'source_excerpt': null,
                      'source_file': null,
                      'image_id': null,
                      'image': <String, Object?>{
                        'query': 'Moscow Kremlin photo',
                        'fallback_query': 'Moscow Kremlin',
                        'kind': 'photo',
                      },
                    },
                    <String, Object?>{
                      'front': 'В каком году основан Кремль?',
                      'back': 'В 1156 году.',
                      'hint': null,
                      'tags': <Object?>['история'],
                      'card_type': 'basic',
                      'source_excerpt': null,
                      'source_file': null,
                      'image_id': null,
                      'image': <String, Object?>{
                        'query': 'Kremlin tower architecture photo',
                        'fallback_query': 'Kremlin tower',
                        'kind': 'photo',
                      },
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

      final FakeCardImageGateway imageGateway = FakeCardImageGateway()
        ..result = CardImageUpload(
          fileName: 'photo.png',
          mimeType: 'image/png',
          bytes: png,
        );

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
        imageGatewayProvider.overrideWithValue(imageGateway),
      ];

      // 1. Форма карточки на боевом графе: Basic + картинка, масок нет.
      await tester.pumpWidget(
        ProviderScope(overrides: overrides, child: const CardFlowApp()),
      );
      await tester.pumpAndSettle();
      final AppLocalizations l10n = l10nOf(tester);

      // 0. «Создать колоду» на боевой оболочке (`StatefulShellRoute`):
      // диалог открывается и закрывается, экран ветки остаётся на месте.
      // Регрессия Nocturne выталкивала из ветки экран вместо маршрута диалога
      // (белый экран, `has popped the last page`) — ADR-036.
      await tester.tap(find.text(l10n.decksCreateDeckFab));
      await tester.pumpAndSettle();
      expect(
        find.text(l10n.deckCreateDialogTitle),
        findsOneWidget,
        reason: 'диалог создания колоды открывается',
      );
      await tester.tap(find.text(l10n.cancel));
      await tester.pumpAndSettle();
      expect(find.text(l10n.deckCreateDialogTitle), findsNothing);
      expect(
        find.text(l10n.decksTitle),
        findsOneWidget,
        reason: 'закрытие диалога не выталкивает экран из ветки',
      );

      await tester.tap(find.text('Мои карточки'));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey<String>('deck-add-card')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const ValueKey<String>('card-form-front')),
        'Что это?',
      );
      await tester.enterText(
        find.byKey(const ValueKey<String>('card-form-back')),
        'Московский Кремль',
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey<String>('card-form-pick-image')),
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('card-form-pick-image')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('card-form-image-preview')),
        findsOneWidget,
        reason: 'картинка видна в форме сразу',
      );
      expect(
        find.byKey(const ValueKey<String>('occlusion-editor-canvas')),
        findsNothing,
        reason: 'маски не включаются принудительно',
      );
      await tester.ensureVisible(
        find.byKey(const ValueKey<String>('card-form-save')),
      );
      await tester.tap(find.byKey(const ValueKey<String>('card-form-save')));
      await tester.pumpAndSettle();

      final List<CardRow> todayCards = await (database.select(
        database.cards,
      )..where((table) => table.deckId.equals('deck-today'))).get();
      expect(todayCards, hasLength(1));
      final CardRow manual = todayCards.single;
      expect(manual.occlusionJson, isNull);
      expect(
        manual.mediaJson,
        isNot('[]'),
        reason: 'медиа привязано к обычной Basic-карточке',
      );
      final MediaRow manualMedia = await (database.select(
        database.media,
      )..where((table) => table.cardId.equals(manual.id))).getSingle();
      final File manualFile = File(
        p.join(base.path, appDataDirectoryName, manualMedia.path),
      );
      expect(manualFile.existsSync(), isTrue);
      expect(manualFile.readAsBytesSync(), png);

      // 2. Дневной лимит исчерпан, но карточка создана сегодня — сессия
      //    открывается без предупреждения, картинка видна.
      await tester.tap(find.text(l10n.reviewStartSession));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.reviewModeClassic));
      await tester.pumpAndSettle();
      expect(
        find.text(l10n.reviewDailyLimitTitle),
        findsNothing,
        reason: 'сегодняшние карточки не блокируются лимитом (ADR-028)',
      );
      expect(find.byType(ReviewSessionScreen), findsOneWidget);
      expect(find.text('Что это?'), findsOneWidget);
      expect(
        find.byKey(const ValueKey<String>('card-image')),
        findsOneWidget,
        reason: 'иллюстрация Basic-карточки отрисована',
      );
      await tester.tap(find.byKey(const ValueKey<String>('review-close')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('review-exit-confirm')),
      );
      await tester.pumpAndSettle();

      // 3. Старая карточка: дневной лимит действует — предупреждение и
      //    «Продолжить без лимита». Назад к списку колод — стрелка AppBar
      //    (`pageBack` ищет английский tooltip, а локаль только ru).
      await tester.tap(find.byIcon(Icons.arrow_back));
      await tester.pumpAndSettle();
      await tester.tap(find.text('Старая колода'));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.reviewStartSession));
      await tester.pumpAndSettle();
      await tester.tap(find.text(l10n.reviewModeClassic));
      await tester.pumpAndSettle();
      expect(find.text(l10n.reviewDailyLimitTitle), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey<String>('review-limit-continue')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ReviewSessionScreen), findsOneWidget);
      expect(find.text('Вчерашняя карточка'), findsOneWidget);

      // 4. Генерация на production-графе: модель → image_query → Wikimedia →
      //    картинка в предпросмотре и media после импорта.
      final ProviderContainer container = ProviderContainer(
        overrides: overrides,
      );
      addTearDown(container.dispose);
      final GenerationRunResult generated = await container
          .read(generationRunnerProvider)
          .run(
            GenerationRunRequest(
              documents: const <ParsedDocument>[],
              account: testProviderAccount(
                presetId: 'openai',
                modelId: 'gpt-4o-mini',
              ),
              deckName: 'Сгенерированная колода',
              wishes: 'Московский Кремль',
            ),
          );
      expect(generated.cards, hasLength(2));
      expect(generated.cards.first.image, isNotNull);
      expect(generated.cards.first.image!.isPlaceholder, isFalse);
      expect(generated.cards.first.image!.provider, 'wikimedia');
      expect(generated.cards.first.image!.bytes, foundPng);
      // Вторая карточка ищет «Kremlin tower» — тот же fake-ответ Commons;
      // картинка тоже настоящая.
      expect(generated.cards[1].image, isNotNull);

      await tester.pumpWidget(
        appWithHome(
          overrides: overrides,
          home: GenerationPreviewScreen(
            request: GenerationRunRequest(
              documents: const <ParsedDocument>[],
              account: testProviderAccount(
                presetId: 'openai',
                modelId: 'gpt-4o-mini',
              ),
              deckName: 'Сгенерированная колода',
              wishes: 'Московский Кремль',
            ),
            result: generated,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('generation-preview-image-0')),
        findsOneWidget,
        reason: 'скачанная картинка видна в предпросмотре',
      );
      expect(find.text(l10n.generationImageSearchFailed(1)), findsNothing);

      await tester.tap(
        find.byKey(const ValueKey<String>('generation-preview-import-all')),
      );
      await tester.pumpAndSettle();

      final List<DeckRow> generatedDecks = await (database.select(
        database.decks,
      )..where((table) => table.name.equals('Сгенерированная колода'))).get();
      expect(generatedDecks, hasLength(1));
      final List<CardRow> generatedCards = await (database.select(
        database.cards,
      )..where((table) => table.deckId.equals(generatedDecks.single.id))).get();
      final CardRow withImage = generatedCards.firstWhere(
        (CardRow row) => row.mediaJson != '[]',
      );
      final MediaRow generatedMedia = await (database.select(
        database.media,
      )..where((table) => table.cardId.equals(withImage.id))).getSingle();
      expect(
        File(p.join(base.path, appDataDirectoryName, generatedMedia.path))
            .existsSync(),
        isTrue,
        reason: 'файл иллюстрации импортированной карточки записан',
      );
    },
    timeout: const Timeout(Duration(minutes: 8)),
  );
}
