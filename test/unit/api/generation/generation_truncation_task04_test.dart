import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/api/generation/card_generation_service.dart';
import 'package:cardflow/api/providers/openai_compatible_adapter.dart';
import 'package:cardflow/domain/generation/generation_error.dart';
import 'package:cardflow/domain/generation/generation_request.dart';
import 'package:cardflow/domain/generation/generation_result.dart';
import 'package:cardflow/domain/generation/provider_account.dart';
import 'package:cardflow/domain/generation/provider_protocol.dart';

import '../../../helpers/generation_fakes.dart';

/// TASK 04, часть 4: модель, упёршаяся в лимит вывода, не должна «съедать»
/// уже сгенерированные карточки.
///
/// Здесь проверяется production-проводка адаптера: реальный
/// `OpenAiCompatibleAdapter` разбирает ответ с `finish_reason: length`, а
/// `CardGenerationService` спасает полные карточки из прерванного JSON.
void main() {
  ProviderAccount account() => ProviderAccount(
    id: 'deepseek',
    label: 'DeepSeek',
    presetId: 'deepseek',
    protocol: ProviderProtocol.openaiCompletions,
    baseUrl: 'https://api.deepseek.com',
    modelId: 'deepseek-chat',
    contextTokens: 128000,
    requiresApiKey: false,
  );

  CardGenerationService serviceWith(FakeGenerationTransport transport) {
    return CardGenerationService(
      adapters: <OpenAiCompatibleAdapter>[const OpenAiCompatibleAdapter()],
      apiKeyStore: FakeApiKeyStore(),
      httpClient: transport,
    );
  }

  GenerationRequest request() => GenerationRequest(
    account: account(),
    materialsText: 'Материал лекции',
    limit: 50,
  );

  Map<String, Object?> truncatedResponse(String content) => <String, Object?>{
    'choices': <Object?>[
      <String, Object?>{
        'message': <String, Object?>{'content': content},
        'finish_reason': 'length',
      },
    ],
    'usage': <String, Object?>{
      'prompt_tokens': 100,
      'completion_tokens': 2000,
      'total_tokens': 2100,
    },
  };

  Map<String, Object?> card(String front) => <String, Object?>{
    'front': front,
    'back': 'Ответ на $front',
    'hint': null,
    'tags': <Object?>[],
    'card_type': 'basic',
    'source_excerpt': null,
    'source_file': null,
    'question_image_ids': <Object?>[],
    'answer_image_ids': <Object?>[],
    'image': null,
  };

  test(
    'оборванный ответ: полные карточки сохраняются, флаг truncated',
    () async {
      final String complete = jsonEncode(<Object?>[
        card('Вопрос 1'),
        card('Вопрос 2'),
      ]);
      // Ответ модели обрезан посреди третьей карточки.
      final String partial =
          '{"cards":${complete.substring(0, complete.length - 1)},'
          '${jsonEncode(card('Вопрос 3')).substring(0, 30)}';
      final transport = FakeGenerationTransport(
        response: truncatedResponse(partial),
      );

      final GenerationResult result = await serviceWith(transport)
          .generate(request());

      expect(result.cards, hasLength(2));
      expect(result.truncated, isTrue);
      expect(result.salvagedCards, 2);
      expect(result.cards.map((card) => card.front), <String>[
        'Вопрос 1',
        'Вопрос 2',
      ], reason: 'порядок ответа модели сохраняется');
    },
  );

  test(
    'оборванный ответ без полных карточек → truncated для восстановления',
    () async {
      final transport = FakeGenerationTransport(
        response: truncatedResponse('{"cards":['),
      );
      await expectLater(
        serviceWith(transport).generate(request()),
        throwsA(
          isA<GenerationException>().having(
            (GenerationException error) => error.code,
            'code',
            GenerationErrorCode.truncated,
          ),
        ),
      );
    },
  );

  test('полный JSON с finish_reason=length не теряет карточки', () async {
    final String content = jsonEncode(<Object?>[
      for (var index = 1; index <= 5; index++) card('Вопрос $index'),
    ]);
    final transport = FakeGenerationTransport(
      response: truncatedResponse('{"cards":$content}'),
    );

    final GenerationResult result = await serviceWith(transport)
        .generate(request());

    expect(result.cards, hasLength(5));
    expect(result.truncated, isTrue);
    expect(result.salvagedCards, 5);
  });

  test('обычный ответ без обрыва: truncated=false, карточки целиком', () async {
    final String content = jsonEncode(<Object?>[
      for (var index = 1; index <= 3; index++) card('Вопрос $index'),
    ]);
    final transport = FakeGenerationTransport(
      response: <String, Object?>{
        'choices': <Object?>[
          <String, Object?>{
            'message': <String, Object?>{'content': '{"cards":$content}'},
            'finish_reason': 'stop',
          },
        ],
      },
    );

    final GenerationResult result = await serviceWith(transport)
        .generate(request());

    expect(result.cards, hasLength(3));
    expect(result.truncated, isFalse);
    expect(result.salvagedCards, 0);
  });
}
