/// Локальная валидация ответа модели по канонической схеме A8.4.
library;

import 'package:json_schema/json_schema.dart';

import 'package:cardflow/api/generation/card_json_schema.dart';

/// Результат поштучной проверки ответа модели по схеме.
class CardPayloadValidation {
  /// Создаёт результат.
  const CardPayloadValidation({
    this.cards = const <Map<String, Object?>>[],
    this.rejectedCards = 0,
    this.rootInvalid = false,
  });

  /// Карточки, прошедшие схему (порядок ответа сохранён).
  final List<Map<String, Object?>> cards;

  /// Сколько карточек не прошло схему (отброшены поштучно, fix-gen Д6).
  final int rejectedCards;

  /// Корень ответа не `{"cards": [...]}` — фрагмент непригоден целиком.
  final bool rootInvalid;
}

/// Валидатор JSON-ответа модели по канонической схеме (SPEC A8.4).
///
/// Типы `json_schema` наружу не утекают: сервис получает список описаний ошибок.
class CardResponseSchema {
  /// Создаёт валидатор; схема по умолчанию — каноническая A8.4.
  CardResponseSchema({JsonSchema? schema, JsonSchema? cardSchema})
    : schema = schema ?? JsonSchema.create(canonicalCardsResponseSchema),
      cardSchema = cardSchema ?? JsonSchema.create(canonicalCardItemSchema());

  /// Обёрнутая JSON-схема (каноническая A8.4 по умолчанию).
  final JsonSchema schema;

  /// Схема одной карточки (поштучная проверка, fix-gen).
  final JsonSchema cardSchema;

  /// Проверяет [json] (декодированный JSON) целиком по канонической схеме.
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

  /// Делит ответ на прошедшие схему карточки и отброшенные.
  ///
  /// Одна невалидная карточка не отменяет остальные (SPEC A8.5 шаг 7,
  /// fix-gen Д6). Корень проверяется отдельно: не объект `{"cards": [...]}` —
  /// [CardPayloadValidation.rootInvalid].
  CardPayloadValidation splitValid(Object? json) {
    if (json is! Map) {
      return const CardPayloadValidation(rootInvalid: true);
    }
    final rawCards = json['cards'];
    if (rawCards is! List) {
      return const CardPayloadValidation(rootInvalid: true);
    }
    final cards = <Map<String, Object?>>[];
    var rejected = 0;
    for (final raw in rawCards) {
      if (raw is! Map) {
        rejected++;
        continue;
      }
      final Map<String, Object?> card = <String, Object?>{
        for (final entry in raw.entries)
          if (entry.key is String) entry.key as String: entry.value,
      };
      if (card.length != raw.length || !cardSchema.validate(card).isValid) {
        rejected++;
        continue;
      }
      cards.add(card);
    }
    return CardPayloadValidation(
      cards: List<Map<String, Object?>>.unmodifiable(cards),
      rejectedCards: rejected,
    );
  }
}
