import 'package:flutter_test/flutter_test.dart';

import 'guard_utils.dart';

/// Шрифты — только локальные ассеты: `google_fonts` запрещён (SPEC A4,
/// REDESIGN-SPEC §2.1, ADR-035). Guard проверяет `pubspec.yaml` и
/// `pubspec.lock` (включая транзитивные записи).
const List<String> forbiddenFontPackages = <String>['google_fonts'];

bool _isForbidden(String name) => forbiddenFontPackages.any(
  (prefix) => name == prefix || name.startsWith('${prefix}_'),
);

/// Пакеты из сетевых загрузчиков шрифтов, найденные в тексте pubspec.
List<String> networkFontPackagesIn(String source) =>
    findForbiddenPackages(source, forbiddenFontPackages);

/// Импорты сетевых загрузчиков шрифтов в исходнике Dart.
List<String> networkFontImportsIn(String dartSource) {
  final imports = RegExp('''import\\s+['"]package:([a-z0-9_]+)/''');
  return imports
      .allMatches(dartSource)
      .map((match) => match.group(1)!)
      .where(_isForbidden)
      .toSet()
      .toList()
    ..sort();
}

void main() {
  group('no_network_fonts: реальный репозиторий', () {
    test('pubspec.lock не содержит сетевых загрузчиков шрифтов', () {
      expect(
        networkFontPackagesIn(readRepoFile('pubspec.lock')),
        isEmpty,
        reason:
            'Пакет из сетевых загрузчиков шрифтов попал в pubspec.lock '
            '(включая транзитивные): шрифты — только ассеты (ADR-035).',
      );
    });

    test('pubspec.yaml не объявляет сетевых загрузчиков шрифтов', () {
      expect(
        networkFontPackagesIn(readRepoFile('pubspec.yaml')),
        isEmpty,
        reason: 'Сетевые загрузчики шрифтов запрещены (ADR-035).',
      );
    });

    test('lib/ не импортирует сетевые загрузчики шрифтов', () {
      final files = repoFiles(
        'lib',
        excludedDirs: const <String>{'.dart_tool', 'build'},
        include: (name) => name.endsWith('.dart'),
      );
      expect(files, isNotEmpty);
      final violations = <String>[];
      for (final file in files) {
        final found = networkFontImportsIn(file.readAsStringSync());
        if (found.isNotEmpty) {
          violations.add('${file.path}: ${found.join(', ')}');
        }
      }
      expect(violations, isEmpty, reason: violations.join('\n'));
    });
  });

  group('no_network_fonts: самопроверка детектора', () {
    test('находит пакет в pubspec.yaml и pubspec.lock', () {
      expect(
        networkFontPackagesIn('dependencies:\n  google_fonts: ^6.0.0\n'),
        contains('google_fonts'),
      );
      expect(
        networkFontPackagesIn(
          'packages:\n  google_fonts:\n    dependency: transitive\n',
        ),
        contains('google_fonts'),
      );
    });

    test('находит импорт в Dart-файле', () {
      expect(
        networkFontImportsIn(
          "import 'package:google_fonts/google_fonts.dart';",
        ),
        contains('google_fonts'),
      );
    });

    test('не ловит похожие безопасные имена', () {
      expect(
        networkFontPackagesIn('dependencies:\n  animated_text_kit: ^4.0.0\n'),
        isEmpty,
      );
      expect(
        networkFontImportsIn("import 'package:flutter/services.dart';"),
        isEmpty,
      );
    });
  });
}
