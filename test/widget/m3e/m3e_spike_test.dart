// Спайк S2 (итерация 1): проверка, что M3E-компоненты реально рендерятся в
// widget-тесте под M3ETheme, подключённой через MaterialApp.builder.
//
// Это доказательство для ADR-007/ADR-001: если компонент M3E не работает в
// тестах, экран переводится на material_ui-эквивалент (фиксируется в отчёте).
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/ui/m3e/m3e.dart';
import 'package:cardflow/ui/theme/app_theme.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// Минимальный harness: MaterialApp (material_ui) + M3ETheme в builder.
///
/// `M3EMaterialApp` не принимает `routerConfig`, поэтому в приложении и в
/// тестах используется MaterialApp, а M3E-тема навешивается через `builder`.
Widget m3eHarness(Widget home) {
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    locale: const Locale('ru'),
    supportedLocales: AppLocalizations.supportedLocales,
    // Делегаты — из material_ui (ADR-001); `AppLocalizations.localizationsDelegates`
    // содержит framework-версию GlobalMaterialLocalizations и не подходит
    // для material_ui MaterialApp.
    localizationsDelegates: <LocalizationsDelegate<dynamic>>[
      AppLocalizations.delegate,
      ...GlobalMaterialLocalizations.delegates,
    ],
    theme: AppTheme.light(),
    darkTheme: AppTheme.dark(),
    builder: (BuildContext context, Widget? child) {
      final Brightness brightness = MediaQuery.platformBrightnessOf(context);
      return M3ETheme(
        data: brightness == Brightness.dark
            ? M3EThemeData.dark(seedColor: AppTheme.seedColor)
            : M3EThemeData.light(seedColor: AppTheme.seedColor),
        child: child!,
      );
    },
    home: home,
  );
}

void main() {
  group('Спайк S2: M3E-компоненты рендерятся под M3ETheme', () {
    testWidgets('M3ECard с headline/subhead/supportingText и onPressed', (
      WidgetTester tester,
    ) async {
      var presses = 0;
      final Widget home = Scaffold(
        body: M3ECard(
          headline: 'Колода «Испанский»',
          subhead: '12 карточек',
          supportingText: 'К повторению: 3',
          onPressed: () => presses++,
        ),
      );

      await tester.pumpWidget(m3eHarness(home));
      await tester.pumpAndSettle();

      expect(find.byType(M3ECard), findsOneWidget);
      expect(find.text('Колода «Испанский»'), findsOneWidget);
      expect(find.text('12 карточек'), findsOneWidget);
      expect(find.text('К повторению: 3'), findsOneWidget);

      await tester.tap(find.text('Колода «Испанский»'));
      await tester.pumpAndSettle();
      expect(presses, 1);
    });

    testWidgets('M3EChip (filter) рендерится и переключается', (
      WidgetTester tester,
    ) async {
      var selected = false;
      final Widget home = StatefulBuilder(
        builder: (BuildContext context, StateSetter setState) {
          return Scaffold(
            body: M3EChip(
              label: 'Просроченные',
              type: M3EChipType.filter,
              selected: selected,
              onPressed: () => setState(() => selected = !selected),
            ),
          );
        },
      );

      await tester.pumpWidget(m3eHarness(home));
      await tester.pumpAndSettle();

      expect(find.byType(M3EChip), findsOneWidget);
      expect(find.text('Просроченные'), findsOneWidget);
      await tester.tap(find.text('Просроченные'));
      await tester.pumpAndSettle();
      expect(selected, isTrue);
    });

    testWidgets('M3ESnackbar.show показывает сообщение и действие', (
      WidgetTester tester,
    ) async {
      var undone = false;
      final Widget home = Scaffold(
        body: Builder(
          builder: (BuildContext context) {
            return Center(
              child: TextButton(
                onPressed: () {
                  M3ESnackbar.show(
                    context,
                    message: 'Колода в архиве',
                    actionLabel: 'Отменить',
                    onAction: () => undone = true,
                    duration: const Duration(seconds: 10),
                  );
                },
                child: const Text('Показать снекбар'),
              ),
            );
          },
        ),
      );

      await tester.pumpWidget(m3eHarness(home));
      await tester.pumpAndSettle();

      await tester.tap(find.text('Показать снекбар'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      expect(find.text('Колода в архиве'), findsOneWidget);
      expect(find.text('Отменить'), findsOneWidget);

      await tester.tap(find.text('Отменить'));
      await tester.pump();
      expect(undone, isTrue);

      // Убираем снекбар, чтобы не влиял на следующий тест.
      M3ESnackbar.defaultController.dismiss(immediate: true);
      await tester.pumpAndSettle();
    });

    testWidgets('M3EExtendedFab и M3ESplitButton рендерятся', (
      WidgetTester tester,
    ) async {
      final Widget home = Scaffold(
        body: Column(
          children: <Widget>[
            M3EExtendedFab(
              label: 'Создать колоду',
              icon: const Icon(Icons.add),
              onPressed: () {},
            ),
            M3ESplitButton<String>(
              label: 'Создать',
              items: const <M3ESplitButtonItem<String>>[
                M3ESplitButtonItem<String>(value: 'manual', child: 'Вручную'),
                M3ESplitButtonItem<String>(value: 'zip', child: 'Импорт ZIP'),
              ],
              onSelected: (_) {},
            ),
          ],
        ),
      );

      await tester.pumpWidget(m3eHarness(home));
      await tester.pumpAndSettle();

      expect(find.byType(M3EExtendedFab), findsOneWidget);
      expect(find.text('Создать колоду'), findsOneWidget);
      expect(find.byType(M3ESplitButton<String>), findsOneWidget);
      expect(find.text('Создать'), findsOneWidget);
    });
  });
}
