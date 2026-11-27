/// Разбор текста ответа модели в JSON канонической схемы A8.4.
///
/// Модели (особенно OpenAI-совместимые серверы без strict-схемы) часто
/// оборачивают JSON в markdown-ограждение или добавляют пояснительный текст —
/// [`CardsJsonExtractor`] снимает обёртку и BOM. Для нативных протоколов со
/// strict-схемой (`openai`, `gemini`, `anthropic`) ответ обязан быть чистым
/// JSON: послабление включается только флагом [CardsJsonExtractor.decode].
library;

import 'dart:convert';

import 'package:cardflow/api/generation/latex_escape_repair.dart';
import 'package:cardflow/domain/generation/generation_error.dart';
import 'package:cardflow/domain/generation/generation_failure_reason.dart';

/// Извлекатель JSON-объекта из текста ответа модели.
class CardsJsonExtractor {
  /// Создаёт извлекатель.
  const CardsJsonExtractor();

  /// Декодирует [raw] в JSON-значение.
  ///
  /// Перед разбором LaTeX-escape восстанавливаются (fix-gen, Д4/Д6):
  /// модель пишет `\frac`/`\alpha` одним слэшем, из-за чего JSON либо молча
  /// портится, либо не разбирается вовсе.
  ///
  /// [tolerant] — разрешить markdown-ограждение и текст вокруг JSON
  /// (OpenAI-совместимый протокол, ADR-021). Иначе ответ обязан быть чистым
  /// JSON-документом.
  ///
  /// Бросает [GenerationException] c `invalidResponse` и причиной `json_parse`,
  /// если JSON не найден; текст ошибки не содержит ответа модели.
  Object? decode(String raw, {required bool tolerant}) {
    final String text = stripBom(repairLatexJsonEscapes(raw));
    final direct = _tryDecode(text);
    if (direct.ok) return direct.value;
    if (tolerant) {
      final String? extracted = extractJsonObject(text);
      if (extracted != null) {
        final second = _tryDecode(extracted);
        if (second.ok) return second.value;
      }
    }
    throw const GenerationException(
      GenerationErrorCode.invalidResponse,
      details: 'Ответ модели не является JSON',
      failureReason: GenerationFailureReason.jsonParse,
    );
  }

  /// Снимает ведущий BOM (U+FEFF): часть серверов отдаёт его перед `{`.
  static String stripBom(String value) {
    var result = value;
    while (result.isNotEmpty && result.codeUnitAt(0) == 0xFEFF) {
      result = result.substring(1);
    }
    return result.trim();
  }

  /// Вырезает JSON-объект из markdown-ограждения или текста вокруг него.
  ///
  /// Режет от первой `{` до последней `}`: так сохраняются вложенные объекты,
  /// а пояснения модели до и после JSON отбрасываются. `null` — объекта нет.
  static String? extractJsonObject(String raw) {
    var text = stripBom(raw);
    final fence = RegExp(
      r'```(?:json)?\s*([\s\S]*?)```',
      caseSensitive: false,
    ).firstMatch(text);
    if (fence != null) text = fence.group(1)!.trim();
    final start = text.indexOf('{');
    final end = text.lastIndexOf('}');
    if (start < 0 || end <= start) return null;
    return text.substring(start, end + 1);
  }

  /// Спасает **полные** карточки из оборванного ответа модели (TASK 04).
  ///
  /// Модель, упёршаяся в лимит вывода (`finish_reason: length`), присылает
  /// JSON без закрывающих `]`/`}` — обычный разбор падает, и раньше все
  /// полученные карточки фрагмента терялись (заказ 50 → «сгенерировано 32»).
  /// Здесь из массива `cards` собираются только целиком закрытые объекты:
  /// незавершённая карточка отбрасывается, всё предыдущее сохраняется и
  /// проверяется по схеме обычным путём.
  ///
  /// Возвращает пустой список, если карточек нет или структура не найдена.
  List<Map<String, Object?>> salvageCards(String raw) {
    final String text = stripBom(repairLatexJsonEscapes(raw));
    // Полный валидный JSON спасать не нужно — берём карточки как есть.
    final direct = _tryDecode(text);
    final List<Map<String, Object?>> result = <Map<String, Object?>>[];
    if (direct.ok && _appendCardsOf(direct.value, result)) return result;
    result.clear();

    final int cardsKey = text.indexOf('"cards"');
    if (cardsKey < 0) return const <Map<String, Object?>>[];
    final int arrayStart = text.indexOf('[', cardsKey);
    if (arrayStart < 0) return const <Map<String, Object?>>[];
    var index = arrayStart + 1;
    while (index < text.length) {
      // Пропускаем пробелы и запятые между карточками.
      while (index < text.length &&
          (text[index] == ' ' ||
              text[index] == '\n' ||
              text[index] == '\r' ||
              text[index] == '\t' ||
              text[index] == ',')) {
        index++;
      }
      if (index >= text.length || text[index] != '{') break;
      final int end = _objectEnd(text, index);
      if (end < 0) break;
      final String chunk = text.substring(index, end + 1);
      final decoded = _tryDecode(chunk);
      if (decoded.ok && decoded.value is Map) {
        result.add(<String, Object?>{
          for (final MapEntry<Object?, Object?> entry
              in (decoded.value! as Map).entries)
            if (entry.key is String) entry.key! as String: entry.value,
        });
      }
      index = end + 1;
    }
    return List<Map<String, Object?>>.unmodifiable(result);
  }

  /// Индекс закрывающей `}` объекта, начавшегося в [start] (`-1` — нет).
  ///
  /// Учитывает строки и экранирование: `}` внутри строки не считается концом.
  static int _objectEnd(String text, int start) {
    var depth = 0;
    var inString = false;
    var escaped = false;
    for (var index = start; index < text.length; index++) {
      final String char = text[index];
      if (inString) {
        if (escaped) {
          escaped = false;
          continue;
        }
        if (char == r'\') {
          escaped = true;
        } else if (char == '"') {
          inString = false;
        }
        continue;
      }
      if (char == '"') {
        inString = true;
        continue;
      }
      if (char == '{' || char == '[') {
        depth++;
        continue;
      }
      if (char == '}' || char == ']') {
        depth--;
        if (depth == 0) return char == '}' ? index : -1;
      }
    }
    return -1;
  }

  bool _appendCardsOf(Object? json, List<Map<String, Object?>> target) {
    if (json is! Map) return false;
    final Object? cards = json['cards'];
    if (cards is! List) return false;
    for (final Object? card in cards) {
      if (card is! Map) continue;
      target.add(<String, Object?>{
        for (final MapEntry<Object?, Object?> entry in card.entries)
          if (entry.key is String) entry.key! as String: entry.value,
      });
    }
    return true;
  }

  /// Пытается декодировать [value]; не бросает исключений.
  ({bool ok, Object? value}) _tryDecode(String value) {
    try {
      return (ok: true, value: jsonDecode(value));
    } on FormatException {
      return (ok: false, value: null);
    }
  }
}
