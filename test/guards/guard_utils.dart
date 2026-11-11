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
  for (final entity in root.listSync(recursive: true, followLinks: false)) {
    if (entity is! File) continue;
    final path = entity.path;
    final segments = path.split(Platform.pathSeparator);
    if (segments.any(excludedDirs.contains)) continue;
    if (include != null && !include(entity.uri.pathSegments.last)) continue;
    result.add(entity);
  }
  return result;
}

/// Ищет запрещённые имена пакетов в тексте `pubspec.lock` или `pubspec.yaml`.
List<String> findForbiddenPackages(
  String source,
  List<String> forbiddenPrefixes,
) {
  final found = <String>{};
  for (final prefix in forbiddenPrefixes) {
    final pattern = RegExp(
      '^\\s+${RegExp.escape(prefix)}(_[a-z0-9_]+)?\\s*:',
      multiLine: true,
    );
    for (final match in pattern.allMatches(source)) {
      found.add(match.group(0)!.trim().replaceAll(':', '').trim());
    }
  }
  return found.toList()..sort();
}
