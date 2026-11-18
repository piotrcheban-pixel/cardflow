import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/api/generation/card_generation_service.dart';
import 'package:cardflow/api/generation/generation_images.dart';
import 'package:cardflow/domain/generation/document_image.dart';
import 'package:cardflow/domain/generation/generated_card.dart';
import 'package:cardflow/domain/generation/generation_attachment.dart';
import 'package:cardflow/domain/generation/generation_provider.dart';
import 'package:cardflow/domain/generation/generation_request.dart';
import 'package:cardflow/domain/generation/generation_result.dart';

import '../../../helpers/generation_fakes.dart';

/// Изображения из PDF доходят до модели как изображения, а не только как
/// `image_id` в тексте (итерация L76, ADR-037).
void main() {
  Map<String, Object?> cardJson({
    String front = 'Какая схема изображена на рисунке?',
    String? imageId = 'img1',
  }) {
    return <String, Object?>{
      'front': front,
      'back': 'Схема фермы с треугольными ячейками.',
      'hint': null,
      'tags': <Object?>['фермы'],
      'card_type': 'basic',
      'source_excerpt': null,
      'source_file': 'лекция.pdf',
      'image_id': imageId,
      'image': <String, Object?>{
        'query': 'truss bridge diagram',
        'fallback_query': 'truss bridge',
        'kind': 'diagram',
      },
    };
  }

  String cardsJson(List<Map<String, Object?>> cards) =>
      jsonEncode(<String, Object?>{'cards': cards});

  CardGenerationService serviceWith(FakeProviderAdapter adapter) {
    return CardGenerationService(
      adapters: <FakeProviderAdapter>[adapter],
      apiKeyStore: FakeApiKeyStore(<String, String>{'custom': 'test-key'}),
      httpClient: FakeGenerationTransport(
        response: <String, Object?>{'ok': true},
      ),
      systemPrompt: 'СИСТЕМНЫЙ ПРОМПТ',
      promptVersion: 'gen-ru-v7',
    );
  }

  Uint8List pngBytes(int seed) {
    return Uint8List.fromList(<int>[
      0x89,
      0x50,
      0x4E,
      0x47,
      0x0D,
      0x0A,
      0x1A,
      0x0A,
      seed,
      seed + 1,
      seed + 2,
    ]);
  }

  DocumentImage pdfImage({
    int page = 2,
    DocumentImageSource source = DocumentImageSource.croppedRegion,
    String? caption,
    int seed = 1,
    int width = 600,
    int height = 300,
  }) {
    return DocumentImage(
      fileName: 'лекция.pdf',
      bytes: pngBytes(seed),
      mediaType: AttachmentMediaType.png,
      page: page,
      source: source,
      caption: caption,
      width: width,
      height: height,
      context: 'Схема фермы',
    );
  }

  test(
    'vision-модель получает байты изображения из PDF с подписью каталога',
    () async {
      final FakeProviderAdapter adapter = FakeProviderAdapter(
        provider: GenerationProvider.openaiCompatible,
        cardsJson: cardsJson(<Map<String, Object?>>[cardJson()]),
      );
      final CardGenerationService service = serviceWith(adapter);

      final GenerationResult result = await service.generate(
        GenerationRequest(
          account: testCustomProviderAccount(supportsVision: true),
          materialsText: 'Файл: лекция.pdf\nСхема фермы и её элементы',
          limit: 3,
          documentImages: <DocumentImage>[pdfImage(page: 2)],
        ),
      );

      final List<GenerationAttachment> parts = adapter.buildArgs!.images;
      expect(parts, hasLength(1), reason: 'Изображение не ушло в запрос');
      expect(parts.single.bytes, pngBytes(1));
      expect(parts.single.mediaType, AttachmentMediaType.png);
      // Подпись каталога с id и страницей идёт перед частью: модель однозначно
      // сопоставляет изображение с image_id.
      expect(parts.single.label, contains('img1'));
      expect(parts.single.label, contains('стр. 2'));
      // Каталог в тексте запроса остаётся.
      expect(adapter.buildArgs!.userContent, contains('<images>'));
      expect(adapter.buildArgs!.userContent, contains('стр. 2'));
      expect(result.cards.single.imageId, 'img1');
    },
  );

  test(
    'модель без Vision: только каталог, изображение не отправляется',
    () async {
      final FakeProviderAdapter adapter = FakeProviderAdapter(
        provider: GenerationProvider.openaiCompatible,
        cardsJson: cardsJson(<Map<String, Object?>>[cardJson()]),
      );
      final CardGenerationService service = serviceWith(adapter);

      final GenerationResult result = await service.generate(
        GenerationRequest(
          account: testCustomProviderAccount(supportsVision: false),
          materialsText: 'Файл: лекция.pdf\nСхема фермы и её элементы',
          limit: 3,
          documentImages: <DocumentImage>[pdfImage()],
        ),
      );

      expect(adapter.buildArgs!.images, isEmpty);
      expect(adapter.buildArgs!.userContent, contains('img1 | лекция.pdf'));
      // image_id валиден и для каталожного изображения: байты найдутся при импорте.
      expect(result.cards.single.imageId, 'img1');
    },
  );

  test('больше лимита изображений: 8 частей, каталог полный', () async {
    final List<DocumentImage> images = <DocumentImage>[
      for (var index = 0; index < 12; index++)
        pdfImage(
          page: index + 1,
          seed: index * 10,
          caption: index == 11 ? 'Рис. 12 Особо важная схема' : null,
          width: 300 + index,
        ),
    ];
    final FakeProviderAdapter adapter = FakeProviderAdapter(
      provider: GenerationProvider.openaiCompatible,
      cardsJson: cardsJson(<Map<String, Object?>>[cardJson()]),
    );
    final CardGenerationService service = serviceWith(adapter);

    await service.generate(
      GenerationRequest(
        account: testCustomProviderAccount(supportsVision: true),
        materialsText: 'Файл: лекция.pdf\nМного схем',
        limit: 5,
        documentImages: images,
      ),
    );

    final String content = adapter.buildArgs!.userContent;
    expect(adapter.buildArgs!.images, hasLength(kMaxVisionDocumentImages));
    // Каталог содержит все изображения, включая не отправленные как часть.
    for (var index = 1; index <= 12; index++) {
      expect(content, contains('img$index |'), reason: 'Нет img$index');
    }
    expect(
      adapter.buildArgs!.images.map((GenerationAttachment part) => part.label),
      anyElement(contains('img12')),
      reason: 'Изображение с подписью должно попасть в приоритет',
    );
  });

  test('повторяющиеся байты не отправляются дважды', () async {
    final FakeProviderAdapter adapter = FakeProviderAdapter(
      provider: GenerationProvider.openaiCompatible,
      cardsJson: cardsJson(<Map<String, Object?>>[cardJson()]),
    );
    final CardGenerationService service = serviceWith(adapter);

    await service.generate(
      GenerationRequest(
        account: testCustomProviderAccount(supportsVision: true),
        materialsText: 'Файл: лекция.pdf\nСхема',
        limit: 3,
        documentImages: <DocumentImage>[
          pdfImage(page: 1, seed: 7),
          pdfImage(page: 3, seed: 7),
        ],
      ),
    );

    expect(adapter.buildArgs!.images, hasLength(1));
    expect(adapter.buildArgs!.userContent, contains('img1 |'));
    expect(adapter.buildArgs!.userContent, contains('img2 |'));
  });

  test('image_id не из каталога обнуляется, карточка остаётся', () async {
    final FakeProviderAdapter adapter = FakeProviderAdapter(
      provider: GenerationProvider.openaiCompatible,
      cardsJson: cardsJson(<Map<String, Object?>>[cardJson(imageId: 'img99')]),
    );
    final CardGenerationService service = serviceWith(adapter);

    final GenerationResult result = await service.generate(
      GenerationRequest(
        account: testCustomProviderAccount(supportsVision: true),
        materialsText: 'Файл: лекция.pdf\nСхема',
        limit: 3,
        documentImages: <DocumentImage>[pdfImage()],
      ),
    );

    expect(result.cards, hasLength(1));
    expect(result.cards.single.imageId, isNull);
    expect(result.cards.single.issues, contains(CardIssueCode.imageIdUnknown));
  });

  test('страница скана попадает в каталог как «область скана»', () async {
    final FakeProviderAdapter adapter = FakeProviderAdapter(
      provider: GenerationProvider.openaiCompatible,
      cardsJson: cardsJson(<Map<String, Object?>>[cardJson()]),
    );
    final CardGenerationService service = serviceWith(adapter);

    await service.generate(
      GenerationRequest(
        account: testCustomProviderAccount(supportsVision: true),
        materialsText: 'Файл: скан.pdf\n',
        limit: 3,
        documentImages: <DocumentImage>[
          pdfImage(
            page: 1,
            source: DocumentImageSource.renderedPage,
          ).withContext(context: null),
        ],
      ),
    );

    expect(adapter.buildArgs!.userContent, contains('стр. 1, страница скана'));
    expect(adapter.buildArgs!.images.single.label, contains('стр. 1'));
  });
}
