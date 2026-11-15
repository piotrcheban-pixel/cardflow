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

  /// Пытается декодировать [value]; не бросает исключений.
  ({bool ok, Object? value}) _tryDecode(String value) {
    try {
      return (ok: true, value: jsonDecode(value));
    } on FormatException {
      return (ok: false, value: null);
    }
  }
}
