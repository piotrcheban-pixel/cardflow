import 'package:flutter/services.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' hide Card;

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/decks/deck_summary.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/cards/card_form_screen.dart';
import 'package:cardflow/ui/decks/deck_screen.dart';
import 'package:cardflow/ui/decks/decks_screen.dart';
import 'package:cardflow/ui/generation/generation_screen.dart';
import 'package:cardflow/ui/review/review_session_screen.dart';
import 'package:cardflow/ui/settings/generation_settings_screen.dart';
import 'package:cardflow/ui/settings/settings_screen.dart';
import 'package:cardflow/ui/statistics/statistics_screen.dart';
import 'package:cardflow/ui/theme/app_contrast.dart';

import '../../helpers/decks_fakes.dart';
import '../../helpers/pump_app.dart';
import '../../helpers/review_fakes.dart';

/// Навигация и выход (находки N1–N8 аудита 1.0).
///
/// Инварианты, которые проверяет файл:
/// * из каждого экрана есть видимый выход в главное меню не длиннее двух
///   действий (без учёта прокрутки и «знания, что меню в бургере»);
/// * `Esc` = системный «назад» на всех экранах и в диалогах;
/// * завершённая сессия закрывается без лишнего подтверждения;
/// * у экрана генерации шапка закреплена и видна после прокрутки формы.
void main() {
  late FakeDeckRepository decks;
  late FakeCardRepository cards;
  late FakeReviewRepository reviews;
  late List<Card> allCards;

  List<Card> deckCards() => <Card>[
    makeCard(
      id: 'card-1',
      deckId: 'deck-1',
      front: 'Первый вопрос',
      back: 'Первый ответ',
      createdAt: DateTime.utc(2026, 11, 20, 10),
    ),
    makeCard(
      id: 'card-2',
      deckId: 'deck-1',
      front: 'Второй вопрос',
      back: 'Второй ответ',
      createdAt: DateTime.utc(2026, 11, 20, 10, 1),
    ),
  ];

  List<Override> overrides() {
    final List<Card> all = deckCards();
    allCards = all;
    decks = FakeDeckRepository(
      summaries: <DeckSummary>[
        makeSummary(
          id: 'deck-1',
          name: 'Физика',
          totalCards: all.length,
          newCards: all.length,
        ),
      ],
    );
    cards = FakeCardRepository(cards: all);
    reviews = FakeReviewRepository();
    return decksOverrides(
      deckRepository: decks,
      cardRepository: cards,
      reviewRepository: reviews,
    );
  }

  Future<void> pumpApp(
    WidgetTester tester, {
    String initialLocation = '/',
  }) async {
    // Широкое окно: боковая панель постоянная, путь в разделы — одно действие.
    tester.view.physicalSize = const Size(1280, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(
      appWithAppRouter(
        overrides: overrides(),
        initialLocation: initialLocation,
      ),
    );
    await tester.pumpAndSettle();
  }

  AppLocalizations l10n(WidgetTester tester) => l10nOf(tester);

  Future<void> pressEsc(WidgetTester tester) async {
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pumpAndSettle();
  }

  Future<void> openDeck(WidgetTester tester) async {
    await tester.tap(
      find.byKey(const ValueKey<String>('deck-card-deck-1')).hitTestable(),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openSession(WidgetTester tester) async {
    await openDeck(tester);
    final AppLocalizations strings = l10n(tester);
    await tester.tap(find.text(strings.reviewStartSession));
    await tester.pumpAndSettle();
    await tester.tap(find.text(strings.reviewModeClassic));
    await tester.pumpAndSettle();
    expect(find.byType(ReviewSessionScreen), findsOneWidget);
  }

  group('главное меню и пути назад', () {
    testWidgets('колоды — главное меню, точка отсчёта', (
      WidgetTester tester,
    ) async {
      await pumpApp(tester);
      expect(find.byType(DecksScreen), findsOneWidget);
    });

    testWidgets('колода → «Назад» → колоды (1 действие)', (
      WidgetTester tester,
    ) async {
      await pumpApp(tester);
      await openDeck(tester);
      expect(find.byType(DeckScreen), findsOneWidget);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(DecksScreen), findsOneWidget);
    });

    testWidgets('колода → Esc → колоды (N3)', (WidgetTester tester) async {
      await pumpApp(tester);
      await openDeck(tester);
      await pressEsc(tester);
      expect(find.byType(DecksScreen), findsOneWidget);
    });

    testWidgets('статистика → «Колоды» в панели (1 действие)', (
      WidgetTester tester,
    ) async {
      await pumpApp(tester);
      final AppLocalizations strings = l10n(tester);
      await tester.tap(find.text(strings.navStatistics).first);
      await tester.pumpAndSettle();
      expect(find.byType(StatisticsScreen), findsOneWidget);

      await tester.tap(find.text(strings.navDecks));
      await tester.pumpAndSettle();
      expect(find.byType(DecksScreen), findsOneWidget);
    });

    testWidgets('настройки → «Колоды» в панели (1 действие)', (
      WidgetTester tester,
    ) async {
      await pumpApp(tester);
      final AppLocalizations strings = l10n(tester);
      await tester.tap(find.text(strings.navSettings).first);
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);

      await tester.tap(find.text(strings.navDecks));
      await tester.pumpAndSettle();
      expect(find.byType(DecksScreen), findsOneWidget);
    });

    testWidgets('провайдеры: «←» → настройки → колоды (2 действия)', (
      WidgetTester tester,
    ) async {
      await pumpApp(tester);
      final AppLocalizations strings = l10n(tester);
      await tester.tap(find.text(strings.navSettings).first);
      await tester.pumpAndSettle();
      expect(find.byType(SettingsScreen), findsOneWidget);

      // «Провайдеры и ключи» — раздел настроек (одно действие).
      final Finder providers = find.text(strings.settingsApiOpenGeneration);
      await tester.ensureVisible(providers);
      await tester.pumpAndSettle();
      await tester.tap(providers);
      await tester.pumpAndSettle();
      expect(find.byType(GenerationSettingsScreen), findsOneWidget);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      // Экран настроек — ветка оболочки: панель с «Колодами» видна.
      await tester.tap(find.text(strings.navDecks).first);
      await tester.pumpAndSettle();
      expect(find.byType(DecksScreen), findsOneWidget);
    });
  });

  group('сессии: Esc, домой и завершение', () {
    testWidgets('Esc в сессии открывает диалог выхода, «Продолжить» остаётся', (
      WidgetTester tester,
    ) async {
      await pumpApp(tester);
      await openSession(tester);
      final AppLocalizations strings = l10n(tester);

      await pressEsc(tester);
      expect(find.text(strings.reviewExitDialogTitle), findsOneWidget);

      await tester.tap(
        find.byKey(const ValueKey<String>('review-exit-cancel')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(ReviewSessionScreen), findsOneWidget);
    });

    testWidgets('Esc в диалоге выхода закрывает диалог, сессия остаётся', (
      WidgetTester tester,
    ) async {
      await pumpApp(tester);
      await openSession(tester);
      final AppLocalizations strings = l10n(tester);
      await tester.tap(find.byKey(const ValueKey<String>('review-close')));
      await tester.pumpAndSettle();
      expect(find.text(strings.reviewExitDialogTitle), findsOneWidget);

      await pressEsc(tester);
      expect(find.text(strings.reviewExitDialogTitle), findsNothing);
      expect(find.byType(ReviewSessionScreen), findsOneWidget);
    });

    testWidgets('сессия → «Выйти» → колода (2 действия)', (
      WidgetTester tester,
    ) async {
      await pumpApp(tester);
      await openSession(tester);
      await tester.tap(find.byKey(const ValueKey<String>('review-close')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('review-exit-confirm')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(DeckScreen), findsOneWidget);
    });

    testWidgets('сессия → «домой» → колоды (не больше 2 действий, N3)', (
      WidgetTester tester,
    ) async {
      await pumpApp(tester);
      await openSession(tester);

      await tester.tap(find.byKey(const ValueKey<String>('review-home')));
      await tester.pumpAndSettle();
      // Первое действие — кнопка «домой», второе — подтверждение выхода.
      await tester.tap(
        find.byKey(const ValueKey<String>('review-exit-confirm')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(DecksScreen), findsOneWidget);
      expect(find.byType(ReviewSessionScreen), findsNothing);
    });

    testWidgets('завершённая сессия: «×» закрывает без диалога (N7)', (
      WidgetTester tester,
    ) async {
      await pumpApp(tester);
      await openSession(tester);
      final AppLocalizations strings = l10n(tester);

      for (final String name in <String>['good', 'good']) {
        // Фейк возвращает снимок карточки в токене undo — иначе запись падает
        // и сессия не доходит до итогов.
        reviews.previousCard = allCards.first;
        await tester.tap(find.byKey(const ValueKey<String>('review-card')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(ValueKey<String>('review-rating-$name')));
        await tester.pumpAndSettle();
      }
      expect(find.text(strings.reviewCompletedTitle), findsOneWidget);

      await tester.tap(find.byKey(const ValueKey<String>('review-close')));
      await tester.pumpAndSettle();
      expect(find.text(strings.reviewExitDialogTitle), findsNothing);
      expect(find.byType(DeckScreen), findsOneWidget);
    });

    testWidgets('тренировка: Esc и кнопка «домой» работают', (
      WidgetTester tester,
    ) async {
      await pumpApp(tester);
      await openDeck(tester);
      final AppLocalizations strings = l10n(tester);
      await tester.tap(find.text(strings.reviewStartSession));
      await tester.pumpAndSettle();
      await tester.tap(find.text(strings.reviewModePractice));
      await tester.pumpAndSettle();

      await pressEsc(tester);
      expect(find.text(strings.reviewExitDialogTitle), findsOneWidget);
      await tester.tap(
        find.byKey(const ValueKey<String>('review-exit-cancel')),
      );
      await tester.pumpAndSettle();

      await tester.tap(find.byKey(const ValueKey<String>('review-home')));
      await tester.pumpAndSettle();
      await tester.tap(
        find.byKey(const ValueKey<String>('review-exit-confirm')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(DecksScreen), findsOneWidget);
    });
  });

  group('генерация: постоянный выход (N1)', () {
    testWidgets('шапка с выходом видна и после прокрутки формы', (
      WidgetTester tester,
    ) async {
      await pumpApp(tester);
      await tester.tap(
        find.byKey(const ValueKey<String>('decks-generate-action')),
      );
      await tester.pumpAndSettle();
      expect(find.byType(GenerationScreen), findsOneWidget);

      final Finder back = find.byKey(const ValueKey<String>('generation-back'));
      expect(back, findsOneWidget);
      expect(back.hitTestable(), findsOneWidget);

      // Прокручиваем форму к разделу модели — кнопка выхода остаётся в шапке.
      await tester.drag(find.byType(ListView).first, const Offset(0, -1200));
      await tester.pumpAndSettle();
      expect(
        back.hitTestable(),
        findsOneWidget,
        reason: 'выход не должен уезжать вместе с содержимым',
      );
    });

    testWidgets('Esc выходит с экрана генерации в колоды', (
      WidgetTester tester,
    ) async {
      await pumpApp(tester);
      await tester.tap(
        find.byKey(const ValueKey<String>('decks-generate-action')),
      );
      await tester.pumpAndSettle();
      await pressEsc(tester);
      expect(find.byType(GenerationScreen), findsNothing);
      expect(find.byType(DecksScreen), findsOneWidget);
    });

    testWidgets('баннер ошибки: контраст ссылки ≥ 4,5:1 (A1/D15)', (
      WidgetTester tester,
    ) async {
      await pumpApp(tester, initialLocation: '/generate');
      final Finder link = find.byKey(
        const ValueKey<String>('generation-open-settings'),
      );
      if (link.evaluate().isEmpty) return; // провайдер настроен — баннера нет
      // Фейковый провайдер по умолчанию не настроен, поэтому баннер есть.
      expect(link, findsOneWidget);
      final TextButton button = tester.widget<TextButton>(link);
      final ThemeData theme = Theme.of(
        tester.element(find.byType(GenerationScreen)),
      );
      final Color background = theme.colorScheme.errorContainer;
      final Color foreground = button.style!.foregroundColor!.resolve(
        <WidgetState>{},
      )!;
      expect(contrastRatio(foreground, background), greaterThanOrEqualTo(4.5));
    });
  });

  group('форма карточки и диалоги', () {
    testWidgets('форма карточки → «←» без правок → колода', (
      WidgetTester tester,
    ) async {
      await pumpApp(tester);
      await openDeck(tester);
      await tester.tap(
        find.byKey(const ValueKey<String>('deck-add-card')).hitTestable(),
      );
      await tester.pumpAndSettle();
      expect(find.byType(CardFormScreen), findsOneWidget);

      await tester.tap(find.byType(BackButton));
      await tester.pumpAndSettle();
      expect(find.byType(DeckScreen), findsOneWidget);
    });

    testWidgets('диалог «Новая колода» закрывается Esc', (
      WidgetTester tester,
    ) async {
      await pumpApp(tester);
      await tester.tap(
        find.byKey(const ValueKey<String>('decks-new-deck')).hitTestable(),
      );
      await tester.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);

      await pressEsc(tester);
      expect(find.byType(Dialog), findsNothing);
      expect(find.byType(DecksScreen), findsOneWidget);
    });

    testWidgets('лист режимов закрывается Esc', (WidgetTester tester) async {
      await pumpApp(tester);
      await openDeck(tester);
      final AppLocalizations strings = l10n(tester);
      await tester.tap(find.text(strings.reviewStartSession));
      await tester.pumpAndSettle();
      expect(find.text(strings.reviewSessionModeTitle), findsOneWidget);

      await pressEsc(tester);
      expect(find.text(strings.reviewSessionModeTitle), findsNothing);
      expect(find.byType(DeckScreen), findsOneWidget);
    });
  });
}
