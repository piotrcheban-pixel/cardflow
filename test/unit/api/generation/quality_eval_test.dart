import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/api/generation/card_content_validator.dart';
import 'package:cardflow/api/generation/card_response_schema.dart';
import 'package:cardflow/api/generation/cards_json_extractor.dart';
import 'package:cardflow/domain/generation/generated_card.dart';

/// Eval-набор из трёх сценариев (fix-gen, Д5): тема без файлов, DOCX с
/// формулами и рисунками, PPTX. Проверяет, что валидатор ловит нарушения
/// качества и что доля пометок считается автоматически.
void main() {
  const CardsJsonExtractor extractor = CardsJsonExtractor();
  final CardResponseSchema schema = CardResponseSchema();
  const CardContentValidator validator = CardContentValidator();

  List<GeneratedCard> evaluate(
    String rawAnswer, {
    String source = '',
    Set<String> imageIds = const <String>{},
  }) {
    final Object? decoded = extractor.decode(rawAnswer, tolerant: true);
    final CardPayloadValidation payload = schema.splitValid(decoded);
    expect(payload.rootInvalid, isFalse);
    final CardValidationOutcome outcome = validator.validateResponseWithRejects(
      <String, Object?>{'cards': payload.cards},
      sourceText: source,
      imageIds: imageIds,
    );
    return outcome.cards;
  }

  String answer(List<Map<String, Object?>> cards) =>
      jsonEncode(<String, Object?>{'cards': cards});

  Map<String, Object?> card({
    required String front,
    required String back,
    String? imageId,
    String? imageQuery,
  }) {
    return <String, Object?>{
      'front': front,
      'back': back,
      'hint': null,
      'tags': <Object?>['статика'],
      'card_type': 'basic',
      'source_excerpt': null,
      'source_file': null,
      'image_id': imageId,
      'image_query': imageQuery,
    };
  }

  /// Доля карточек с пометками качества — метрика отчёта итерации.
  double markedShare(List<GeneratedCard> cards) {
    if (cards.isEmpty) return 0;
    return cards.where((GeneratedCard card) => card.hasIssues).length /
        cards.length;
  }

  test('сценарий 1: тема без файлов «Статика: аксиомы и фермы»', () {
    // Сырой ответ модели — с одиночным обратным слэшем LaTeX (как в жизни).
    final raw =
        '{"cards":['
        '{"front":"При каком условии две силы уравновешивают друг друга?",'
        '"back":"Когда они равны по модулю и противоположны.",'
        '"card_type":"basic","tags":["статика"],"hint":null,'
        '"source_excerpt":null,"source_file":null,"image_id":null,'
        '"image_query":null},'
        '{"front":"Каким соотношением связаны число стержней \$s\$ и узлов \$n\$ '
        'у плоской фермы?","back":"\$s = 2n - 3\$",'
        '"card_type":"basic","tags":["фермы"],"hint":null,'
        '"source_excerpt":null,"source_file":null,"image_id":null,'
        '"image_query":null},'
        '{"front":"Формула геометрической неизменяемости плоской фермы '
        '\$s = 2n - 3\$","back":"\$s = 2n - 3\$",'
        '"card_type":"basic","tags":["фермы"],"hint":null,'
        '"source_excerpt":null,"source_file":null,"image_id":null,'
        '"image_query":null},'
        '{"front":"Какой тип мостовой конструкции состоит из стержней?",'
        '"back":"Ферменный мост.","card_type":"basic","tags":["фермы"],'
        '"hint":null,"source_excerpt":null,"source_file":null,'
        '"image_id":null,"image_query":"truss bridge structure engineering"}'
        ']}';

    final cards = evaluate(raw);
    expect(cards, hasLength(4));
    expect(cards[1].back, r'$s = 2n - 3$');
    // Д5-пример: ответ в вопросе — пометка, карточка не удалена.
    expect(cards[2].issues, contains(CardIssueCode.answerInFront));
    expect(cards[3].imageQuery, 'truss bridge structure engineering');
    expect(markedShare(cards), greaterThan(0));
  });

  test('сценарий 2: DOCX с формулами и рисунками', () {
    const source =
        'Аксиома о равновесии двух сил. Число стержней s и узлов n '
        'связаны формулой s = 2n - 3. Ферма — стержневая система.';
    final raw = answer(<Map<String, Object?>>[
      card(
        front: 'Каким соотношением связаны число стержней и узлов фермы?',
        back: r'$s = 2n - 3$',
        imageId: 'img1',
      ),
      card(
        front: 'При каком условии две силы уравновешивают друг друга?',
        back: 'Когда они равны по модулю и направлены противоположно.',
        imageId: 'img1',
        imageQuery: 'physics free body diagram inclined plane',
      ),
      card(front: 'Шкала геометрической неизменяемости', back: 's = 2n - 3'),
    ]);

    final cards = evaluate(raw, source: source, imageIds: <String>{'img1'});
    expect(cards, hasLength(3));
    // 7.14: image_id в приоритете, а image остаётся запасным вариантом.
    expect(cards[0].imageId, 'img1');
    expect(cards[0].imageQuery, isNull);
    expect(cards[1].imageId, 'img1');
    expect(cards[1].imageQuery, 'physics free body diagram inclined plane');
    // Заголовок вместо вопроса — мягкая пометка.
    expect(cards[2].issues, contains(CardIssueCode.frontLooksLikeHeading));
  });

  test('сценарий 3: PPTX с иллюстрациями и длинным ответом', () {
    final raw = answer(<Map<String, Object?>>[
      card(
        front: 'Какой тип мостовой конструкции состоит из стержней?',
        back: 'Ферменный мост.',
        imageQuery: 'truss bridge structure engineering',
      ),
      card(
        front: 'Чему равно число стержней фермы?',
        back: '${'Много объяснений. ' * 4}Итог.',
      ),
    ]);

    final cards = evaluate(raw);
    expect(cards, hasLength(2));
    expect(cards[0].imageQuery, 'truss bridge structure engineering');
    expect(cards[1].issues, contains(CardIssueCode.backTooVerbose));
    expect(markedShare(cards), 0.5);
  });
}
