import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'guard_utils.dart';

/// Пакеты-обёртки над WebView/HTML, запрещённые SPEC A3 полностью —
/// в том числе как транзитивные зависимости.
const List<String> forbiddenPackagePrefixes = <String>[
  'webview_flutter',
  'flutter_inappwebview',
  'flutter_html',
  'flutter_widget_from_html',
  'webview_flutter_plus',
  'flutter_webview_plugin',
  'webview_cef',
];

bool _isForbiddenPackage(String name) => forbiddenPackagePrefixes.any(
  (prefix) => name == prefix || name.startsWith('${prefix}_'),
);

/// Ищет запрещённые пакеты в тексте `pubspec.lock` / `pubspec.yaml`.
List<String> forbiddenPackagesIn(String source) =>
    findForbiddenPackages(source, forbiddenPackagePrefixes);

/// Ищет импорты запрещённых пакетов в исходнике Dart.
List<String> forbiddenImportsIn(String dartSource) {
  final imports = RegExp('''import\\s+['"]package:([a-z0-9_]+)/''');
  return imports
      .allMatches(dartSource)
      .map((match) => match.group(1)!)
      .where(_isForbiddenPackage)
      .toSet()
      .toList()
    ..sort();
}

void main() {
  group('no_webview: реальный репозиторий', () {
    test('pubspec.lock не содержит запрещённых пакетов (включая транзитивные)', () {
      final lock = readRepoFile('pubspec.lock');
      expect(
        forbiddenPackagesIn(lock),
        isEmpty,
        reason:
            'Запрещённые WebView/HTML-пакеты найдены в pubspec.lock (SPEC A3).',
      );
    });

    test('pubspec.yaml не объявляет запрещённых зависимостей', () {
      final pubspec = readRepoFile('pubspec.yaml');
      expect(
        forbiddenPackagesIn(pubspec),
        isEmpty,
        reason: 'Запрещённые WebView/HTML-пакеты объявлены в pubspec.yaml (SPEC A3).',
      );
    });

    test('исходники lib/ не импортируют запрещённые пакеты', () {
      final files = repoFiles(
        'lib',
        excludedDirs: const <String>{'.dart_tool', 'build'},
        include: (name) => name.endsWith('.dart'),
      );
      expect(
        files,
        isNotEmpty,
        reason: 'В lib/ нет Dart-файлов — проверка не имеет смысла.',
      );
      final violations = <String>[];
      for (final file in files) {
        final found = forbiddenImportsIn(file.readAsStringSync());
        if (found.isNotEmpty) {
          violations.add('${file.path}: ${found.join(', ')}');
        }
      }
      expect(
        violations,
        isEmpty,
        reason: 'Найдены импорты запрещённых пакетов: $violations',
      );
    });
  });

  group('no_webview: самопроверка детектора', () {
    test('находит прямую зависимость в pubspec.yaml', () {
      const source =
          'dependencies:\n  flutter:\n    sdk: flutter\n  webview_flutter: ^4.0.0\n';
      expect(forbiddenPackagesIn(source), contains('webview_flutter'));
    });

    test('находит транзитивную зависимость в pubspec.lock', () {
      const lock = '''
packages:
  flutter_inappwebview_android:
    dependency: transitive
    description:
      name: flutter_inappwebview_android
    version: "1.0.0"
''';
      expect(
        forbiddenPackagesIn(lock),
        contains('flutter_inappwebview_android'),
      );
    });

    test('не считает запрещённым безопасное имя', () {
      const lock = '''
packages:
  archive:
    dependency: "direct main"
    version: "4.0.7"
''';
      expect(forbiddenPackagesIn(lock), isEmpty);
      expect(
        forbiddenImportsIn("import 'package:archive/archive.dart';"),
        isEmpty,
      );
    });

    test('находит запрещённый импорт в Dart-файле', () {
      expect(
        forbiddenImportsIn("import 'package:flutter_html/flutter_html.dart';"),
        contains('flutter_html'),
      );
    });

    test('реальный pubspec.lock проекта существует и непустой', () {
      final lock = File(
        '${projectRoot().path}${Platform.pathSeparator}pubspec.lock',
      );
      expect(lock.existsSync(), isTrue);
      expect(lock.readAsStringSync().length, greaterThan(100));
    });
  });
}
