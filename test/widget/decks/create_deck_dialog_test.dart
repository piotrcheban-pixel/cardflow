import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cardflow/domain/decks/deck_summary.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/app.dart';
import 'package:cardflow/ui/decks/decks_screen.dart';

import '../../helpers/decks_fakes.dart';
import '../../helpers/pump_app.dart';
import '../../helpers/settings_fakes.dart';

/// Кнопка «Создать колоду» на **production-проводке** (оболочка + роутер).
///
/// Регрессия этапа 3 «Nocturne»: кнопки диалога строились во внешнем
/// `BuildContext` экрана, поэтому `Navigator.of(context).pop()` попадал в
/// **ветку** `StatefulShellRoute`, а не в маршрут диалога. Экран «Мои колоды»
/// вылетал из ветки, `showDialog`-фьючер не завершался — приложение показывало
/// белый экран (`You have popped the last page off of the stack`) и повисало.
///
/// Поэтому тест поднимает не изолированный экран, а `CardFlowApp` с настоящим
/// `createAppRouter()`: без вложенного навигатора ветки дефект невоспроизводим
/// (урок M5 из ретроспективы итерации 1 — фикс проверяется на проводке).
void main() {
  FakeDeckRepository repositoryWith(List<DeckSummary> summaries) =>
      FakeDeckRepository(summaries: summaries);

  Future<void> pumpApp(
    WidgetTester tester,
    FakeDeckRepository repository,
  ) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: decksOverrides(
          deckRepository: repository,
          statisticsRepository: FakeStatisticsRepository(),
          appSettingsStore: FakeAppSettingsStore(),
        ),
        child: const CardFlowApp(),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openCreateDialog(
    WidgetTester tester,
    AppLocalizations l10n,
  ) async {
    await tester.tap(find.byKey(const ValueKey<String>('decks-new-deck')));
    await tester.pumpAndSettle();
    // Заголовок диалога совпадает с подписью кнопки шапки, поэтому
    // открытие проверяем по полю ввода (ADR-036: диалог на оболочке).
    expect(
      find.byKey(const ValueKey<String>('deck-name-submit')),
      findsOneWidget,
    );
  }

  testWidgets('диалог создания открывается и закрывается, экран не исчезает', (
    WidgetTester tester,
  ) async {
    final FakeDeckRepository repository = repositoryWith(<DeckSummary>[
      makeSummary(id: 'deck-1', name: 'Испанский'),
    ]);
    await pumpApp(tester, repository);
    final AppLocalizations l10n = l10nOf(tester);
    expect(find.byType(DecksScreen), findsOneWidget);

    await openCreateDialog(tester, l10n);

    await tester.tap(find.text(l10n.cancel));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('deck-name-submit')),
      findsNothing,
    );
    expect(
      find.byType(DecksScreen),
      findsOneWidget,
      reason: 'Закрытие диалога не должно выталкивать экран из ветки оболочки',
    );
    expect(find.text(l10n.decksTitle), findsOneWidget);
    expect(repository.createdNames, isEmpty);
  });

  testWidgets('ввод имени создаёт колоду и закрывает диалог', (
    WidgetTester tester,
  ) async {
    final FakeDeckRepository repository = repositoryWith(<DeckSummary>[
      makeSummary(id: 'deck-1', name: 'Испанский'),
    ]);
    await pumpApp(tester, repository);
    final AppLocalizations l10n = l10nOf(tester);

    await openCreateDialog(tester, l10n);

    await tester.enterText(find.byType(TextField), '  ТОЭ  ');
    await tester.tap(find.byKey(const ValueKey<String>('deck-name-submit')));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey<String>('deck-name-submit')),
      findsNothing,
    );
    expect(repository.createdNames, <String>['ТОЭ']);
    expect(find.byType(DecksScreen), findsOneWidget);
  });

  testWidgets('пустое имя не создаёт колоду и показывает ошибку', (
    WidgetTester tester,
  ) async {
    final FakeDeckRepository repository = repositoryWith(<DeckSummary>[]);
    await pumpApp(tester, repository);
    final AppLocalizations l10n = l10nOf(tester);

    await openCreateDialog(tester, l10n);
    await tester.tap(find.byKey(const ValueKey<String>('deck-name-submit')));
    await tester.pumpAndSettle();

    expect(find.text(l10n.deckNameEmptyError), findsOneWidget);
    expect(
      find.byKey(const ValueKey<String>('deck-name-submit')),
      findsOneWidget,
    );
    expect(repository.createdNames, isEmpty);

    await tester.tap(find.text(l10n.cancel));
    await tester.pumpAndSettle();
    expect(
      find.byKey(const ValueKey<String>('deck-name-submit')),
      findsNothing,
    );
    expect(find.byType(DecksScreen), findsOneWidget);
  });
}
