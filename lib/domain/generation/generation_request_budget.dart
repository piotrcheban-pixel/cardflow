/// Бюджет одного запроса генерации по формулам ADR-040 §3.
///
/// `inputTokens = ceil((P + D) × (1 + m))`, где `P` — служебная часть
/// (промпт, схема, обёртка, `<wishes>`, `<outline>`, хвост `<task>`), `D` —
/// материалы части, `m` — запас точности. Ограничения проверяются раздельно:
/// суммарное окно, отдельный лимит входа, лимит вывода и байты тела.
/// Домен не зависит от Flutter.
library;

import 'dart:math' as math;

import 'package:cardflow/domain/generation/generation_planning_config.dart';
import 'package:cardflow/domain/generation/model_limits.dart';

/// Точность подсчёта входа.
enum InputAccuracy {
  /// Нативный подсчёт провайдера (`count_tokens`).
  exact,

  /// Консервативная оценка приложения.
  estimated,
}

/// Бюджет одного запроса: числа и сработавшие ограничения.
final class RequestBudget {
  /// Создаёт бюджет с готовыми числами.
  const RequestBudget({
    required this.fixedTokens,
    required this.materialTokens,
    required this.inputTokens,
    required this.maxTokens,
    required this.outputCapTokens,
    required this.marginTokens,
    required this.accuracy,
    required this.contextExceeded,
    required this.payloadExceeded,
    this.contextTokens,
    this.roomTokens,
    this.maxInputTokensLimit,
    this.maxRequestBytesLimit,
  });

  /// Считает бюджет запроса.
  ///
  /// [requestBytes] — оценка тела (текст + base64 вложений + запас JSON); если
  /// задан и превышает лимит модели, поднимается [payloadExceeded].
  factory RequestBudget.compute({
    required ModelLimits limits,
    required int fixedTokens,
    required int materialTokens,
    required int desiredOutputTokens,
    InputAccuracy accuracy = InputAccuracy.estimated,
    GenerationPlanningConfig config = const GenerationPlanningConfig(),
    int requestBytes = 0,
    int? countedInputTokens,
  }) {
    final int fixed = math.max(0, fixedTokens);
    final int material = math.max(0, materialTokens);
    final bool exactCount = countedInputTokens != null;
    final double marginRate = config.margin(
      exact: accuracy == InputAccuracy.exact || exactCount,
    );
    final int counted = countedInputTokens ?? (fixed + material);
    final int marginTokens = (counted * marginRate).ceil();
    final int inputTokens = counted + marginTokens;

    final int? contextTokens = limits.contextTokens.value;
    final int? maxInputTokens = limits.maxInputTokens.value;
    final int? maxRequestBytes = limits.maxRequestBytes.value;
    final int? maxOutputTokens = limits.maxOutputTokens.value;
    final bool inputOnly =
        limits.contextSemantics == ContextSemantics.inputOnly;

    final int outputCapTokens;
    if (maxOutputTokens != null) {
      outputCapTokens = maxOutputTokens;
    } else if (contextTokens != null) {
      outputCapTokens = math.min(
        config.defaultOutputTokens,
        math.max(1, contextTokens ~/ 2),
      );
    } else {
      outputCapTokens = config.unknownContextOutputTokens;
    }

    int maxTokens = math.min(desiredOutputTokens, outputCapTokens);
    int? roomTokens;
    var contextExceeded = false;

    if (contextTokens != null) {
      if (inputOnly) {
        // Окно — только вход: выход не вычитается повторно.
        if (inputTokens > contextTokens) contextExceeded = true;
      } else {
        roomTokens = contextTokens - inputTokens;
        if (roomTokens < 0) contextExceeded = true;
        maxTokens = math.min(maxTokens, math.max(0, roomTokens));
      }
    } else if (!inputOnly) {
      // Окно неизвестно: план ограничивается допущением (его применяет
      // InputPlanner), а ответ — консервативным лимитом.
      maxTokens = math.min(maxTokens, config.unknownContextOutputTokens);
    }
    if (maxInputTokens != null && inputTokens > maxInputTokens) {
      contextExceeded = true;
    }
    if (maxTokens < 0) maxTokens = 0;

    final bool payloadExceeded =
        maxRequestBytes != null && requestBytes > maxRequestBytes;

    return RequestBudget(
      fixedTokens: fixed,
      materialTokens: material,
      inputTokens: inputTokens,
      maxTokens: maxTokens,
      outputCapTokens: outputCapTokens,
      marginTokens: marginTokens,
      accuracy: accuracy,
      contextExceeded: contextExceeded,
      payloadExceeded: payloadExceeded,
      contextTokens: contextTokens,
      roomTokens: roomTokens,
      maxInputTokensLimit: maxInputTokens,
      maxRequestBytesLimit: maxRequestBytes,
    );
  }

  /// Служебная часть запроса (`P`), токенов.
  final int fixedTokens;

  /// Материалы части (`D`), токенов.
  final int materialTokens;

  /// Вход с запасом (`ceil((P + D) × (1 + m))`).
  final int inputTokens;

  /// Сколько токенов разрешено на ответ в этом запросе.
  final int maxTokens;

  /// Потолок вывода модели (известный лимит или допущение).
  final int outputCapTokens;

  /// Применённый запас точности, токенов.
  final int marginTokens;

  /// Вид точности входа.
  final InputAccuracy accuracy;

  /// Окно контекста модели (`null` — неизвестно).
  final int? contextTokens;

  /// Место под ответ после входа (только для total-семантики).
  final int? roomTokens;

  /// Отдельный лимит входа модели (`null` — не задан).
  final int? maxInputTokensLimit;

  /// Лимит тела запроса (`null` — не задан).
  final int? maxRequestBytesLimit;

  /// Вход превышает окно/отдельный лимит входа.
  final bool contextExceeded;

  /// Тело запроса превышает лимит байтов.
  final bool payloadExceeded;

  /// true, если вход посчитан нативно.
  bool get isExact => accuracy == InputAccuracy.exact;

  @override
  String toString() =>
      'RequestBudget(input: $inputTokens, max: $maxTokens, '
      'context: ${contextTokens ?? 'unknown'}, '
      'exceeded: $contextExceeded)';
}
