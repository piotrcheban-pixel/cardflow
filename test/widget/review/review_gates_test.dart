import 'package:flutter/rendering.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' hide Card;

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/decks/deck_summary.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/review/review_card_view.dart';
import 'package:cardflow/ui/review/review_session_screen.dart';
import 'package:cardflow/ui/review/review_toolbar.dart';
import 'package:cardflow/ui/study/study_session_chrome.dart';
import 'package:cardflow/ui/theme/app_theme.dart';
import 'package:cardflow/ui/theme/app_tokens.dart';

import '../../helpers/decks_fakes.dart';
import '../../helpers/pump_app.dart';
import '../../helpers/review_fakes.dart';

/// Автотесты гейтов G1–G11 визуального аудита v7 (review_visual/GATES.md).
///
/// Каждый тест повторяет требование гейта числами: наличие/отсутствие кнопок в
/// дереве, размеры на 2K/FullHD (2560×1440 и 1920×1080 логических), зазоры,
/// появление панели оценок анимацией и единая трактовка вопроса в режимах.
void main() {
  List<Card> cards({int count = 2}) => <Card>[
    for (int index = 0; index < count; index++)
      makeCard(
        id: 'card-${index + 1}',
        deckId: 'deck-1',
        front: index == 0
            ? 'Сформулируйте закон Ома для участка цепи'
            : 'Вопрос номер ${index + 1}',
        back:
            'Сила тока на участке цепи прямо пропорциональна напряжению '
            'и обратно пропорциональна сопротивлению участка.',
        createdAt: DateTime.utc(2026, 11, 20, 10, index),
      ),
  ];

  List<Override> overridesFor(List<Card> deckCards) => decksOverrides(
    deckRepository: FakeDeckRepository(
      summaries: <DeckSummary>[
        makeSummary(
          id: 'deck-1',
          name: 'Физика',
          totalCards: deckCards.length,
          newCards: deckCards.length,
        ),
      ],
    ),
    cardRepository: FakeCardRepository(cards: deckCards),
    reviewRepository: FakeReviewRepository(),
  );

  /// Поднимает экран сессии на заданном размере и пользовательском масштабе
  /// текста (владелец работает на 90 % — как в живом приложении).
  Future<void> pumpSession(
    WidgetTester tester,
    Size size, {
    double textScale = 1,
    List<Card>? deckCards,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    // Фактор адаптива — как в проде от физического размера экрана.
    AppAdaptive.debugOverride = size.width >= 3200
        ? 1.45
        : size.width >= 2400
        ? 1.24
        : 1.0;
    addTearDown(() => AppAdaptive.debugOverride = null);
    final List<Card> source = deckCards ?? cards();
    await tester.pumpWidget(
      ProviderScope(
        overrides: overridesFor(source),
        child: MaterialApp(
          locale: const Locale('ru'),
          supportedLocales: AppLocalizations.supportedLocales,
          localizationsDelegates: ruLocalizationDelegates,
          theme: AppTheme.light(),
          builder: (BuildContext context, Widget? child) => MediaQuery(
            data: MediaQuery.of(context)
                .copyWith(textScaler: TextScaler.linear(textScale)),
            child: child!,
          ),
          home: ReviewSessionScreen(deckId: 'deck-1'),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> reveal(WidgetTester tester) async {
    await tester.tap(find.byKey(const ValueKey<String>('review-card')));
    // Переворот 300 мс + появление панели (220 мс).
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 320));
    await tester.pump(const Duration(milliseconds: 260));
  }

  group('G1: оценки существуют только после ответа', () {
    for (final (String label, Size size) in <(String, Size)>[
      ('2K 2560×1440', Size(2560, 1440)),
      ('FullHD 1920×1080', Size(1920, 1080)),
    ]) {
      testWidgets('$label: до ответа панели оценок нет в дереве', (
        WidgetTester tester,
      ) async {
        await pumpSession(tester, size);
        for (final String name in <String>['again', 'hard', 'good', 'easy']) {
          expect(
            find.byKey(ValueKey<String>('review-rating-$name')),
            findsNothing,
            reason: 'G1: до раскрытия нет ни оценки, ни серой кнопки',
          );
        }
        expect(
          find.byKey(const ValueKey<String>('review-rating-hint')),
          findsNothing,
        );
        expect(
          find.byKey(const ValueKey<String>('review-keyboard-hints-front')),
          findsNothing,
        );
        expect(find.byType(ReviewToolbar), findsNothing);
        expect(
          find.byKey(const ValueKey<String>('review-reveal')),
          findsOneWidget,
          reason: 'единственное действие лицевой стороны',
        );
        await reveal(tester);
        expect(find.byType(ReviewToolbar), findsOneWidget);
        for (final String name in <String>['again', 'hard', 'good', 'easy']) {
          final FilledButton button = tester.widget<FilledButton>(
            find.byKey(ValueKey<String>('review-rating-$name')),
          );
          expect(button.onPressed, isNotNull, reason: '«$name» активна');
        }
        expect(
          find.byKey(const ValueKey<String>('review-reveal')),
          findsNothing,
          reason: 'G1: «Показать ответ» после раскрытия исчезает',
        );
      });
    }
  });

  group('G2: компактная панель оценок (≥44 на телефоне, ≥56 на широком)', () {
    for (final (String label, Size size) in <(String, Size)>[
      ('2K 2560×1440', Size(2560, 1440)),
      ('FullHD 1920×1080', Size(1920, 1080)),
      ('mobile 390×844', Size(390, 844)),
    ]) {
      testWidgets('кнопки и подписи: $label', (WidgetTester tester) async {
        await pumpSession(tester, size, textScale: 0.9);
        await reveal(tester);
        final bool mobile = size.width < AppSizes.mobileBreakpoint;
        final double scale = MediaQuery.of(
          tester.element(find.byKey(const ValueKey<String>('review-card'))),
        ).textScaler.scale(1);
        for (final String name in <String>['again', 'hard', 'good', 'easy']) {
          final Size button = tester.getSize(
            find.byKey(ValueKey<String>('review-rating-$name')),
          );
          // TASK 04 / ADR-046: на телефоне кнопка 48 px (цель ≥44), на
          // широком экране — прежние 56 px. Обрезка подписи проверяется
          // отдельно ниже (FittedBox, без ellipsis).
          expect(
            button.height,
            greaterThanOrEqualTo(
              mobile ? AppSizes.minTouchTarget : AppSizes.ratingButtonHeight,
            ),
            reason: mobile
                ? 'G2: «$name» ${button.height} < 44'
                : 'G2: «$name» ${button.height} < 56',
          );
        }
        // Кегль подписи: 16 на телефоне / 18 на широком, пользовательский
        // масштаб 0,9; нижняя граница — 14 на телефоне и 16 на десктопе.
        final RichText label = tester.widget<RichText>(
          find
              .descendant(
                of: find.byKey(const ValueKey<String>('review-rating-good')),
                matching: find.byType(RichText),
              )
              .first,
        );
        final double rendered = (label.text.style?.fontSize ?? 0) * scale;
        expect(
          rendered,
          greaterThanOrEqualTo(mobile ? 14 : 16),
          reason: 'G2: подпись оценки $rendered < ${mobile ? 14 : 16}',
        );
        // G6: зазор между оценками — 8 на сетке 2×2, 12 на широкой панели.
        final Rect again = tester.getRect(
          find.byKey(const ValueKey<String>('review-rating-again')),
        );
        final Rect hard = tester.getRect(
          find.byKey(const ValueKey<String>('review-rating-hard')),
        );
        final double gap = hard.left > again.left
            ? hard.left - again.right
            : again.top - hard.bottom;
        expect(
          gap,
          greaterThanOrEqualTo(mobile ? 8 : 12),
          reason: 'G6: зазор $gap < ${mobile ? 8 : 12}',
        );
      });
    }
  });

  group('G3: карточка ≥60 % ширины, высота — по содержимому', () {
    for (final (String label, Size size) in <(String, Size)>[
      ('2K 2560×1440', Size(2560, 1440)),
      ('FullHD 1920×1080', Size(1920, 1080)),
      ('4K 3840×2160', Size(3840, 2160)),
    ]) {
      testWidgets('$label: вопрос и ответ', (WidgetTester tester) async {
        await pumpSession(tester, size);
        final Size card = tester.getSize(
          find.byKey(const ValueKey<String>('review-card')),
        );
        expect(
          card.width / size.width,
          greaterThanOrEqualTo(0.6),
          reason: 'G3: карточка ${card.width} из ${size.width}',
        );
        // Аудит v8: карточка «обнимает» содержимое — она не растягивается на
        // всю рабочую область (иначе 80 % строк оставались пустыми), но и не
        // превращается в полоску.
        expect(card.height / size.height, inInclusiveRange(0.25, 0.9));
        await reveal(tester);
        final Size answered = tester.getSize(
          find.byKey(const ValueKey<String>('review-card')),
        );
        expect(answered.width / size.width, greaterThanOrEqualTo(0.6));
        expect(answered.height / size.height, inInclusiveRange(0.25, 0.9));
      });
    }

    // F01/V3: карточка — главный объект постоянного размера (62 % рабочей
    // области); длинный вопрос не растягивает её, а прокручивается внутри.
    testWidgets('высота карточки ≥62 % рабочей области при любом контенте', (
      WidgetTester tester,
    ) async {
      await pumpSession(tester, const Size(1920, 1080));
      final double shortCard = tester
          .getSize(find.byKey(const ValueKey<String>('review-card')))
          .height;
      expect(
        shortCard,
        greaterThanOrEqualTo((1080 - 56) * 0.62 - 1),
        reason: 'короткий вопрос: ${shortCard}px < 62 % рабочей области',
      );
      final List<Card> longCards = <Card>[
        makeCard(
          id: 'long-1',
          deckId: 'deck-1',
          front: List<String>.filled(
            14,
            'Длинный вопрос карточки для проверки высоты по содержимому',
          ).join(' '),
          back: 'Ответ',
          createdAt: DateTime.utc(2026, 11, 20),
        ),
      ];
      // Новый экран: иначе State сохранится и останется прежняя карточка.
      await tester.pumpWidget(const SizedBox());
      await pumpSession(tester, const Size(1920, 1080), deckCards: longCards);
      final double longCard = tester
          .getSize(find.byKey(const ValueKey<String>('review-card')))
          .height;
      expect(
        longCard,
        shortCard,
        reason: 'высота не зависит от длины вопроса: $longCard ≠ $shortCard',
      );
      // Длинный вопрос доступен через прокрутку внутри карточки (F27).
      final Scrollbar scrollbar = tester.widget<Scrollbar>(
        find.descendant(
          of: find.byKey(const ValueKey<String>('review-card')),
          matching: find.byType(Scrollbar),
        ),
      );
      expect(scrollbar.thumbVisibility, isTrue);
    });
  });

  group('G5: недоступные действия скрыты', () {
    testWidgets('undo без истории и клавиатурные подсказки отсутствуют', (
      WidgetTester tester,
    ) async {
      await pumpSession(tester, const Size(1920, 1080));
      expect(find.byKey(const ValueKey<String>('review-undo')), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('review-keyboard-hints')),
        findsNothing,
      );
      await reveal(tester);
      expect(
        find.byKey(const ValueKey<String>('review-undo')),
        findsNothing,
        reason: 'после раскрытия истории ещё нет — undo не рисуется',
      );
    });
  });

  group('G7: типографика', () {
    testWidgets('вопрос ≥28 на 2K, ответ ≥22, интерлиньяж ответа 1,3–1,5', (
      WidgetTester tester,
    ) async {
      await pumpSession(tester, const Size(2560, 1440));
      final RenderParagraph question = tester.renderObject<RenderParagraph>(
        find.textContaining('Сформулируйте закон Ома'),
      );
      expect(question.text.style?.fontSize, greaterThanOrEqualTo(28));
      await reveal(tester);
      final RenderParagraph answer = tester.renderObject<RenderParagraph>(
        find.textContaining('Сила тока на участке'),
      );
      expect(answer.text.style?.fontSize, greaterThanOrEqualTo(22));
      final double heightFactor = answer.text.style!.height!;
      expect(
        heightFactor,
        inInclusiveRange(1.3, 1.5),
        reason: 'G7: межстрочный ответа $heightFactor',
      );
    });
  });

  group('G9: движение', () {
    testWidgets('переворот 280–350 мс, панель оценок появляется fade', (
      WidgetTester tester,
    ) async {
      expect(
        kReviewCardFlipDuration.inMilliseconds,
        inInclusiveRange(280, 350),
      );
      await pumpSession(tester, const Size(1920, 1080));
      await tester.tap(find.byKey(const ValueKey<String>('review-card')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 320));
      // Панель создана в момент смены лица — она ещё не полностью проявилась.
      final Finder opacity = find.descendant(
        of: find.byKey(const ValueKey<String>('review-rating-panel')),
        matching: find.byType(Opacity),
      );
      expect(opacity, findsWidgets, reason: 'G9: появление — через Opacity');
      final double start = tester.widget<Opacity>(opacity.first).opacity;
      expect(start, lessThan(1.0), reason: 'панель проявляется, а не мигает');
      await tester.pump(const Duration(milliseconds: 260));
      final double finish = tester.widget<Opacity>(opacity.first).opacity;
      expect(finish, 1.0);
    });
  });

  group('G10: узкие окна', () {
    // 562×260 — живое окно 844×390 физических px при масштабе Windows 150 %:
    // аудит v8 поймал здесь переполнение карточки и две недоступные оценки.
    for (final Size size in <Size>[
      Size(844, 390),
      Size(562, 260),
      Size(390, 844),
      Size(800, 600),
      Size(533, 400),
    ]) {
      testWidgets('${size.width.toInt()}×${size.height.toInt()}: без обрезки', (
        WidgetTester tester,
      ) async {
        await pumpSession(tester, size);
        expect(find.textContaining('Сформулируйте закон Ома'), findsOneWidget);
        expect(tester.takeException(), isNull);
        final Rect card = tester.getRect(
          find.byKey(const ValueKey<String>('review-card')),
        );
        expect(card.height, greaterThanOrEqualTo(120));
        await reveal(tester);
        expect(tester.takeException(), isNull);
        // G10: все четыре оценки доступны и лежат внутри карточки.
        final Rect cardAnswered = tester.getRect(
          find.byKey(const ValueKey<String>('review-card')),
        );
        for (final String name in <String>['again', 'hard', 'good', 'easy']) {
          final Rect button = tester.getRect(
            find.byKey(ValueKey<String>('review-rating-$name')),
          );
          expect(
            button.bottom,
            lessThanOrEqualTo(cardAnswered.bottom + 0.5),
            reason: 'G10: «$name» выходит за нижнюю кромку карточки',
          );
          expect(button.top, greaterThanOrEqualTo(cardAnswered.top - 0.5));
          // TASK 04 / ADR-046: на телефоне компактная кнопка 48 px; цель
          // касания остаётся ≥44, поэтому «доступность» гейта не ослаблена.
          expect(
            button.height,
            greaterThanOrEqualTo(AppSizes.minTouchTarget),
            reason: 'G10: «$name» ${button.height} < 44',
          );
        }
      });
    }
  });

  group('G11: единая трактовка вопроса в режимах проверки', () {
    // Набор как в study_modes_test: осмысленные ответы и «предыдущая карточка»
    // для фейкового журнала — иначе режимы показывают пустое состояние.
    List<Card> studyCards() => <Card>[
      for (final (int index, String answer) in <String>[
        'Митохондрия',
        'Хлоропласт',
        'Лизосома',
        'Гольджи',
        'Рибосома',
        'Ядро',
      ].indexed)
        makeCard(
          id: 'study-$index',
          deckId: 'deck-1',
          front: 'Вопрос $index?',
          back: answer,
          createdAt: DateTime.now(),
          updatedAt: DateTime.now(),
        ),
    ];

    for (final String route in <String>['test', 'typing', 'true-false']) {
      testWidgets('режим $route: вопрос в общей карточке', (
        WidgetTester tester,
      ) async {
        tester.view.physicalSize = const Size(1920, 1080);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        final List<Card> deck = studyCards();
        final FakeReviewRepository reviews = FakeReviewRepository()
          ..previousCard = deck.first;
        await tester.pumpWidget(
          appWithRouter(
            overrides: decksOverrides(
              deckRepository: FakeDeckRepository(),
              cardRepository: FakeCardRepository(cards: deck),
              reviewRepository: reviews,
              practiceRepository: FakePracticeRepository(),
            ),
            routes: decksRoutes(),
            initialLocation: '/decks/deck-1/$route',
          ),
        );
        await tester.pumpAndSettle();
        expect(
          find.byType(StudyQuestionCard),
          findsOneWidget,
          reason: 'G11: вопрос на той же поверхности, что в «Классике»',
        );
        expect(find.text('ВОПРОС'), findsOneWidget);
      });
    }
  });

  group('Дубли действий', () {
    testWidgets('в дереве сессии нет повторяющихся ключей действий', (
      WidgetTester tester,
    ) async {
      await pumpSession(tester, const Size(1920, 1080));
      await reveal(tester);
      final Map<Key, int> counts = <Key, int>{};
      for (final Element element in find.byType(Widget).evaluate()) {
        final Key? key = element.widget.key;
        if (key == null) continue;
        counts[key] = (counts[key] ?? 0) + 1;
      }
      final List<Key> duplicates = <Key>[
        for (final MapEntry<Key, int> entry in counts.entries)
          if (entry.value > 1) entry.key,
      ];
      expect(duplicates, isEmpty, reason: 'дубли ключей: $duplicates');
    });
  });
}
