import 'dart:io';

/// Общие утилиты guard-тестов: поиск корня проекта, чтение файлов, обход дерева.

/// Возвращает абсолютный путь к корню проекта (каталог с pubspec.yaml).
Directory projectRoot() {
  var dir = Directory.current.absolute;
  for (var i = 0; i < 10; i++) {
    if (File('${dir.path}${Platform.pathSeparator}pubspec.yaml').existsSync()) {
      return dir;
    }
    final parent = dir.parent;
    if (parent.path == dir.path) break;
    dir = parent;
  }
  throw StateError(
    'Не найден корень проекта (pubspec.yaml) от ${Directory.current.path}',
  );
}

String readRepoFile(String relativePath) {
  final file = File(
    [
      projectRoot().path,
      ...relativePath.split('/'),
    ].join(Platform.pathSeparator),
  );
  if (!file.existsSync()) {
    throw StateError('Ожидаемый файл репозитория отсутствует: $relativePath');
  }
  return file.readAsStringSync();
}

/// Рекурсивно обходит файлы проекта.
///
/// [relativeRoot] — путь от корня, например `lib`. [excludedDirs] — имена
/// каталогов, которые не обходим (build, .dart_tool и т.п.).
///
/// Исключения проверяются по имени каталога при обходе (путь относительно
/// корня проекта), поэтому репозиторий на CI в `/home/runner/work/...`
/// не отфильтровывается целиком.
List<File> repoFiles(
  String relativeRoot, {
  Set<String> excludedDirs = const <String>{},
  bool Function(String fileName)? include,
}) {
  final result = <File>[];
  final root = Directory(
    [
      projectRoot().path,
      ...relativeRoot.split('/'),
    ].join(Platform.pathSeparator),
  );
  if (!root.existsSync()) return result;

  void walk(Directory directory) {
    for (final entity in directory.listSync(followLinks: false)) {
      if (entity is Directory) {
        if (!excludedDirs.contains(entity.uri.pathSegments.last)) {
          walk(entity);
        }
        continue;
      }
      if (entity is! File) continue;
      if (include != null && !include(entity.uri.pathSegments.last)) continue;
      result.add(entity);
    }
  }

  walk(root);
  return result;
}

/// Ищет запрещённые имена пакетов в тексте `pubspec.lock` или `pubspec.yaml`.
List<String> findForbiddenPackages(
  String source,
  List<String> forbiddenPrefixes,
) {
  final found = <String>{};
  for (final prefix in forbiddenPrefixes) {
    final escaped = RegExp.escape(prefix);
    // Блочный YAML: `  package:` / `  package_plugin:`.
    final blockPattern = RegExp(
      '^\\s+($escaped(_[a-z0-9_]+)?)\\s*:',
      multiLine: true,
    );
    // Кавычки: `"package":` / 'package':.
    final quotedPattern = RegExp('''['"]($escaped(_[a-z0-9_]+)?)['"]\\s*:''');
    // Flow-style YAML: `{package: …}` / `, package: …`.
    final flowPattern = RegExp('[\\[{,]\\s*($escaped(_[a-z0-9_]+)?)\\s*:');
    for (final pattern in <RegExp>[blockPattern, quotedPattern, flowPattern]) {
      for (final match in pattern.allMatches(source)) {
        final name = match.group(1);
        if (name != null) found.add(name);
      }
    }
  }
  return found.toList()..sort();
}
