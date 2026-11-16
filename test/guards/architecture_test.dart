import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'guard_utils.dart';

/// Архитектурные guard-правила из AGENTS.md и ADR-001:
/// 1) `package:flutter/material.dart` в `lib/` запрещён — Material-база только `material_ui`;
/// 2) `material_3_expressive` импортируется только через `lib/ui/m3e/`;
/// 3) `lib/domain/` не зависит от Flutter/Material/UI-пакетов;
/// 4) `lib/ui/design/` (дизайн-система Nocturne) не зависит от слоёв
///    состояния, роутера, домена, данных и API (ADR-035, REDESIGN-PLAN 1.1).
const String frameworkMaterialImport = 'package:flutter/material.dart';
const String m3ePackagePrefix = 'package:material_3_expressive/';

/// Что дизайн-система не имеет права импортировать (кроме Flutter/Material).
const List<String> designForbiddenPrefixes = <String>[
  'package:cardflow/ui/state/',
  'package:cardflow/ui/router/',
  'package:cardflow/domain/',
  'package:cardflow/data/',
  'package:cardflow/api/',
];

/// Префикс каталога дизайн-системы.
const String designPathPrefix = 'lib/ui/design/';

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
  if (path.startsWith(designPathPrefix)) {
    for (final import in imports) {
      if (designForbiddenPrefixes.any(import.startsWith)) {
        violations.add(
          '$path: дизайн-система не должна импортировать $import '
          '(ADR-035: значения передаются сверху InheritedWidget)',
        );
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

    test('ловит импорт слоёв состояния/домена в дизайн-системе', () {
      for (final String forbidden in designForbiddenPrefixes) {
        expect(
          architectureViolations(
            'lib/ui/design/nc_theme.dart',
            "import '${forbidden}app_providers.dart';",
          ),
          isNotEmpty,
          reason: 'Дизайн-система не должна импортировать $forbidden',
        );
      }
    });

    test('дизайн-система может импортировать Flutter и токены', () {
      expect(
        architectureViolations(
          'lib/ui/design/ambient/ambient_background.dart',
          "import 'package:material_ui/material_ui.dart';\n"
              "import 'package:cardflow/ui/design/tokens/nc_colors.dart';",
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
