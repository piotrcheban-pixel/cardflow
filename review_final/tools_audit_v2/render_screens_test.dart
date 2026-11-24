// Финальный визуальный аудит: рендер основных экранов CardFlow на точных
// размерах + измерения (ширины, отступы, размеры шрифтов, кнопок).
//
// Run:
//   .fvm/versions/3.47.9/bin/flutter.bat test review_final/tools/render_screens_test.dart --no-pub
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
import 'package:cardflow/ui/components/app_layout.dart';
import 'package:cardflow/ui/router/app_router.dart';
import 'package:cardflow/ui/theme/app_theme.dart';
import 'package:cardflow/ui/theme/app_tokens.dart';

import '../../test/helpers/decks_fakes.dart';
import '../../test/helpers/pump_app.dart'
    show decksOverrides, ruLocalizationDelegates;
import '../../test/helpers/review_fakes.dart';
import '../../test/helpers/session_fakes.dart';
import '../../test/helpers/settings_fakes.dart';

const String _assets = 'build/windows/x64/runner/Debug/data/flutter_assets';
const String _outDir = 'review_final/screenshots/audit_v2/rendered';

Future<void> _loadFont(String family, String path) async {
  final Uint8List bytes = File(path).readAsBytesSync();
  final ByteData data = ByteData.view(bytes.buffer);
  final FontLoader loader = FontLoader(family)
    ..addFont(Future<ByteData>.value(data));
  await loader.load();
}

class Cfg {
  const Cfg(this.name, this.size, this.factor, this.textScale);
  final String name;
  final Size size;
  final double factor;
  final double textScale;
}

const Cfg _c2k = Cfg('2k150', Size(1706.7, 940), 1.24, 0.9);
const Cfg _c800 = Cfg('800', Size(533.3, 400), 1.0, 1.0);
const Cfg _cm390 = Cfg('m390', Size(390, 844), 1.0, 1.0);
const Cfg _cm844 = Cfg('m844', Size(844, 390), 1.0, 1.0);
const Cfg _cfhd100 = Cfg('fhd100', Size(1920, 1080), 1.0, 1.0);
const Cfg _cw1680 = Cfg('w1680', Size(1680, 1050), 1.0, 1.0);
const Cfg _cw1440 = Cfg('w1440', Size(1440, 900), 1.0, 1.0);
const Cfg _cw1366 = Cfg('w1366', Size(1366, 768), 1.0, 1.0);
const Cfg _cwuxga = Cfg('wuxga', Size(1280, 1024), 1.0, 1.0);
const Cfg _cw21x9 = Cfg('w21x9', Size(2560, 1080), 1.0, 1.0);

final DateTime _now = DateTime.utc(2026, 11, 23, 12);

List<DeckSummary> _summaries() => <DeckSummary>[
  makeSummary(
    id: 'deck-1',
    name: 'Электротехника',
    totalCards: 71,
    newCards: 9,
    inProgressCards: 59,
    dueCards: 60,
  ),
  makeSummary(
    id: 'deck-2',
    name: 'Тест фигни',
    totalCards: 134,
    newCards: 100,
    inProgressCards: 34,
    dueCards: 33,
  ),
  makeSummary(
    id: 'deck-3',
    name: 'ЛРЗ_Трехфазная_цепь_звездой_заполненная',
    totalCards: 40,
    newCards: 18,
    inProgressCards: 18,
    dueCards: 22,
  ),
  makeSummary(
    id: 'deck-4',
    name: 'Вопросы для подготовки',
    totalCards: 30,
    newCards: 7,
    inProgressCards: 16,
    dueCards: 16,
  ),
  makeSummary(
    id: 'deck-5',
    name: 'Кинематика',
    totalCards: 15,
    newCards: 0,
    inProgressCards: 15,
    dueCards: 15,
  ),
  makeSummary(
    id: 'deck-6',
    name: 'Эл тех',
    totalCards: 13,
    newCards: 1,
    inProgressCards: 11,
    dueCards: 11,
  ),
];

List<Card> _cards() => <Card>[
  for (int i = 1; i <= 8; i++)
    makeCard(
      id: 'card-$i',
      deckId: 'deck-1',
      front: i == 1
          ? 'Чему равен ток нейтрального провода при симметричной активной нагрузке фаз?'
          : 'Вопрос $i по электротехнике: как определяется линейное напряжение?',
      back: 'Ответ $i: между линейными проводами.',
      tags: const <String>['#трёхфазные цепи', '#нейтраль'],
      state: i.isEven ? CardState.review : CardState.newCard,
      createdAt: _now,
      updatedAt: _now,
    ),
];

List<Override> _overrides(double textScale) => decksOverrides(
  deckRepository: FakeDeckRepository(summaries: _summaries()),
  cardRepository: FakeCardRepository(cards: _cards()),
  reviewRepository: FakeReviewRepository(),
  practiceRepository: FakePracticeRepository(),
  sessionPresetRepository: FakeSessionPresetRepository(),
  leechRepository: FakeLeechRepository(),
  appSettingsStore: FakeAppSettingsStore(
    settings: AppSettings.defaults.copyWith(textScale: textScale),
  ),
);

Widget _app(Cfg cfg, String location, {Brightness brightness = Brightness.light}) {
  final GlobalKey<NavigatorState> key = GlobalKey<NavigatorState>();
  return ProviderScope(
    overrides: _overrides(cfg.textScale),
    child: MaterialApp.router(
      debugShowCheckedModeBanner: false,
      locale: const Locale('ru'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: ruLocalizationDelegates,
      theme: brightness == Brightness.light
          ? AppTheme.light(scale: cfg.factor)
          : AppTheme.dark(scale: cfg.factor),
      routerConfig: createAppRouter(initialLocation: location, navigatorKey: key),
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

Future<void> _pump(WidgetTester tester, Cfg cfg, String location,
    {Brightness brightness = Brightness.light}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = cfg.size;
  addTearDown(tester.view.reset);
  AppAdaptive.debugOverride = cfg.factor;
  addTearDown(() => AppAdaptive.debugOverride = null);
  await tester.pumpWidget(_app(cfg, location, brightness: brightness));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 500));
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

void _rects(WidgetTester tester, Cfg cfg, String screen, List<String> keys) {
  final List<String> parts = <String>[];
  for (final String k in keys) {
    final Finder f = find.byKey(ValueKey<String>(k));
    if (f.evaluate().isEmpty) {
      parts.add('$k=absent');
      continue;
    }
    final Rect r = tester.getRect(f.first);
    parts.add('$k=${r.width.toStringAsFixed(0)}x${r.height.toStringAsFixed(0)}'
        '@${r.left.toStringAsFixed(0)},${r.top.toStringAsFixed(0)}');
  }
  // ignore: avoid_print
  print('RECT $screen|${cfg.name}|${parts.join(' ')}');
}

void _fonts(WidgetTester tester, Cfg cfg, String screen, Finder root) {
  final MediaQueryData media = MediaQuery.of(tester.element(root));
  final double ts = media.textScaler.scale(1);
  final Map<String, int> sizes = <String, int>{};
  for (final Element e in find
      .descendant(of: root, matching: find.byType(RichText))
      .evaluate()) {
    final RichText rt = e.widget as RichText;
    final String key = ((rt.text.style?.fontSize ?? 0) * ts).toStringAsFixed(1);
    sizes[key] = (sizes[key] ?? 0) + 1;
  }
  // ignore: avoid_print
  print('FONTS $screen|${cfg.name}|'
      '${sizes.entries.map((MapEntry<String, int> e) => '${e.key}x${e.value}').join(' ')}');
  // Ширина контентной колонки относительно окна (V2/V10).
  final List<String> widths = <String>[];
  for (final Element e in find.byType(AppContentWidth).evaluate()) {
    final Element? inner = find
        .descendant(
          of: find.byElementPredicate((Element x) => x == e),
          matching: find.byType(ConstrainedBox),
        )
        .evaluate()
        .firstOrNull;
    final RenderObject? ro = inner?.renderObject;
    if (ro is! RenderBox || !ro.hasSize || ro.size.width < 1) continue;
    final Offset o = ro.localToGlobal(Offset.zero);
    widths.add('${ro.size.width.toStringAsFixed(0)}@${o.dx.toStringAsFixed(0)}');
  }
  // ignore: avoid_print
  print('PAGE $screen|${cfg.name}|viewport=${media.size.width.toStringAsFixed(0)} '
      'columns=${widths.take(3).join(',')} '
      'share=${widths.isEmpty ? 'n/a' : (100 * double.parse(widths.first.split('@').first) / media.size.width).toStringAsFixed(1)}%');
}

void _overflowCheck(WidgetTester tester, Cfg cfg, String screen) {
  final List<String> issues = <String>[];
  for (final Element e in find.byType(RichText).evaluate()) {
    final RichText rt = e.widget as RichText;
    final RenderParagraph rp = e.renderObject! as RenderParagraph;
    if (rp.didExceedMaxLines) {
      final String t = rt.text.toPlainText();
      issues.add(t.length > 20 ? t.substring(0, 20) : t);
    }
  }
  // ignore: avoid_print
  print('OVERFLOW $screen|${cfg.name}|${issues.isEmpty ? 'none' : issues.join(';')}');
}

void _chipAndButtonAudit(WidgetTester tester, Cfg cfg, String screen) {
  final List<String> small = <String>[];
  for (final Element e in find
      .byWidgetPredicate((Widget w) =>
          w is FilledButton ||
          w is OutlinedButton ||
          w is TextButton ||
          w is IconButton ||
          w is SegmentedButton)
      .evaluate()) {
    final RenderBox box = e.renderObject! as RenderBox;
    if (!box.hasSize) continue;
    final Size s = box.size;
    if (s.height < 44 && s.height > 0) {
      small.add('${e.widget.runtimeType}:'
          '${s.width.toStringAsFixed(0)}x${s.height.toStringAsFixed(0)}');
    }
  }
  // ignore: avoid_print
  print('SMALLBTN $screen|${cfg.name}|${small.isEmpty ? 'none' : small.join(';')}');
}

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

  tearDownAll(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, null);
  });

  const Map<String, String> screens = <String, String>{
    'decks': '/',
    'deck': '/decks/deck-1',
    'settings': '/settings',
    'statistics': '/statistics',
    'generation': '/generate',
    'constructor': '/constructor',
    'test': '/decks/deck-1/test',
    'typing': '/decks/deck-1/typing',
    'match': '/decks/deck-1/match',
    'truefalse': '/decks/deck-1/true-false',
    'cardform': '/decks/deck-1/cards/new',
    'practice': '/decks/deck-1/practice',
  };

  for (final Cfg cfg in <Cfg>[_cfhd100, _cw1680, _cw1440, _cw1366, _cwuxga, _cw21x9]) {
    for (final MapEntry<String, String> entry in screens.entries) {
      // На очень мелких размерах достаточно ключевых экранов.
      if ((cfg == _c800 || cfg == _cm844) &&
          !<String>['decks', 'deck', 'test', 'settings', 'generation']
              .contains(entry.key)) {
        continue;
      }
      if (cfg == _cm390 &&
          !<String>['decks', 'deck', 'test', 'settings', 'statistics']
              .contains(entry.key)) {
        continue;
      }
      testWidgets('${entry.key} ${cfg.name}', (WidgetTester tester) async {
        await _pump(tester, cfg, entry.value);
        _fonts(tester, cfg, entry.key, find.byType(Scaffold).first);
        _overflowCheck(tester, cfg, entry.key);
        _chipAndButtonAudit(tester, cfg, entry.key);
        _rects(tester, cfg, entry.key, <String>[
          'decks-kpi-total',
          'decks-new-deck',
          'decks-import',
          'deck-start-session',
          'deck-add-card-button',
          'review-mode-classic',
        ]);
        await _shoot(tester, 'screen_${entry.key}_${cfg.name}');
      }, timeout: const Timeout(Duration(seconds: 180)));
    }
  }

  // Диалоги и листы: выхода из сессии, режимов, удаления колоды.
  testWidgets('exit dialog 2k', (WidgetTester tester) async {
    await _pump(tester, _c2k, '/decks/deck-1/study');
    await tester.tap(find.byKey(const ValueKey<String>('review-close')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 350));
    _rects(tester, _c2k, 'exitDialog', <String>[
      'review-exit-confirm',
      'review-exit-cancel',
    ]);
    _fonts(tester, _c2k, 'exitDialog', find.byType(Dialog).first);
    await _shoot(tester, 'screen_exit_dialog_2k150');
  }, timeout: const Timeout(Duration(seconds: 180)));

  testWidgets('modes sheet 2k', (WidgetTester tester) async {
    await _pump(tester, _c2k, '/decks/deck-1');
    await tester.tap(find.byKey(const ValueKey<String>('deck-start-session')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    _rects(tester, _c2k, 'modesSheet', <String>[
      'review-mode-classic',
      'review-mode-feed',
      'review-mode-practice',
      'review-mode-test',
      'review-mode-typing',
      'review-mode-match',
      'review-mode-true-false',
      'review-mode-constructor',
    ]);
    await _shoot(tester, 'screen_modes_sheet_2k150');
  }, timeout: const Timeout(Duration(seconds: 180)));

  testWidgets('delete deck dialog 2k', (WidgetTester tester) async {
    await _pump(tester, _c2k, '/decks/deck-1');
    await tester.tap(find.byKey(const ValueKey<String>('deck-overflow-menu')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await _shoot(tester, 'screen_deck_overflow_2k150');
  }, timeout: const Timeout(Duration(seconds: 180)));

  // Светлая/тёмная темы основного экрана — цельность палитры.
  testWidgets('decks dark 2k', (WidgetTester tester) async {
    await _pump(tester, _c2k, '/', brightness: Brightness.dark);
    await _shoot(tester, 'screen_decks_dark_2k150');
  }, timeout: const Timeout(Duration(seconds: 180)));

  testWidgets('settings appearance dark 2k', (WidgetTester tester) async {
    await _pump(tester, _c2k, '/settings', brightness: Brightness.dark);
    await _shoot(tester, 'screen_settings_dark_2k150');
  }, timeout: const Timeout(Duration(seconds: 180)));
}
