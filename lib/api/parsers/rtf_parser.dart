import 'dart:convert';
import 'dart:typed_data';

import 'package:cardflow/api/parsers/document_parser.dart';
import 'package:cardflow/api/parsers/parsed_document_builder.dart';
import 'package:cardflow/domain/text/document_format.dart';
import 'package:cardflow/domain/text/parsed_document.dart';
import 'package:cardflow/domain/text/parser_exception.dart';
import 'package:enough_convert/enough_convert.dart';

/// Минимальный RTF-конвертер (SPEC A8.3, ADR-010).
///
/// Поддержка: `\'hh` с кодовой страницей из `\ansicpg` (cp1251 по умолчанию,
/// cp1252, KOI8-R/U), `\uN` с пропуском `\ucN` (значение `\uc` ограничено
/// группой, как в спеке), `\par`/`\line`/`\tab`, экранирование `\\`/`\{`/`\}`,
/// control symbols `\~`/`\-`/`\_`, пропуск групп `fonttbl`/`colortbl`/
/// `stylesheet`/`pict`/`info` и `\*`-групп (пропускается текущая группа).
class RtfParser implements DocumentParser {
  /// Создаёт парсер RTF.
  const RtfParser();

  @override
  DocumentFormat get format => DocumentFormat.rtf;

  @override
  Future<ParsedDocument> parse(
    Uint8List bytes, {
    required String fileName,
  }) async {
    final String raw = latin1.decode(bytes);
    final String trimmed = raw.trimLeft();
    if (!trimmed.startsWith('{\\rtf')) {
      throw const ParserException(
        ParserErrorCode.unreadableFile,
        details: 'Файл не является RTF (нет {\\rtf)',
      );
    }
    final String text = _RtfConverter().convert(trimmed);
    final ParsedDocumentBuilder builder = ParsedDocumentBuilder(
      format: format,
      fileName: fileName,
    );
    builder.addLines(text.split('\n'));
    return builder.build();
  }
}

/// Группы-назначения, содержимое которых не является текстом документа.
const Set<String> _skippedDestinations = <String>{
  'fonttbl',
  'colortbl',
  'stylesheet',
  'pict',
  'info',
  'header',
  'footer',
  'object',
  'themedata',
  'datastore',
  'listtable',
  'listoverridetable',
  'generator',
  'xmlnstbl',
};

/// Состояние группы, восстанавливаемое на `}`.
class _GroupState {
  const _GroupState({required this.skipping, required this.unicodeSkip});

  final bool skipping;
  final int unicodeSkip;
}

/// Пошаговый конвертер RTF-разметки в текст.
class _RtfConverter {
  final StringBuffer _output = StringBuffer();
  final List<int> _escapedBytes = <int>[];
  final List<_GroupState> _groups = <_GroupState>[];

  int _codepage = 1251;
  int _unicodeSkip = 1;
  int _pendingSkip = 0;
  bool _skipping = false;

  String convert(String source) {
    int index = 0;
    while (index < source.length) {
      final String char = source[index];
      if (_pendingSkip > 0) {
        index = _consumeSkippedCharacter(source, index);
        continue;
      }
      if (char == '{') {
        _groups.add(
          _GroupState(skipping: _skipping, unicodeSkip: _unicodeSkip),
        );
        index++;
        continue;
      }
      if (char == '}') {
        if (_groups.isNotEmpty) {
          final _GroupState state = _groups.removeLast();
          _skipping = state.skipping;
          _unicodeSkip = state.unicodeSkip;
        }
        index++;
        continue;
      }
      if (char == '\\') {
        index = _handleControl(source, index);
        continue;
      }
      if (char == '\n' || char == '\r' || char == '\t') {
        // Сырые переводы строк/табы RTF-потока — форматирование файла,
        // а не текст документа (переносы строк в исходнике игнорируются).
        index++;
        continue;
      }
      if (!_skipping) {
        _flushEscapedBytes();
        _output.write(char);
      }
      index++;
    }
    _flushEscapedBytes();
    return _output.toString();
  }

  /// Потребляет один символ «подстановки» после `\uN` (fallback/`\ucN`).
  int _consumeSkippedCharacter(String source, int index) {
    final String char = source[index];
    if (char == '\\') {
      final int next = index + 1;
      if (next < source.length && source[next] == "'") {
        _pendingSkip--;
        return next + 3;
      }
      _pendingSkip--;
      return next + 1;
    }
    _pendingSkip--;
    return index + 1;
  }

  /// Обрабатывает управляющее слово/символ, начиная с обратного слэша.
  int _handleControl(String source, int index) {
    final int start = index + 1;
    if (start >= source.length) {
      return start;
    }
    final String first = source[start];
    if (first == '*') {
      // `\*` помечает текущую группу как служебную — пропускаем её целиком.
      _skipping = true;
      return start + 1;
    }
    if (first == "'") {
      if (start + 2 >= source.length) {
        return source.length;
      }
      final String hex = source.substring(start + 1, start + 3);
      final int? byte = int.tryParse(hex, radix: 16);
      if (byte != null && !_skipping) {
        _escapedBytes.add(byte);
      }
      return start + 3;
    }
    if (first == '\\' || first == '{' || first == '}') {
      if (!_skipping) {
        _flushEscapedBytes();
        _output.write(first);
      }
      return start + 1;
    }
    if (first == '~' || first == '_' || first == '-') {
      if (!_skipping) {
        _flushEscapedBytes();
        switch (first) {
          case '~':
            // Неразрывный пробел.
            _output.write(' ');
          case '_':
            // Неразрывный дефис.
            _output.write('-');
          case '-':
            // Мягкий перенос — в тексте не нужен.
            break;
        }
      }
      return start + 1;
    }
    if (first == '\n' || first == '\r') {
      return start + 1;
    }
    int cursor = start;
    while (cursor < source.length && _isControlLetter(source[cursor])) {
      cursor++;
    }
    if (cursor == start) {
      return start + 1;
    }
    final String word = source.substring(start, cursor);
    final int numberStart = cursor;
    if (cursor < source.length &&
        (source[cursor] == '-' || _isDigit(source[cursor]))) {
      cursor++;
      while (cursor < source.length && _isDigit(source[cursor])) {
        cursor++;
      }
    }
    final int? parameter = numberStart == cursor
        ? null
        : int.tryParse(source.substring(numberStart, cursor));
    if (cursor < source.length && source[cursor] == ' ') {
      cursor++;
    }
    _applyControlWord(word, parameter);
    return cursor;
  }

  void _applyControlWord(String word, int? parameter) {
    if (_skippedDestinations.contains(word)) {
      _skipping = true;
      return;
    }
    if (_skipping) {
      return;
    }
    switch (word) {
      case 'ansicpg':
        _codepage = parameter ?? _codepage;
      case 'uc':
        _unicodeSkip = parameter ?? _unicodeSkip;
      case 'u':
        final int? codeUnit = parameter;
        if (codeUnit != null) {
          _flushEscapedBytes();
          final int normalized = codeUnit < 0 ? codeUnit + 65536 : codeUnit;
          _output.writeCharCode(normalized);
          _pendingSkip = _unicodeSkip;
        }
      case 'par':
      case 'line':
        _flushEscapedBytes();
        _output.write('\n');
      case 'tab':
        _flushEscapedBytes();
        _output.write('\t');
      default:
        break;
    }
  }

  /// Декодирует накопленные `\'hh`-байты в текущей кодовой странице.
  void _flushEscapedBytes() {
    if (_escapedBytes.isEmpty) {
      return;
    }
    final Uint8List bytes = Uint8List.fromList(_escapedBytes);
    _escapedBytes.clear();
    switch (_codepage) {
      case 1251:
        _output.write(const Windows1251Codec().decode(bytes));
      case 1252:
        _output.write(const Windows1252Codec().decode(bytes));
      case 20866:
        _output.write(const Koi8rCodec().decode(bytes));
      case 21866:
        _output.write(const Koi8uCodec().decode(bytes));
      case 65001:
        _output.write(utf8.decode(bytes, allowMalformed: true));
      default:
        // Для русского RTF по умолчанию cp1251 (ADR-010).
        _output.write(const Windows1251Codec().decode(bytes));
    }
  }

  bool _isControlLetter(String char) {
    final int code = char.codeUnitAt(0);
    return (code >= 0x41 && code <= 0x5A) || (code >= 0x61 && code <= 0x7A);
  }

  bool _isDigit(String char) {
    final int code = char.codeUnitAt(0);
    return code >= 0x30 && code <= 0x39;
  }
}
