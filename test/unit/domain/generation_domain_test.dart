import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/generation/generated_card.dart';
import 'package:cardflow/domain/generation/generation_error.dart';
import 'package:cardflow/domain/generation/generation_provider.dart';
import 'package:cardflow/domain/generation/generation_request.dart';
import 'package:cardflow/domain/generation/provider_account.dart';
import 'package:cardflow/domain/generation/provider_protocol.dart';
import 'package:cardflow/domain/generation/generation_result.dart';

/// Красная фаза итерации 3b: доменные модели слоя генерации (SPEC A8.2, A8.4, A8.6).
void main() {
  group('GenerationProvider', () {
    test('wireName соответствует generation_jobs.provider', () {
      expect(GenerationProvider.openai.wireName, 'openai');
      expect(GenerationProvider.gemini.wireName, 'gemini');
      expect(GenerationProvider.anthropic.wireName, 'anthropic');
      expect(GenerationProvider.openaiCompatible.wireName, 'openai_compatible');
      expect(GenerationProvider.values, hasLength(4));
    });

    test('fromWire разбирает известные значения и падает на неизвестном', () {
      for (final provider in GenerationProvider.values) {
        expect(GenerationProvider.fromWire(provider.wireName), provider);
      }
      expect(
        () => GenerationProvider.fromWire('deepseek'),
        throwsA(isA<FormatException>()),
      );
    });
  });

  group('GenerationException', () {
    test('несёт код, retryAfter и details, details не в UI-контракте', () {
      const exception = GenerationException(
        GenerationErrorCode.rateLimited,
        retryAfter: Duration(seconds: 7),
        details: 'HTTP 429',
      );
      expect(exception.code, GenerationErrorCode.rateLimited);
      expect(exception.retryAfter, const Duration(seconds: 7));
      expect(exception.details, 'HTTP 429');
      expect(exception.toString(), contains('rateLimited'));
    });

    test('все коды A8.6, noMaterials (3c), вложений (7.8), плана (02B) и '
        'хранилища (фикс генерации) есть', () {
      expect(GenerationErrorCode.values.toSet(), <GenerationErrorCode>{
        GenerationErrorCode.missingApiKey,
        GenerationErrorCode.providerNotConfigured,
        GenerationErrorCode.invalidApiKey,
        GenerationErrorCode.badRequest,
        GenerationErrorCode.contextOverflow,
        GenerationErrorCode.payloadTooLarge,
        GenerationErrorCode.rateLimited,
        GenerationErrorCode.serverUnavailable,
        GenerationErrorCode.timeout,
        GenerationErrorCode.network,
        GenerationErrorCode.cancelled,
        GenerationErrorCode.emptyResponse,
        GenerationErrorCode.truncated,
        GenerationErrorCode.refused,
        GenerationErrorCode.invalidResponse,
        GenerationErrorCode.noMaterials,
        GenerationErrorCode.visionUnsupported,
        GenerationErrorCode.fileWithoutTextAndVision,
        GenerationErrorCode.pdfScanUnsupported,
        GenerationErrorCode.pdfScanVisionRequired,
        GenerationErrorCode.attachmentTooLarge,
        GenerationErrorCode.storageUnavailable,
      });
    });

    test('providerReason — безопасная причина 400, не входит в details', () {
      const exception = GenerationException(
        GenerationErrorCode.badRequest,
        details: 'HTTP 400',
        providerReason: 'invalid characters in content',
      );
      expect(exception.providerReason, 'invalid characters in content');
      expect(exception.details, 'HTTP 400');
      expect(exception.toString(), isNot(contains('invalid characters')));
    });
  });

  group('GeneratedCard', () {
    test(
      'immutable-значение: равенство по полям, теги и пометки сравниваются',
      () {
        const first = GeneratedCard(
          front: 'Вопрос',
          back: 'Ответ',
          cardType: CardType.basic,
          tags: <String>['тег'],
          issues: <CardIssueCode>[CardIssueCode.tagsAdjusted],
        );
        const same = GeneratedCard(
          front: 'Вопрос',
          back: 'Ответ',
          cardType: CardType.basic,
          tags: <String>['тег'],
          issues: <CardIssueCode>[CardIssueCode.tagsAdjusted],
        );
        const other = GeneratedCard(
          front: 'Вопрос',
          back: 'Ответ',
          cardType: CardType.basic,
          tags: <String>['другой'],
        );

        expect(first, same);
        expect(first.hashCode, same.hashCode);
        expect(first, isNot(other));
        expect(first.hasIssues, isTrue);
        expect(other.hasIssues, isFalse);
      },
    );

    test('по умолчанию нет тегов/пометок, hint и цитата null', () {
      const card = GeneratedCard(
        front: 'f',
        back: 'b',
        cardType: CardType.cloze,
      );
      expect(card.tags, isEmpty);
      expect(card.issues, isEmpty);
      expect(card.hint, isNull);
      expect(card.sourceExcerpt, isNull);
      expect(card.sourceFile, isNull);
    });
  });

  group('TokenUsage / GenerationResult / GenerationRequest', () {
    test('TokenUsage сравнивается по полям', () {
      const usage = TokenUsage(
        promptTokens: 10,
        completionTokens: 20,
        totalTokens: 30,
      );
      expect(
        usage,
        const TokenUsage(
          promptTokens: 10,
          completionTokens: 20,
          totalTokens: 30,
        ),
      );
      expect(usage, isNot(const TokenUsage(promptTokens: 10)));
      expect(usage.hashCode, isNot(0));
    });

    test(
      'GenerationRequest хранит аккаунт, материалы и пожелания опциональны',
      () {
        final ProviderAccount account = ProviderAccount(
          id: 'gemini',
          label: 'Gemini',
          presetId: 'gemini',
          protocol: ProviderProtocol.geminiGenerateContent,
          baseUrl: 'https://generativelanguage.googleapis.com',
          modelId: 'gemini-test',
          requiresApiKey: true,
        );
        final GenerationRequest request = GenerationRequest(
          account: account,
          materialsText: 'Материал',
          limit: 12,
        );
        expect(request.account, account);
        expect(
          request.account.protocol,
          ProviderProtocol.geminiGenerateContent,
        );
        expect(request.materialsText, 'Материал');
        expect(request.limit, 12);
        expect(request.wishes, isNull);
      },
    );

    test('GenerationResult хранит карточки, расход и версию промпта', () {
      const result = GenerationResult(
        provider: GenerationProvider.anthropic,
        model: 'claude-test',
        promptVersion: 'gen-ru-v2',
        cards: <GeneratedCard>[],
        usage: TokenUsage(totalTokens: 5),
      );
      expect(result.provider, GenerationProvider.anthropic);
      expect(result.model, 'claude-test');
      expect(result.promptVersion, 'gen-ru-v2');
      expect(result.cards, isEmpty);
      expect(result.usage.totalTokens, 5);
      expect(result.toString(), contains('anthropic'));
    });
  });
}
