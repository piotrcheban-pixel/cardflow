/// Локальная валидация ответа модели по канонической схеме A8.4.
library;

import 'package:json_schema/json_schema.dart';

import 'package:cardflow/api/generation/card_json_schema.dart';

/// Валидатор JSON-ответа модели по канонической схеме (SPEC A8.4).
///
/// Типы `json_schema` наружу не утекают: сервис получает список описаний ошибок.
class CardResponseSchema {
  /// Создаёт валидатор; схема по умолчанию — каноническая A8.4.
  CardResponseSchema({JsonSchema? schema})
    : schema = schema ?? JsonSchema.create(canonicalCardsResponseSchema);

  /// Обёрнутая JSON-схема (каноническая A8.4 по умолчанию).
  final JsonSchema schema;

  /// Проверяет [json] (декодированный JSON).
  ///
  /// Возвращает пустой список, если ответ валиден; иначе — описания нарушений
  /// (пути внутри JSON; используются только в диагностике, не в UI).
  List<String> validate(Object? json) {
    final results = schema.validate(json);
    if (results.isValid) return const <String>[];
    return results.errors
        .map((error) => error.toString())
        .toList(growable: false);
  }

  /// Валиден ли [json] по канонической схеме.
  bool isValid(Object? json) => schema.validate(json).isValid;
}
