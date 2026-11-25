import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart' hide Card;

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/cards/card_form_screen.dart';

import '../../helpers/decks_fakes.dart';
import '../../helpers/pump_app.dart';

/// TASK 04 / ADR-046: редактор карточки на телефоне.
///
/// Контракт:
/// * длинные объяснения не занимают поток — они в подсказке «?»;
/// * заголовок стороны изображений не сжимается в узкую колонку;
/// * дополнительное действие «+» — цель ≥44;
/// * «Дополнительно» свёрнуто у новой карточки и раскрывается по нажатию;
/// * нижняя панель сохранения — на всю ширину, внутри SafeArea;
/// * ни одного RenderFlex overflow на 320–390 px и при кегле 130 %.
void main() {
  Future<void> pumpForm(
    WidgetTester tester, {
    required Size size,
    required double textScale,
    Card? card,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final List<Override> overrides = decksOverrides(
      deckRepository: FakeDeckRepository(),
      cardRepository: FakeCardRepository(
        cards: card == null ? const <Card>[] : <Card>[card],
      ),
    );
    await tester.pumpWidget(
      appWithHome(
        overrides: overrides,
        home: MediaQuery(
          data: MediaQueryData(
            size: size,
            textScaler: TextScaler.linear(textScale),
          ),
          child: CardFormScreen(deckId: 'deck-1', cardId: card?.id),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  for (final (String label, Size size, double textScale)
      in <(String, Size, double)>[
        ('360', Size(360, 800), 1),
        ('360 кегль 130 %', Size(360, 800), 1.3),
        ('320', Size(320, 640), 1),
      ]) {
    testWidgets('$label: без узкой колонки, overflow и срезанных подписей', (
      WidgetTester tester,
    ) async {
      await pumpForm(tester, size: size, textScale: textScale);
      final AppLocalizations l10n = l10nOf(tester);

      // Длинное пояснение секции изображений не висит в потоке.
      expect(find.text(l10n.cardFormImageHint), findsNothing);
      expect(
        find.byKey(const ValueKey<String>('app-info-card-form-image-info')),
        findsOneWidget,
      );

      // «Дополнительно» у новой карточки свёрнуто: теги не занимают место.
      expect(
        find.byKey(const ValueKey<String>('card-form-additional-toggle')),
        findsOneWidget,
      );
      await tester.tap(
        find.byKey(const ValueKey<String>('card-form-additional-toggle')),
      );
      await tester.pumpAndSettle();
      expect(
        find.byKey(const ValueKey<String>('card-form-tags')),
        findsOneWidget,
      );

      // Найти секции изображений и проверить геометрию заголовков.
      final Finder frontImages = find.byKey(
        const ValueKey<String>('card-form-question-images'),
      );
      await tester.scrollUntilVisible(
        frontImages,
        300,
        scrollable: find.byType(Scrollable).first,
      );
      await tester.pumpAndSettle();

      final Rect titleRect = tester.getRect(
        find.byKey(const ValueKey<String>('card-form-question-images-title')),
      );
      final double titleLine =
          (Theme.of(tester.element(frontImages))
                  .textTheme
                  .titleSmall
                  ?.fontSize ??
              16) *
          textScale;
      // Две строки — допустимо; «столбик» из 4–6 строк (дефект M-02) — нет.
      expect(
        titleRect.height,
        lessThanOrEqualTo(titleLine * 1.45 * 2 + 2),
        reason: 'заголовок стороны изображений сжался в колонку',
      );
      expect(titleRect.width, greaterThan(150));

      final Finder add = find.byKey(
        const ValueKey<String>('card-form-add-question-image'),
      );
      expect(add, findsOneWidget);
      final Rect addRect = tester.getRect(add);
      expect(addRect.height, greaterThanOrEqualTo(44));
      expect(addRect.width, greaterThanOrEqualTo(44));

      // Нижняя панель: кнопка на всю ширину (с полями 16+16), не «остров».
      final Rect save = tester.getRect(
        find.byKey(const ValueKey<String>('card-form-save')),
      );
      expect(save.height, greaterThanOrEqualTo(44));
      expect(save.width, greaterThanOrEqualTo(size.width - 40));
      expect(save.bottom, lessThanOrEqualTo(size.height));

      expect(tester.takeException(), isNull);
    }, timeout: const Timeout(Duration(seconds: 180)));
  }

  testWidgets('подсказка «?» открывает пояснение, а не занимает экран', (
    WidgetTester tester,
  ) async {
    await pumpForm(tester, size: const Size(360, 800), textScale: 1);
    final AppLocalizations l10n = l10nOf(tester);

    final Finder info = find.byKey(
      const ValueKey<String>('app-info-card-form-image-info'),
    );
    await tester.scrollUntilVisible(
      info,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(info);
    await tester.pumpAndSettle();

    expect(find.text(l10n.cardFormImageInfoTitle), findsOneWidget);
    expect(find.text(l10n.cardFormImageHint), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('app-info-close')));
    await tester.pumpAndSettle();
    expect(find.text(l10n.cardFormImageHint), findsNothing);
  }, timeout: const Timeout(Duration(seconds: 180)));

  testWidgets('тип карточки при редактировании: причина в подсказке', (
    WidgetTester tester,
  ) async {
    final Card card = makeCard(
      id: 'card-1',
      deckId: 'deck-1',
      front: 'Вопрос',
      back: 'Ответ',
    );
    await pumpForm(
      tester,
      size: const Size(360, 800),
      textScale: 1,
      card: card,
    );
    final AppLocalizations l10n = l10nOf(tester);

    expect(find.text(l10n.cardFormTypeImmutable), findsNothing);
    final Finder info = find.byKey(
      const ValueKey<String>('app-info-card-form-type-info'),
    );
    await tester.scrollUntilVisible(
      info,
      300,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    await tester.tap(info);
    await tester.pumpAndSettle();
    expect(find.text(l10n.cardFormTypeImmutable), findsOneWidget);
    expect(tester.takeException(), isNull);
  }, timeout: const Timeout(Duration(seconds: 180)));
}
