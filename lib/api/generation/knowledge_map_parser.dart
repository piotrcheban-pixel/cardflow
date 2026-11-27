/// Разбор ответа модели на `gen-map-v1` в доменные единицы знания (этап
/// Understanding, TASK «Срез 3»).
///
/// Правила разбора (Q8/Q9):
/// - id единицы присваивает приложение (`ku:<fragmentId>#<индекс ответа>`);
/// - `section_id` модели — подсказка: принимается только для известного раздела;
/// - якорь на блок вне запроса отбрасывается, единица без якорей — тоже;
/// - одна невалидная единица не отменяет остальные (поштучная проверка A8.4);
/// - невалидный корень ответа делает фрагмент непригодным (пометка в прогоне).
///
/// Типы `json_schema` наружу не утекают: прогон получает код причины и число
/// отброшенных единиц, а не объекты валидатора.
library;

import 'package:json_schema/json_schema.dart';

import 'package:cardflow/api/generation/cards_json_extractor.dart';
import 'package:cardflow/domain/generation/generation_error.dart';
import 'package:cardflow/domain/generation/knowledge_map.dart';

/// Причина непригодности ответа модели для фрагмента.
enum KnowledgeMapFailureReason {
  /// Ответ не является JSON (включая пустую строку).
  jsonParse('json_parse'),

  /// Корень не `{"units": [...]}` или единица не по схеме.
  schemaInvalid('schema_invalid'),

  /// Ответ оборван по лимиту вывода.
  truncated('truncated'),

  /// Вызов модели завершился ошибкой.
  providerError('provider_error');

  /// Создаёт причину с машинным кодом.
  const KnowledgeMapFailureReason(this.code);

  /// Машинный код для журнала/диагностики.
  final String code;
}

/// Контекст фрагмента: что именно отправлено модели в этом запросе.
class KnowledgeMapFragmentContext {
  /// Создаёт контекст.
  const KnowledgeMapFragmentContext({
    required this.fragmentId,
    required this.sectionId,
    this.blockIds = const <String>{},
    this.sectionIds = const <String>{},
  });

  /// id фрагмента (раздел `ContentModel`).
  final String fragmentId;

  /// Раздел фрагмента — значение по умолчанию для `section_id`.
  final String sectionId;

  /// id блоков, отправленных в запросе (якоря вне набора отбрасываются).
  final Set<String> blockIds;

  /// id разделов документа: подсказка `section_id` принимается только из них.
  final Set<String> sectionIds;
}

/// Результат разбора ответа на один фрагмент.
class KnowledgeMapParseOutcome {
  /// Успешный разбор.
  const KnowledgeMapParseOutcome.success({
    required this.units,
    this.rejectedUnits = 0,
  }) : failureReason = null;

  /// Ответ непригоден для фрагмента.
  const KnowledgeMapParseOutcome.failure(
    KnowledgeMapFailureReason reason, {
    this.rejectedUnits = 0,
  }) : failureReason = reason,
       units = const <KnowledgeUnit>[];

  /// Разобранные единицы (в порядке ответа, id присвоены приложением).
  final List<KnowledgeUnit> units;

  /// Сколько единиц отброшено поштучно (схема/семантика).
  final int rejectedUnits;

  /// Причина непригодности; `null` — ответ разобран.
  final KnowledgeMapFailureReason? failureReason;

  /// true, если ответ разобран (возможно, в пустой список).
  bool get isSuccess => failureReason == null;
}

/// Схема единицы: создаётся один раз на изолят из канона `knowledge_map.dart`.
final JsonSchema _unitSchema = JsonSchema.create(
  canonicalKnowledgeUnitSchema(),
);

/// Разбор ответа модели `gen-map-v1`.
class KnowledgeMapParser {
  /// Создаёт парсер.
  const KnowledgeMapParser({this.extractor = const CardsJsonExtractor()});

  /// Извлекатель JSON из текста ответа (BOM, markdown-ограждение, LaTeX).
  final CardsJsonExtractor extractor;

  /// Разбирает [raw]; [tolerant] разрешает markdown-ограждение и текст вокруг
  /// JSON (OpenAI-совместимые серверы без strict-схемы, ADR-021).
  KnowledgeMapParseOutcome parse(
    String raw, {
    required KnowledgeMapFragmentContext context,
    bool tolerant = false,
  }) {
    final Object? decoded;
    try {
      decoded = extractor.decode(raw, tolerant: tolerant);
    } on GenerationException {
      return const KnowledgeMapParseOutcome.failure(
        KnowledgeMapFailureReason.jsonParse,
      );
    }
    if (decoded is! Map) {
      return const KnowledgeMapParseOutcome.failure(
        KnowledgeMapFailureReason.schemaInvalid,
      );
    }
    final Object? rawUnits = decoded['units'];
    if (rawUnits is! List) {
      return const KnowledgeMapParseOutcome.failure(
        KnowledgeMapFailureReason.schemaInvalid,
      );
    }

    final List<KnowledgeUnit> units = <KnowledgeUnit>[];
    var rejectedUnits = 0;
    for (var index = 0; index < rawUnits.length; index++) {
      final KnowledgeUnit? unit = _parseUnit(
        rawUnits[index],
        index: index,
        context: context,
      );
      if (unit == null) {
        rejectedUnits++;
        continue;
      }
      units.add(unit);
    }
    return KnowledgeMapParseOutcome.success(
      units: List<KnowledgeUnit>.unmodifiable(units),
      rejectedUnits: rejectedUnits,
    );
  }

  KnowledgeUnit? _parseUnit(
    Object? raw, {
    required int index,
    required KnowledgeMapFragmentContext context,
  }) {
    if (raw is! Map) return null;
    final Map<String, Object?> item = <String, Object?>{
      for (final MapEntry<Object?, Object?> entry in raw.entries)
        if (entry.key is String) entry.key! as String: entry.value,
    };
    if (item.length != raw.length) return null;
    if (!_unitSchema.validate(item).isValid) return null;

    final String statement = (item['statement']! as String).trim();
    if (statement.isEmpty) return null;
    final KnowledgeUnitKind? kind = KnowledgeUnitKind.fromWire(
      item['kind']! as String,
    );
    if (kind == null) return null;
    final double salience = (item['salience']! as num).toDouble();
    if (!salience.isFinite || salience < 0 || salience > 1) return null;

    final List<KnowledgeAnchor> anchors = _parseAnchors(
      item['anchors']! as List<Object?>,
      allowedBlockIds: context.blockIds,
    );
    if (anchors.isEmpty) return null;

    final String? hint = (item['section_id'] as String?)?.trim();
    return KnowledgeUnit(
      id: 'ku:${context.fragmentId}#$index',
      sectionId: _resolveSection(hint, context),
      topic: (item['topic']! as String).trim(),
      kind: kind,
      statement: statement,
      anchors: anchors,
      salience: salience,
      splittable: item['splittable']! as bool,
    );
  }

  /// `section_id` — подсказка модели: принимается только для известного
  /// раздела, иначе единица относится к разделу фрагмента.
  String _resolveSection(String? hint, KnowledgeMapFragmentContext context) {
    if (hint != null &&
        hint.isNotEmpty &&
        (context.sectionIds.isEmpty || context.sectionIds.contains(hint))) {
      return hint;
    }
    return context.sectionId;
  }

  List<KnowledgeAnchor> _parseAnchors(
    List<Object?> raw, {
    required Set<String> allowedBlockIds,
  }) {
    final List<KnowledgeAnchor> anchors = <KnowledgeAnchor>[];
    for (final Object? value in raw) {
      if (value is! Map) continue;
      final Object? blockIdValue = value['block_id'];
      final Object? quoteValue = value['quote'];
      if (blockIdValue is! String || quoteValue is! String) continue;
      final String blockId = blockIdValue.trim();
      final String quote = quoteValue.trim();
      if (blockId.isEmpty || quote.isEmpty) continue;
      if (allowedBlockIds.isNotEmpty && !allowedBlockIds.contains(blockId)) {
        continue;
      }
      anchors.add(KnowledgeAnchor(blockId: blockId, quote: quote));
    }
    return List<KnowledgeAnchor>.unmodifiable(anchors);
  }
}
