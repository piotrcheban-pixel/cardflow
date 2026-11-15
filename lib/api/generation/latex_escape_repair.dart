/// Восстановление LaTeX, испорченного JSON-экранированием (fix-gen, Д4/Д6).
///
/// Модель пишет LaTeX внутри JSON-строк с одним обратным слэшем. JSON-декодер
/// тогда либо превращает `\f`/`\t`/`\b`/`\r`/`\n` в управляющие символы
/// (`\frac` → form feed + `rac`), либо не может разобрать документ вообще
/// (`\alpha`, `\sum`, `\Delta`, `\cdot` — недопустимые escape-последовательности).
/// Модуль — чистая функция над текстом: до `jsonDecode` удваивает слэши у
/// LaTeX-команд, после разбора восстанавливает команды из управляющих символов.
library;

/// Имена LaTeX-команд, которые JSON-декодер молча портит escape-последовательностями
/// `\b`, `\f`, `\n`, `\r`, `\t` (первая буква команды — буква escape).
const Set<String> _commandsStartingWithEscapeLetter = <String>{
  // \b…
  'backslash',
  'bar',
  'because',
  'begin',
  'beta',
  'bf',
  'bigcap',
  'bigcirc',
  'bigcup',
  'bigoplus',
  'bigotimes',
  'bigtriangleup',
  'bigvee',
  'bigwedge',
  'binom',
  'bmod',
  'boldsymbol',
  'bot',
  'bowtie',
  'breve',
  'bullet',
  // \f…
  'fbox',
  'fcolorbox',
  'flat',
  'footnote',
  'forall',
  'frac',
  'frown',
  // \n…
  'nabla',
  'natural',
  'ncong',
  'ndash',
  'nearrow',
  'neg',
  'neq',
  'nexists',
  'ngeq',
  'nleftarrow',
  'nleq',
  'nmid',
  'nolimits',
  'not',
  'notin',
  'nparallel',
  'nrightarrow',
  'nsubseteq',
  'nsupseteq',
  'nu',
  'nvdash',
  'nwarrow',
  // \r…
  'rangle',
  'rbrace',
  'rceil',
  'rfloor',
  'rho',
  'right',
  'rightarrow',
  'rightleftarrows',
  'rightleftharpoons',
  'rightthreetimes',
  'rm',
  'root',
  'rvert',
  'rVert',
  // \t…
  'tan',
  'tanh',
  'tau',
  'tbinom',
  'tdot',
  'text',
  'textbf',
  'textit',
  'textrm',
  'texttt',
  'tfrac',
  'therefore',
  'theta',
  'thinspace',
  'tilde',
  'times',
  'to',
  'top',
  'triangle',
  'triangleq',
  'twoheadrightarrow',
};

/// Символы, которые JSON допускает после обратного слэша в строке.
const Set<String> _jsonEscapeLetters = <String>{'b', 'f', 'n', 'r', 't', 'u'};

/// Восстанавливает LaTeX в сыром тексте ответа модели до `jsonDecode`.
///
/// - недопустимые JSON escape (`\alpha`, `\sum`, `\Delta`, `\cdot`) удваиваются
///   всегда — иначе документ не разбирается вовсе;
/// - допустимые (`\frac`, `\theta`, `\nabla`, …) удваиваются, только если хвост
///   после буквы образует известную LaTeX-команду: обычный `\n` между словами
///   остаётся переносом строки.
String repairLatexJsonEscapes(String raw) {
  final StringBuffer buffer = StringBuffer();
  var index = 0;
  var inString = false;
  while (index < raw.length) {
    final String char = raw[index];
    if (char == r'\' && index + 1 < raw.length) {
      final String next = raw[index + 1];
      if (!inString) {
        buffer.write(char);
        index++;
        continue;
      }
      if (next == r'\' || next == '"' || next == '/') {
        buffer
          ..write(char)
          ..write(next);
        index += 2;
        continue;
      }
      if (next == 'u') {
        final bool hex =
            index + 6 <= raw.length &&
            RegExp(r'^[0-9a-fA-F]{4}$')
                .hasMatch(raw.substring(index + 2, index + 6));
        if (hex) {
          buffer.write(raw.substring(index, index + 6));
          index += 6;
          continue;
        }
        buffer
          ..write(r'\\')
          ..write(next);
        index += 2;
        continue;
      }
      if (_jsonEscapeLetters.contains(next)) {
        final String rest = raw.substring(index + 2);
        if (_matchesLatexCommand(next, rest)) {
          buffer
            ..write(r'\\')
            ..write(next);
        } else {
          buffer
            ..write(char)
            ..write(next);
        }
        index += 2;
        continue;
      }
      // Недопустимый JSON escape: это LaTeX (или мусор) — удваиваем слэш.
      buffer
        ..write(r'\\')
        ..write(next);
      index += 2;
      continue;
    }
    if (char == '"') inString = !inString;
    buffer.write(char);
    index++;
  }
  return buffer.toString();
}

/// Начинается ли [rest] с хвоста LaTeX-команды `letter + rest`.
bool _matchesLatexCommand(String letter, String rest) {
  for (final String command in _commandsStartingWithEscapeLetter) {
    if (!command.startsWith(letter)) continue;
    final String tail = command.substring(1);
    if (tail.isEmpty) continue;
    if (rest.startsWith(tail)) return true;
  }
  return false;
}

/// Восстанавливает команды, уже испорченные в управляющие символы.
///
/// Применяется к тексту карточки после разбора JSON. Управляющий символ
/// заменяется на `\` + букву, если вместе с последующим хвостом получается
/// известная команда; восстанавливаются только символы внутри `$…$`/`$$…$$`.
String repairLatexControlCharacters(String text) {
  if (!text.contains(r'$')) return text;
  final List<int> codes = text.runes.toList(growable: false);
  final StringBuffer buffer = StringBuffer();
  var index = 0;
  var inFormula = false;
  while (index < codes.length) {
    final int code = codes[index];
    if (code == 0x24) {
      final bool display = index + 1 < codes.length && codes[index + 1] == 0x24;
      if (inFormula && display) {
        buffer.write(r'$$');
        inFormula = false;
        index += 2;
        continue;
      }
      if (!inFormula) {
        inFormula = true;
        buffer.write(display ? r'$$' : r'$');
        index += display ? 2 : 1;
        continue;
      }
      inFormula = false;
      buffer.write(r'$');
      index++;
      continue;
    }
    if (inFormula && _controlCharacterLetter(code) != null) {
      final String letter = _controlCharacterLetter(code)!;
      final String rest = String.fromCharCodes(codes.skip(index + 1));
      final String trimmed = rest.trimLeft();
      final String? command = _controlCommand(letter, trimmed);
      if (command != null) {
        final int spaces = rest.length - trimmed.length;
        buffer
          ..write(r'\')
          ..write(command);
        index += 1 + spaces + (command.length - 1);
        continue;
      }
    }
    buffer.writeCharCode(code);
    index++;
  }
  return buffer.toString();
}

/// Буква LaTeX-команды, которую JSON-декодер заменил управляющим символом.
String? _controlCharacterLetter(int code) {
  return switch (code) {
    0x08 => 'b',
    0x09 => 't',
    0x0A => 'n',
    0x0C => 'f',
    0x0D => 'r',
    _ => null,
  };
}

/// Известная команда, начинающаяся с [letter] и продолжающаяся [rest].
String? _controlCommand(String letter, String rest) {
  String? best;
  for (final String command in _commandsStartingWithEscapeLetter) {
    if (!command.startsWith(letter)) continue;
    final String tail = command.substring(1);
    if (tail.isEmpty || !rest.startsWith(tail)) continue;
    if (best == null || command.length > best.length) best = command;
  }
  return best;
}

/// Нормализует разделители формул: `\(…\)` → `$…$`, `\[…\]` → `$$…$$`.
///
/// SPEC A7.10: поддерживаются только `$…$` и `$$…$$`; модель иногда пишет
/// LaTeX-разделители других видов — их нужно привести к поддерживаемым.
String normalizeLatexDelimiters(String text) {
  var result = text;
  result = result.replaceAllMapped(
    RegExp(r'\\\(([\s\S]*?)\\\)'),
    (Match match) => '\$${match.group(1)}\$',
  );
  result = result.replaceAllMapped(
    RegExp(r'\\\[([\s\S]*?)\\\]'),
    (Match match) => '\$\$${match.group(1)}\$\$',
  );
  return result;
}
