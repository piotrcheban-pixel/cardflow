/// Профиль совместимости схемы ответа (TASK «Срез 13», часть 2).
///
/// OpenAI-совместимые серверы (DeepSeek) отвечают `400` на strict
/// `json_schema`. Лестница ADR-021 (`strict` → без схемы → без схемы и
/// `max_tokens`) раньше срабатывала **на каждом** запросе: 12 разделов
/// Understanding = 24 HTTP-обмена, каждый батч карточек — ещё два.
///
/// Профиль помнит отказ провайдера **один раз на прогон**: ключ —
/// провайдер + модель + схема, значение — какие ступени лестницы уже
/// отвергнуты. Следующие запросы того же прогона идут сразу со следующей
/// ступени, не тратя запрос на заведомо отказной strict-вариант.
///
/// Профиль изменяемый по назначению: это кэш факта «провайдер не принимает
/// strict-схему», а не сущность домена. Область жизни — один прогон
/// (production-проводка создаёт его в `GenerationV3PathRunner.run`);
/// персист между запусками — отдельное решение, а не свойство лестницы.
library;

/// Отвергнутая ступень лестницы ADR-021.
enum SchemaCompatRung {
  /// Strict `json_schema` (+ `max_tokens`).
  strictSchema('strict_schema'),

  /// Без схемы, но с `max_tokens`.
  schemaOff('schema_off'),

  /// Без схемы и без `max_tokens`.
  minimal('minimal');

  const SchemaCompatRung(this.wireName);

  /// Машинный код ступени (диагностика и тесты).
  final String wireName;
}

/// Что известно о совместимости провайдера с моделью и схемой ответа.
class SchemaCompatProfile {
  /// Создаёт пустой профиль (ничего не известно).
  SchemaCompatProfile();

  final Map<String, Set<SchemaCompatRung>> _rejected =
      <String, Set<SchemaCompatRung>>{};

  /// Ключ факта: провайдер, модель и версия схемы.
  ///
  /// Схема входит в ключ намеренно: новая схема — новый договор, и отказ на
  /// старой не должен «заразить» новую.
  static String keyOf({
    required String provider,
    required String model,
    required String schema,
  }) => '$provider\u0000$model\u0000$schema';

  /// true — ступень [rung] уже отвергнута для этой комбинации.
  bool isRejected({
    required String provider,
    required String model,
    required String schema,
    required SchemaCompatRung rung,
  }) {
    final Set<SchemaCompatRung>? rejected =
        _rejected[keyOf(provider: provider, model: model, schema: schema)];
    return rejected != null && rejected.contains(rung);
  }

  /// Запоминает отказ провайдера на ступени [rung].
  void rememberRejected({
    required String provider,
    required String model,
    required String schema,
    required SchemaCompatRung rung,
  }) {
    _rejected
        .putIfAbsent(
          keyOf(provider: provider, model: model, schema: schema),
          () => <SchemaCompatRung>{},
        )
        .add(rung);
  }

  /// Сколько фактов профиль помнит (для диагностики).
  int get factCount => _rejected.values.fold(
    0,
    (int sum, Set<SchemaCompatRung> rejected) => sum + rejected.length,
  );
}
