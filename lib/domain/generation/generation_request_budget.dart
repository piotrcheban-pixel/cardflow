/// Бюджет одного запроса генерации по формулам ADR-040 §3.
///
/// `inputTokens = ceil((P + D) × (1 + m))`, где `P` — служебная часть
/// (промпт, схема, обёртка, `<wishes>`, `<outline>`, хвост `<task>`), `D` —
/// материалы части, `m` — запас точности. Ограничения проверяются раздельно:
/// суммарное окно, отдельный лимит входа, лимит вывода и байты тела.
/// Домен не зависит от Flutter.
library;

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
  factory RequestBudget.compute({
    required ModelLimits limits,
    required int fixedTokens,
    required int materialTokens,
    required int desiredOutputTokens,
    InputAccuracy accuracy = InputAccuracy.estimated,
    GenerationPlanningConfig config = const GenerationPlanningConfig(),
    int requestBytes = 0,
  }) {
    // RED-фаза итерации 7.18: контракт зафиксирован, формулы — следующий шаг.
    return const RequestBudget(
      fixedTokens: 0,
      materialTokens: 0,
      inputTokens: 0,
      maxTokens: 0,
      outputCapTokens: 0,
      marginTokens: 0,
      accuracy: InputAccuracy.estimated,
      contextExceeded: false,
      payloadExceeded: false,
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
      'semantics: ${contextExceeded ? 'overflow' : 'ok'})';
}
