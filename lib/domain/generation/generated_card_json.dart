/// JSON-формат сгенерированной карточки для черновика прогона (TASK «Срез 8»).
///
/// Черновик хранится в БД в момент принятия (`card_drafts.card_json`), поэтому
/// структура карточки должна пережить перезапуск приложения. Байты изображений
/// **не** сериализуются: файл-хранилище не дублируется в БД, а картинка
/// разрешается при импорте в колоду; в JSON остаются только идентификаторы
/// каталога `<images>` и запросы внешнего поиска.
///
/// Формат (версия 1) — плоский объект с `version`; неизвестный тип карточки или
/// версия — [FormatException]: черновик, который нельзя понять, не подменяется
/// «примерно такой» карточкой.
library;

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/generation/card_image_kind.dart';
import 'package:cardflow/domain/generation/generated_card.dart';
import 'package:cardflow/domain/generation/generated_card_image_side.dart';

/// Версия формата JSON черновика карточки.
const int generatedCardJsonVersion = 1;

/// Кодирует [card] в JSON-объект формата v1 (без байтов изображений).
Map<String, Object?> encodeGeneratedCardJson(GeneratedCard card) {
  return <String, Object?>{
    'version': generatedCardJsonVersion,
    'front': card.front,
    'back': card.back,
    'card_type': card.cardType.wireName,
    'hint': card.hint,
    'tags': card.tags,
    'source_excerpt': card.sourceExcerpt,
    'source_file': card.sourceFile,
    'issues': <String>[
      for (final CardIssueCode issue in card.issues) issue.name,
    ],
    'image_query': card.imageQuery,
    'image_fallback_query': card.imageFallbackQuery,
    'image_kind': card.imageKind.wireName,
    'image_side': card.imageSide.wireName,
    'question_image_ids': card.questionImageIds,
    'answer_image_ids': card.answerImageIds,
    'is_occlusion': card.isOcclusion,
    'occlusion_json': card.occlusionJson,
    'section_id': card.sectionId,
    'unit_id': card.unitId,
    'angle': card.angle,
    'quote_ref': card.quoteRef,
  };
}

/// Декодирует карточку из JSON-объекта формата v1.
GeneratedCard decodeGeneratedCardJson(Map<String, Object?> json) {
  final Object? version = json['version'];
  if (version != generatedCardJsonVersion) {
    throw FormatException('Неизвестная версия черновика карточки: $version');
  }
  final Object? rawFront = json['front'];
  final Object? rawBack = json['back'];
  if (rawFront is! String || rawBack is! String) {
    throw const FormatException('У черновика карточки нет front/back');
  }
  final Object? rawType = json['card_type'];
  if (rawType is! String) {
    throw const FormatException('У черновика карточки нет card_type');
  }
  final List<String> tags = _strings(json['tags']);
  final List<String> questionImageIds = _strings(json['question_image_ids']);
  final List<String> answerImageIds = _strings(json['answer_image_ids']);
  final List<CardIssueCode> issues = <CardIssueCode>[];
  for (final String name in _strings(json['issues'])) {
    for (final CardIssueCode issue in CardIssueCode.values) {
      if (issue.name == name) {
        issues.add(issue);
        break;
      }
    }
  }
  return GeneratedCard(
    front: rawFront,
    back: rawBack,
    cardType: CardType.fromWire(rawType),
    hint: _stringOrNull(json['hint']),
    tags: tags,
    sourceExcerpt: _stringOrNull(json['source_excerpt']),
    sourceFile: _stringOrNull(json['source_file']),
    issues: issues,
    imageQuery: _stringOrNull(json['image_query']),
    imageFallbackQuery: _stringOrNull(json['image_fallback_query']),
    imageKind:
        GeneratedCardImageKind.tryParse(json['image_kind']) ??
        GeneratedCardImageKind.photo,
    imageSide: GeneratedCardImageSide.parseOrDefault(json['image_side']),
    questionImageIds: questionImageIds,
    answerImageIds: answerImageIds,
    isOcclusion: json['is_occlusion'] == true,
    occlusionJson: _stringOrNull(json['occlusion_json']),
    sectionId: _stringOrNull(json['section_id']),
    unitId: _stringOrNull(json['unit_id']),
    angle: _stringOrNull(json['angle']),
    quoteRef: _stringOrNull(json['quote_ref']),
  );
}

List<String> _strings(Object? raw) {
  if (raw is! List<Object?>) return const <String>[];
  return <String>[
    for (final Object? value in raw)
      if (value is String) value,
  ];
}

String? _stringOrNull(Object? raw) => raw is String ? raw : null;
