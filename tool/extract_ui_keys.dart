// Извлекает контрактные ключи `ValueKey<String>` из `lib/ui/**`.
//
// Снимок генерируется ОДИН раз до правок визуального слоя и затем охраняется
// `test/guards/ui_key_contract_test.dart`: ключ исчез из кода — тест упал
// (REDESIGN-PLAN, «Ключи — контракт»).
//
//   fvm dart run tool/extract_ui_keys.dart            # печать снимка
//   fvm dart run tool/extract_ui_keys.dart --write    # запись фикстуры
//
// Нормализация: интерполяции внутри литерала заменяются на `*`, поэтому
// `ValueKey<String>('deck-card-${deck.id}')` превращается в `deck-card-*`
// (шаблон), а `ValueKey<String>('review-card')` остаётся литералом. Если
// аргумент — выражение, из него берутся все строковые литералы
// (`show ? 'a-$n' : 'b-$n'` → `a-*`, `b-*`); выражение без литералов
// (например `ValueKey<String>(card.id)`) в снимок не попадает.
import 'dart:io';

/// Один найденный ключ.
class UiKey {
  /// Создаёт запись о ключе.
  const UiKey({
    required this.pattern,
    required this.file,
    required this.line,
    required this.interpolated,
  });

  /// Нормализованный ключ: интерполяции заменены на `*`.
  final String pattern;

  /// Путь файла относительно корня проекта (`lib/ui/...`).
  final String file;

  /// Номер строки, где начинается `ValueKey<String>(`.
  final int line;

  /// Был ли в литерале интерполяция (`$id`, `${...}`).
  final bool interpolated;

  /// Строка снимка.
  String get fixtureLine => pattern;
}

/// Ключи, вычисляемые выражением без строковых литералов.
///
/// В снимок не попадают: их значение известно только в рантайме.
class DynamicUiKey {
  /// Создаёт запись о динамическом ключе.
  const DynamicUiKey({
    required this.expression,
    required this.file,
    required this.line,
  });

  /// Исходное выражение аргумента.
  final String expression;

  /// Путь файла относительно корня проекта.
  final String file;

  /// Номер строки.
  final int line;
}

/// Результат разбора одного файла.
class UiKeyScan {
  /// Создаёт результат разбора.
  const UiKeyScan({required this.keys, required this.dynamic});

  /// Литеральные и шаблонные ключи.
  final List<UiKey> keys;

  /// Ключи, вычисляемые выражением без литералов.
  final List<DynamicUiKey> dynamic;
}

const String _marker = 'ValueKey<String>(';

bool _isIdentifierStart(int codeUnit) {
  final bool lower = codeUnit >= 0x61 && codeUnit <= 0x7A;
  final bool upper = codeUnit >= 0x41 && codeUnit <= 0x5A;
  final bool underscore = codeUnit == 0x5F;
  final bool dollar = codeUnit == 0x24;
  return lower || upper || underscore || dollar;
}

bool _isIdentifierPart(int codeUnit) =>
    _isIdentifierStart(codeUnit) ||
    (codeUnit >= 0x30 && codeUnit <= 0x39) ||
    codeUnit >= 0x80;

bool _isWhitespace(int codeUnit) =>
    codeUnit == 0x20 ||
    codeUnit == 0x09 ||
    codeUnit == 0x0A ||
    codeUnit == 0x0D;

int _lineOf(String source, int offset) {
  var line = 1;
  for (var i = 0; i < offset && i < source.length; i++) {
    if (source.codeUnitAt(i) == 0x0A) line++;
  }
  return line;
}

/// Строковый литерал Dart: нормализованный текст, интерполяции и конец.
class _Literal {
  const _Literal(this.pattern, this.interpolated, this.end);

  final String pattern;
  final bool interpolated;

  /// Индекс сразу после закрывающей кавычки.
  final int end;
}

/// Разбирает литерал, начинающийся с кавычки в позиции [quoteIndex].
_Literal _readLiteral(String source, int quoteIndex) {
  final quote = source[quoteIndex];
  final buffer = StringBuffer();
  var interpolated = false;
  var i = quoteIndex + 1;
  while (i < source.length) {
    final String char = source[i];
    if (char == r'\' && i + 1 < source.length) {
      buffer.write(char);
      buffer.write(source[i + 1]);
      i += 2;
      continue;
    }
    if (char == quote) {
      return _Literal(buffer.toString(), interpolated, i + 1);
    }
    if (char == r'$' && i + 1 < source.length) {
      final String next = source[i + 1];
      if (next == '{') {
        var depth = 0;
        var j = i + 1;
        while (j < source.length) {
          final String c = source[j];
          if (c == '{') depth++;
          if (c == '}') {
            depth--;
            if (depth == 0) break;
          }
          j++;
        }
        buffer.write('*');
        interpolated = true;
        i = j + 1;
        continue;
      }
      if (_isIdentifierStart(next.codeUnitAt(0))) {
        var j = i + 1;
        while (j < source.length && _isIdentifierPart(source.codeUnitAt(j))) {
          j++;
        }
        buffer.write('*');
        interpolated = true;
        i = j;
        continue;
      }
    }
    buffer.write(char);
    i++;
  }
  return _Literal(buffer.toString(), interpolated, source.length);
}

/// Разбирает `source` и возвращает ключи `ValueKey<String>`.
UiKeyScan extractUiKeysFromSource(String source, {String file = '<source>'}) {
  final keys = <UiKey>[];
  final dynamicKeys = <DynamicUiKey>[];
  var index = 0;
  while (true) {
    final int marker = source.indexOf(_marker, index);
    if (marker == -1) break;
    final int line = _lineOf(source, marker);
    var cursor = marker + _marker.length;
    while (cursor < source.length && _isWhitespace(source.codeUnitAt(cursor))) {
      cursor++;
    }
    if (cursor >= source.length) break;
    final int codeUnit = source.codeUnitAt(cursor);
    if (codeUnit == 0x27 || codeUnit == 0x22) {
      final _Literal literal = _readLiteral(source, cursor);
      keys.add(
        UiKey(
          pattern: literal.pattern,
          file: file,
          line: line,
          interpolated: literal.interpolated,
        ),
      );
      index = literal.end;
      continue;
    }
    // Выражение вместо литерала: `ValueKey<String>(state.current!.id)`.
    var end = cursor;
    var depth = 0;
    while (end < source.length) {
      final String c = source[end];
      if (c == '(') depth++;
      if (c == ')') {
        if (depth == 0) break;
        depth--;
      }
      end++;
    }
    final String expression = source.substring(cursor, end).trim();
    final List<_Literal> literals = _literalsIn(expression);
    if (literals.isEmpty) {
      dynamicKeys.add(
        DynamicUiKey(expression: expression, file: file, line: line),
      );
    } else {
      for (final _Literal literal in literals) {
        keys.add(
          UiKey(
            pattern: literal.pattern,
            file: file,
            line: line,
            interpolated: literal.interpolated,
          ),
        );
      }
    }
    index = end + 1;
  }
  return UiKeyScan(keys: keys, dynamic: dynamicKeys);
}

/// Все строковые литералы внутри выражения.
List<_Literal> _literalsIn(String expression) {
  final literals = <_Literal>[];
  var i = 0;
  while (i < expression.length) {
    final String char = expression[i];
    if (char == "'" || char == '"') {
      final _Literal literal = _readLiteral(expression, i);
      literals.add(literal);
      i = literal.end;
      continue;
    }
    i++;
  }
  return literals;
}

/// Обходит `lib/ui/**` и собирает все ключи.
UiKeyScan extractUiKeys(Directory root) {
  final uiRoot = Directory(
    '${root.path}${Platform.pathSeparator}lib${Platform.pathSeparator}ui',
  );
  final keys = <UiKey>[];
  final dynamicKeys = <DynamicUiKey>[];
  if (!uiRoot.existsSync()) {
    return UiKeyScan(keys: keys, dynamic: dynamicKeys);
  }
  final files =
      uiRoot
          .listSync(recursive: true, followLinks: false)
          .whereType<File>()
          .where((file) => file.path.endsWith('.dart'))
          .toList()
        ..sort((a, b) => a.path.compareTo(b.path));
  for (final file in files) {
    final relative = file.path
        .substring(root.path.length + 1)
        .replaceAll(Platform.pathSeparator, '/');
    final scan = extractUiKeysFromSource(
      file.readAsStringSync(),
      file: relative,
    );
    keys.addAll(scan.keys);
    dynamicKeys.addAll(scan.dynamic);
  }
  return UiKeyScan(keys: keys, dynamic: dynamicKeys);
}

/// Сортированный список строк снимка (только ключи, без путей).
List<String> fixtureLines(UiKeyScan scan) {
  final lines = scan.keys.map((key) => key.fixtureLine).toSet().toList()
    ..sort();
  return lines;
}

/// Корень проекта (каталог с `pubspec.yaml`).
Directory projectRoot([Directory? from]) {
  var directory = from ?? Directory.current.absolute;
  for (var i = 0; i < 10; i++) {
    final candidate = File(
      '${directory.path}${Platform.pathSeparator}pubspec.yaml',
    );
    if (candidate.existsSync()) return directory;
    final parent = directory.parent;
    if (parent.path == directory.path) break;
    directory = parent;
  }
  throw StateError('Не найден корень проекта от ${Directory.current.path}');
}

/// Запускает извлечение и печатает (или пишет) снимок.
void main(List<String> args) {
  final Directory root = projectRoot();
  final UiKeyScan scan = extractUiKeys(root);
  final List<String> lines = fixtureLines(scan);
  final bool write = args.contains('--write');
  final File fixture = File(
    '${root.path}${Platform.pathSeparator}test${Platform.pathSeparator}guards'
    '${Platform.pathSeparator}fixtures${Platform.pathSeparator}ui_keys.txt',
  );
  if (write) {
    fixture.parent.createSync(recursive: true);
    fixture.writeAsStringSync('${lines.join('\n')}\n');
    stdout.writeln('Записано ключей: ${lines.length} → ${fixture.path}');
  } else {
    stdout.writeln(lines.join('\n'));
  }
  if (scan.dynamic.isNotEmpty) {
    stderr.writeln(
      'Ключи, вычисляемые выражением без литералов (в снимок не попадают): '
      '${scan.dynamic.length}',
    );
    for (final dynamicKey in scan.dynamic) {
      stderr.writeln(
        '  ${dynamicKey.file}:${dynamicKey.line}: ${dynamicKey.expression}',
      );
    }
  }
}
