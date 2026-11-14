import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/app.dart';

import '../helpers/decks_fakes.dart';
import '../helpers/pump_app.dart';

/// Локализация приложения: только `ru` (SPEC 3.1, 3.5).
///
/// Итерация 1: корень — `MaterialApp.router` (ADR: GoRouter), экран «Колоды»
/// использует Riverpod-провайдеры, поэтому приложение пумпится в
/// `ProviderScope` с фейковым data-слоем (без БД/плагинов/сети).
void main() {
  Widget appUnderTest() {
    return ProviderScope(
      overrides: decksOverrides(deckRepository: FakeDeckRepository()),
      child: const CardFlowApp(),
    );
  }

  group('Локализация приложения: только ru (SPEC 3.1, 3.5)', () {
    testWidgets(
      'MaterialApp работает с локалью ru и русскими системными строками',
      (tester) async {
        await tester.pumpWidget(appUnderTest());
        await tester.pumpAndSettle();

        final context = tester.element(find.byType(Scaffold).first);
        expect(Localizations.localeOf(context), const Locale('ru'));
        expect(AppLocalizations.supportedLocales, const <Locale>[Locale('ru')]);

        final material = MaterialLocalizations.of(context);
        expect(material.cancelButtonLabel, 'Отмена');
        expect(material.pasteButtonLabel, 'Вставить');
        expect(material.okButtonLabel, 'ОК');
      },
    );

    testWidgets('заголовок приложения берётся из ARB (appTitle)', (
      tester,
    ) async {
      await tester.pumpWidget(appUnderTest());
      await tester.pumpAndSettle();

      final context = tester.element(find.byType(Scaffold).first);
      expect(AppLocalizations.of(context).appTitle, 'CardFlow');
    });

    testWidgets('делегаты локализации Material и Widgets доступны', (
      tester,
    ) async {
      await tester.pumpWidget(appUnderTest());
      await tester.pumpAndSettle();

      final context = tester.element(find.byType(Scaffold).first);
      expect(MaterialLocalizations.of(context), isNotNull);
      expect(WidgetsLocalizations.of(context), isNotNull);
    });
  });
}
