import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/api/generation/card_generation_service.dart';
import 'package:cardflow/domain/generation/document_image.dart';
import 'package:cardflow/domain/generation/generated_card.dart';
import 'package:cardflow/domain/generation/generation_attachment.dart';
import 'package:cardflow/domain/generation/generation_error.dart';
import 'package:cardflow/domain/generation/generation_failure_reason.dart';
import 'package:cardflow/domain/generation/generation_request.dart';
import 'package:cardflow/domain/generation/generation_result.dart';

import '../../../helpers/generation_fakes.dart';

/// Блок `<images>` и поштучная проверка схемы в сервисе генерации (fix-gen).
void main() {
  Map<String, Object?> cardJson({
    String front = 'При каком условии две силы уравновешены?',
    String? imageId,
    String? imageQuery,
  }) {
    return <String, Object?>{
      'front': front,
      'back': 'Когда равны по модулю и противоположны.',
      'hint': null,
      'tags': <Object?>['статика'],
      'card_type': 'basic',
      'source_excerpt': null,
      'source_file': null,
      'image_id': imageId,
      'image_query': imageQuery,
    };
  }

  String cardsJson(List<Map<String, Object?>> cards) =>
      jsonEncode(<String, Object?>{'cards': cards});

  CardGenerationService serviceWith({
    required FakeProviderAdapter adapter,
    required FakeGenerationTransport transport,
  }) {
    return CardGenerationService(
      adapters: <FakeProviderAdapter>[adapter],
      apiKeyStore: FakeApiKeyStore(<String, String>{'openai': 'test-key'}),
      httpClient: transport,
      systemPrompt: 'СИСТЕМНЫЙ ПРОМПТ',
      promptVersion: 'gen-ru-v5',
    );
  }

  DocumentImage documentImage() {
    return DocumentImage(
      fileName: 'статика.docx',
      bytes: Uint8List.fromList(<int>[0x89, 0x50, 0x4E, 0x47, 1, 2, 3]),
      mediaType: AttachmentMediaType.png,
      caption: 'Рис. 1. Две силы',
      context: 'Аксиома о равновесии двух сил',
    );
  }

  test(
    'каталог <images> уходит в запрос, image_id проходит валидацию',
    () async {
      final adapter = FakeProviderAdapter(
        cardsJson: cardsJson(<Map<String, Object?>>[cardJson(imageId: 'img1')]),
      );
      final transport = FakeGenerationTransport(
        response: <String, Object?>{'ok': true},
      );
      final service = serviceWith(adapter: adapter, transport: transport);

      final GenerationResult result = await service.generate(
        GenerationRequest(
          account: testProviderAccount(presetId: 'openai', modelId: 'gpt-4o'),
          materialsText: 'Файл: статика.docx\nАксиома о равновесии двух сил',
          limit: 5,
          documentImages: <DocumentImage>[documentImage()],
        ),
      );

      final String userContent = adapter.buildArgs!.userContent;
      expect(userContent, contains('<images>'));
      expect(
        userContent,
        contains(
          'img1 | статика.docx | Рис. 1. Две силы | '
          'Аксиома о равновесии двух сил',
        ),
      );
      expect(result.cards.single.imageId, 'img1');
      expect(result.rejectedCards, 0);
    },
  );

  test('image_id не из каталога обнуляется, карточка остаётся', () async {
    final adapter = FakeProviderAdapter(
      cardsJson: cardsJson(<Map<String, Object?>>[
        cardJson(imageId: 'img9', imageQuery: 'ball physics'),
      ]),
    );
    final transport = FakeGenerationTransport(
      response: <String, Object?>{'ok': true},
    );
    final service = serviceWith(adapter: adapter, transport: transport);

    final result = await service.generate(
      GenerationRequest(
        account: testProviderAccount(presetId: 'openai', modelId: 'gpt-4o'),
        materialsText: 'Файл: статика.docx\nАксиома о равновесии двух сил',
        limit: 5,
        documentImages: <DocumentImage>[documentImage()],
      ),
    );

    expect(result.cards, hasLength(1));
    expect(result.cards.single.imageId, isNull);
    expect(result.cards.single.issues, contains(CardIssueCode.imageIdUnknown));
    // Запрос сохраняется: изображение из файла не найдено, внешний поиск — можно.
    expect(result.cards.single.imageQuery, 'ball physics');
  });

  test('корень не {"cards": [...]} → schema_invalid без сети', () async {
    final adapter = FakeProviderAdapter(cardsJson: '{"cards": "нет"}');
    final transport = FakeGenerationTransport(
      response: <String, Object?>{'ok': true},
    );
    final service = serviceWith(adapter: adapter, transport: transport);

    await expectLater(
      service.generate(
        GenerationRequest(
          account: testProviderAccount(presetId: 'openai', modelId: 'gpt-4o'),
          materialsText: 'Материал',
          limit: 3,
        ),
      ),
      throwsA(
        isA<GenerationException>()
            .having(
              (GenerationException error) => error.code,
              'code',
              GenerationErrorCode.invalidResponse,
            )
            .having(
              (GenerationException error) => error.reason,
              'reason',
              GenerationFailureReason.schemaInvalid,
            ),
      ),
    );
  });

  test('одна карточка без обязательного ключа не роняет фрагмент', () async {
    final Map<String, Object?> broken = cardJson(front: 'Без back');
    broken.remove('back');
    final adapter = FakeProviderAdapter(
      cardsJson: cardsJson(<Map<String, Object?>>[broken, cardJson()]),
    );
    final transport = FakeGenerationTransport(
      response: <String, Object?>{'ok': true},
    );
    final service = serviceWith(adapter: adapter, transport: transport);

    final result = await service.generate(
      GenerationRequest(
        account: testProviderAccount(presetId: 'openai', modelId: 'gpt-4o'),
        materialsText: 'Материал',
        limit: 3,
      ),
    );

    expect(result.cards, hasLength(1));
    expect(result.rejectedCards, 1);
  });
}
