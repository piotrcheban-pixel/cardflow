import 'dart:io';

import 'package:cardflow/api/parsers/pdfium_bootstrap.dart';
import 'package:flutter_test/flutter_test.dart';

/// TASK 04, часть 2: каталог кэша PDFium не вычисляется из `HOME`.
///
/// Причина дефекта «PDF на Android → Не удалось прочитать файл»:
/// `pdfrxInitialize()` без `tmpPath` на не-Windows платформах делает
/// `Platform.environment['HOME']!`, а в Android-процессе `HOME` не задан —
/// `null check operator used on a null value` **до** открытия документа, и
/// парсер возвращал `unreadableFile` на любом корректном PDF.
void main() {
  test('явный каталог кэша имеет приоритет над значением по умолчанию', () {
    const String explicit = '/data/user/0/ru.example/cardflow/cache/pdfium';
    expect(pdfiumCacheDirectoryFor(explicit), explicit);
    expect(pdfiumCacheDirectoryFor('  $explicit  '), explicit);
  });

  test('без явного каталога используется временный каталог ОС', () {
    final String fallback = pdfiumCacheDirectoryFor(null);
    expect(fallback, startsWith(Directory.systemTemp.path));
    expect(fallback, contains('cardflow-pdf'));
    expect(pdfiumCacheDirectoryFor(''), fallback);
    expect(pdfiumCacheDirectoryFor('   '), fallback);
  });

  test('каталог по умолчанию не вычисляется из переменных окружения', () {
    // Ключ HOME может быть задан на Windows; важно, что функция его не
    // использует: значение — всегда systemTemp, даже если HOME другой.
    final String? home = Platform.environment['HOME'];
    final String fallback = pdfiumCacheDirectoryFor(null);
    if (home != null && home.isNotEmpty) {
      expect(fallback, isNot('$home/.pdfrx'));
    }
    expect(fallback, startsWith(Directory.systemTemp.path));
  });
}
