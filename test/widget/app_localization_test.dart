import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/app.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

void main() {
  group('Локализация приложения: только ru (SPEC 3.1, 3.5)', () {
    testWidgets(
      'MaterialApp работает с локалью ru и русскими системными строками',
      (tester) async {
        await tester.pumpWidget(const CardFlowApp());
        await tester.pumpAndSettle();

        final context = tester.element(find.byType(Scaffold));

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
      await tester.pumpWidget(const CardFlowApp());
      await tester.pumpAndSettle();

      final context = tester.element(find.byType(Scaffold));
      expect(AppLocalizations.of(context).appTitle, 'CardFlow');
      expect(find.text('CardFlow'), findsOneWidget);
    });

    testWidgets('делегаты локализации Material и Widgets доступны', (
      tester,
    ) async {
      await tester.pumpWidget(const CardFlowApp());
      await tester.pumpAndSettle();

      final context = tester.element(find.byType(Scaffold));
      expect(MaterialLocalizations.of(context), isNotNull);
      expect(WidgetsLocalizations.of(context), isNotNull);
    });
  });
}
