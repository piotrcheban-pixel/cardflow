import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/domain/generation/generation_error.dart';
import 'package:cardflow/l10n/app_localizations.dart';
import 'package:cardflow/l10n/app_localizations_ru.dart';
import 'package:cardflow/ui/generation/generation_error_message.dart';

/// Красная фаза итерации 3b: коды ошибок генерации → строки ARB (SPEC A8.6).
void main() {
  final AppLocalizations l10n = AppLocalizationsRu();

  test('каждый код GenerationErrorCode покрыт непустой строкой ARB', () {
    for (final code in GenerationErrorCode.values) {
      final message = generationErrorCodeMessage(l10n, code);
      expect(
        message.trim(),
        isNotEmpty,
        reason: 'Пустое сообщение: ${code.name}',
      );
      expect(
        message,
        isNot(contains('GenerationException')),
        reason: code.name,
      );
    }
  });

  test('Rate limited: Retry-After в секундах с падежами', () {
    expect(
      generationErrorCodeMessage(
        l10n,
        GenerationErrorCode.rateLimited,
        retryAfter: const Duration(seconds: 1),
      ),
      contains('1 секунду'),
    );
    expect(
      generationErrorCodeMessage(
        l10n,
        GenerationErrorCode.rateLimited,
        retryAfter: const Duration(seconds: 3),
      ),
      contains('3 секунды'),
    );
    expect(
      generationErrorCodeMessage(
        l10n,
        GenerationErrorCode.rateLimited,
        retryAfter: const Duration(seconds: 5),
      ),
      contains('5 секунд'),
    );
    expect(
      generationErrorCodeMessage(
        l10n,
        GenerationErrorCode.rateLimited,
        retryAfter: const Duration(seconds: 11),
      ),
      contains('11 секунд'),
    );
    expect(
      generationErrorCodeMessage(
        l10n,
        GenerationErrorCode.rateLimited,
        retryAfter: const Duration(seconds: 21),
      ),
      contains('21 секунду'),
    );
  });

  test('Rate limited без Retry-After — отдельная строка без числа', () {
    final message = generationErrorCodeMessage(
      l10n,
      GenerationErrorCode.rateLimited,
    );
    expect(message, l10n.generationErrorRateLimitedNoDelay);
    expect(message, isNot(contains('{')));
  });

  test('ключ: недействителен и не задан — разные сообщения', () {
    expect(
      generationErrorCodeMessage(l10n, GenerationErrorCode.invalidApiKey),
      isNot(
        generationErrorCodeMessage(l10n, GenerationErrorCode.missingApiKey),
      ),
    );
    expect(
      generationErrorCodeMessage(l10n, GenerationErrorCode.invalidApiKey),
      l10n.generationErrorInvalidApiKey,
    );
  });

  test('ненастроенный OpenAI-совместимый сервер — своё сообщение', () {
    expect(
      generationErrorCodeMessage(
        l10n,
        GenerationErrorCode.providerNotConfigured,
      ),
      l10n.generationErrorProviderNotConfigured,
    );
    expect(
      generationErrorCodeMessage(
        l10n,
        GenerationErrorCode.providerNotConfigured,
      ),
      isNot(
        generationErrorCodeMessage(l10n, GenerationErrorCode.missingApiKey),
      ),
    );
  });

  test(
    'timeout и network — «нет подключения»; ошибки модели — отдельные строки',
    () {
      expect(
        generationErrorCodeMessage(l10n, GenerationErrorCode.timeout),
        l10n.generationErrorNoConnection,
      );
      expect(
        generationErrorCodeMessage(l10n, GenerationErrorCode.network),
        l10n.generationErrorNoConnection,
      );
      expect(
        generationErrorCodeMessage(l10n, GenerationErrorCode.truncated),
        l10n.generationErrorUnexpectedResponse,
      );
      expect(
        generationErrorCodeMessage(l10n, GenerationErrorCode.refused),
        l10n.generationErrorUnexpectedResponse,
      );
      expect(
        generationErrorCodeMessage(l10n, GenerationErrorCode.invalidResponse),
        l10n.generationErrorUnexpectedResponse,
      );
      expect(
        generationErrorCodeMessage(l10n, GenerationErrorCode.emptyResponse),
        l10n.generationErrorEmptyResponse,
      );
      expect(
        generationErrorCodeMessage(l10n, GenerationErrorCode.cancelled),
        l10n.generationErrorCancelled,
      );
    },
  );

  test('400 с причиной провайдера показывает реальную причину', () {
    final message = generationErrorCodeMessage(
      l10n,
      GenerationErrorCode.badRequest,
      providerReason: 'invalid characters in content',
    );
    expect(message, contains('invalid characters in content'));
    expect(
      message,
      l10n.generationErrorBadRequestReason('invalid characters in content'),
    );
    expect(
      generationErrorCodeMessage(l10n, GenerationErrorCode.badRequest),
      l10n.generationErrorBadRequest,
      reason: 'без причины — прежняя строка',
    );
  });

  test('вложения: ошибки vision и пустого текста — разные строки', () {
    expect(
      generationErrorCodeMessage(l10n, GenerationErrorCode.visionUnsupported),
      l10n.generationErrorVisionUnsupported,
    );
    expect(
      generationErrorCodeMessage(
        l10n,
        GenerationErrorCode.fileWithoutTextAndVision,
      ),
      l10n.generationErrorFileWithoutTextAndVision,
    );
    expect(
      generationErrorCodeMessage(l10n, GenerationErrorCode.pdfScanUnsupported),
      l10n.generationErrorPdfScanUnsupported,
    );
    expect(
      generationErrorCodeMessage(l10n, GenerationErrorCode.attachmentTooLarge),
      l10n.generationErrorAttachmentTooLarge,
    );
    expect(
      generationErrorCodeMessage(l10n, GenerationErrorCode.noMaterials),
      l10n.generationErrorNoMaterials,
    );
  });

  test('причина провайдера из GenerationException доходит до сообщения', () {
    final message = generationErrorMessage(
      l10n,
      const GenerationException(
        GenerationErrorCode.badRequest,
        providerReason: 'invalid characters in content',
      ),
    );
    expect(message, contains('invalid characters in content'));
  });

  test('GenerationException маппится по коду, сырые details не утекают', () {
    const exception = GenerationException(
      GenerationErrorCode.serverUnavailable,
      details: 'HTTP 503: upstream failure',
    );
    final message = generationErrorMessage(l10n, exception);
    expect(message, l10n.generationErrorServerUnavailable);
    expect(message, isNot(contains('503')));
    expect(message, isNot(contains('upstream')));
    expect(message, isNot(contains('GenerationException')));
  });

  test('произвольная ошибка → общая строка ARB без текста исключения', () {
    final message = generationErrorMessage(l10n, StateError('внутренний сбой'));
    expect(message, l10n.generationErrorGeneric);
    expect(message, isNot(contains('внутренний сбой')));
  });

  test('в ARB нет пустых строк генерации и нет сырых кодов', () {
    final messages = <String>[
      for (final code in GenerationErrorCode.values)
        generationErrorCodeMessage(l10n, code),
    ];
    for (final message in messages) {
      expect(message.trim(), isNotEmpty);
      expect(message, isNot(contains('{')), reason: 'ICU не должен утекать');
    }
  });
}
