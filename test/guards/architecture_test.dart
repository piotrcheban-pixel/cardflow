import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'guard_utils.dart';

/// Архитектурные guard-правила из AGENTS.md и ADR-001:
/// 1) `package:flutter/material.dart` в `lib/` запрещён — Material-база только `material_ui`;
/// 2) `material_3_expressive` импортируется только через `lib/ui/m3e/`;
/// 3) `lib/domain/` не зависит от Flutter/Material/UI-пакетов.
const String frameworkMaterialImport = 'package:flutter/material.dart';
const String m3ePackagePrefix = 'package:material_3_expressive/';

const List<String> domainForbiddenPrefixes = <String>[
  'package:flutter/',
  'package:material_ui/',
  'package:material_3_expressive/',
  'package:cupertino_ui/',
];

/// Все импорты пакетов из исходника Dart.
List<String> packageImports(String dartSource) {
  final pattern = RegExp('''import\\s+['"](package:[^'"]+)['"]''');
  return pattern
      .allMatches(dartSource)
      .map((match) => match.group(1)!)
      .toList();
}

/// Нарушения архитектурных правил для файла `relativePath` (например `lib/ui/app.dart`).
List<String> architectureViolations(String relativePath, String dartSource) {
  final violations = <String>[];
  final path = relativePath.replaceAll(r'\', '/');
  final imports = packageImports(dartSource);

  if (imports.contains(frameworkMaterialImport)) {
    violations.add(
      '$path: импорт $frameworkMaterialImport запрещён (ADR-001: только material_ui)',
    );
  }
  for (final import in imports) {
    if (import.startsWith(m3ePackagePrefix) &&
        !path.startsWith('lib/ui/m3e/')) {
      violations.add('$path: импорт $import разрешён только в lib/ui/m3e/');
    }
  }
  if (path.startsWith('lib/domain/')) {
    for (final import in imports) {
      if (domainForbiddenPrefixes.any(import.startsWith)) {
        violations.add('$path: domain не должен импортировать $import');
      }
    }
  }
  return violations;
}

void main() {
  group('architecture: реальный репозиторий', () {
    test('lib/ не содержит запрещённых импортов', () {
      final files = repoFiles(
        'lib',
        excludedDirs: const <String>{'.dart_tool', 'build'},
        include: (name) => name.endsWith('.dart'),
      );
      expect(files, isNotEmpty);

      final violations = <String>[];
      final root = projectRoot().path;
      for (final file in files) {
        final relative = file.path
            .substring(root.length + 1)
            .replaceAll(Platform.pathSeparator, '/');
        violations.addAll(
          architectureViolations(relative, file.readAsStringSync()),
        );
      }
      expect(violations, isEmpty, reason: violations.join('\n'));
    });
  });

  group('architecture: самопроверка детектора', () {
    test('ловит framework Material в lib/', () {
      expect(
        architectureViolations(
          'lib/ui/app.dart',
          "import 'package:flutter/material.dart';",
        ),
        isNotEmpty,
      );
    });

    test('ловит M3E-импорт вне lib/ui/m3e/', () {
      expect(
        architectureViolations(
          'lib/ui/decks/decks_screen.dart',
          "import 'package:material_3_expressive/material_3_expressive.dart';",
        ),
        isNotEmpty,
      );
      expect(
        architectureViolations(
          'lib/ui/m3e/m3e.dart',
          "export 'package:material_3_expressive/material_3_expressive.dart';",
        ),
        isEmpty,
      );
    });

    test('ловит Flutter-импорт в domain', () {
      expect(
        architectureViolations(
          'lib/domain/scheduling/rating.dart',
          "import 'package:flutter/widgets.dart';",
        ),
        isNotEmpty,
      );
      expect(
        architectureViolations(
          'lib/domain/scheduling/rating.dart',
          "import 'package:fsrs/fsrs.dart';",
        ),
        isEmpty,
      );
    });

    test('не ловит material_ui в ui', () {
      expect(
        architectureViolations(
          'lib/ui/app.dart',
          "import 'package:material_ui/material_ui.dart';",
        ),
        isEmpty,
      );
    });

    test('извлекает импорты и игнорирует экспорт', () {
      final imports = packageImports(
        "import 'dart:io';\nimport 'package:fsrs/fsrs.dart';\n"
        "export 'package:material_3_expressive/material_3_expressive.dart';",
      );
      expect(imports, <String>['package:fsrs/fsrs.dart']);
    });
  });
}
