import 'dart:io';

/// Проверяет покрытие рукописного кода по `coverage/lcov.info`.
///
/// Сгенерированные файлы (`*.g.dart`, `*.freezed.dart`, `app_localizations*.dart`,
/// `*.mocks.dart`) исключаются: они не пишутся руками и в порог не входят.
///
/// Запуск: `dart run tool/coverage_check.dart --min=80`
void main(List<String> args) {
  var minPercent = 80.0;
  for (final arg in args) {
    if (arg.startsWith('--min=')) {
      minPercent = double.parse(arg.substring('--min='.length));
    }
  }

  final lcovFile = File('coverage/lcov.info');
  if (!lcovFile.existsSync()) {
    stderr.writeln(
      'coverage/lcov.info не найден. Сначала: fvm flutter test --coverage',
    );
    exit(2);
  }

  // Исключения из покрытия (ADR-005, addendum):
  //  - сгенерированный код — не пишется руками;
  //  - `lib/data/db/tables.dart` — декларативный DSL drift: геттеры колонок
  //    заменяются сгенерированными полями `$...Table`, пользовательские
  //    геттеры в рантайме не исполняются (0/89 строк законно). Сама схема
  //    проверяется schema-тестом по PRAGMA/sqlite_master, а не покрытием.
  final excluded = <RegExp>[
    RegExp(r'\.g\.dart$'),
    RegExp(r'\.freezed\.dart$'),
    RegExp(r'\.mocks\.dart$'),
    RegExp(r'app_localizations(_[a-z]+)?\.dart$'),
    RegExp(r'^lib/data/db/tables\.dart$'),
  ];

  final records = <_FileCoverage>[];
  _FileCoverage? current;
  for (final rawLine in lcovFile.readAsLinesSync()) {
    final line = rawLine.trim();
    if (line.startsWith('SF:')) {
      current = _FileCoverage(line.substring(3));
    } else if (line.startsWith('DA:') && current != null) {
      final parts = line.substring(3).split(',');
      if (parts.length >= 2) {
        current.addLine(int.parse(parts[0]), int.parse(parts[1]));
      }
    } else if (line == 'end_of_record' && current != null) {
      records.add(current);
      current = null;
    }
  }

  final handwritten = records.where((record) {
    final path = record.path.replaceAll(r'\', '/');
    if (!path.startsWith('lib/')) return false;
    return !excluded.any((pattern) => pattern.hasMatch(path));
  }).toList()..sort((a, b) => a.path.compareTo(b.path));

  if (handwritten.isEmpty) {
    stderr.writeln('В lcov.info нет файлов рукописного кода из lib/.');
    exit(2);
  }

  var totalLines = 0;
  var totalHit = 0;
  stdout.writeln(
    'Покрытие рукописного кода (lib/, без сгенерированных файлов):',
  );
  for (final record in handwritten) {
    totalLines += record.total;
    totalHit += record.hit;
    stdout.writeln(
      '  ${record.percent.toStringAsFixed(1).padLeft(5)}%  '
      '(${record.hit}/${record.total})  ${record.path}',
    );
  }

  final percent = totalLines == 0 ? 0.0 : totalHit * 100 / totalLines;
  stdout.writeln(
    '\nИтого: ${percent.toStringAsFixed(1)}% ($totalHit/$totalLines), '
    'порог ${minPercent.toStringAsFixed(1)}%',
  );

  // Предупреждение о рукописных файлах lib/, не попавших в lcov
  // (например, точка входа lib/main.dart не исполняется в тестах).
  final measured = handwritten
      .map((record) => record.path.replaceAll(r'\', '/'))
      .toSet();
  final missing = <String>[];
  final libDir = Directory('lib');
  if (libDir.existsSync()) {
    for (final entity in libDir.listSync(recursive: true, followLinks: false)) {
      if (entity is! File) continue;
      final path = entity.path.replaceAll(r'\', '/');
      if (!path.endsWith('.dart')) continue;
      if (excluded.any((pattern) => pattern.hasMatch(path))) continue;
      if (measured.contains(path)) continue;
      missing.add(path);
    }
  }
  if (missing.isNotEmpty) {
    stdout.writeln('\nНе измерены (нет в lcov): ${missing.join(', ')}');
  }

  if (percent + 1e-9 < minPercent) {
    stderr.writeln(
      'ПОКРЫТИЕ НИЖЕ ПОРОГА: ${percent.toStringAsFixed(1)}% < $minPercent%',
    );
    exit(1);
  }
  stdout.writeln('ПОРОГ ПРОЙДЕН');
}

class _FileCoverage {
  _FileCoverage(this.path);

  final String path;
  final Map<int, int> lines = <int, int>{};

  void addLine(int line, int count) => lines[line] = count;

  int get total => lines.length;

  int get hit => lines.values.where((count) => count > 0).length;

  double get percent => total == 0 ? 100 : hit * 100 / total;
}
