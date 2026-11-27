import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'guard_utils.dart';

/// Убирает строчные комментарии: проверяем только исполняемый код.
///
/// В `pdfium_bootstrap.dart` `HOME` упоминается **в объяснении дефекта**, а
/// `pdfrxInitialize()` — в доке `PdfParser`; guard не должен на них падать.
String _code(String source) {
  return source
      .split('\n')
      .where((String line) {
        final String trimmed = line.trimLeft();
        return !trimmed.startsWith('//') && !trimmed.startsWith('*');
      })
      .join('\n');
}

/// Guard TASK 04, часть 2: PDFium инициализируется только с явным каталогом.
///
/// `pdfrxInitialize()` без `tmpPath` на не-Windows платформах читает
/// `Platform.environment['HOME']!`; в Android-процессе `HOME` не задан, поэтому
/// разыменование `null` падало **до** открытия документа, и любой корректный
/// PDF показывал «Не удалось прочитать файл». Единственная разрешённая точка
/// инициализации — `ensurePdfiumInitialized` (`pdfium_bootstrap.dart`), которая
/// всегда передаёт `tmpPath`.
void main() {
  test('в lib/ нет pdfrxInitialize() вне pdfium_bootstrap.dart', () {
    final List<File> files = repoFiles(
      'lib',
      excludedDirs: const <String>{'.dart_tool', 'build'},
      include: (String name) => name.endsWith('.dart'),
    );
    expect(files, isNotEmpty);

    final violations = <String>[];
    for (final File file in files) {
      if (file.uri.pathSegments.last == 'pdfium_bootstrap.dart') continue;
      if (!RegExp(r'pdfrxInitialize\s*\(')
          .hasMatch(_code(file.readAsStringSync()))) {
        continue;
      }
      violations.add(file.path);
    }
    expect(
      violations,
      isEmpty,
      reason:
          'Прямой pdfrxInitialize() без tmpPath на Android падает на HOME '
          '(TASK 04). Используйте ensurePdfiumInitialized: $violations',
    );
  });

  test('ensurePdfiumInitialized передаёт tmpPath и не читает HOME', () {
    final String code = _code(
      readRepoFile('lib/api/parsers/pdfium_bootstrap.dart'),
    );
    expect(code, contains('pdfrxInitialize(tmpPath: path)'));
    expect(
      code,
      isNot(contains("environment['HOME']")),
      reason: 'HOME на Android не задан — каталог не должен от него зависеть',
    );
    expect(code, contains('Pdfrx.cacheDirectoryPath = path'));
  });
}
