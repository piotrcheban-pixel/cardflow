// TASK 04 (мобильный UX/UI) — базовые снимки ключевых экранов на телефоне.
//
// Рендерит production-экраны с production-темой, реальными шрифтами Inter и
// MaterialIcons и снимает PNG через OffsetLayer.toImage (AGENTS.md, ретро
// «Фикс мобильного Empty State»). Ничего в lib/ не меняет.
//
// Run:
//   fvm flutter test review_visual/tools/t4_mobile_shots_test.dart --no-pub
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' hide Card;

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/cards/media_metadata.dart';
import 'package:cardflow/domain/generation/card_image_kind.dart';
import 'package:cardflow/domain/decks/deck_summary.dart';
import 'package:cardflow/domain/settings/app_settings.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/cards/card_form_screen.dart';
import 'package:cardflow/ui/decks/deck_screen.dart';
import 'package:cardflow/ui/decks/decks_screen.dart';
import 'package:cardflow/ui/review/feed_session_screen.dart';
import 'package:cardflow/ui/review/practice_session_screen.dart';
import 'package:cardflow/ui/review/review_session_screen.dart';
import 'package:cardflow/ui/theme/app_theme.dart';

import '../../test/helpers/decks_fakes.dart';
import '../../test/helpers/pump_app.dart'
    show appWithAppRouter, decksOverrides, ruLocalizationDelegates;
import '../../test/helpers/settings_fakes.dart';

const String _outDir = 'journal/task04/screenshots';
const String _variant = String.fromEnvironment('T4_SHOTS', defaultValue: 'before');

const String kLongFront =
    'Почему в трёхфазной цепи при симметричной нагрузке ток в нейтральном '
    'проводе равен нулю и как это используется при расчёте?';
const String kLongBack =
    'Сумма мгновенных значений фазных токов в любой момент времени равна нулю, '
    'поэтому по нейтральному проводу ток не протекает. Это позволяет '
    'рассчитывать каждую фазу независимо, заменить трёхфазную цепь тремя '
    'однофазными и не закладывать сечение нейтрали по рабочему току.';
const String kShortFront = 'Сколько будет 855 − 499?';
const String kShortBack = '356';

Future<void> _loadFont(String family, String path) async {
  final Uint8List bytes = File(path).readAsBytesSync();
  final ByteData data = ByteData.view(bytes.buffer);
  final FontLoader loader = FontLoader(family)
    ..addFont(Future<ByteData>.value(data));
  await loader.load();
}

Future<Uint8List> _makePng(int width, int height, int seed) async {
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final Canvas canvas = Canvas(recorder);
  final Rect rect = Rect.fromLTWH(0, 0, width.toDouble(), height.toDouble());
  canvas.drawRect(
    rect,
    Paint()
      ..shader = ui.Gradient.linear(rect.topLeft, rect.bottomRight, <Color>[
        Color(0xFF9FB7D9 + seed * 0x000811),
        Color(0xFF4E6A93 - seed * 0x000207),
      ]),
  );
  final Paint line = Paint()
    ..color = const Color(0xFFF2F6FF).withValues(alpha: 0.55)
    ..strokeWidth = 6;
  for (int i = 0; i < 7; i++) {
    canvas.drawLine(
      Offset(20 + i * 46, height * 0.72),
      Offset(30 + i * 46, height * (0.24 + 0.05 * (i % 3))),
      line,
    );
  }
  final ui.Image image = await recorder.endRecording().toImage(width, height);
  final ByteData? data = await image.toByteData(format: ui.ImageByteFormat.png);
  return data!.buffer.asUint8List();
}

Card _imageCard({
  required String id,
  required String front,
  required String back,
  required List<String> questionMedia,
  required List<String> answerMedia,
}) {
  return makeCard(
    id: id,
    deckId: 'deck-1',
    front: front,
    back: back,
    createdAt: DateTime.utc(2026, 11, 12, 9),
    questionMediaIds: questionMedia,
    answerMediaIds: answerMedia,
    sourceExcerpt:
        'Трёхфазные цепи: симметричный режим и расчёт по одной фазе. '
        'Учебник, глава 4, § 4.3.',
  );
}

Widget _app({
  required List<Override> overrides,
  required Widget home,
  required double textScale,
}) {
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: const Locale('ru'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: ruLocalizationDelegates,
      theme: AppTheme.light(scale: 1),
      builder: (BuildContext context, Widget? child) {
        final MediaQueryData media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(
            textScaler: TextScaler.linear(textScale),
            padding: const EdgeInsets.only(top: 24),
            viewPadding: const EdgeInsets.only(top: 24),
          ),
          child: child ?? const SizedBox.shrink(),
        );
      },
      home: home,
    ),
  );
}

void _configure(WidgetTester tester, Size size) {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
}

Future<void> _pump(WidgetTester tester) async {
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 400));
  await tester.pump(const Duration(milliseconds: 400));
}

Future<void> _shoot(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    final RenderView view = tester.binding.renderViews.first;
    final OffsetLayer layer = view.debugLayer! as OffsetLayer;
    final ui.Image image = await layer.toImage(view.paintBounds);
    final ByteData? data = await image.toByteData(
      format: ui.ImageByteFormat.png,
    );
    final File file = File('$_outDir/$_variant/$name.png');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(data!.buffer.asUint8List());
    // ignore: avoid_print
    print('SHOT $_outDir/$_variant/$name.png ${image.width}x${image.height}');
  });
}

void _dumpOverflow(WidgetTester tester, String label) {
  final Object? error = tester.takeException();
  // ignore: avoid_print
  print('EXC $label ${error == null ? 'none' : error.toString()}');
}

void _dumpRect(WidgetTester tester, String label, Finder finder) {
  if (finder.evaluate().isEmpty) {
    // ignore: avoid_print
    print('RECT $label none');
    return;
  }
  final Rect r = tester.getRect(finder.first);
  // ignore: avoid_print
  print(
    'RECT $label ${r.left.toStringAsFixed(1)},${r.top.toStringAsFixed(1)} '
    '${r.width.toStringAsFixed(1)}x${r.height.toStringAsFixed(1)}',
  );
}

void main() {
  late Uint8List q1;
  late Uint8List q2;
  late Uint8List a1;
  final String flutterRoot = Platform.environment['FLUTTER_ROOT'] ?? '';
  final String iconsPath =
      '$flutterRoot/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf';

  setUpAll(() async {
    await _loadFont('Inter', 'assets/fonts/Inter-Variable.ttf');
    if (File(iconsPath).existsSync()) {
      await _loadFont('MaterialIcons', iconsPath);
    }
    q1 = await _makePng(640, 360, 1);
    q2 = await _makePng(420, 640, 2);
    a1 = await _makePng(640, 420, 3);
  });

  final Map<String, (Size, double)> configs = <String, (Size, double)>{
    '360x800': (const Size(360, 800), 1.0),
    '390x844': (const Size(390, 844), 1.0),
    '360x800t130': (const Size(360, 800), 1.3),
    '320x640': (const Size(320, 640), 1.0),
  };

  for (final MapEntry<String, (Size, double)> entry in configs.entries) {
    final Size size = entry.value.$1;
    final double textScale = entry.value.$2;
    final String tag = entry.key;

    testWidgets('T4 decks first launch $tag', (WidgetTester tester) async {
      _configure(tester, size);
      await tester.pumpWidget(
        _app(
          textScale: textScale,
          home: const DecksScreen(),
          overrides: decksOverrides(
            deckRepository: FakeDeckRepository(),
            appSettingsStore: FakeAppSettingsStore(
              settings: AppSettings.defaults.copyWith(textScale: textScale),
            ),
          ),
        ),
      );
      await _pump(tester);
      _dumpOverflow(tester, 'decks-$tag');
      _dumpRect(
        tester,
        'decks-ai-setup',
        find.byKey(const ValueKey<String>('decks-welcome-ai-setup')),
      );
      await _shoot(tester, 'decks_first_launch_$tag');
    }, timeout: const Timeout(Duration(seconds: 180)));

    testWidgets('T4 session revealed $tag', (WidgetTester tester) async {
      _configure(tester, size);
      final Card card = _imageCard(
        id: 'card-1',
        front: kShortFront,
        back: kShortBack,
        questionMedia: <String>['q1'],
        answerMedia: <String>['a1'],
      );
      await tester.pumpWidget(
        _app(
          textScale: textScale,
          home: const ReviewSessionScreen(deckId: 'deck-1'),
          overrides: decksOverrides(
            deckRepository: FakeDeckRepository(
              summaries: <DeckSummary>[
                makeSummary(id: 'deck-1', name: 'Электротехника', totalCards: 1),
              ],
            ),
            cardRepository: FakeCardRepository(cards: <Card>[card]),
            cardMediaRepository: FakeCardMediaRepository(
              bytesById: <String, Uint8List>{'q1': q1, 'a1': a1},
              metadataById: <String, MediaMetadata>{
                'q1': const MediaMetadata(kind: GeneratedCardImageKind.photo),
                'a1': const MediaMetadata(kind: GeneratedCardImageKind.photo),
              },
            ),
            appSettingsStore: FakeAppSettingsStore(
              settings: AppSettings.defaults.copyWith(textScale: textScale),
            ),
          ),
        ),
      );
      await _pump(tester);
      _dumpOverflow(tester, 'session-q-$tag');
      await _shoot(tester, 'session_question_$tag');
      await tester.tap(find.byKey(const ValueKey<String>('review-reveal')));
      await _pump(tester);
      _dumpOverflow(tester, 'session-a-$tag');
      _dumpRect(
        tester,
        'session-rating-hard',
        find.byKey(const ValueKey<String>('review-rating-hard')),
      );
      _dumpRect(
        tester,
        'session-card',
        find.byKey(const ValueKey<String>('review-card-face')),
      );
      await _shoot(tester, 'session_answer_$tag');
    }, timeout: const Timeout(Duration(seconds: 180)));

    testWidgets('T4 practice revealed $tag', (WidgetTester tester) async {
      _configure(tester, size);
      final Card card = _imageCard(
        id: 'card-1',
        front: kShortFront,
        back: kShortBack,
        questionMedia: <String>['q1'],
        answerMedia: <String>['a1'],
      );
      await tester.pumpWidget(
        _app(
          textScale: textScale,
          home: const PracticeSessionScreen(deckId: 'deck-1'),
          overrides: decksOverrides(
            deckRepository: FakeDeckRepository(
              summaries: <DeckSummary>[
                makeSummary(id: 'deck-1', name: 'Электротехника', totalCards: 2),
              ],
            ),
            cardRepository: FakeCardRepository(cards: <Card>[card]),
            cardMediaRepository: FakeCardMediaRepository(
              bytesById: <String, Uint8List>{'q1': q1, 'a1': a1},
              metadataById: <String, MediaMetadata>{
                'q1': const MediaMetadata(kind: GeneratedCardImageKind.photo),
                'a1': const MediaMetadata(kind: GeneratedCardImageKind.photo),
              },
            ),
            appSettingsStore: FakeAppSettingsStore(
              settings: AppSettings.defaults.copyWith(textScale: textScale),
            ),
          ),
        ),
      );
      await _pump(tester);
      await tester.tap(find.byKey(const ValueKey<String>('practice-reveal')));
      await _pump(tester);
      _dumpOverflow(tester, 'practice-$tag');
      _dumpRect(
        tester,
        'practice-rating-hard',
        find.byKey(const ValueKey<String>('review-rating-hard')),
      );
      await _shoot(tester, 'practice_answer_$tag');
    }, timeout: const Timeout(Duration(seconds: 180)));

    testWidgets('T4 feed $tag', (WidgetTester tester) async {
      _configure(tester, size);
      final Card card = _imageCard(
        id: 'card-1',
        front: kLongFront,
        back: kLongBack,
        questionMedia: <String>['q1', 'q2'],
        answerMedia: <String>['a1'],
      );
      await tester.pumpWidget(
        _app(
          textScale: textScale,
          home: const FeedSessionScreen(deckId: 'deck-1'),
          overrides: decksOverrides(
            deckRepository: FakeDeckRepository(
              summaries: <DeckSummary>[
                makeSummary(id: 'deck-1', name: 'Электротехника', totalCards: 2),
              ],
            ),
            cardRepository: FakeCardRepository(cards: <Card>[
              card,
              _imageCard(
                id: 'card-2',
                front: 'Что такое реактивная мощность?',
                back: 'Мощность, которая циркулирует между источником и '
                    'реактивными элементами и не совершает полезной работы.',
                questionMedia: const <String>[],
                answerMedia: const <String>[],
              ),
            ]),
            cardMediaRepository: FakeCardMediaRepository(
              bytesById: <String, Uint8List>{'q1': q1, 'q2': q2, 'a1': a1},
              metadataById: <String, MediaMetadata>{
                'q1': const MediaMetadata(kind: GeneratedCardImageKind.photo),
                'q2': const MediaMetadata(kind: GeneratedCardImageKind.photo),
                'a1': const MediaMetadata(kind: GeneratedCardImageKind.photo),
              },
            ),
            appSettingsStore: FakeAppSettingsStore(
              settings: AppSettings.defaults.copyWith(textScale: textScale),
            ),
          ),
        ),
      );
      await _pump(tester);
      _dumpOverflow(tester, 'feed-q-$tag');
      await _shoot(tester, 'feed_question_$tag');
      await tester.tap(find.byKey(const ValueKey<String>('feed-card-card-1')));
      await _pump(tester);
      _dumpOverflow(tester, 'feed-a-$tag');
      _dumpRect(
        tester,
        'feed-flip',
        find.byKey(const ValueKey<String>('feed-card-card-1')),
      );
      await _shoot(tester, 'feed_answer_$tag');
    }, timeout: const Timeout(Duration(seconds: 180)));

    testWidgets('T4 card form $tag', (WidgetTester tester) async {
      _configure(tester, size);
      final Card card = _imageCard(
        id: 'card-1',
        front: kLongFront,
        back: kLongBack,
        questionMedia: <String>['q1', 'q2'],
        answerMedia: <String>['a1'],
      );
      await tester.pumpWidget(
        _app(
          textScale: textScale,
          home: const CardFormScreen(deckId: 'deck-1', cardId: 'card-1'),
          overrides: decksOverrides(
            deckRepository: FakeDeckRepository(
              summaries: <DeckSummary>[
                makeSummary(id: 'deck-1', name: 'Электротехника', totalCards: 1),
              ],
            ),
            cardRepository: FakeCardRepository(cards: <Card>[card]),
            cardMediaRepository: FakeCardMediaRepository(
              bytesById: <String, Uint8List>{'q1': q1, 'q2': q2, 'a1': a1},
              metadataById: <String, MediaMetadata>{
                'q1': const MediaMetadata(kind: GeneratedCardImageKind.photo),
                'q2': const MediaMetadata(kind: GeneratedCardImageKind.photo),
                'a1': const MediaMetadata(kind: GeneratedCardImageKind.photo),
              },
            ),
            appSettingsStore: FakeAppSettingsStore(
              settings: AppSettings.defaults.copyWith(textScale: textScale),
            ),
          ),
        ),
      );
      await _pump(tester);
      _dumpOverflow(tester, 'cardform-top-$tag');
      await _shoot(tester, 'cardform_top_$tag');
      await tester.drag(find.byType(SingleChildScrollView).first, const Offset(0, -520));
      await _pump(tester);
      _dumpOverflow(tester, 'cardform-media-$tag');
      _dumpRect(
        tester,
        'cardform-question-images-title',
        find.byKey(
          const ValueKey<String>('card-form-question-images-title'),
        ),
      );
      _dumpRect(
        tester,
        'cardform-add-question',
        find.byKey(
          const ValueKey<String>('card-form-add-question-image'),
        ),
      );
      await _shoot(tester, 'cardform_media_$tag');
      await tester.drag(find.byType(SingleChildScrollView).first, const Offset(0, -720));
      await _pump(tester);
      _dumpOverflow(tester, 'cardform-bottom-$tag');
      await _shoot(tester, 'cardform_bottom_$tag');
    }, timeout: const Timeout(Duration(seconds: 180)));

    testWidgets('T4 deck screen $tag', (WidgetTester tester) async {
      _configure(tester, size);
      final Card card = _imageCard(
        id: 'card-1',
        front: kShortFront,
        back: kShortBack,
        questionMedia: const <String>[],
        answerMedia: const <String>[],
      );
      await tester.pumpWidget(
        _app(
          textScale: textScale,
          home: const DeckScreen(deckId: 'deck-1'),
          overrides: decksOverrides(
            deckRepository: FakeDeckRepository(
              summaries: <DeckSummary>[
                makeSummary(
                  id: 'deck-1',
                  name: 'Электротехника',
                  totalCards: 12,
                  newCards: 7,
                  dueCards: 5,
                ),
              ],
            ),
            cardRepository: FakeCardRepository(cards: <Card>[card]),
            appSettingsStore: FakeAppSettingsStore(
              settings: AppSettings.defaults.copyWith(textScale: textScale),
            ),
          ),
        ),
      );
      await _pump(tester);
      _dumpOverflow(tester, 'deck-$tag');
      await _shoot(tester, 'deck_$tag');
      final Finder start = find.text('Начать сессию');
      if (start.evaluate().isNotEmpty) {
        await tester.tap(start.first);
        await _pump(tester);
        _dumpOverflow(tester, 'deck-sheet-$tag');
        _dumpRect(tester, 'deck-sheet', find.byType(BottomSheet));
        await _shoot(tester, 'deck_modes_sheet_$tag');
      } else {
        // ignore: avoid_print
        print('SHEET $tag start-session not found');
      }
    }, timeout: const Timeout(Duration(seconds: 180)));
  }

  // Длинный ответ + очень большое изображение: проверка переполнения.
  testWidgets('T4 session long text 360x800', (WidgetTester tester) async {
    _configure(tester, const Size(360, 800));
    final Card card = _imageCard(
      id: 'card-1',
      front: kLongFront * 2,
      back: kLongBack * 3,
      questionMedia: <String>['q2', 'q2'],
      answerMedia: <String>['a1', 'a1'],
    );
    await tester.pumpWidget(
      _app(
        textScale: 1,
        home: const ReviewSessionScreen(deckId: 'deck-1'),
        overrides: decksOverrides(
          deckRepository: FakeDeckRepository(),
          cardRepository: FakeCardRepository(cards: <Card>[card]),
          cardMediaRepository: FakeCardMediaRepository(
            bytesById: <String, Uint8List>{'q2': q2, 'a1': a1},
            metadataById: <String, MediaMetadata>{
              'q2': const MediaMetadata(kind: GeneratedCardImageKind.photo),
              'a1': const MediaMetadata(kind: GeneratedCardImageKind.photo),
            },
          ),
        ),
      ),
    );
    await _pump(tester);
    await tester.tap(find.byKey(const ValueKey<String>('review-reveal')));
    await _pump(tester);
    _dumpOverflow(tester, 'session-long');
    await _shoot(tester, 'session_long_text_360x800');
  }, timeout: const Timeout(Duration(seconds: 180)));

  // Прочие мобильные экраны: настройки, статистика, генерация.
  for (final (String name, String route) in <(String, String)>[
    ('settings', '/settings'),
    ('statistics', '/statistics'),
    ('generation', '/generate'),
  ]) {
    testWidgets('T4 $name 390x844', (WidgetTester tester) async {
      _configure(tester, const Size(390, 844));
      await tester.pumpWidget(
        appWithAppRouter(
          overrides: decksOverrides(
            deckRepository: FakeDeckRepository(
              summaries: <DeckSummary>[
                makeSummary(
                  id: 'deck-1',
                  name: 'Электротехника',
                  totalCards: 12,
                  newCards: 7,
                  dueCards: 5,
                ),
              ],
            ),
            cardRepository: FakeCardRepository(
              cards: <Card>[
                makeCard(
                  id: 'card-1',
                  deckId: 'deck-1',
                  front: kShortFront,
                  back: kShortBack,
                ),
              ],
            ),
          ),
          initialLocation: route,
        ),
      );
      await _pump(tester);
      _dumpOverflow(tester, '$name-390x844');
      await _shoot(tester, '${name}_390x844');
    }, timeout: const Timeout(Duration(seconds: 180)));
  }}
