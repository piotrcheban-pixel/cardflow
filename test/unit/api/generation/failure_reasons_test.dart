import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/api/generation/card_content_validator.dart';
import 'package:cardflow/api/generation/card_json_schema.dart';
import 'package:cardflow/api/generation/card_response_schema.dart';
import 'package:cardflow/api/generation/cards_json_extractor.dart';
import 'package:cardflow/domain/generation/generation_error.dart';
import 'package:cardflow/domain/generation/generation_failure_reason.dart';

/// Внутренние коды причин падения фрагмента (fix-gen, Д6).
void main() {
  test('у каждой ошибки есть причина по умолчанию', () {
    expect(
      GenerationException(GenerationErrorCode.truncated).reason,
      GenerationFailureReason.truncated,
    );
    expect(
      GenerationException(GenerationErrorCode.refused).reason,
      GenerationFailureReason.refusal,
    );
    expect(
      GenerationException(GenerationErrorCode.badRequest).reason,
      GenerationFailureReason.httpClientError,
    );
    expect(
      GenerationException(GenerationErrorCode.serverUnavailable).reason,
      GenerationFailureReason.httpServerError,
    );
    expect(
      GenerationException(GenerationErrorCode.network).reason,
      GenerationFailureReason.network,
    );
    expect(
      GenerationException(GenerationErrorCode.timeout).reason,
      GenerationFailureReason.network,
    );
  });

  test('явная причина важнее выведенной из кода (safety)', () {
    const error = GenerationException(
      GenerationErrorCode.refused,
      failureReason: GenerationFailureReason.safety,
    );
    expect(error.reason, GenerationFailureReason.safety);
    expect(error.reason.code, 'safety');
  });

  test('коды причин — машинные строки для generation_jobs', () {
    expect(GenerationFailureReason.jsonParse.code, 'json_parse');
    expect(GenerationFailureReason.schemaInvalid.code, 'schema_invalid');
    expect(
      GenerationFailureReason.validatorRejected.code,
      'validator_rejected',
    );
    expect(GenerationFailureReason.httpClientError.code, 'http_4xx');
    expect(GenerationFailureReason.httpServerError.code, 'http_5xx');
    expect(GenerationFailureReason.tryParse('json_parse'), isNotNull);
    expect(GenerationFailureReason.tryParse('мусор'), isNull);
  });

  group('json_parse / schema_invalid / validator_rejected различаются', () {
    const extractor = CardsJsonExtractor();

    test('не JSON → json_parse', () {
      expect(
        () => extractor.decode('не json', tolerant: true),
        throwsA(
          isA<GenerationException>().having(
            (GenerationException error) => error.reason,
            'reason',
            GenerationFailureReason.jsonParse,
          ),
        ),
      );
    });

    test('корень не {"cards": [...]} → schema_invalid', () {
      final validation = CardResponseSchema().splitValid(<String, Object?>{
        'cards': 'нет',
      });
      expect(validation.rootInvalid, isTrue);
    });

    test('одна плохая карточка отбрасывается, остальные проходят', () {
      Map<String, Object?> card({required String front}) => <String, Object?>{
        'front': front,
        'back': 'Ответ',
        'hint': null,
        'tags': <Object?>['тег'],
        'card_type': 'basic',
        'source_excerpt': null,
        'source_file': null,
        'image_id': null,
        'image_query': null,
      };
      final validation = CardResponseSchema().splitValid(<String, Object?>{
        'cards': <Object?>[
          card(front: 'Хорошая карточка?'),
          <String, Object?>{'front': 'Без back'},
        ],
      });
      expect(validation.rejectedCards, 1);
      expect(validation.cards, hasLength(1));
    });

    test('структурно непригодные карточки → validator_rejected (счёт)', () {
      final outcome = const CardContentValidator().validateResponseWithRejects(
        <String, Object?>{
          'cards': <Object?>[
            <String, Object?>{
              'front': 3,
              'back': 'Ответ',
              'card_type': 'basic',
            },
            'мусор',
          ],
        },
        sourceText: 'текст',
      );
      expect(outcome.cards, isEmpty);
      expect(outcome.rejectedCards, 2);
    });

    test('канон схемы содержит image_id (ADR-029)', () {
      final properties =
          ((canonicalCardsResponseSchema['properties']!
                      as Map<String, Object?>)['cards']!
                  as Map<String, Object?>)['items']!
              as Map<String, Object?>;
      expect(
        (properties['properties']! as Map<String, Object?>).keys,
        contains('image_id'),
      );
      expect((properties['required']! as List<Object?>), contains('image_id'));
      expect(jsonEncode(properties), contains('image_id'));
    });
  });
}
