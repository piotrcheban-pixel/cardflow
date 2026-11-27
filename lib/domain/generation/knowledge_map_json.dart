/// JSON-формат карты знаний v1 (TASK «Срез 8»: кэш карты на БД).
///
/// Карта знаний — доменный тип (`knowledge_map.dart`); кэш понимания
/// (`KnowledgeMapCache`, порт в `ports.dart`) хранит её на диске, поэтому нужен
/// формат хранения. Он чисто доменный (без drift и Flutter): кадр сериализуется
/// один раз и одинаково читается in-memory и drift-реализациями.
///
/// Формат (версия 1):
/// ```json
/// {"version": 1, "document_id": "doc:file.pdf", "units": [
///   {"id": "ku:doc:file.pdf#0", "section_id": "s1", "topic": "…",
///    "kind": "definition", "statement": "…", "salience": 0.8,
///    "splittable": false, "anchors": [{"block_id": "b1", "quote": "…"}]}]}
/// ```
/// Проверки при чтении строгие: неизвестная версия, кривой вид единицы,
/// `salience` вне 0..1, пустые якоря или дубли id — [FormatException], а не
/// «нулевая карта»: повреждённый кэш должен лечиться пересчётом, а не тихо
/// подменять понимание материала.
library;

import 'dart:convert';

import 'package:cardflow/domain/generation/knowledge_map.dart';

/// Версия формата JSON карты знаний.
const int knowledgeMapJsonVersion = 1;

/// Кодирует карту [map] в JSON-объект формата v1.
Map<String, Object?> encodeKnowledgeMapJson(KnowledgeMap map) {
  return <String, Object?>{
    'version': knowledgeMapJsonVersion,
    'document_id': map.documentId,
    'units': <Object?>[
      for (final KnowledgeUnit unit in map.units)
        <String, Object?>{
          'id': unit.id,
          'section_id': unit.sectionId,
          'topic': unit.topic,
          'kind': unit.kind.wireName,
          'statement': unit.statement,
          'salience': unit.salience,
          'splittable': unit.splittable,
          'anchors': <Object?>[
            for (final KnowledgeAnchor anchor in unit.anchors)
              <String, Object?>{
                'block_id': anchor.blockId,
                'quote': anchor.quote,
              },
          ],
        },
    ],
  };
}

/// Декодирует карту знаний из JSON-объекта формата v1.
///
/// Ошибки формата — [FormatException] с машинным описанием места: текст
/// материала и утверждения в сообщение не попадают.
KnowledgeMap decodeKnowledgeMapJson(Map<String, Object?> json) {
  final Object? version = json['version'];
  if (version != knowledgeMapJsonVersion) {
    throw FormatException('Неизвестная версия карты знаний: $version');
  }
  final Object? rawDocumentId = json['document_id'];
  if (rawDocumentId is! String || rawDocumentId.isEmpty) {
    throw const FormatException('У карты знаний нет document_id');
  }
  final Object? rawUnits = json['units'];
  if (rawUnits is! List<Object?>) {
    throw const FormatException('У карты знаний нет списка units');
  }
  final List<KnowledgeUnit> units = <KnowledgeUnit>[];
  final Set<String> ids = <String>{};
  for (var index = 0; index < rawUnits.length; index++) {
    final KnowledgeUnit unit = _decodeUnit(rawUnits[index], index);
    if (!ids.add(unit.id)) {
      throw FormatException('Дубль id единицы в карте знаний: ${unit.id}');
    }
    units.add(unit);
  }
  return KnowledgeMap(documentId: rawDocumentId, units: units);
}

/// Декодирует JSON-строку карты знаний; ошибка формата — [FormatException].
KnowledgeMap decodeKnowledgeMapJsonString(String raw) {
  final Object? decoded;
  try {
    decoded = _jsonDecode(raw);
  } on FormatException {
    throw const FormatException('Карта знаний не является JSON');
  }
  if (decoded is! Map<String, Object?>) {
    throw const FormatException('Карта знаний должна быть JSON-объектом');
  }
  return decodeKnowledgeMapJson(decoded);
}

/// Кодирует карту в JSON-строку (для колонки `knowledge_maps.map_json`).
String encodeKnowledgeMapJsonString(KnowledgeMap map) =>
    _jsonEncode(encodeKnowledgeMapJson(map));

KnowledgeUnit _decodeUnit(Object? raw, int index) {
  if (raw is! Map<String, Object?>) {
    throw FormatException('Единица карты знаний #$index — не объект');
  }
  String requireString(String key) {
    final Object? value = raw[key];
    if (value is! String || value.isEmpty) {
      throw FormatException('У единицы #$index нет поля $key');
    }
    return value;
  }

  final String id = requireString('id');
  final String sectionId = requireString('section_id');
  final String statement = requireString('statement');
  final Object? rawTopic = raw['topic'];
  final String topic = rawTopic is String ? rawTopic : '';
  final Object? rawKind = raw['kind'];
  final KnowledgeUnitKind? kind = rawKind is String
      ? KnowledgeUnitKind.fromWire(rawKind)
      : null;
  if (kind == null) {
    throw FormatException('Неизвестный вид единицы #$index: $rawKind');
  }
  final Object? rawSalience = raw['salience'];
  if (rawSalience is! num || rawSalience < 0 || rawSalience > 1) {
    throw FormatException('salience единицы #$index вне 0..1: $rawSalience');
  }
  final Object? rawSplittable = raw['splittable'];
  if (rawSplittable is! bool) {
    throw FormatException('У единицы #$index нет поля splittable');
  }
  final Object? rawAnchors = raw['anchors'];
  if (rawAnchors is! List<Object?> || rawAnchors.isEmpty) {
    throw FormatException('У единицы #$index нет якорей');
  }
  final List<KnowledgeAnchor> anchors = <KnowledgeAnchor>[];
  for (var anchorIndex = 0; anchorIndex < rawAnchors.length; anchorIndex++) {
    final Object? rawAnchor = rawAnchors[anchorIndex];
    if (rawAnchor is! Map<String, Object?>) {
      throw FormatException('Якорь #$anchorIndex единицы #$index — не объект');
    }
    final Object? blockId = rawAnchor['block_id'];
    final Object? quote = rawAnchor['quote'];
    if (blockId is! String ||
        blockId.isEmpty ||
        quote is! String ||
        quote.isEmpty) {
      throw FormatException(
        'Якорь #$anchorIndex единицы #$index без блока или цитаты',
      );
    }
    anchors.add(KnowledgeAnchor(blockId: blockId, quote: quote));
  }
  return KnowledgeUnit(
    id: id,
    sectionId: sectionId,
    topic: topic,
    kind: kind,
    statement: statement,
    anchors: anchors,
    salience: rawSalience.toDouble(),
    splittable: rawSplittable,
  );
}

// `dart:convert` — стандартная библиотека: JSON-формат хранения не делает домен
// зависимым от Flutter, сети или БД.
Object? _jsonDecode(String raw) => jsonDecode(raw);

String _jsonEncode(Object? value) => jsonEncode(value);
