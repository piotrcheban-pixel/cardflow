import 'package:flutter_test/flutter_test.dart';

import 'guard_utils.dart';

/// Guard L26: PDF-тесты в CI должны реально выполняться на Linux и macOS.
///
/// `flutter test` на этих ОС не находит PDFium сам: Flutter engine cache не
/// содержит `libpdfium`, а `pdfium_dart` 0.4.1 в тестовом окружении не находит
/// bundled native asset (L26, CI run 43484685899). Поэтому workflow обязан
/// скачать тот же релиз PDFium, который использует build-hook `pdfium_dart`
/// (`bblanchon/pdfium-binaries`, `chromium/8125`), и экспортировать
/// `PDFIUM_PATH` до шага тестов. Этот guard ловит удаление/переупорядочивание
/// шага (иначе `test (ubuntu/macos)` снова станут красными).
///
/// Второй guard запрещает «зелёный, потому что выключили»: PDF-тесты не
/// помечаются `skip`/тегом и в `setUpAll` реально вызывают `pdfrxInitialize()`.
void main() {
  final String workflow = readRepoFile('.github/workflows/ci.yml');

  /// Текст job'а `test` (от объявления до следующего job'а).
  String testJobSection() {
    final int start = workflow.indexOf('\n  test:\n');
    if (start < 0) {
      return '';
    }
    final int next = workflow.indexOf('\n  build-desktop:', start);
    return next < 0
        ? workflow.substring(start)
        : workflow.substring(start, next);
  }

  test('workflow: job test скачивает PDFium из pinned-релиза для Linux/macOS', () {
    final String job = testJobSection();
    expect(job, isNotEmpty, reason: 'в ci.yml не найден job test');

    expect(
      job,
      contains('PDFium для PDF-тестов'),
      reason: 'нет шага бутстрапа PDFium в job test',
    );
    // Тот же релиз, который pdfium_dart 0.4.1 скачивает своим build-hook;
    // другой релиз может не совпасть с привязками pdfium_dart.
    expect(
      job,
      contains('bblanchon/pdfium-binaries/releases/download/chromium%2F8125'),
      reason: 'PDFium должен скачиваться из pinned-релиза chromium/8125',
    );
    expect(job, contains('pdfium-linux-x64.tgz'));
    expect(job, contains('pdfium-mac-arm64.tgz'));
    expect(job, contains('lib/libpdfium.so'));
    expect(job, contains('lib/libpdfium.dylib'));
    expect(job, contains('PDFIUM_PATH='));
    expect(job, contains(r'>> "$GITHUB_ENV"'));
    expect(
      job,
      contains("if: runner.os != 'Windows'"),
      reason:
          'на Windows PDFium работает без бутстрапа — шаг не должен его ломать',
    );
  });

  test('workflow: PDFium-шаг стоит до шага тестов и не в build-job', () {
    final String job = testJobSection();
    final int bootstrap = job.indexOf('PDFium для PDF-тестов');
    final int tests = job.indexOf('Тесты (кроме golden)');
    expect(bootstrap, greaterThan(0));
    expect(tests, greaterThan(0));
    expect(
      bootstrap,
      lessThan(tests),
      reason: 'PDFIUM_PATH должен быть в env до запуска тестов',
    );

    final int buildMobile = workflow.indexOf('\n  build-mobile:\n');
    expect(
      workflow.indexOf('PDFium для PDF-тестов', buildMobile),
      -1,
      reason:
          'бутстрап PDFium нужен только job-у test (сборки не гоняют тесты)',
    );
  });

  test('PDF-тесты не пропускаются молча: setUpAll инициализирует PDFium', () {
    for (final String path in <String>[
      'test/unit/api/parsers/pdf_parser_test.dart',
      'test/integration/file_parsing_pipeline_test.dart',
    ]) {
      final String source = readRepoFile(path);
      expect(
        source,
        contains('pdfrxInitialize()'),
        reason: '$path: нет реальной инициализации PDFium в setUpAll',
      );
      expect(
        source,
        isNot(contains('markTestSkipped')),
        reason: '$path: PDF-тесты не должны скипаться молча',
      );
      expect(
        RegExp(r'\bskip\s*:').hasMatch(source),
        isFalse,
        reason: '$path: PDF-тесты не должны иметь skip',
      );
      expect(
        source,
        isNot(contains("tags: ['pdf']")),
        reason: '$path: PDF-тесты не выносятся в отдельный тег (L26)',
      );
    }
  });
}
