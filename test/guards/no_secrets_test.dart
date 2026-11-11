import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'guard_utils.dart';

/// Реалистичные форматы ключей (SPEC 3.4): OpenAI `sk-…`, Anthropic `sk-ant-…`,
/// Google `AIza…`. Шаблоны в документации («sk-», «AIza») не считаются ключами.
final List<RegExp> secretPatterns = <RegExp>[
  RegExp(r'sk-[A-Za-z0-9_\-]{20,}'),
  RegExp(r'sk-ant-[A-Za-z0-9_\-]{20,}'),
  RegExp(r'AIza[0-9A-Za-z_\-]{30,}'),
];

/// Расширения, которые не считаем текстом (бинарные артефакты).
const Set<String> binaryExtensions = <String>{
  '.png',
  '.jpg',
  '.jpeg',
  '.gif',
  '.webp',
  '.ico',
  '.bmp',
  '.zip',
  '.gz',
  '.tar',
  '.tgz',
  '.7z',
  '.ttf',
  '.otf',
  '.woff',
  '.woff2',
  '.dll',
  '.exe',
  '.so',
  '.dylib',
  '.a',
  '.o',
  '.class',
  '.jar',
  '.pdf',
  '.docx',
  '.xlsx',
  '.pptx',
};

/// Каталоги, которые не являются исходниками проекта.
const Set<String> excludedScanDirs = <String>{
  '.git',
  '.dart_tool',
  'build',
  '.fvm',
  'coverage',
  '.idea',
  '.vscode',
  'node_modules',
  'work',
  'ephemeral',
};

List<String> detectSecrets(String text) {
  final found = <String>[];
  for (final pattern in secretPatterns) {
    for (final match in pattern.allMatches(text)) {
      final value = match.group(0)!;
      found.add('${value.substring(0, 3)}…(${value.length} символов)');
    }
  }
  return found;
}

List<File> scannableFiles(Directory root) {
  final result = <File>[];
  for (final entity in root.listSync(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    final segments = entity.path.split(Platform.pathSeparator);
    if (segments.any(excludedScanDirs.contains)) continue;
    final name = entity.uri.pathSegments.last;
    final ext = name.contains('.') ? name.substring(name.lastIndexOf('.')) : '';
    if (binaryExtensions.contains(ext)) continue;
    final length = entity.lengthSync();
    if (length > 1024 * 1024) continue;
    result.add(entity);
  }
  return result;
}

void main() {
  group('no_secrets: реальный репозиторий', () {
    test('в файлах репозитория нет строк, похожих на ключи API', () {
      final root = projectRoot();
      final violations = <String>[];
      final files = scannableFiles(root);
      expect(files, isNotEmpty);
      for (final file in files) {
        final String text;
        try {
          text = file.readAsStringSync();
        } on FileSystemException {
          // Не декодируется как UTF-8 — значит, бинарный артефакт; пропускаем.
          continue;
        }
        for (final secret in detectSecrets(text)) {
          violations.add('${file.path}: $secret');
        }
      }
      expect(
        violations,
        isEmpty,
        reason: 'Найдены похожие на ключи строки (SPEC 3.4): $violations',
      );
    });

    test(
      'в docs/agent-prompt.md и SPEC.md упоминаются только шаблоны, не ключи',
      () {
        for (final path in <String>['docs/agent-prompt.md', 'SPEC.md']) {
          expect(detectSecrets(readRepoFile(path)), isEmpty, reason: path);
        }
      },
    );
  });

  group('no_secrets: самопроверка детектора', () {
    test('находит ключ OpenAI', () {
      // Собирается в рантайме, чтобы в исходнике не было строки-ключа.
      final fake = 'sk-${'proj-'}${'A' * 32}';
      expect(detectSecrets('const key = "$fake";'), isNotEmpty);
    });

    test('находит ключ Anthropic', () {
      final fake = 'sk-ant-${'api03-'}${'b' * 32}';
      expect(detectSecrets(fake), isNotEmpty);
    });

    test('находит ключ Google', () {
      final fake = 'AIza${'C' * 35}';
      expect(detectSecrets(fake), isNotEmpty);
    });

    test('не считает ключом упоминание шаблона', () {
      expect(detectSecrets('строки, похожие на sk-, AIza, sk-ant-'), isEmpty);
    });

    test('сканирует pubspec.lock как текстовый файл', () {
      final lock = readRepoFile('pubspec.lock');
      expect(lock, isNotEmpty);
      expect(detectSecrets(lock), isEmpty);
    });
  });
}
