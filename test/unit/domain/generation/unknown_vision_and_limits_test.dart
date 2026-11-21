import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/api/generation/generation_plan_builder.dart';
import 'package:cardflow/domain/generation/document_image.dart';
import 'package:cardflow/domain/generation/generation_attachment.dart';
import 'package:cardflow/domain/generation/generation_plan.dart';
import 'package:cardflow/domain/generation/model_capabilities.dart';
import 'package:cardflow/domain/generation/model_limits.dart';
import 'package:cardflow/domain/generation/model_limits_resolver.dart';
import 'package:cardflow/domain/generation/provider_account.dart';
import 'package:cardflow/domain/generation/provider_protocol.dart';
import 'package:cardflow/domain/text/document_format.dart';
import 'package:cardflow/domain/text/parsed_document.dart';

/// Итерация 7.18.3 §4–§5: три состояния поддержки изображений и честный
/// список неизвестных характеристик (`max_request_bytes` — не «32 МБ факт»).
void main() {
  ProviderAccount customAccount({bool visionConfigured = false}) =>
      ProviderAccount(
        id: 'custom',
        label: 'Свой сервер',
        protocol: ProviderProtocol.anthropicMessages,
        baseUrl: 'https://api.example.test',
        modelId: 'some-model',
        requiresApiKey: true,
        supportsVision: visionConfigured,
        visionConfigured: visionConfigured,
      );

  DocumentImage imageOf() => DocumentImage(
    fileName: 'схема.png',
    bytes: Uint8List.fromList(
      List<int>.generate(4096, (int i) => (i * 7 + 1) % 251),
    ),
    mediaType: AttachmentMediaType.png,
    width: 800,
    height: 600,
    sectionIndex: 0,
    caption: 'Схема',
  );

  GenerationAttachment attachmentOf() => GenerationAttachment(
    fileName: 'фото.png',
    mediaType: AttachmentMediaType.png,
    bytes: Uint8List.fromList(
      List<int>.generate(4096, (int i) => (i * 11 + 3) % 251),
    ),
  );

  GenerationPlan build(
    ModelCapabilities capabilities, {
    bool attachment = false,
    bool embedded = false,
  }) {
    const String docText = 'Материал лекции о фотосинтезе.';
    return const GenerationPlanBuilder().build(
      documents: <ParsedDocument>[
        ParsedDocument(
          format: DocumentFormat.txt,
          fileName: 'лекция.txt',
          text: docText,
          sections: <ParsedSection>[
            ParsedSection(start: 0, end: docText.length),
          ],
          images: embedded
              ? <DocumentImage>[imageOf()]
              : const <DocumentImage>[],
        ),
      ],
      capabilities: capabilities,
      attachments: attachment
          ? <GenerationAttachment>[attachmentOf()]
          : const <GenerationAttachment>[],
      documentImages: embedded
          ? const <DocumentImage>[]
          : <DocumentImage>[imageOf()],
      requestedCards: 3,
    );
  }

  test(
    'custom-аккаунт без visionConfigured: поддержка неизвестна, не false',
    () {
      final ProviderAccount account = customAccount();
      final ModelLimits limits = resolveModelLimits(account: account);
      expect(limits.supportsImageInput.value, isNull);
      final ModelCapabilities capabilities = resolveModelCapabilities(account);
      expect(
        capabilities.supportsVision,
        isNull,
        reason: 'неизвестность нельзя выдавать за подтверждённое false',
      );
      expect(
        capabilities.unknownFields,
        contains(ModelCapabilities.unknownImageInput),
      );
    },
  );

  test('неизвестный Vision: изображения отправляются с предупреждением', () {
    final ModelCapabilities capabilities = resolveModelCapabilities(
      customAccount(),
    );
    final GenerationPlan plan = build(capabilities);
    expect(plan.validity.isInvalid, isFalse, reason: 'нет данных — не запрет');
    expect(
      plan.validity.warnings,
      contains(PlanWarningCode.imagesVisionUnconfirmed),
    );
    expect(
      plan.validity.warnings,
      isNot(contains(PlanWarningCode.imagesWithoutVision)),
    );
    expect(plan.imagesSentToModel, 1);
    expect(
      plan.chunks.single.imageParts,
      hasLength(1),
      reason: 'изображение уходит частью, а не только каталогом',
    );
  });

  test('неизвестный Vision: вложение пользователя не блокирует план', () {
    final GenerationPlan plan = build(
      resolveModelCapabilities(customAccount()),
      attachment: true,
    );
    expect(plan.validity.isInvalid, isFalse);
    expect(
      plan.validity.warnings,
      contains(PlanWarningCode.imagesVisionUnconfirmed),
    );
  });

  test('подтверждённое false: план не врёт о поддержке (каталог)', () {
    final GenerationPlan plan = build(
      const ModelCapabilities(
        contextWindowTokens: 128000,
        contextSource: CapabilitySource.userConfigured,
        supportsVision: false,
        visionSource: CapabilitySource.officialCatalog,
      ),
      embedded: true,
    );
    expect(plan.validity.isInvalid, isFalse);
    expect(
      plan.validity.warnings,
      contains(PlanWarningCode.imagesWithoutVision),
    );
    expect(
      plan.validity.warnings,
      isNot(contains(PlanWarningCode.imagesVisionUnconfirmed)),
    );
    expect(plan.imagesSentToModel, 0);
    expect(plan.imagesUnsupported, 1);
  });

  test('подтверждённое false: вложение пользователя — невыполнимый план', () {
    final GenerationPlan plan = build(
      const ModelCapabilities(
        contextWindowTokens: 128000,
        contextSource: CapabilitySource.userConfigured,
        supportsVision: false,
        visionSource: CapabilitySource.officialCatalog,
      ),
      attachment: true,
    );
    expect(plan.validity.isInvalid, isTrue);
    expect(plan.validity.reason, PlanInvalidReason.imagesWithoutVision);
  });

  test('подтверждённое true: точный путь без предупреждения о Vision', () {
    final GenerationPlan plan = build(
      const ModelCapabilities(
        contextWindowTokens: 128000,
        contextSource: CapabilitySource.userConfigured,
        supportsVision: true,
        visionSource: CapabilitySource.officialCatalog,
      ),
    );
    expect(plan.validity.isInvalid, isFalse);
    expect(plan.imagesSentToModel, 1);
    expect(
      plan.validity.warnings,
      isNot(contains(PlanWarningCode.imagesVisionUnconfirmed)),
    );
  });

  test('max_request_bytes в unknownFields лимитов, возможностей и плана', () {
    final ModelLimits limits = resolveModelLimits(account: customAccount());
    expect(
      limits.unknownFields,
      contains('max_request_bytes'),
      reason: '32 МБ — допущение приложения, а не характеристика модели',
    );
    final ModelCapabilities capabilities = resolveModelCapabilities(
      customAccount(),
    );
    expect(
      capabilities.unknownFields,
      contains(ModelCapabilities.unknownMaxRequestBytes),
    );
    final GenerationPlan plan = build(capabilities);
    expect(plan.unknownFields, contains('max_request_bytes'));
  });

  test('userConfigured Vision приоритетнее провайдера и каталога', () {
    final ProviderAccount account = customAccount(visionConfigured: true)
        .copyWith(supportsVision: true);
    final ModelLimits limits = resolveModelLimits(account: account);
    expect(limits.supportsImageInput.value, isTrue);
    expect(limits.supportsImageInput.source, CapabilitySource.userConfigured);
  });
}
