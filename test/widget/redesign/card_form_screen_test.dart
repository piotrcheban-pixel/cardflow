import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_math_fork/flutter_math.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart' hide Card;

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/cards/card_media.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/cards/card_form_screen.dart';
import 'package:cardflow/ui/design/design.dart';

import '../../helpers/decks_fakes.dart';
import '../../helpers/glass_budget.dart';
import '../../helpers/nc_harness.dart';
import '../../helpers/nc_screen_harness.dart';
import '../../helpers/redesign_screen_fixtures.dart';

/// Форма карточки в оформлении Nocturne (REDESIGN-SPEC §9.4).
void main() {
  final AppLocalizations l10n = ncL10n;

  Uint8List png() => base64Decode(
    'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mNk'
    '+A8AAQUBAScY42YAAAAASUVORK5CYII=',
  );

  FakeCardImageGateway imageGateway() => FakeCardImageGateway()
    ..result = CardImageUpload(
      fileName: 'pic.png',
      mimeType: 'image/png',
      bytes: png(),
    );

  Future<void> pumpForm(
    WidgetTester tester, {
    String? cardId,
    Size size = const Size(390, 844),
    FakeCardImageGateway? gateway,
  }) => pumpNcScreen(
    tester,
    home: CardFormScreen(deckId: 'deck-bio', cardId: cardId),
    overrides: ncStage3Overrides(imageGateway: gateway ?? imageGateway()),
    config: NcScreenConfig(size: size),
  );

  testWidgets('ключи §9.4 новой карточки: поля, тип, сохранение', (
    WidgetTester tester,
  ) async {
    await pumpForm(tester);

    for (final String key in <String>[
      'card-form-front',
      'card-form-back',
      'card-form-hint',
      'card-form-tags',
      'card-form-source',
      'card-form-pick-image',
      'card-form-save',
    ]) {
      expect(find.byKey(ValueKey<String>(key)), findsOneWidget, reason: key);
    }
    expect(find.byType(NcSegmented<CardType>), findsOneWidget);
    expect(find.text(l10n.cardTypeBasic), findsOneWidget);
    expect(find.text(l10n.cardTypeBasicReversed), findsOneWidget);
    expect(find.text(l10n.cardTypeCloze), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('card-form-delete')),
      findsNothing,
      reason: 'Удаление доступно только при редактировании',
    );
  });

  testWidgets('подсказка синтаксиса и предпросмотр LaTeX', (
    WidgetTester tester,
  ) async {
    await pumpForm(tester);
    expect(find.text(l10n.cardFormSyntaxHint), findsOneWidget);

    await tester.enterText(
      find.byKey(const ValueKey<String>('card-form-front')),
      r'Формула $x^2 + y^2$',
    );
    await tester.pumpAndSettle();
    final Finder preview = find.byKey(
      const ValueKey<String>('card-form-front-preview'),
    );
    expect(preview, findsOneWidget);
    await tester.tap(
      find.descendant(of: preview, matching: find.byType(NcIconButton)),
    );
    await tester.pumpAndSettle();
    expect(find.byType(Math), findsOneWidget);
  });

  testWidgets('теги превращаются в NcChip.tag только визуально', (
    WidgetTester tester,
  ) async {
    await pumpForm(tester);
    await tester.enterText(
      find.byKey(const ValueKey<String>('card-form-tags')),
      'биология, клетка',
    );
    await tester.pumpAndSettle();

    final Finder chips = find.descendant(
      of: find.byKey(const ValueKey<String>('card-form-tags-preview')),
      matching: find.byType(NcChip),
    );
    expect(chips, findsNWidgets(2));
    expect(find.text('биология'), findsOneWidget);
    expect(find.text('клетка'), findsOneWidget);
  });

  testWidgets('медиа: ключи изображения и переключатель масок', (
    WidgetTester tester,
  ) async {
    await pumpForm(tester);
    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('card-form-pick-image')),
    );
    await tester.pumpAndSettle();
    await tester.tap(
      find.byKey(const ValueKey<String>('card-form-pick-image')),
    );
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('card-form-image-preview')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('card-form-remove-image')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('card-form-occlusion-toggle')),
      findsOneWidget,
    );

    await tester.ensureVisible(
      find.byKey(const ValueKey<String>('card-form-occlusion-toggle')),
    );
    await tester.tap(
      find.byKey(const ValueKey<String>('card-form-occlusion-toggle')),
    );
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('occlusion-editor-canvas')),
      findsOneWidget,
    );
  });

  testWidgets('удаление: NcDialog с ключами подтверждения и отмены', (
    WidgetTester tester,
  ) async {
    final FakeCardRepository cards = FakeCardRepository(
      cards: <Card>[
        makeCard(
          id: 'card-1',
          deckId: 'deck-bio',
          front: 'Вопрос',
          back: 'Ответ',
          tags: <String>['биология', 'клетка'],
        ),
      ],
    );
    await pumpNcScreen(
      tester,
      home: const CardFormScreen(deckId: 'deck-bio', cardId: 'card-1'),
      overrides: ncStage3Overrides(cardRepository: cards),
    );

    expect(
      find.byKey(const ValueKey<String>('card-form-delete')),
      findsOneWidget,
    );
    await tester.tap(find.byKey(const ValueKey<String>('card-form-delete')));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('card-delete-confirm')),
      findsOneWidget,
    );
    expect(
      find.byKey(const ValueKey<String>('card-delete-cancel')),
      findsOneWidget,
    );
  });

  testWidgets('бюджет стекла ≤ 2, textScale 2,0 без overflow', (
    WidgetTester tester,
  ) async {
    await pumpForm(tester);
    expectGlassBudget(tester, maxGroups: 2);
    expect(find.byType(BackdropFilter), findsWidgets);
  });

  testWidgets('textScale 2,0 на телефоне 360 × 740 без overflow', (
    WidgetTester tester,
  ) async {
    await pumpNcScreenAtTextScale2(
      tester,
      home: const CardFormScreen(deckId: 'deck-bio'),
      overrides: ncStage3Overrides(),
    );
    expect(
      find.byKey(const ValueKey<String>('card-form-save')),
      findsOneWidget,
    );
  });

  testWidgets('ширины: колонка max 680 на ПК и узкая на телефоне', (
    WidgetTester tester,
  ) async {
    await pumpForm(tester, size: const Size(1440, 900));
    expect(
      tester
          .getSize(find.byKey(const ValueKey<String>('card-form-front')))
          .width,
      lessThanOrEqualTo(680),
    );

    await pumpForm(tester);
    expect(
      tester
          .getSize(find.byKey(const ValueKey<String>('card-form-front')))
          .width,
      lessThan(680),
    );
  });

  testWidgets('сохранение возвращает результат прежним путём', (
    WidgetTester tester,
  ) async {
    final GoRouter router = GoRouter(
      initialLocation: '/decks/deck-bio/cards/new',
      routes: <RouteBase>[
        GoRoute(
          path: '/decks/:id/cards/new',
          builder: (BuildContext context, GoRouterState state) =>
              CardFormScreen(deckId: state.pathParameters['id']!),
        ),
      ],
    );
    addTearDown(router.dispose);
    await pumpNcScreen(tester, router: router, overrides: ncStage3Overrides());
    await tester.enterText(
      find.byKey(const ValueKey<String>('card-form-front')),
      'Вопрос',
    );
    await tester.enterText(
      find.byKey(const ValueKey<String>('card-form-back')),
      'Ответ',
    );
    await tester.tap(find.byKey(const ValueKey<String>('card-form-save')));
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
  });
}
