// Финальный визуальный аудит CardFlow: рендер production-экранов сессии на
// точных логических размерах (4K/2K/FullHD/21:9/compact/mobile) с реальными
// шрифтами Inter/MaterialIcons, измерением геометрии и сохранением PNG.
//
// Run:
//   .fvm/versions/3.47.9/bin/flutter.bat test review_final/tools/render_card_test.dart --no-pub
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart' hide Card;

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/decks/deck_summary.dart';
import 'package:cardflow/domain/settings/app_settings.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/review/review_toolbar.dart';
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

Future<void> _loadFont(String family, String path) async {
  final Uint8List bytes = File(path).readAsBytesSync();
  final ByteData data = ByteData.view(bytes.buffer);
  final FontLoader loader = FontLoader(family)
    ..addFont(Future<ByteData>.value(data));
  await loader.load();
}

/// Конфигурация экрана: логический размер, адаптивный множитель, масштаб текста.
class Cfg {
  const Cfg(this.name, this.size, this.factor, this.textScale);
  final String name;
  final Size size;
  final double factor;
  final double textScale;
}

const List<Cfg> _configs = <Cfg>[
  Cfg('4k100', Size(3840, 2160), 1.45, 1.0),
  Cfg('4k150', Size(2560, 1440), 1.45, 1.0),
  Cfg('2k100', Size(2560, 1440), 1.24, 1.0),
  Cfg('2k150', Size(1706.7, 940), 1.24, 0.9),
  Cfg('fhd100', Size(1920, 1080), 1.0, 1.0),
  Cfg('fhd150', Size(1280, 720), 1.0, 0.9),
  Cfg('wuxga', Size(1280, 1024), 1.0, 1.0),
  Cfg('xga', Size(853.3, 682.7), 1.0, 1.0),
  Cfg('1680', Size(1120, 700), 1.0, 1.0),
  Cfg('1440', Size(960, 600), 1.0, 1.0),
  Cfg('1366', Size(910.7, 512), 1.0, 1.0),
  Cfg('1024', Size(682.7, 512), 1.0, 1.0),
  Cfg('800', Size(533.3, 400), 1.0, 1.0),
  Cfg('w21x9', Size(1706.7, 720), 1.11, 1.0),
  Cfg('m390', Size(390, 844), 1.0, 1.0),
  Cfg('m844', Size(844, 390), 1.0, 1.0),
];

final DateTime _now = DateTime.utc(2026, 11, 23, 12);

List<Card> _cards() => <Card>[
  makeCard(
    id: 'card-1',
    deckId: 'deck-1',
    front: 'Между какими проводниками действует линейное напряжение?',
    back: 'Между линейными проводами.',
    createdAt: _now,
    updatedAt: _now,
  ),
  makeCard(
    id: 'card-2',
    deckId: 'deck-1',
    front: 'Чему равно напряжение между нейтральным проводом и землёй?',
    back: 'Нулю в нормальном режиме.',
    createdAt: _now,
    updatedAt: _now,
  ),
  makeCard(
    id: 'card-3',
    deckId: 'deck-1',
    front: 'Сколько векторных диаграмм строят по результатам измерений?',
    back: 'Две: диаграмму токов и диаграмму напряжений.',
    createdAt: _now,
    updatedAt: _now,
  ),
];

List<DeckSummary> _summaries() => <DeckSummary>[
  makeSummary(
    id: 'deck-1',
    name: 'Электротехника',
    totalCards: 71,
    newCards: 9,
    inProgressCards: 59,
    dueCards: 60,
  ),
];

List<Override> _overrides(double textScale) => decksOverrides(
  deckRepository: FakeDeckRepository(summaries: _summaries()),
  cardRepository: FakeCardRepository(cards: _cards()),
  reviewRepository: FakeReviewRepository(),
  practiceRepository: FakePracticeRepository(),
  appSettingsStore: FakeAppSettingsStore(
    settings: AppSettings.defaults.copyWith(textScale: textScale),
  ),
);

Widget _app({
  required Cfg cfg,
  required String location,
  Brightness brightness = Brightness.light,
}) {
  final GlobalKey<NavigatorState> key = GlobalKey<NavigatorState>();
  final GoRouter router = createAppRouter(
    initialLocation: location,
    navigatorKey: key,
  );
  final ThemeData theme = brightness == Brightness.light
      ? AppTheme.light(scale: cfg.factor)
      : AppTheme.dark(scale: cfg.factor);
  return ProviderScope(
    overrides: _overrides(cfg.textScale),
    child: MaterialApp.router(
      debugShowCheckedModeBanner: false,
      locale: const Locale('ru'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: ruLocalizationDelegates,
      theme: theme,
      routerConfig: router,
      builder: (BuildContext context, Widget? child) {
        final MediaQueryData media = MediaQuery.of(context);
        return MediaQuery(
          data: media.copyWith(textScaler: TextScaler.linear(cfg.textScale)),
          child: child ?? const SizedBox.shrink(),
        );
      },
    ),
  );
}

Future<void> _pump(WidgetTester tester, Cfg cfg, String location) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = cfg.size;
  addTearDown(tester.view.reset);
  AppAdaptive.debugOverride = cfg.factor;
  addTearDown(() => AppAdaptive.debugOverride = null);
  await tester.pumpWidget(_app(cfg: cfg, location: location));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 450));
}

Future<void> _shoot(WidgetTester tester, String name) async {
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

double _textScale(WidgetTester tester, Finder within) {
  final MediaQueryData media = MediaQuery.of(tester.element(within));
  return media.textScaler.scale(1);
}

/// Прямоугольники текста/иконок/кнопок внутри карточки — для оценки пустоты.
List<Rect> _contentRects(WidgetTester tester, Finder cardFinder) {
  final List<Rect> rects = <Rect>[];
  void add(Finder f) {
    for (final Element e in f.evaluate()) {
      final RenderObject? ro = e.renderObject;
      if (ro is! RenderBox || !ro.hasSize || !ro.attached) continue;
      final Offset o = ro.localToGlobal(Offset.zero);
      final Rect r = o & ro.size;
      if (r.width < 1 || r.height < 1) continue;
      rects.add(r);
    }
  }

  add(find.descendant(of: cardFinder, matching: find.byType(RichText)));
  add(find.descendant(of: cardFinder, matching: find.byType(Image)));
  add(find.descendant(of: cardFinder, matching: find.byType(Divider)));
  add(find.descendant(of: cardFinder, matching: find.byType(FilledButton)));
  add(find.descendant(of: cardFinder, matching: find.byType(OutlinedButton)));
  add(find.descendant(of: cardFinder, matching: find.byType(TextButton)));
  return rects;
}

double _emptyShare(WidgetTester tester, Finder cardFinder, Rect card) {
  final List<Rect> rects = _contentRects(tester, cardFinder);
  if (rects.isEmpty) return 1;
  const double step = 3;
  int total = 0;
  int covered = 0;
  for (double y = card.top; y < card.bottom; y += step) {
    for (double x = card.left; x < card.right; x += step) {
      total++;
      for (final Rect r in rects) {
        if (r.contains(Offset(x, y))) {
          covered++;
          break;
        }
      }
    }
  }
  return total == 0 ? 1 : 1 - covered / total;
}

/// Вариант А (решение владельца): пустота = самая длинная сплошная полоса
/// карточки, в которой нет ни текста, ни кнопок, ни изображений.
///
/// Считается по строкам: строка «занята», если её пересекает хотя бы один
/// прямоугольник контента; ответ — максимальный вертикальный пробег пустых
/// строк / высоту карточки.
double _emptyBand(WidgetTester tester, Finder cardFinder, Rect card) {
  final List<Rect> rects = _contentRects(tester, cardFinder);
  if (rects.isEmpty || card.height <= 0) return 1;
  int best = 0;
  int run = 0;
  for (double y = card.top; y < card.bottom; y += 1) {
    bool covered = false;
    for (final Rect r in rects) {
      if (y >= r.top &&
          y < r.bottom &&
          r.right > card.left &&
          r.left < card.right) {
        covered = true;
        break;
      }
    }
    if (covered) {
      run = 0;
    } else {
      run++;
      if (run > best) best = run;
    }
  }
  return best / card.height;
}

void _measureCard(WidgetTester tester, Cfg cfg, String screen) {
  final Finder card = find.byKey(const ValueKey<String>('review-card'));
  if (card.evaluate().isEmpty) {
    // ignore: avoid_print
    print('MEAS $screen|${cfg.name}|card=absent');
    return;
  }
  final Rect r = tester.getRect(card);
  final MediaQueryData media = MediaQuery.of(tester.element(card));
  final double bodyH = media.size.height - AppSizes.headerHeight;
  final double empty = _emptyShare(tester, card, r);
  final double emptyBand = _emptyBand(tester, card, r);
  final Finder reveal = find.byKey(const ValueKey<String>('review-reveal'));
  final String revealText = reveal.evaluate().isEmpty
      ? 'none'
      : '${tester.getSize(reveal).width.toStringAsFixed(0)}x'
            '${tester.getSize(reveal).height.toStringAsFixed(0)}';
  final bool toolbar = find.byType(ReviewToolbar).evaluate().isNotEmpty;
  String rating = 'none';
  String gap = 'none';
  if (toolbar) {
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
        '${good.width.toStringAsFixed(0)}x${good.height.toStringAsFixed(0)}';
    gap = (hard.left - again.right).toStringAsFixed(0);
  }
  final double ts = _textScale(tester, card);
  final List<String> fonts = <String>[];
  for (final Element e
      in find
          .descendant(of: card, matching: find.byType(RichText))
          .evaluate()) {
    final RichText rt = e.widget as RichText;
    final double fs = (rt.text.style?.fontSize ?? 0) * ts;
    final String t = rt.text.toPlainText().replaceAll('\n', ' ');
    fonts.add(
      '${fs.toStringAsFixed(1)}:"${t.length > 26 ? '${t.substring(0, 26)}…' : t}"',
    );
  }
  // ignore: avoid_print
  print(
    'MEAS $screen|${cfg.name}|viewport=${media.size.width.toStringAsFixed(1)}x'
    '${media.size.height.toStringAsFixed(1)} factor=${cfg.factor} '
    'text=${cfg.textScale} card=${r.width.toStringAsFixed(0)}x'
    '${r.height.toStringAsFixed(0)} shareW=${(100 * r.width / media.size.width).toStringAsFixed(1)}% '
    'shareBodyH=${(100 * r.height / bodyH).toStringAsFixed(1)}% '
    'empty=${(100 * empty).toStringAsFixed(1)}% band=${(100 * emptyBand).toStringAsFixed(1)}% reveal=$revealText '
    'rating=$rating gap=$gap fonts=[${fonts.join(';')}]',
  );
}

void _measureGeneric(
  WidgetTester tester,
  Cfg cfg,
  String screen,
  List<String> keys,
) {
  final List<String> parts = <String>[];
  for (final String k in keys) {
    final Finder f = find.byKey(ValueKey<String>(k));
    if (f.evaluate().isEmpty) {
      parts.add('$k=absent');
      continue;
    }
    final Rect r = tester.getRect(f);
    parts.add(
      '$k=${r.width.toStringAsFixed(0)}x${r.height.toStringAsFixed(0)}'
      '@${r.left.toStringAsFixed(0)},${r.top.toStringAsFixed(0)}',
    );
  }
  // ignore: avoid_print
  print('RECT $screen|${cfg.name}|${parts.join(' ')}');
}

void _measureFonts(WidgetTester tester, Cfg cfg, String screen, Finder root) {
  final double ts = _textScale(tester, root);
  final Map<String, int> sizes = <String, int>{};
  for (final Element e
      in find
          .descendant(of: root, matching: find.byType(RichText))
          .evaluate()) {
    final RichText rt = e.widget as RichText;
    final double fs = (rt.text.style?.fontSize ?? 0) * ts;
    final String key = fs.toStringAsFixed(1);
    sizes[key] = (sizes[key] ?? 0) + 1;
  }
  final List<String> sorted = sizes.entries
      .map((MapEntry<String, int> e) => '${e.key}x${e.value}')
      .toList();
  // ignore: avoid_print
  print('FONTS $screen|${cfg.name}|${sorted.join(' ')}');
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

  Future<void> reveal(WidgetTester tester, String cardKey) async {
    await tester.tap(find.byKey(ValueKey<String>(cardKey)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 340));
    await tester.pump(const Duration(milliseconds: 280));
  }

  for (final Cfg cfg in _configs) {
    testWidgets('classic Q ${cfg.name}', (WidgetTester tester) async {
      await _pump(tester, cfg, '/decks/deck-1/study');
      _measureCard(tester, cfg, 'classicQ');
      _measureGeneric(tester, cfg, 'classicQ', <String>[
        'review-reveal',
        'review-rating-again',
        'review-rating-good',
        'review-close',
      ]);
      _measureFonts(tester, cfg, 'classicQ', find.byType(Scaffold).first);
      await _shoot(tester, 'card_classic_Q_${cfg.name}');
    }, timeout: const Timeout(Duration(seconds: 180)));

    testWidgets('classic A ${cfg.name}', (WidgetTester tester) async {
      await _pump(tester, cfg, '/decks/deck-1/study');
      await reveal(tester, 'review-card');
      _measureCard(tester, cfg, 'classicA');
      _measureGeneric(tester, cfg, 'classicA', <String>[
        'review-reveal',
        'review-rating-again',
        'review-rating-easy',
      ]);
      await _shoot(tester, 'card_classic_A_${cfg.name}');
    }, timeout: const Timeout(Duration(seconds: 180)));
  }

  // Лента: меньше конфигураций (та же площадь, другая вёрстка).
  for (final Cfg cfg in <Cfg>[
    _configs[3],
    _configs[5],
    _configs[7],
    _configs[9],
    _configs[10],
    _configs[11],
    _configs[13],
    _configs[14],
  ]) {
    testWidgets('feed Q ${cfg.name}', (WidgetTester tester) async {
      await _pump(tester, cfg, '/decks/deck-1/feed');
      await tester.pump(const Duration(milliseconds: 300));
      _measureCard(tester, cfg, 'feedQ');
      final Finder feedCard = find.descendant(
        of: find.byKey(const ValueKey<String>('feed-card-card-1')),
        matching: find.byKey(const ValueKey<String>('feed-swipe-transform')),
      );
      if (feedCard.evaluate().isNotEmpty) {
        final Rect r = tester.getRect(feedCard.first);
        // ignore: avoid_print
        print(
          'FEEDRECT feedQ|${cfg.name}|card=${r.width.toStringAsFixed(0)}x'
          '${r.height.toStringAsFixed(0)}@${r.left.toStringAsFixed(0)},'
          '${r.top.toStringAsFixed(0)} band='
          '${(100 * _emptyBand(tester, feedCard.first, r)).toStringAsFixed(1)}%',
        );
      }
      _measureGeneric(tester, cfg, 'feedQ', <String>[
        'feed-rate-hint',
        'feed-toolbar',
        'feed-pause',
      ]);
      await _shoot(tester, 'card_feed_Q_${cfg.name}');
    }, timeout: const Timeout(Duration(seconds: 180)));

    testWidgets('feed A ${cfg.name}', (WidgetTester tester) async {
      await _pump(tester, cfg, '/decks/deck-1/feed');
      await tester.pump(const Duration(milliseconds: 300));
      await reveal(tester, 'feed-swipe-transform');
      final Finder toolbar = find.byType(ReviewToolbar);
      if (toolbar.evaluate().isNotEmpty) {
        final Rect t = tester.getRect(toolbar.first);
        final Rect r = tester.getRect(
          find.byKey(const ValueKey<String>('review-rating-again')),
        );
        // ignore: avoid_print
        print(
          'FEEDTOOLBAR feedA|${cfg.name}|toolbar=${t.width.toStringAsFixed(0)}x'
          '${t.height.toStringAsFixed(0)}@${t.left.toStringAsFixed(0)},'
          '${t.top.toStringAsFixed(0)} again=${r.width.toStringAsFixed(0)}x'
          '${r.height.toStringAsFixed(0)}@${r.left.toStringAsFixed(0)}',
        );
      }
      _measureCard(tester, cfg, 'feedA');
      final Finder feedCard = find.descendant(
        of: find.byKey(const ValueKey<String>('feed-card-card-1')),
        matching: find.byKey(const ValueKey<String>('feed-swipe-transform')),
      );
      if (feedCard.evaluate().isNotEmpty) {
        final Rect r = tester.getRect(feedCard.first);
        // ignore: avoid_print
        print(
          'FEEDRECT feedA|${cfg.name}|card=${r.width.toStringAsFixed(0)}x'
          '${r.height.toStringAsFixed(0)} band='
          '${(100 * _emptyBand(tester, feedCard.first, r)).toStringAsFixed(1)}%',
        );
      }
      await _shoot(tester, 'card_feed_A_${cfg.name}');
    }, timeout: const Timeout(Duration(seconds: 180)));
  }

  // Тёмная тема карточки — 2K live.
  testWidgets('classic A dark 2k150', (WidgetTester tester) async {
    final Cfg cfg = _configs[3];
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = cfg.size;
    addTearDown(tester.view.reset);
    AppAdaptive.debugOverride = cfg.factor;
    addTearDown(() => AppAdaptive.debugOverride = null);
    await tester.pumpWidget(
      _app(
        cfg: cfg,
        location: '/decks/deck-1/study',
        brightness: Brightness.dark,
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 450));
    await reveal(tester, 'review-card');
    _measureCard(tester, cfg, 'classicA-dark');
    await _shoot(tester, 'card_classic_A_dark_2k150');
  }, timeout: const Timeout(Duration(seconds: 180)));
}
