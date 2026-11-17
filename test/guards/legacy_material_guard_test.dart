import 'package:flutter_test/flutter_test.dart';

import 'guard_utils.dart';

/// Guard миграции этапа 3 (REDESIGN-SPEC §9, REDESIGN-PLAN «Экраны»).
///
/// Файл экрана считается переведённым на `Nc*`-компоненты, только если в нём
/// не осталось legacy-Material виджетов из списка этапа. Комментарии
/// вырезаются: упоминание имени в документации не считается использованием.
/// Список пополняется по шагам 3.1–3.8 в том же red-коммите, что и тесты
/// экрана.

/// Запрещённые виджеты (имя — для сообщения, шаблон — код).
const Map<String, String> bannedWidgets = <String, String>{
  'AppBar': r'\bAppBar\s*\(',
  'ListTile': r'\bListTile\s*\(',
  'SwitchListTile': r'\bSwitchListTile\s*\(',
  'FilledButton': r'\bFilledButton\s*\(',
  'SegmentedButton': r'\bSegmentedButton\s*\(',
  'Card': r'\bCard\s*\(',
  'M3ECard': r'\bM3ECard\s*\(',
  'M3ESplitButton': r'\bM3ESplitButton\s*\(',
  'M3EExtendedFab': r'\bM3EExtendedFab\s*\(',
  'CircularProgressIndicator': r'\bCircularProgressIndicator\s*\(',
  // Оболочка этапа 3.1: навигация — только `NcNavDock`/`NcNavRail`/сайдбар.
  'NavigationBar': r'\bNavigationBar\s*\(',
  'NavigationRail': r'\bNavigationRail\s*\(',
};

/// Переведённые файлы этапа 3 (пополняется по шагам).
const List<String> migratedFiles = <String>[
  'lib/ui/shell/app_shell.dart',
  'lib/ui/decks/decks_screen.dart',
  'lib/ui/decks/deck_actions.dart',
  'lib/ui/decks/deck_screen.dart',
  'lib/ui/cards/card_form_screen.dart',
  'lib/ui/cards/occlusion_mask_editor.dart',
  'lib/ui/cards/content/card_content_view.dart',
  'lib/ui/cards/content/card_image_view.dart',
  'lib/ui/cards/content/card_text.dart',
  'lib/ui/cards/content/cloze_text.dart',
  'lib/ui/cards/content/inline_latex_text.dart',
  'lib/ui/cards/content/latex_text.dart',
  'lib/ui/cards/content/occlusion_image_view.dart',
];

/// Убирает комментарии, чтобы упоминание виджета в документации не считалось
/// использованием.
String stripDartComments(String source) {
  final String withoutBlocks = source.replaceAll(RegExp(r'/\*[\s\S]*?\*/'), '');
  return withoutBlocks.replaceAll(RegExp(r'//[^\n]*'), '');
}

/// Найденные legacy-виджеты в [source] (отсортированные имена).
List<String> findLegacyWidgets(String source) {
  final String code = stripDartComments(source);
  final List<String> found = <String>[];
  for (final MapEntry<String, String> entry in bannedWidgets.entries) {
    if (RegExp(entry.value).hasMatch(code)) found.add(entry.key);
  }
  return found..sort();
}

void main() {
  group('guard миграции: экраны этапа 3 без legacy-Material', () {
    for (final String path in migratedFiles) {
      test('$path без AppBar/ListTile/FilledButton/M3E-виджетов', () {
        final List<String> found = findLegacyWidgets(readRepoFile(path));
        expect(
          found,
          isEmpty,
          reason:
              'В $path остались Material-виджеты $found — REDESIGN-SPEC §9 '
              'требует Nc*-компоненты (REDESIGN-PLAN, этап 3).',
        );
      });
    }
  });

  group('guard миграции: самопроверка', () {
    test('ловит legacy-виджеты', () {
      expect(
        findLegacyWidgets(
          'Widget build(BuildContext context) => Scaffold('
          'appBar: AppBar(title: Text("x")), '
          'body: ListTile(title: Text("y")));',
        ),
        <String>['AppBar', 'ListTile'],
      );
    });

    test('не путает Nc-компоненты с запрещёнными', () {
      expect(
        findLegacyWidgets(
          'NcTopBar(title: "x"); NcCardTile(title: Text("y")); '
          'NcSplitButton(label: "z"); NcListRow(title: Text("w"));',
        ),
        isEmpty,
      );
    });

    test('комментарии не считаются использованием', () {
      expect(
        findLegacyWidgets('// Заменяет AppBar(\n/* и ListTile( */\n'),
        isEmpty,
      );
    });
  });
}
