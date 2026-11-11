import 'dart:convert';
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
  '.exp',
  '.lib',
  '.pdb',
  '.obj',
  '.ilk',
  '.res',
  '.snapshot',
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

/// Декодирует файл для поиска секретов без «слепых зон»: UTF-8, при ошибке —
/// latin1 (однобайтовая, декодирует любые байты). Так guard не пропускает
/// файл в cp1251/битой кодировке, содержащий ключ.
String decodeForScan(List<int> bytes) {
  try {
    return utf8.decode(bytes);
  } on FormatException {
    return latin1.decode(bytes);
  }
}

List<File> scannableFiles(Directory root) {
  final result = <File>[];

  void walk(Directory directory) {
    for (final entity in directory.listSync(followLinks: false)) {
      final name = entity.uri.pathSegments.last;
      if (entity is Directory) {
        // Исключения проверяются по имени каталога при обходе, т.е. по пути
        // ОТНОСИТЕЛЬНО корня проекта. Так репозиторий, лежащий на CI внутри
        // /home/runner/work/..., не отфильтровывается целиком (регрессия CI).
        if (!excludedScanDirs.contains(name)) walk(entity);
        continue;
      }
      if (entity is! File) continue; // symlink'и не читаем
      final extension = name.contains('.')
          ? name.substring(name.lastIndexOf('.'))
          : '';
      if (binaryExtensions.contains(extension)) continue;
      if (entity.lengthSync() > 1024 * 1024) continue;
      result.add(entity);
    }
  }

  walk(root);
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
        final text = decodeForScan(file.readAsBytesSync());
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

    test(
      'decodeForScan декодирует UTF-8 и не-UTF-8 (latin1) без слепых зон',
      () {
        final fake = 'sk-${'proj-'}${'A' * 32}';
        final utf8Bytes = utf8.encode('ключ = $fake');
        final cp1251Bytes = <int>[
          0xea,
          0xeb,
          0xfe,
          0xf7,
          0x20,
          ...latin1.encode(fake),
        ];

        expect(decodeForScan(utf8Bytes), contains(fake));
        expect(detectSecrets(decodeForScan(cp1251Bytes)), isNotEmpty);
        expect(
          detectSecrets(decodeForScan(<int>[0xff, 0xfe, 0x00, 0x41])),
          isEmpty,
        );
      },
    );

    test(
      'корень проекта внутри каталога «work» не скрывает файлы (регрессия CI)',
      () {
        // GitHub Actions на Linux/macOS клонирует репозиторий в
        // /home/runner/work/<repo>/<repo> — абсолютный путь содержит «work».
        // Исключения должны проверяться по пути ОТНОСИТЕЛЬНО корня проекта,
        // иначе на CI отфильтровываются все файлы и guard становится пустым.
        final temp = Directory.systemTemp.createTempSync('cardflow_guard_');
        addTearDown(() => temp.deleteSync(recursive: true));
        final repo = Directory(
          <String>[temp.path, 'work', 'cardflow'].join(Platform.pathSeparator),
        )..createSync(recursive: true);
        File(<String>[repo.path, 'pubspec.yaml'].join(Platform.pathSeparator))
            .writeAsStringSync('name: cardflow');
        File(<String>[repo.path, 'notes.md'].join(Platform.pathSeparator))
            .writeAsStringSync('нет секретов');

        final files = scannableFiles(repo);

        expect(
          files.map((file) => file.uri.pathSegments.last).toSet(),
          containsAll(<String>['pubspec.yaml', 'notes.md']),
        );
      },
    );
  });
}
