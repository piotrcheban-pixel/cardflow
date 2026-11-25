// Скриншот-харнесс для визуальной проверки правок аудита 2.0.
//
// Рендерит ключевые экраны в точных логических размерах и сохраняет PNG в
// `work/shots/`. Запуск:
//   fvm flutter test tool/screenshots/audit2_test.dart --no-pub
// Шрифты (Inter, MaterialIcons) подкладываются из собранных flutter_assets —
// иначе кириллица рендерится квадратами.
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:material_ui/material_ui.dart' hide Card;

import 'package:cardflow/domain/cards/card.dart' as domain;
import 'package:cardflow/domain/decks/deck_summary.dart';
import 'package:cardflow/domain/statistics/statistics.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/review/review_toolbar.dart';
import 'package:cardflow/ui/review/session_card.dart';
import 'package:cardflow/ui/theme/app_theme.dart';

import '../../test/helpers/decks_fakes.dart';
import '../../test/helpers/pump_app.dart'
    show appWithAppRouter, decksOverrides, ruLocalizationDelegates;
import '../../test/helpers/review_fakes.dart';
import '../../test/helpers/settings_fakes.dart';

const String _assetDir = 'build/windows/x64/runner/Debug/data/flutter_assets';

Future<void> _loadFonts() async {
  Future<void> load(String family, String path) async {
    final File file = File(path);
    if (!file.existsSync()) return;
    final Uint8List bytes = file.readAsBytesSync();
    final FontLoader loader = FontLoader(family)
      ..addFont(Future<ByteData>.value(ByteData.view(bytes.buffer)));
    await loader.load();
  }

  await load('Inter', 'assets/fonts/Inter-Variable.ttf');
  await load('MaterialIcons', '$_assetDir/fonts/MaterialIcons-Regular.otf');
}

Future<void> _shoot(WidgetTester tester, String name) async {
  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('goldens/$name.png'),
  );
}

void main() {
  final Uint8List landscape = Uint8List.fromList(
    img.encodePng(img.Image(width: 800, height: 450)),
  );

  setUpAll(() async {
    await _loadFonts();
  });

  Future<void> pumpAt(WidgetTester tester, Size size) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = size;
    addTearDown(tester.view.reset);
  }

  Widget cardHarness({
    required String front,
    required String back,
    required bool revealed,
    String? mediaId,
    bool withRatings = true,
  }) {
    final domain.Card card = makeCard(
      id: 'card-1',
      deckId: 'deck-1',
      front: front,
      back: back,
      questionMediaIds: mediaId == null ? const <String>[] : <String>[mediaId],
    );
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      locale: const Locale('ru'),
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: ruLocalizationDelegates,
      theme: AppTheme.light(),
      home: Scaffold(
        backgroundColor: AppTheme.light().colorScheme.surface,
        body: SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: SessionCard(
              front: front,
              back: back,
              card: card,
              mediaBytes: mediaId == null
                  ? const <String, Uint8List>{}
                  : <String, Uint8List>{mediaId: landscape},
              revealed: revealed,
              onTap: () {},
              questionFooter: FilledButton(
                onPressed: () {},
                child: const Text('Показать ответ'),
              ),
              answerFooter: withRatings
                  ? ReviewToolbar(enabled: true, onRating: (dynamic _) {})
                  : null,
            ),
          ),
        ),
      ),
    );
  }

  testWidgets('карточка: вопрос с картинкой, 1280×720', (
    WidgetTester tester,
  ) async {
    await pumpAt(tester, const Size(1280, 720));
    await tester.pumpWidget(
      cardHarness(
        front:
            'Как называют свойство теста измерять именно ту характеристику, '
            'для которой он создан, и насколько устойчивы результаты '
            'при повторных измерениях?',
        back: 'Валидность — соответствие теста измеряемому свойству.',
        revealed: false,
        mediaId: 'media-q',
      ),
    );
    await tester.pumpAndSettle();
    await _shoot(tester, 'card_front_1280');
  });

  testWidgets('карточка: ответ с оценками, 1280×720', (
    WidgetTester tester,
  ) async {
    await pumpAt(tester, const Size(1280, 720));
    await tester.pumpWidget(
      cardHarness(
        front: 'Что такое валидность теста?',
        back:
            'Валидность — это соответствие теста тому свойству, которое он '
            'измеряет, и устойчивость результатов при повторных измерениях. '
            'Различают содержательную, конструктную и критериальную валидность.',
        revealed: true,
      ),
    );
    await tester.pumpAndSettle();
    await _shoot(tester, 'card_back_1280');
  });

  testWidgets('карточка: ответ на телефоне 390×844', (
    WidgetTester tester,
  ) async {
    await pumpAt(tester, const Size(390, 844));
    await tester.pumpWidget(
      cardHarness(
        front: 'Что такое трёхфазная цепь?',
        back:
            'Совокупность трёх однофазных цепей с тремя синусоидальными ЭДС '
            'одинаковой частоты и амплитуды, сдвинутыми по фазе на 120 градусов. '
            'Такая система ЭДС создаёт вращающееся магнитное поле, которое и '
            'приводит во вращение ротор двигателя.',
        revealed: true,
      ),
    );
    await tester.pumpAndSettle();
    await _shoot(tester, 'card_back_390');
  });

  List<Override> overrides({List<DeckSummary>? summaries}) {
    // Фейк отдаёт снимок карточки в токене undo — иначе запись оценки падает и
    // режимы показывают снекбар ошибки вместо фидбека.
    final FakeReviewRepository reviews = FakeReviewRepository()
      ..previousCard = _cards().first;
    return decksOverrides(
      deckRepository: FakeDeckRepository(summaries: summaries ?? _summaries()),
      cardRepository: FakeCardRepository(cards: _cards()),
      reviewRepository: reviews,
    );
  }

  testWidgets('колоды: сетка 1280×720', (WidgetTester tester) async {
    await pumpAt(tester, const Size(1280, 720));
    await tester.pumpWidget(
      appWithAppRouter(overrides: overrides(), initialLocation: '/'),
    );
    await tester.pumpAndSettle();
    await _shoot(tester, 'decks_grid_1280');
  });

  testWidgets('колоды: список 1280×720', (WidgetTester tester) async {
    await pumpAt(tester, const Size(1280, 720));
    await tester.pumpWidget(
      appWithAppRouter(overrides: overrides(), initialLocation: '/'),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const ValueKey<String>('decks-view-list')));
    await tester.pumpAndSettle();
    await _shoot(tester, 'decks_list_1280');
  });

  testWidgets('экран колоды 1280×720', (WidgetTester tester) async {
    await pumpAt(tester, const Size(1280, 720));
    await tester.pumpWidget(
      appWithAppRouter(
        overrides: overrides(),
        initialLocation: '/decks/deck-1',
      ),
    );
    await tester.pumpAndSettle();
    await _shoot(tester, 'deck_1280');
  });

  testWidgets('настройки: телефон 390×844', (WidgetTester tester) async {
    await pumpAt(tester, const Size(390, 844));
    await tester.pumpWidget(
      appWithAppRouter(overrides: overrides(), initialLocation: '/settings'),
    );
    await tester.pumpAndSettle();
    await _shoot(tester, 'settings_390');
  });

  testWidgets('тест: отвеченный вопрос 1280×720', (WidgetTester tester) async {
    await pumpAt(tester, const Size(1280, 720));
    await tester.pumpWidget(
      appWithAppRouter(
        overrides: overrides(),
        initialLocation: '/decks/deck-1/test',
      ),
    );
    await tester.pumpAndSettle();
    // Первый вариант — фиксированный ответ, показывает текстовый фидбек
    // (если вариантов нет, кадр фиксирует пустое состояние — это тоже сигнал).
    final Finder option = find.byKey(const ValueKey<String>('study-option-0'));
    if (option.evaluate().isNotEmpty) {
      await tester.tap(option);
      await tester.pumpAndSettle();
    }
    await _shoot(tester, 'test_answered_1280');
  });

  testWidgets('статистика 1280×720', (WidgetTester tester) async {
    await pumpAt(tester, const Size(1280, 720));
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    final StatisticsSnapshot snapshot = StatisticsCalculator.build(
      reviews: <ReviewSample>[
        for (int day = 0; day < 120; day++)
          for (int count = 0; count < 1 + day % 4; count++)
            ReviewSample(
              cardId: 'card-${day % 7}',
              rating: count % 5 == 0 ? 1 : 3,
              reviewedAt: today.subtract(Duration(days: day)),
            ),
      ],
      tagsByCard: <String, List<String>>{
        for (int i = 0; i < 7; i++)
          'card-$i': <String>[i.isEven ? 'электротехника' : 'теория'],
      },
      dueDates: <DateTime>[today, today.add(const Duration(days: 1))],
      now: today.add(const Duration(hours: 12)),
    );
    await tester.pumpWidget(
      appWithAppRouter(
        overrides: decksOverrides(
          deckRepository: FakeDeckRepository(summaries: _summaries()),
          cardRepository: FakeCardRepository(cards: _cards()),
          reviewRepository: FakeReviewRepository(),
          statisticsRepository: FakeStatisticsRepository(snapshot: snapshot),
        ),
        initialLocation: '/statistics',
      ),
    );
    await tester.pumpAndSettle();
    await _shoot(tester, 'statistics_1280');
  });

  /// Данные статистики: 120 дней повторений и прогноз на неделю.
  StatisticsSnapshot statisticsSnapshot() {
    final DateTime now = DateTime.now();
    final DateTime today = DateTime(now.year, now.month, now.day);
    return StatisticsCalculator.build(
      reviews: <ReviewSample>[
        for (int day = 0; day < 120; day++)
          for (int count = 0; count < 1 + day % 4; count++)
            ReviewSample(
              cardId: 'card-${day % 7}',
              rating: count % 5 == 0 ? 1 : 3,
              reviewedAt: today.subtract(Duration(days: day)),
            ),
      ],
      tagsByCard: <String, List<String>>{
        for (int i = 0; i < 7; i++)
          'card-$i': <String>[i.isEven ? 'электротехника' : 'теория'],
      },
      dueDates: <DateTime>[
        today,
        today.add(const Duration(days: 1, hours: 9)),
        today.add(const Duration(days: 2, hours: 18)),
        today.add(const Duration(days: 3, hours: 9)),
        today.add(const Duration(days: 5, hours: 12)),
      ],
      now: today.add(const Duration(hours: 12)),
    );
  }

  Future<void> pumpStatistics(WidgetTester tester, Size size) async {
    await pumpAt(tester, size);
    await tester.pumpWidget(
      appWithAppRouter(
        overrides: decksOverrides(
          deckRepository: FakeDeckRepository(summaries: _summaries()),
          cardRepository: FakeCardRepository(cards: _cards()),
          reviewRepository: FakeReviewRepository(),
          statisticsRepository: FakeStatisticsRepository(
            snapshot: statisticsSnapshot(),
          ),
        ),
        initialLocation: '/statistics',
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('статистика: календарь 1280×720', (WidgetTester tester) async {
    await pumpStatistics(tester, const Size(1280, 720));
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey<String>('statistics-heatmap')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await _shoot(tester, 'statistics_calendar_1280');
  });

  testWidgets('статистика: графики 1280×720', (WidgetTester tester) async {
    await pumpStatistics(tester, const Size(1280, 720));
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey<String>('statistics-forecast')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await _shoot(tester, 'statistics_charts_1280');
  });

  testWidgets('статистика: удержание и темы 1280×720', (
    WidgetTester tester,
  ) async {
    await pumpStatistics(tester, const Size(1280, 720));
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey<String>('statistics-retention-panel')),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await _shoot(tester, 'statistics_details_1280');
  });

  testWidgets('статистика: календарь на телефоне 390×844', (
    WidgetTester tester,
  ) async {
    await pumpStatistics(tester, const Size(390, 844));
    await tester.scrollUntilVisible(
      find.byKey(const ValueKey<String>('statistics-heatmap')),
      160,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await _shoot(tester, 'statistics_calendar_390');
  });

  testWidgets('статистика: графики на телефоне 390×844', (
    WidgetTester tester,
  ) async {
    await pumpStatistics(tester, const Size(390, 844));
    final AppLocalizations l10n = AppLocalizations.of(
      tester.element(find.byType(Scaffold).first),
    );
    // Прокручиваем к заголовку карточки прогноза: видно и шапку (чип), и график.
    await tester.scrollUntilVisible(
      find.text(l10n.statisticsForecastTitle),
      160,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await _shoot(tester, 'statistics_charts_390');
  });

  testWidgets('колоды: телефон 390×844', (WidgetTester tester) async {
    await pumpAt(tester, const Size(390, 844));
    await tester.pumpWidget(
      appWithAppRouter(overrides: overrides(), initialLocation: '/'),
    );
    await tester.pumpAndSettle();
    await _shoot(tester, 'decks_390');
  });
}

List<DeckSummary> _summaries() => <DeckSummary>[
  makeSummary(
    id: 'deck-1',
    name: 'Электротехника',
    totalCards: 71,
    dueCards: 46,
    newCards: 9,
    inProgressCards: 62,
  ),
  makeSummary(
    id: 'deck-2',
    name: 'Тест фигни',
    totalCards: 134,
    dueCards: 33,
    newCards: 12,
    inProgressCards: 100,
  ),
  makeSummary(
    id: 'deck-3',
    name: 'ЛРЗ_Трехфазная_цепь_звездой',
    totalCards: 40,
    dueCards: 22,
    newCards: 4,
    inProgressCards: 30,
  ),
  makeSummary(id: 'deck-4', name: 'Кинематика', totalCards: 15, dueCards: 0),
];

List<domain.Card> _cards() => <domain.Card>[
  makeCard(
    id: 'card-1',
    deckId: 'deck-1',
    front: 'Чему равен ток нейтрального провода при симметричной нагрузке?',
    back: 'Нулю',
    tags: const <String>['трёхфазные цепи', 'нейтраль'],
  ),
  makeCard(
    id: 'card-2',
    deckId: 'deck-1',
    front: 'К каким проводам подключён источник трёхфазного напряжения?',
    back: 'К фазным',
    tags: const <String>['трёхфазные цепи'],
  ),
  makeCard(
    id: 'card-3',
    deckId: 'deck-1',
    front: 'Какое фазное напряжение в опыте 4?',
    back: '127 В',
  ),
  makeCard(
    id: 'card-4',
    deckId: 'deck-1',
    front: 'Как называется свойство теста измерять то, что нужно?',
    back: 'Валидность',
  ),
  makeCard(
    id: 'card-5',
    deckId: 'deck-1',
    front: 'Что такое корреляция?',
    back: 'Корреляция',
  ),
  makeCard(
    id: 'card-6',
    deckId: 'deck-1',
    front: 'Что такое надёжность теста?',
    back: 'Надёжность',
  ),
];
