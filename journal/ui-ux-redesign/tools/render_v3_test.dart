// Визуальная приёмка редизайна v3 (ADR-044/045): production-экраны на
// эталонных размерах в реальных шрифтах, светлая и тёмная темы.
//
// Run:
//   .fvm/versions/3.47.9/bin/flutter.bat test journal/ui-ux-redesign/tools/render_v3_test.dart --no-pub
//
// Пишет PNG в journal/ui-ux-redesign/screenshots/. Файлы проекта не меняет,
// данные владельца не используются (только фейковый data-слой тестов).
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
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/router/app_router.dart';
import 'package:cardflow/ui/theme/app_theme.dart';
import 'package:cardflow/ui/theme/app_tokens.dart';

import '../../../test/helpers/decks_fakes.dart';
import '../../../test/helpers/pump_app.dart'
    show appBuilderWith, decksOverrides, ruLocalizationDelegates;
import '../../../test/helpers/review_fakes.dart';

const String _assets = 'build/windows/x64/runner/Release/data/flutter_assets';
const String _outDir = 'journal/ui-ux-redesign/screenshots';

Future<void> _loadFont(String family, String path) async {
  final Uint8List bytes = File(path).readAsBytesSync();
  final ByteData data = ByteData.view(bytes.buffer);
  final FontLoader loader = FontLoader(family)
    ..addFont(Future<ByteData>.value(data));
  await loader.load();
}

class Cfg {
  const Cfg(this.name, this.size, this.factor);
  final String name;
  final Size size;
  final double factor;
}

const Cfg _c2k = Cfg('2k', Size(1706.7, 940), 1.24);
const Cfg _cFhd = Cfg('fhd', Size(1280, 720), 1.0);
const Cfg _cMobile = Cfg('m390', Size(390, 844), 1.0);
const Cfg _cNarrow = Cfg('m260', Size(260, 562), 1.0);

final DateTime _now = DateTime.utc(2026, 11, 24, 12);

List<Card> _cards() => <Card>[
  makeCard(
    id: 'card-1',
    deckId: 'deck-1',
    front: 'Что такое электрический ток?',
    back: 'Направленное движение заряженных частиц под действием электрического поля.',
    createdAt: _now.subtract(const Duration(days: 3)),
  ),
  makeCard(
    id: 'card-2',
    deckId: 'deck-1',
    front: 'Единица измерения напряжения в системе СИ',
    back:
        'Вольт (В) — разность потенциалов, при которой работа 1 Дж совершается '
        'переносом заряда 1 Кл.',
    createdAt: _now.subtract(const Duration(days: 2)),
  ),
  makeCard(
    id: 'card-3',
    deckId: 'deck-1',
    front: 'Закон Ома для участка цепи',
    back:
        'Сила тока прямо пропорциональна напряжению и обратно пропорциональна '
        'сопротивлению участка: I = U / R.',
    createdAt: _now.subtract(const Duration(days: 2)),
  ),
  makeCard(
    id: 'card-4',
    deckId: 'deck-1',
    front: 'Что показывает амперметр и как он включается?',
    back:
        'Силу тока. Включается последовательно с участком цепи; внутреннее '
        'сопротивление должно быть малым.',
    createdAt: _now.subtract(const Duration(days: 1)),
  ),
  makeCard(
    id: 'card-5',
    deckId: 'deck-1',
    front: 'Мощность постоянного тока',
    back: 'P = U · I = I² · R = U² / R. Единица — ватт (Вт).',
    createdAt: _now.subtract(const Duration(hours: 12)),
  ),
  makeCard(
    id: 'card-6',
    deckId: 'deck-1',
    front: 'Первый закон Кирхгофа',
    back: 'Алгебраическая сумма токов в узле электрической цепи равна нулю.',
    createdAt: _now.subtract(const Duration(hours: 6)),
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
  makeSummary(
    id: 'deck-2',
    name: 'История России',
    totalCards: 134,
    newCards: 100,
    inProgressCards: 34,
    dueCards: 33,
  ),
  makeSummary(
    id: 'deck-3',
    name: 'Английские фразовые глаголы',
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
    inProgressCards: 20,
    dueCards: 2,
  ),
];

List<Override> _overrides() => decksOverrides(
  deckRepository: FakeDeckRepository(summaries: _summaries()),
  cardRepository: FakeCardRepository(cards: _cards()),
  reviewRepository: FakeReviewRepository(),
);

Widget _app(Cfg cfg, String location, Brightness brightness) {
  final GlobalKey<NavigatorState> key = GlobalKey<NavigatorState>();
  return ProviderScope(
    overrides: _overrides(),
    child: MaterialApp.router(
      debugShowCheckedModeBanner: false,
      locale: const Locale('ru'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: ruLocalizationDelegates,
      theme: brightness == Brightness.light
          ? AppTheme.light(scale: cfg.factor)
          : AppTheme.dark(scale: cfg.factor),
      routerConfig: createAppRouter(
        initialLocation: location,
        navigatorKey: key,
      ),
      builder: (BuildContext context, Widget? child) =>
          appBuilderWith(context, child, key),
    ),
  );
}

Future<void> _pump(
  WidgetTester tester,
  Cfg cfg,
  String location, {
  Brightness brightness = Brightness.light,
}) async {
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = cfg.size;
  addTearDown(tester.view.reset);
  AppAdaptive.debugOverride = cfg.factor;
  addTearDown(() => AppAdaptive.debugOverride = null);
  await tester.pumpWidget(_app(cfg, location, brightness));
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 600));
  await tester.pumpAndSettle();
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

void main() {
  setUpAll(() async {
    await _loadFont('Inter', '$_assets/assets/fonts/Inter-Variable.ttf');
    await _loadFont(
      'MaterialIcons',
      // Полный шрифт из SDK: subset собранных ассетов не содержит новые глифы.
      '.fvm/versions/3.47.9/bin/cache/artifacts/material_fonts/materialicons-regular.otf',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(SystemChannels.platform, (
          MethodCall call,
        ) async {
          return null;
        });
  });

  testWidgets('v3: колоды/колода/классика/лента на 2K, FullHD, mobile', (
    WidgetTester tester,
  ) async {
    // Колоды и фильтры (счётчики в чипах — новая композиция).
    await _pump(tester, _c2k, AppRoutes.decksPath);
    await _shoot(tester, '01_decks_2k_light');
    await tester.tap(find.byKey(const ValueKey<String>('decks-filter-due')));
    await tester.pumpAndSettle();
    await _shoot(tester, '02_decks_filter_due_2k_light');
    await tester.tap(find.byKey(const ValueKey<String>('decks-filter-all')));
    await tester.pumpAndSettle();

    // Поиск с фокусом (кнопка «Найти колоду»).
    await tester.tap(find.byKey(const ValueKey<String>('shell-search-action')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 120));
    await tester.enterText(
      find.byKey(const ValueKey<String>('decks-search-field')),
      'Электр',
    );
    await tester.pumpAndSettle();
    await _shoot(tester, '03_decks_search_2k_light');

    // Колода.
    await _pump(tester, _c2k, '/decks/deck-1');
    await _shoot(tester, '04_deck_2k_light');

    // Классика: вопрос и ответ с новыми кнопками оценок.
    await _pump(tester, _c2k, '/decks/deck-1/study');
    await _shoot(tester, '05_classic_question_2k_light');
    await tester.tap(find.byKey(const ValueKey<String>('review-card')));
    await tester.pumpAndSettle();
    await _shoot(tester, '06_classic_answer_2k_light');

    // Лента: вопрос/ответ и вторая карточка.
    await _pump(tester, _c2k, '/decks/deck-1/feed');
    await _shoot(tester, '07_feed_question_2k_light');
    await tester.tap(find.text('Что такое электрический ток?'));
    await tester.pumpAndSettle();
    await _shoot(tester, '08_feed_answer_2k_light');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    await _shoot(tester, '09_feed_next_2k_light');

    // Тёмная тема: лента и классика.
    await _pump(
      tester,
      _c2k,
      '/decks/deck-1/feed',
      brightness: Brightness.dark,
    );
    await _shoot(tester, '10_feed_question_2k_dark');
    await tester.tap(find.text('Что такое электрический ток?'));
    await tester.pumpAndSettle();
    await _shoot(tester, '11_feed_answer_2k_dark');
    await _pump(
      tester,
      _c2k,
      '/decks/deck-1/study',
      brightness: Brightness.dark,
    );
    await tester.tap(find.byKey(const ValueKey<String>('review-card')));
    await tester.pumpAndSettle();
    await _shoot(tester, '12_classic_answer_2k_dark');

    // Mobile: колоды, лента, классика.
    await _pump(tester, _cMobile, AppRoutes.decksPath);
    await _shoot(tester, '13_decks_m390_light');
    await _pump(tester, _cMobile, '/decks/deck-1/feed');
    await _shoot(tester, '14_feed_m390_light');
    await tester.tap(find.text('Что такое электрический ток?'));
    await tester.pumpAndSettle();
    await _shoot(tester, '15_feed_answer_m390_light');
    await _pump(tester, _cMobile, '/decks/deck-1/study');
    await tester.tap(find.byKey(const ValueKey<String>('review-card')));
    await tester.pumpAndSettle();
    await _shoot(tester, '16_classic_answer_m390_light');

    // FullHD и очень низкое окно — проверка отсутствия переполнений.
    await _pump(tester, _cFhd, '/decks/deck-1/feed');
    await _shoot(tester, '17_feed_fhd_light');
    await _pump(tester, _cNarrow, '/decks/deck-1/feed');
    await tester.tap(find.byType(GestureDetector).first);
    await tester.pumpAndSettle();
    await _shoot(tester, '18_feed_m260_light');
    expect(tester.takeException(), isNull);
  });
}
