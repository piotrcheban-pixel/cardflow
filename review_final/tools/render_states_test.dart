// Финальный аудит: состояния (пусто, завершено, ошибка, загрузка, диалоги).
// Run: .fvm/versions/3.47.9/bin/flutter.bat test review_final/tools/render_states_test.dart --no-pub
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' hide Card;

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/decks/deck_summary.dart';
import 'package:cardflow/domain/settings/app_settings.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/router/app_router.dart';
import 'package:cardflow/ui/theme/app_theme.dart';
import 'package:cardflow/ui/theme/app_tokens.dart';

import '../../test/helpers/decks_fakes.dart';
import '../../test/helpers/pump_app.dart'
    show decksOverrides, ruLocalizationDelegates;
import '../../test/helpers/review_fakes.dart';
import '../../test/helpers/settings_fakes.dart';

const String _assets = 'build/windows/x64/runner/Debug/data/flutter_assets';
const String _outDir = 'review_final/screenshots/rendered';
const Size _size2k = Size(1706.7, 940);
const double _factor = 1.24;
final DateTime _now = DateTime.utc(2026, 11, 23, 12);

Future<void> _loadFont(String family, String path) async {
  final Uint8List bytes = File(path).readAsBytesSync();
  final ByteData data = ByteData.view(bytes.buffer);
  final FontLoader loader = FontLoader(family)
    ..addFont(Future<ByteData>.value(data));
  await loader.load();
}

Widget _app({
  required List<Card> cards,
  required String location,
  Object? cardsError,
  Brightness brightness = Brightness.light,
}) {
  final FakeCardRepository repo = FakeCardRepository(cards: cards)
    ..cardsByDeckError = cardsError;
  final List<Override> overrides = decksOverrides(
    deckRepository: FakeDeckRepository(
      summaries: <DeckSummary>[
        makeSummary(
          id: 'deck-1',
          name: 'Электротехника',
          totalCards: cards.length,
          dueCards: cards.length,
          newCards: cards.length,
        ),
      ],
    ),
    cardRepository: repo,
    reviewRepository: FakeReviewRepository(),
    appSettingsStore: FakeAppSettingsStore(
      settings: AppSettings.defaults.copyWith(textScale: 0.9),
    ),
  );
  final GlobalKey<NavigatorState> key = GlobalKey<NavigatorState>();
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp.router(
      debugShowCheckedModeBanner: false,
      locale: const Locale('ru'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: ruLocalizationDelegates,
      theme: brightness == Brightness.light
          ? AppTheme.light(scale: _factor)
          : AppTheme.dark(scale: _factor),
      routerConfig: createAppRouter(initialLocation: location, navigatorKey: key),
      builder: (BuildContext context, Widget? child) {
        final MediaQueryData media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(textScaler: const TextScaler.linear(0.9)),
          child: child ?? const SizedBox.shrink(),
        );
      },
    ),
  );
}

Future<void> _pump(WidgetTester tester, Widget app, {int ms = 500}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = _size2k;
  addTearDown(tester.view.reset);
  AppAdaptive.debugOverride = _factor;
  addTearDown(() => AppAdaptive.debugOverride = null);
  await tester.pumpWidget(app);
  await tester.pump();
  await tester.pump(Duration(milliseconds: ms));
}

Future<void> _shoot(WidgetTester tester, String name) async {
  await tester.runAsync(() async {
    final RenderView view = tester.binding.renderViews.first;
    final OffsetLayer layer = view.debugLayer! as OffsetLayer;
    final ui.Image image = await layer.toImage(view.paintBounds);
    final ByteData? data = await image.toByteData(format: ui.ImageByteFormat.png);
    final File file = File('$_outDir/$name.png');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(data!.buffer.asUint8List());
    // ignore: avoid_print
    print('SHOT $name ${image.width}x${image.height}');
  });
}

List<Card> _cards(int n) => <Card>[
  for (int i = 1; i <= n; i++)
    makeCard(
      id: 'card-$i',
      deckId: 'deck-1',
      front: 'Вопрос $i: чему равно линейное напряжение?',
      back: 'Ответ $i: между линейными проводами.',
      createdAt: _now,
      updatedAt: _now,
    ),
];

void main() {
  setUpAll(() async {
    await _loadFont('Inter', '$_assets/assets/fonts/Inter-Variable.ttf');
    await _loadFont('MaterialIcons', '$_assets/fonts/MaterialIcons-Regular.otf');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          SystemChannels.platform,
          (MethodCall call) async => null,
        );
  });

  testWidgets('empty session', (WidgetTester tester) async {
    await _pump(
      tester,
      _app(cards: const <Card>[], location: '/decks/deck-1/study'),
    );
    _rects(tester, 'empty');
    await _shoot(tester, 'state_empty_session_2k150');
  }, timeout: const Timeout(Duration(seconds: 120)));

  testWidgets('load error', (WidgetTester tester) async {
    await _pump(
      tester,
      _app(
        cards: _cards(1),
        cardsError: StateError('db'),
        location: '/decks/deck-1/study',
      ),
    );
    _rects(tester, 'error');
    await _shoot(tester, 'state_error_session_2k150');
  }, timeout: const Timeout(Duration(seconds: 120)));

  testWidgets('completed', (WidgetTester tester) async {
    await _pump(
      tester,
      _app(cards: _cards(1), location: '/decks/deck-1/study'),
    );
    await tester.tap(find.byKey(const ValueKey<String>('review-card')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 340));
    await tester.pump(const Duration(milliseconds: 280));
    await tester.tap(find.byKey(const ValueKey<String>('review-rating-good')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    _rects(tester, 'completed');
    await _shoot(tester, 'state_completed_2k150');
  }, timeout: const Timeout(Duration(seconds: 120)));

  testWidgets('plan missing', (WidgetTester tester) async {
    await _pump(
      tester,
      _app(cards: _cards(1), location: '/session/classic'),
    );
    await _shoot(tester, 'state_plan_missing_2k150');
  }, timeout: const Timeout(Duration(seconds: 120)));

  testWidgets('loading frame', (WidgetTester tester) async {
    await _pump(
      tester,
      _app(cards: _cards(2), location: '/decks/deck-1/study'),
      ms: 0,
    );
    await _shoot(tester, 'state_loading_2k150');
  }, timeout: const Timeout(Duration(seconds: 120)));

  testWidgets('empty decks first launch', (WidgetTester tester) async {
    final List<Override> overrides = decksOverrides(
      deckRepository: FakeDeckRepository(summaries: const <DeckSummary>[]),
      cardRepository: FakeCardRepository(),
      reviewRepository: FakeReviewRepository(),
      appSettingsStore: FakeAppSettingsStore(
        settings: AppSettings.defaults.copyWith(textScale: 0.9),
      ),
    );
    final GlobalKey<NavigatorState> key = GlobalKey<NavigatorState>();
    await _pump(
      tester,
      ProviderScope(
        overrides: overrides,
        child: MaterialApp.router(
          debugShowCheckedModeBanner: false,
          locale: const Locale('ru'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: ruLocalizationDelegates,
          theme: AppTheme.light(scale: _factor),
          routerConfig: createAppRouter(navigatorKey: key),
          builder: (BuildContext context, Widget? child) {
            final MediaQueryData media = MediaQuery.of(context);
            return MediaQuery(
              data: media.copyWith(textScaler: const TextScaler.linear(0.9)),
              child: child ?? const SizedBox.shrink(),
            );
          },
        ),
      ),
    );
    await _shoot(tester, 'state_empty_decks_2k150');
  }, timeout: const Timeout(Duration(seconds: 120)));

  testWidgets('deck screen overflow menu', (WidgetTester tester) async {
    await _pump(
      tester,
      _app(cards: _cards(3), location: '/decks/deck-1'),
    );
    await tester.tap(find.byKey(const ValueKey<String>('deck-overflow-menu')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await _shoot(tester, 'state_deck_menu_2k150');
  }, timeout: const Timeout(Duration(seconds: 120)));

  testWidgets('deck delete dialog', (WidgetTester tester) async {
    await _pump(
      tester,
      _app(cards: _cards(3), location: '/decks/deck-1'),
    );
    await tester.tap(find.byKey(const ValueKey<String>('deck-overflow-menu')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final Finder delete = find.text('Удалить');
    if (delete.evaluate().isNotEmpty) {
      await tester.tap(delete.last);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }
    await _shoot(tester, 'state_delete_deck_2k150');
  }, timeout: const Timeout(Duration(seconds: 120)));
}

void _rects(WidgetTester tester, String label) {
  final List<String> parts = <String>[];
  for (final String k in <String>[
    'review-empty-continue',
    'review-empty-practice',
    'review-rating-good',
    'deck-card-delete-cancel',
    'deck-card-delete-confirm',
  ]) {
    final Finder f = find.byKey(ValueKey<String>(k));
    if (f.evaluate().isEmpty) continue;
    final Rect r = tester.getRect(f.first);
    parts.add('$k=${r.width.toStringAsFixed(0)}x${r.height.toStringAsFixed(0)}');
  }
  // ignore: avoid_print
  print('STATE $label|${parts.isEmpty ? 'no keys' : parts.join(' ')}');
}
