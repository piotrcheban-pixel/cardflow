/// Единый результат разбора ответа модели — нормализация адаптеров (срез 5).
///
/// Четыре адаптера провайдеров (`lib/api/providers/`) исторически сообщают
/// исход по-разному: часть поводов — исключения (`GenerationException`), часть
/// — поля ответа. Этап Generation должен видеть **один** тип с одинаковыми
/// полями: `content`, `finishReason`, `usage`, `refusal`, `rawError`. Адаптеры
/// при этом не переписываются: нормализация — надстройка.
library;

import 'package:cardflow/api/providers/generation_provider_adapter.dart';
import 'package:cardflow/domain/generation/generation_error.dart';
import 'package:cardflow/domain/generation/generation_result.dart';

/// Причина остановки ответа модели в едином словаре адаптеров.
enum ProviderFinishReason {
  /// Модель закончила ответ сама (`stop`/`end_turn`).
  stop('stop'),

  /// Ответ оборван лимитом вывода (`finish_reason: length`, `MAX_TOKENS`).
  length('length'),

  /// Отказ модели или safety-фильтр (`refusal`).
  refusal('refusal'),

  /// Провайдер вернул пустой контент без отказа.
  empty('empty'),

  /// Сбой протокола/транспорта: подробности — в [ProviderResult.rawError].
  error('error');

  const ProviderFinishReason(this.wireName);

  /// Значение для журнала запуска и диагностики.
  final String wireName;
}

/// Нормализованный ответ модели: контент и причина остановки в одном словаре.
class ProviderResult {
  /// Создаёт результат.
  const ProviderResult({
    this.content = '',
    required this.finishReason,
    this.usage = const TokenUsage(),
    this.refusal = false,
    this.rawError,
    this.detail,
  });

  /// Контент ответа (JSON-строка по схеме карточек); пуст при ошибке/отказе.
  final String content;

  /// Причина остановки в едином словаре.
  final ProviderFinishReason finishReason;

  /// Фактический расход токенов (если провайдер сообщил).
  final TokenUsage usage;

  /// Модель отказалась отвечать (safety/refusal).
  final bool refusal;

  /// Машинный код ошибки провайдера/транспорта; `null` — ошибки нет.
  final GenerationErrorCode? rawError;

  /// Диагностическая причина (без ключей и материалов).
  final String? detail;

  /// Есть ли контент для разбора.
  bool get hasContent => content.trim().isNotEmpty;

  /// Ответ оборван по лимиту вывода.
  bool get isTruncated => finishReason == ProviderFinishReason.length;

  /// Исход — ошибка: контента для разбора нет.
  ///
  /// Обрезанный ответ **с** контентом ошибкой не является (полные карточки
  /// спасаются и разбираются); обрезанный без контента — является.
  bool get isError => rawError != null && !hasContent;

  @override
  String toString() =>
      'ProviderResult(${finishReason.wireName}'
      '${rawError == null ? '' : ', ${rawError!.name}'}, '
      '${content.length} симв.)';
}

/// Нормализация ответов существующих адаптеров в [ProviderResult].
class ProviderResponseNormalizer {
  /// Создаёт нормализатор.
  const ProviderResponseNormalizer();

  /// Разбирает JSON-ответ [json] адаптером [adapter] в единый результат.
  ///
  /// Исключение адаптера не пробрасывается, а становится результатом с
  /// [ProviderResult.rawError]: этап решает, повторять запрос или нет.
  /// Отмена — единственное исключение, которое пропускается наверх: прогон
  /// должен остановиться, а не «получить ошибку батча».
  ProviderResult normalize(
    GenerationProviderAdapter adapter,
    Map<String, Object?> json,
  ) {
    final ProviderRawResponse raw;
    try {
      raw = adapter.parseResponse(json);
    } on GenerationException catch (error) {
      if (error.code == GenerationErrorCode.cancelled) rethrow;
      return fromFailure(error);
    }
    return ProviderResult(
      content: raw.cardsJson,
      finishReason: raw.truncated
          ? ProviderFinishReason.length
          : ProviderFinishReason.stop,
      usage: raw.usage,
    );
  }

  /// Нормализует сбой адаптера/транспорта.
  ProviderResult fromFailure(GenerationException error) {
    final GenerationErrorCode code = error.code;
    final bool refusal = code == GenerationErrorCode.refused;
    final ProviderFinishReason finishReason = switch (code) {
      GenerationErrorCode.refused => ProviderFinishReason.refusal,
      GenerationErrorCode.emptyResponse => ProviderFinishReason.empty,
      GenerationErrorCode.truncated => ProviderFinishReason.length,
      _ => ProviderFinishReason.error,
    };
    return ProviderResult(
      finishReason: finishReason,
      refusal: refusal,
      rawError: code,
      detail: error.details,
    );
  }
}
