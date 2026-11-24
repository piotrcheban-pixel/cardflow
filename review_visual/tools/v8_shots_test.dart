// v8 audit harness: renders the production review session at exact logical sizes
// (4K, exact 2K, FullHD, mobile) with real Inter/MaterialIcons fonts, prints
// geometry measurements and the widget tree of interactive elements.
//
// Run:
//   .fvm/versions/3.47.9/bin/flutter.bat test review_visual/tools/v8_shots_test.dart --no-pub
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:image/image.dart' as img;
import 'package:material_ui/material_ui.dart' hide Card;

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/cards/media_metadata.dart';
import 'package:cardflow/domain/generation/card_image_kind.dart';
import 'package:cardflow/domain/decks/deck_summary.dart';
import 'package:cardflow/domain/settings/app_settings.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/review/review_session_screen.dart';
import 'package:cardflow/ui/review/review_toolbar.dart';
import 'package:cardflow/ui/theme/app_theme.dart';
import 'package:cardflow/ui/theme/app_tokens.dart';

import '../../test/helpers/decks_fakes.dart';
import '../../test/helpers/pump_app.dart'
    show decksOverrides, ruLocalizationDelegates;
import '../../test/helpers/review_fakes.dart';
import '../../test/helpers/settings_fakes.dart';

const String _assets = 'build/windows/x64/runner/Debug/data/flutter_assets';
const String _outDir = 'review_visual/screenshots/v7_after';

Future<void> _loadFont(String family, String path) async {
  final Uint8List bytes = File(path).readAsBytesSync();
  final ByteData data = ByteData.view(bytes.buffer);
  final FontLoader loader = FontLoader(family)
    ..addFont(Future<ByteData>.value(data));
  await loader.load();
}

Card _card() => makeCard(
  id: 'card-1',
  deckId: 'deck-1',
  front: 'Сколько векторных диаграмм строят по результатам измерений и вычислений?',
  back: 'Две: диаграмму токов и диаграмму напряжений.',
  createdAt: DateTime.utc(2026, 11, 13, 10),
);

/// Карточка с иллюстрацией на стороне ответа (гейт G4).
Card _imageCard() => makeCard(
  id: 'card-img',
  deckId: 'deck-1',
  front: 'Какая схема изображена на рисунке?',
  back: 'Схема замещения трёхфазной цепи.',
  mediaIds: const <String>['media-1'],
  createdAt: DateTime.utc(2026, 11, 13, 10),
);

/// PNG с рамкой и диагоналями: по краям видно обрезку, внутри — пропорции.
Uint8List _patternPng(int width, int height) {
  final img.Image image = img.Image(width: width, height: height);
  img.fill(image, color: img.ColorRgb8(236, 240, 250));
  img.drawRect(
    image,
    x1: 2,
    y1: 2,
    x2: width - 3,
    y2: height - 3,
    color: img.ColorRgb8(53, 37, 205),
    thickness: 6,
  );
  img.drawLine(
    image,
    x1: 0,
    y1: 0,
    x2: width - 1,
    y2: height - 1,
    color: img.ColorRgb8(186, 26, 26),
    thickness: 4,
  );
  img.drawLine(
    image,
    x1: width - 1,
    y1: 0,
    x2: 0,
    y2: height - 1,
    color: img.ColorRgb8(186, 26, 26),
    thickness: 4,
  );
  return Uint8List.fromList(img.encodePng(image));
}

Widget _imageHarness({
  required double scale,
  required double textScale,
  required Uint8List image,
}) {
  final List<Override> overrides = decksOverrides(
    deckRepository: FakeDeckRepository(
      summaries: <DeckSummary>[
        makeSummary(id: 'deck-1', name: 'Эл тех', totalCards: 12, newCards: 1),
      ],
    ),
    cardRepository: FakeCardRepository(cards: <Card>[_imageCard()]),
    reviewRepository: FakeReviewRepository(),
    cardMediaRepository: FakeCardMediaRepository(
      bytesById: <String, Uint8List>{'media-1': image},
      metadataById: const <String, MediaMetadata>{
        'media-1': MediaMetadata(
          provider: 'wikimedia',
          license: 'CC BY-SA 4.0',
          kind: GeneratedCardImageKind.photo,
        ),
      },
    ),
    appSettingsStore: FakeAppSettingsStore(
      settings: AppSettings.defaults.copyWith(textScale: textScale),
    ),
  );
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  final GoRouter router = GoRouter(
    initialLocation: '/decks/deck-1/study',
    navigatorKey: navigatorKey,
    routes: <GoRoute>[
      GoRoute(
        path: '/decks/:id/study',
        builder: (BuildContext context, GoRouterState state) =>
            ReviewSessionScreen(deckId: state.pathParameters['id']!),
      ),
    ],
  );
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp.router(
      debugShowCheckedModeBanner: false,
      locale: const Locale('ru'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: ruLocalizationDelegates,
      theme: AppTheme.light(scale: scale),
      routerConfig: router,
    ),
  );
}

Widget _harness({required double scale, required double textScale}) {
  final List<Override> overrides = decksOverrides(
    deckRepository: FakeDeckRepository(
      summaries: <DeckSummary>[
        makeSummary(id: 'deck-1', name: 'Эл тех', totalCards: 12, newCards: 1),
      ],
    ),
    cardRepository: FakeCardRepository(cards: <Card>[_card()]),
    reviewRepository: FakeReviewRepository(),
    appSettingsStore: FakeAppSettingsStore(
      settings: AppSettings.defaults.copyWith(textScale: textScale),
    ),
  );
  final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();
  final GoRouter router = GoRouter(
    initialLocation: '/decks/deck-1/study',
    navigatorKey: navigatorKey,
    routes: <GoRoute>[
      GoRoute(
        path: '/decks/:id/study',
        builder: (BuildContext context, GoRouterState state) =>
            ReviewSessionScreen(deckId: state.pathParameters['id']!),
      ),
    ],
  );
  return ProviderScope(
    overrides: overrides,
    child: MaterialApp.router(
      debugShowCheckedModeBanner: false,
      locale: const Locale('ru'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: ruLocalizationDelegates,
      theme: AppTheme.light(scale: scale),
      routerConfig: router,
    ),
  );
}

Future<void> _shoot(WidgetTester tester, String name) async {
  // Real engine work (rasterising the layer and encoding PNG) must run outside
  // the fake-async zone, otherwise the widget test never completes.
  await tester.runAsync(() async {
    final RenderView view = tester.binding.renderViews.first;
    final OffsetLayer layer = view.debugLayer! as OffsetLayer;
    final ui.Image image = await layer.toImage(view.paintBounds);
    final ByteData? data = await image.toByteData(
      format: ui.ImageByteFormat.png,
    );
    final File file = File('$_outDir/$name.png');
    file.parent.createSync(recursive: true);
    file.writeAsBytesSync(data!.buffer.asUint8List());
    // ignore: avoid_print
    print('SHOT $name ${image.width}x${image.height}');
  });
}

Future<void> _pump(
  WidgetTester tester,
  double scale,
  double textScale,
  Size size,
) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = size;
  addTearDown(tester.view.reset);
  AppAdaptive.debugOverride = scale;
  addTearDown(() => AppAdaptive.debugOverride = null);
  await tester.pumpWidget(_harness(scale: scale, textScale: textScale));
  await tester.pumpAndSettle();
}

/// Font sizes actually painted inside the card (descending).
List<double> _cardFonts(WidgetTester tester) {
  final Finder card = find.byKey(const ValueKey<String>('review-card'));
  final MediaQueryData media = MediaQuery.of(tester.element(card));
  final List<double> sizes = <double>[];
  for (final Element element
      in find
          .descendant(of: card, matching: find.byType(RichText))
          .evaluate()) {
    final RichText rich = element.widget as RichText;
    final double base = rich.text.style?.fontSize ?? 0;
    sizes.add(
      double.parse((base * media.textScaler.scale(1)).toStringAsFixed(2)),
    );
  }
  sizes.sort((double a, double b) => b.compareTo(a));
  return sizes;
}

/// Font size of the rating label (inside the rating button).
double _ratingFont(WidgetTester tester) {
  final Finder label = find.descendant(
    of: find.byKey(const ValueKey<String>('review-rating-good')),
    matching: find.text(
      AppLocalizations.of(
        tester.element(find.byKey(const ValueKey<String>('review-card'))),
      ).ratingGood,
    ),
  );
  if (label.evaluate().isEmpty) return 0;
  final RichText rich = tester.widget<RichText>(
    find.descendant(of: label, matching: find.byType(RichText)).first,
  );
  final MediaQueryData media = MediaQuery.of(
    tester.element(find.byKey(const ValueKey<String>('review-card'))),
  );
  return double.parse(
    ((rich.text.style?.fontSize ?? 0) * media.textScaler.scale(1))
        .toStringAsFixed(2),
  );
}

Future<void> _measure(WidgetTester tester, String label) async {
  final Finder cardFinder = find.byKey(const ValueKey<String>('review-card'));
  final Size card = tester.getSize(cardFinder);
  final Rect cardRect = tester.getRect(cardFinder);
  final MediaQueryData media = MediaQuery.of(tester.element(cardFinder));
  final double windowWidth = media.size.width;
  final Finder revealFinder = find.byKey(
    const ValueKey<String>('review-reveal'),
  );
  final String reveal = revealFinder.evaluate().isEmpty
      ? 'none'
      : '${tester.getSize(revealFinder).width.toStringAsFixed(1)}x'
            '${tester.getSize(revealFinder).height.toStringAsFixed(1)}';
  final bool hasToolbar = find.byType(ReviewToolbar).evaluate().isNotEmpty;
  String rating = 'none';
  String gap = 'none';
  String ratingFont = 'none';
  if (hasToolbar) {
    final Size good = tester.getSize(
      find.byKey(const ValueKey<String>('review-rating-good')),
    );
    final Rect again = tester.getRect(
      find.byKey(const ValueKey<String>('review-rating-again')),
    );
    final Rect hard = tester.getRect(
      find.byKey(const ValueKey<String>('review-rating-hard')),
    );
    rating =
        '${good.width.toStringAsFixed(1)}x${good.height.toStringAsFixed(1)}';
    gap = (hard.left - again.right).toStringAsFixed(1);
    ratingFont = _ratingFont(tester).toStringAsFixed(2);
  }
  final List<double> fonts = _cardFonts(tester);
  // ignore: avoid_print
  print(
    'MEASURE $label viewport=${media.size.width.toStringAsFixed(1)}x'
    '${media.size.height.toStringAsFixed(1)} '
    'card=${card.width.toStringAsFixed(1)}x${card.height.toStringAsFixed(1)} '
    'cardShareW=${(100 * card.width / windowWidth).toStringAsFixed(1)} '
    'cardLeft=${cardRect.left.toStringAsFixed(1)} '
    'rating=$rating gap=$gap reveal=$reveal '
    'cardFonts=${fonts.take(4).join(",")} ratingFont=$ratingFont',
  );
}

void _dumpInteractive(WidgetTester tester, String label) {
  final List<String> found = <String>[];
  for (final String key in <String>[
    'review-close',
    'review-undo',
    'review-why',
    'review-reveal',
    'review-rating-again',
    'review-rating-hard',
    'review-rating-good',
    'review-rating-easy',
    'review-rating-hint',
    'review-keyboard-hints-front',
    'review-keyboard-hints',
  ]) {
    final Finder f = find.byKey(ValueKey<String>(key));
    if (f.evaluate().isEmpty) continue;
    final String state;
    switch (key) {
      case 'review-rating-again':
      case 'review-rating-hard':
      case 'review-rating-good':
      case 'review-rating-easy':
        state = tester.widget<FilledButton>(f).onPressed == null
            ? 'DISABLED'
            : 'enabled';
      case 'review-undo':
        state = tester.widget<IconButton>(f).onPressed == null
            ? 'DISABLED'
            : 'enabled';
      default:
        state = 'visible';
    }
    found.add('$key($state)');
  }
  // ignore: avoid_print
  print('TREE $label visibleInteractive=${found.length} ${found.join(' ')}');
}

void main() {
  setUpAll(() async {
    await _loadFont('Inter', '$_assets/assets/fonts/Inter-Variable.ttf');
    await _loadFont(
      'MaterialIcons',
      '$_assets/fonts/MaterialIcons-Regular.otf',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
          SystemChannels.platform,
          (MethodCall call) async => null,
        );
  });

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  // ---- configurations -----------------------------------------------------
  final Map<String, (double, double, Size)> configs =
      <String, (double, double, Size)>{
        '2k150': (1.24, 0.9, const Size(1707, 940)),
        '2k100': (1.24, 1.0, const Size(2560, 1440)),
        '4k100': (1.45, 1.0, const Size(3840, 2160)),
        '4k150': (1.45, 1.0, const Size(2560, 1440)),
        'fhd': (1.0, 0.9, const Size(1920, 1080)),
        '390x844': (1.0, 1.0, const Size(390, 844)),
        '844x390': (1.0, 1.0, const Size(844, 390)),
      };
  const Map<String, String> titles = <String, String>{
    '2k150': '2K live 1707x940 text90',
    '2k100': '2K exact 2560x1440',
    '4k100': '4K 3840x2160 at 100%',
    '4k150': '4K at 150% = 2560x1440 logical',
    'fhd': 'FullHD 1920x1080 text90',
    '390x844': 'mobile portrait 390x844',
    '844x390': 'mobile landscape 844x390',
  };

  for (final MapEntry<String, (double, double, Size)> entry
      in configs.entries) {
    final (double, double, Size) cfg = entry.value;

    testWidgets('Q ${titles[entry.key]}', (WidgetTester tester) async {
      await _pump(tester, cfg.$1, cfg.$2, cfg.$3);
      _dumpInteractive(tester, '${entry.key}-question');
      await _measure(tester, '${entry.key}-question');
      await _shoot(tester, 'v8_${entry.key}_classic_question');
    }, timeout: const Timeout(Duration(seconds: 120)));

    testWidgets('A ${titles[entry.key]}', (WidgetTester tester) async {
      await _pump(tester, cfg.$1, cfg.$2, cfg.$3);
      await tester.tap(find.byKey(const ValueKey<String>('review-card')));
      // Переворот 300 мс, затем появление панели оценок (fade+slide 220 мс):
      // кадр снимается после обеих анимаций, иначе панель ещё прозрачна.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 320));
      await tester.pump(const Duration(milliseconds: 260));
      await tester.pump(const Duration(milliseconds: 100));
      _dumpInteractive(tester, '${entry.key}-answer');
      await _measure(tester, '${entry.key}-answer');
      await _shoot(tester, 'v8_${entry.key}_classic_answer');
    }, timeout: const Timeout(Duration(seconds: 120)));
  }
  // ---- G4: изображения целиком (contain), без cover-обрезки ----
  List<(String name, int w, int h)> images = <(String, int, int)>[
    ('photo_960x720', 960, 720),
    ('tall_960x1371', 960, 1371),
    ('wide_1500x511', 1500, 511),
  ];
  for (final (String name, int w, int h) in images) {
    testWidgets('IMG $name', (WidgetTester tester) async {
      tester.view.devicePixelRatio = 1.0;
      tester.view.physicalSize = const Size(1707, 940);
      addTearDown(tester.view.reset);
      AppAdaptive.debugOverride = 1.24;
      addTearDown(() => AppAdaptive.debugOverride = null);
      await tester.pumpWidget(
        _imageHarness(scale: 1.24, textScale: 0.9, image: _patternPng(w, h)),
      );
      await tester.pumpAndSettle();
      // Тап по надзаголовку карточки, а не по картинке (иначе откроется
      // полноэкранный просмотр вместо раскрытия ответа).
      final Rect cardRect = tester.getRect(
        find.byKey(const ValueKey<String>('review-card')),
      );
      await tester.tapAt(cardRect.topLeft + const Offset(30, 40));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 320));
      await tester.pump(const Duration(milliseconds: 260));
      await tester.pump(const Duration(milliseconds: 100));
      // Декодирование PNG — реальная работа движка: даём ей пройти вне
      // fake-async, иначе в кадре останется скелетон.
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 400)),
      );
      await tester.pump();
      final Finder image = find.byKey(
        const ValueKey<String>('card-image-media-1'),
      );
      if (image.evaluate().isNotEmpty) {
        final Size size = tester.getSize(image);
        // ignore: avoid_print
        print(
          'IMAGE $name rendered=${size.width.toStringAsFixed(1)}x'
          '${size.height.toStringAsFixed(1)} ar='
          '${(size.width / size.height).toStringAsFixed(3)} '
          'source_ar=${(w / h).toStringAsFixed(3)}',
        );
      }
      await _shoot(tester, 'v8_img_$name');
    }, timeout: const Timeout(Duration(seconds: 120)));
  }
}
