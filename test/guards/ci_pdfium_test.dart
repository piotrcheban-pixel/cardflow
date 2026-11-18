import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'guard_utils.dart';

/// Guard L26: PDF-тесты в CI должны реально выполняться на всех трёх ОС.
///
/// `flutter test` на Linux/macOS не находит PDFium сам: Flutter engine cache не
/// содержит `libpdfium`, а `pdfium_dart` 0.4.1 в тестовом окружении не находит
/// bundled native asset (L26, CI run 43484685899). Поэтому job `test` обязан
/// скачать тот же pinned релиз PDFium, что использует build-hook `pdfium_dart`
/// (`bblanchon/pdfium-binaries`, `chromium/8125`), сверить sha256 и
/// экспортировать `PDFIUM_PATH` до шага тестов — на всех трёх ОС (Windows тоже,
/// чтобы механизм не зависел от неявного native-assets окружения раннера).
///
/// Дополнительно guard фиксирует «честность» зелёного: матрица ОС не сужена,
/// команда тестов не исключает pdf-тег, `dart_test.yaml` не выключает тесты,
/// PDF-тесты не помечаются `skip`/тегами и в `setUpAll` реально вызывают
/// `pdfrxInitialize()`.
void main() {
  // Ревью B1: на windows-раннере checkout может дать CRLF. Нормализуем
  // переводы строк перед сверкой маркеров; `.gitattributes` (eol=lf) —
  // дополнительная защита, проверяется отдельным тестом.
  final String workflow = readRepoFile('.github/workflows/ci.yml')
      .replaceAll('\r\n', '\n')
      .replaceAll('\r', '\n');

  /// Текст job'а [jobId] — от объявления до следующего job'а верхнего уровня.
  String jobSection(String jobId) {
    final RegExp startPattern = RegExp('(^|\\n)  ${RegExp.escape(jobId)}:\\n');
    final RegExpMatch? startMatch = startPattern.firstMatch(workflow);
    if (startMatch == null) {
      return '';
    }
    final String rest = workflow.substring(startMatch.end);
    final RegExpMatch? next = RegExp(r'\n  [a-zA-Z][\w-]*:\n').firstMatch(rest);
    return next == null ? rest : rest.substring(0, next.start);
  }

  test('workflow: матрица test покрывает ubuntu, windows и macos', () {
    final String job = jobSection('test');
    expect(job, isNotEmpty, reason: 'в ci.yml не найден job test');
    expect(
      job,
      contains('os: [ubuntu-latest, windows-latest, macos-latest]'),
      reason:
          'PDF-тесты должны идти на всех трёх ОС (L26), не только на Windows',
    );
  });

  test('workflow: PDFium-бутстрап Linux/macOS — pinned релиз и sha256', () {
    final String job = jobSection('test');
    expect(job, contains('PDFium для PDF-тестов (Linux/macOS)'));
    expect(
      job,
      contains('bblanchon/pdfium-binaries/releases/download/chromium%2F8125'),
      reason: 'PDFium должен скачиваться из pinned-релиза chromium/8125',
    );
    expect(job, contains('pdfium-linux-x64.tgz'));
    expect(job, contains('pdfium-mac-arm64.tgz'));
    expect(job, contains('lib/libpdfium.so'));
    expect(job, contains('lib/libpdfium.dylib'));
    // Ревью L1: целостность нативного кода обязательна — sha256 обоих ассетов.
    expect(
      job,
      contains(
        'e1c3ce6e270cb5e0c20816b379ad9f2c1309972697c505f508de92bf5e7d6659',
      ),
    );
    expect(
      job,
      contains(
        '4939bd935ac83ddc09a3a4f038bc43a19cea1660316a3667f26cb07a070e139d',
      ),
    );
    // Ревью L2: сетевой шаг с таймаутами и ретраями.
    expect(job, contains('--connect-timeout'));
    expect(job, contains('--max-time'));
    expect(job, contains('--retry 3'));
    expect(job, contains('PDFIUM_PATH='));
    expect(job, contains(r'>> "$GITHUB_ENV"'));
    expect(
      RegExp(r"if:\s*runner\.os\s*!=\s*'Windows'").hasMatch(job),
      isTrue,
      reason: 'Linux/macOS-шаг условный, Windows не должен его выполнять',
    );
  });

  test('workflow: PDFium-бутстрап Windows — pinned релиз и sha256', () {
    final String job = jobSection('test');
    expect(job, contains('PDFium для PDF-тестов (Windows)'));
    expect(
      job,
      contains('bblanchon/pdfium-binaries/releases/download/chromium%2F8125'),
    );
    expect(job, contains('pdfium-win-x64.tgz'));
    expect(job, contains('bin/pdfium.dll'));
    expect(
      job,
      contains(
        '9a964261760cff52570aabf038ab346d3a5034dd8b30d0d5fe8861235d356b8b',
      ),
    );
    expect(job, contains('Get-FileHash'));
    expect(job, contains('TimeoutSec'));
    expect(job, contains('PDFIUM_PATH='));
    expect(job, contains('GITHUB_ENV'));
    expect(
      RegExp(r"if:\s*runner\.os\s*==\s*'Windows'").hasMatch(job),
      isTrue,
      reason: 'Windows-шаг должен быть явным (M1 ревью)',
    );
  });

  test('workflow: PDFium-шаги до тестов и нет в других job', () {
    final String job = jobSection('test');
    final int tests = job.indexOf('Тесты (кроме golden)');
    expect(tests, greaterThan(0));
    for (final String step in <String>[
      'PDFium для PDF-тестов (Linux/macOS)',
      'PDFium для PDF-тестов (Windows)',
    ]) {
      final int index = job.indexOf(step);
      expect(index, greaterThan(0), reason: 'нет шага "$step"');
      expect(
        index,
        lessThan(tests),
        reason: 'PDFIUM_PATH должен быть в env до запуска тестов',
      );
    }
    for (final String jobId in <String>[
      'quality',
      'build-desktop',
      'build-mobile',
    ]) {
      expect(
        jobSection(jobId),
        isNot(contains('PDFium')),
        reason: '$jobId: бутстрап PDFium нужен только job-у test',
      );
    }
  });

  test('workflow: тесты исключают golden и live, без фильтров pdf/--tags', () {
    final String job = jobSection('test');
    expect(
      job,
      contains('flutter test --exclude-tags golden,live --coverage'),
      reason:
          'golden — эталоны снимаются отдельно; live — сетевые проверки, '
          'обычный прогон должен быть офлайновым (L92)',
    );
    expect(job, isNot(contains('golden,pdf')));
    expect(job, isNot(contains('golden, pdf')));
    expect(job, isNot(contains('--tags')));
    expect(
      RegExp(r'--plain-name|--name\b').hasMatch(job),
      isFalse,
      reason: 'нельзя фильтровать тесты по имени — PDF-тесты должны идти',
    );
    expect(
      job,
      isNot(contains('continue-on-error')),
      reason: 'падение PDF-тестов нельзя глушить continue-on-error',
    );
  });

  test('.gitattributes: checkout не даёт CRLF (B1 ревью)', () {
    final String attributes = readRepoFile('.gitattributes')
        .replaceAll('\r\n', '\n');
    expect(
      RegExp(
        r'^\*\s+text=auto\s+eol=lf\s*$',
        multiLine: true,
      ).hasMatch(attributes),
      isTrue,
      reason: 'guard-тесты сверяют маркеры файлов — CRLF на Windows ломал L26 guard',
    );
  });

  test('dart_test.yaml не отключает PDF-тесты', () {
    final File config = File(
      <String>[
        projectRoot().path,
        'dart_test.yaml',
      ].join(Platform.pathSeparator),
    );
    if (!config.existsSync()) {
      return;
    }
    final String content = config.readAsStringSync();
    expect(
      content,
      isNot(contains('skip')),
      reason: 'PDF-тесты не выключаются',
    );
    expect(
      RegExp(r'^\s*tags\s*:', multiLine: true).hasMatch(content),
      isFalse,
      reason: 'PDF-тесты не выносятся в тег через dart_test.yaml',
    );
  });

  test('PDF-тесты не пропускаются молча: setUpAll инициализирует PDFium', () {
    for (final String path in <String>[
      'test/unit/api/parsers/pdf_parser_test.dart',
      'test/integration/file_parsing_pipeline_test.dart',
    ]) {
      final String source = readRepoFile(path).replaceAll('\r\n', '\n');
      expect(
        source,
        contains('pdfrxInitialize()'),
        reason: '$path: нет реальной инициализации PDFium в setUpAll',
      );
      expect(
        RegExp(
          r'\bmarkTestSkipped\b|\bskip\s*:|\btestOn\s*\(|@Tags\s*\(|\btags\s*:',
        ).hasMatch(source),
        isFalse,
        reason:
            '$path: PDF-тесты не должны скипаться/тегироваться/фильтроваться',
      );
    }
  });
}
