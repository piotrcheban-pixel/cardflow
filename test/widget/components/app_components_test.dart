import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cardflow/ui/components/app_dialogs.dart';
import 'package:cardflow/ui/components/app_layout.dart';
import 'package:cardflow/ui/components/app_surfaces.dart';

import '../../helpers/pump_app.dart';

/// Дизайн-система v2 (ADR-038): общие компоненты и правило диалогов ADR-036.
void main() {
  Future<void> pumpHome(WidgetTester tester, Widget home) async {
    await tester.pumpWidget(
      appWithHome(overrides: const <Override>[], home: home),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('AppPanel: нажатие и семантика, содержимое видно', (
    WidgetTester tester,
  ) async {
    int taps = 0;
    await pumpHome(
      tester,
      Scaffold(
        body: AppPanel(
          onTap: () => taps++,
          semanticLabel: 'Панель',
          child: const Text('Содержимое'),
        ),
      ),
    );

    expect(find.text('Содержимое'), findsOneWidget);
    await tester.tap(find.text('Содержимое'));
    await tester.pumpAndSettle();
    expect(taps, 1);
    expect(
      tester.getSemantics(find.text('Содержимое')).label,
      contains('Панель'),
    );
  });

  testWidgets('AppStatusChip: тона используют роли темы', (
    WidgetTester tester,
  ) async {
    await pumpHome(
      tester,
      const Scaffold(
        body: Wrap(
          children: <Widget>[
            AppStatusChip(label: 'Успех', tone: AppStatusTone.success),
            AppStatusChip(
              label: 'Ошибка',
              tone: AppStatusTone.danger,
              icon: Icons.error_outline,
            ),
          ],
        ),
      ),
    );

    expect(find.text('Успех'), findsOneWidget);
    expect(find.text('Ошибка'), findsOneWidget);
    final BuildContext context = tester.element(find.text('Успех'));
    final ColorScheme scheme = Theme.of(context).colorScheme;
    final Container container = tester.widget<Container>(
      find
          .ancestor(of: find.text('Успех'), matching: find.byType(Container))
          .first,
    );
    expect(
      (container.decoration! as BoxDecoration).color,
      scheme.secondaryContainer,
    );
  });

  testWidgets('AppProgressBar: значение и семантика', (
    WidgetTester tester,
  ) async {
    await pumpHome(
      tester,
      const Scaffold(
        body: AppProgressBar(value: 0.4, semanticsLabel: 'Прогресс'),
      ),
    );
    final LinearProgressIndicator indicator = tester
        .widget<LinearProgressIndicator>(find.byType(LinearProgressIndicator));
    expect(indicator.value, 0.4);
    expect(indicator.semanticsLabel, 'Прогресс');
  });

  testWidgets('AppEmptyState и AppErrorState: действия живые', (
    WidgetTester tester,
  ) async {
    int retries = 0;
    await pumpHome(
      tester,
      Scaffold(
        body: ListView(
          children: <Widget>[
            AppEmptyState(
              icon: Icons.inbox,
              title: 'Пусто',
              message: 'Ничего нет',
              actions: <Widget>[
                FilledButton(onPressed: () {}, child: const Text('Создать')),
              ],
            ),
            AppErrorState(
              message: 'Ошибка загрузки',
              retryLabel: 'Повторить',
              onRetry: () => retries++,
            ),
          ],
        ),
      ),
    );

    expect(find.text('Пусто'), findsOneWidget);
    expect(find.text('Ничего нет'), findsOneWidget);
    expect(find.text('Создать'), findsOneWidget);
    await tester.ensureVisible(find.text('Повторить'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Повторить'));
    await tester.pumpAndSettle();
    expect(retries, 1);
  });

  testWidgets('AppDialog закрывается из контекста диалога (правило ADR-036)', (
    WidgetTester tester,
  ) async {
    String? result;
    await pumpHome(
      tester,
      Scaffold(
        body: Builder(
          builder: (BuildContext context) => Center(
            child: FilledButton(
              key: const ValueKey<String>('open-dialog'),
              onPressed: () async {
                result = await showAppDialog<String>(
                  context: context,
                  title: 'Заголовок',
                  subtitle: 'Пояснение',
                  closeLabel: 'Закрыть',
                  bodyBuilder: (BuildContext dialogContext) =>
                      const Text('Тело диалога'),
                  actionsBuilder: (BuildContext dialogContext) => <Widget>[
                    TextButton(
                      key: const ValueKey<String>('dialog-confirm'),
                      onPressed: () =>
                          Navigator.of(dialogContext).pop('готово'),
                      child: const Text('Подтвердить'),
                    ),
                  ],
                );
              },
              child: const Text('Открыть'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey<String>('open-dialog')));
    await tester.pumpAndSettle();
    expect(find.text('Тело диалога'), findsOneWidget);
    expect(find.text('Пояснение'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey<String>('dialog-confirm')));
    await tester.pumpAndSettle();
    expect(find.text('Тело диалога'), findsNothing);
    expect(find.text('Открыть'), findsOneWidget);
    expect(result, 'готово');
  });

  testWidgets('AppSheetHeader и showAppSheet: лист возвращает выбор', (
    WidgetTester tester,
  ) async {
    String? chosen;
    await pumpHome(
      tester,
      Scaffold(
        body: Builder(
          builder: (BuildContext context) => Center(
            child: FilledButton(
              onPressed: () async {
                chosen = await showAppSheet<String>(
                  context: context,
                  builder: (BuildContext sheetContext) => Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      const AppSheetHeader(
                        title: 'Выбор',
                        subtitle: 'Один вариант',
                      ),
                      ListTile(
                        key: const ValueKey<String>('sheet-choice'),
                        title: const Text('Вариант'),
                        onTap: () => Navigator.of(sheetContext).pop('вариант'),
                      ),
                    ],
                  ),
                );
              },
              child: const Text('Открыть лист'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('Открыть лист'));
    await tester.pumpAndSettle();
    expect(find.text('Выбор'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey<String>('sheet-choice')));
    await tester.pumpAndSettle();
    expect(find.text('Выбор'), findsNothing);
    expect(chosen, 'вариант');
  });

  testWidgets('AppPageHeader: на узком экране действия переносятся', (
    WidgetTester tester,
  ) async {
    tester.view.physicalSize = const Size(360, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await pumpHome(
      tester,
      Scaffold(
        body: AppPageScaffold(
          header: AppPageHeader(
            title: 'Заголовок страницы',
            breadcrumb: 'КОНФИГУРАЦИЯ / Система',
            subtitle: const Text('Пояснение'),
            actions: <Widget>[
              OutlinedButton(onPressed: () {}, child: const Text('Импорт')),
              FilledButton(onPressed: () {}, child: const Text('Создать')),
            ],
          ),
          slivers: const <Widget>[Text('Контент')],
        ),
      ),
    );

    expect(find.text('Заголовок страницы'), findsOneWidget);
    expect(find.text('Импорт'), findsOneWidget);
    expect(find.text('Создать'), findsOneWidget);
    expect(find.text('Контент'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('AppDashedBorder рисуется без исключений', (
    WidgetTester tester,
  ) async {
    await pumpHome(
      tester,
      const Scaffold(
        body: AppDashedBorder(
          child: Padding(padding: EdgeInsets.all(24), child: Text('Зона')),
        ),
      ),
    );
    expect(find.text('Зона'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
