import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'guard_utils.dart';

/// Guard-тест дизайн-системы Nocturne (REDESIGN-SPEC §1.1, ADR-035):
/// сырые цвета (`Color(0x…)`, `Colors.*`, `Color.fromARGB/RGBO`) в `lib/ui/**`
/// разрешены только в `lib/ui/design/tokens/nc_colors.dart`.
///
/// Долг этапа 1: на старте редизайна в `lib/ui/` уже были литералы цвета
/// (экраны «Теста»/«Ввода», просмотр картинки, старый `AppTheme`). Экранные
/// файлы на этапе 1 не редактируются, поэтому долг заморожен в
/// `fixtures/design_tokens_baseline.txt`: новый литерал валит тест сразу, а
/// вычищенный требует удалить строку из фикстуры (burn-down в этапах 3–4).
const String tokensFile = 'lib/ui/design/tokens/nc_colors.dart';

/// Фикстура замороженного долга.
const String designTokensBaselinePath =
    'test/guards/fixtures/design_tokens_baseline.txt';

/// Литералы цвета, которые ищет guard.
final List<RegExp> rawColorPatterns = <RegExp>[
  RegExp(r'Color\(0x[0-9A-Fa-f]{6,8}\)'),
  RegExp(r'\bColors\.[A-Za-z][A-Za-z0-9]*'),
  RegExp(r'Color\.fromARGB'),
  RegExp(r'Color\.fromRGBO'),
];

/// Одно нарушение: файл и найденный литерал.
class RawColorViolation {
  /// Создаёт нарушение.
  const RawColorViolation(this.file, this.literal);

  /// Путь относительно корня проекта (`lib/ui/...`).
  final String file;

  /// Точный найденный литерал.
  final String literal;

  /// Строка фикстуры (`путь<TAB>литерал`).
  String get key => '$file\t$literal';

  @override
  String toString() => key;
}

/// Ищет литералы цвета в исходнике [dartSource] файла [relativePath].
List<RawColorViolation> findRawColors(String relativePath, String dartSource) {
  final path = relativePath.replaceAll(r'\', '/');
  final violations = <RawColorViolation>[];
  for (final String line in dartSource.split('\n')) {
    // Комментарии не влияют на рендер — не считаем литералом.
    if (line.trimLeft().startsWith('//')) continue;
    for (final RegExp pattern in rawColorPatterns) {
      for (final RegExpMatch match in pattern.allMatches(line)) {
        violations.add(RawColorViolation(path, match.group(0)!));
      }
    }
  }
  return violations;
}

/// Все нарушения в `lib/ui/**` (кроме файла токенов).
List<RawColorViolation> scanUiRawColors() {
  final files = repoFiles('lib/ui', include: (name) => name.endsWith('.dart'));
  final root = projectRoot().path;
  final violations = <RawColorViolation>[];
  for (final File file in files) {
    final String relative = file.path
        .substring(root.length + 1)
        .replaceAll(Platform.pathSeparator, '/');
    if (relative == tokensFile) continue;
    violations.addAll(findRawColors(relative, file.readAsStringSync()));
  }
  return violations;
}

void main() {
  group('design_tokens: реальный репозиторий', () {
    test('сырые цвета только в nc_colors.dart', () {
      final Set<String> current = scanUiRawColors()
          .map((violation) => violation.key)
          .toSet();
      final Set<String> baseline = readFixtureSet(designTokensBaselinePath);

      final List<String> added = current.difference(baseline).toList()..sort();
      expect(
        added,
        isEmpty,
        reason:
            'Сырые цвета вне $tokensFile. Используйте NcTheme/NcColors '
            '(REDESIGN-SPEC §1.1, ADR-035):\n${added.join('\n')}',
      );

      final List<String> stale = baseline.difference(current).toList()..sort();
      expect(
        stale,
        isEmpty,
        reason:
            'Долг из $designTokensBaselinePath закрыт — удалите строки из '
            'фикстуры (burn-down):\n${stale.join('\n')}',
      );
    });
  });

  group('design_tokens: самопроверка детектора', () {
    test('ловит Color(0x…), Colors.*, fromARGB и fromRGBO', () {
      final List<RawColorViolation> found = findRawColors(
        'lib/ui/foo.dart',
        'final Color a = Color(0xFF112233);\n'
            'final Color b = Colors.red;\n'
            'final Color c = Color.fromARGB(255, 1, 2, 3);\n'
            'final Color d = Color.fromRGBO(1, 2, 3, 0.5);\n',
      );
      expect(found.map((violation) => violation.literal).toList(), <String>[
        'Color(0xFF112233)',
        'Colors.red',
        'Color.fromARGB',
        'Color.fromRGBO',
      ]);
    });

    test('не ловит токены, роли темы и комментарии', () {
      expect(
        findRawColors(
          'lib/ui/foo.dart',
          'final Color a = NcColors.dark.ink0;\n'
              'color: Theme.of(context).colorScheme.primary;\n'
              '// Colors.red в комментарии не считается\n',
        ),
        isEmpty,
      );
    });
  });
}
