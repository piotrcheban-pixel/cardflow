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

/// Результат нативного подсчёта и добавка, которую он не видит.
///
/// [tokens] — ровно то число, что вернул провайдер (с мультимодальными
/// частями). [estimatedExtraTokens] — части запроса, которые провайдер в
/// подсчёт не включил (например, схема ответа Gemini, вхождение которой в
/// `totalTokens` не подтверждено документацией). Такая добавка — оценка, а
/// значит результат уже **не** полностью точный.
final class NativeInputCount {
  /// Создаёт результат подсчёта.
  const NativeInputCount({
    required this.tokens,
    this.estimatedExtraTokens = 0,
    this.estimatedComponents = const <String>[],
    required this.source,
  }) : assert(tokens >= 0, 'Токены не могут быть отрицательными'),
       assert(estimatedExtraTokens >= 0),
       assert(source != '', 'У подсчёта обязан быть источник');

  /// Число токенов, возвращённое провайдером.
  final int tokens;

  /// Ключ компонента: схема ответа (Gemini; вхождение в `totalTokens`
  /// документацией не подтверждено — оценивается отдельно).
  static const String schemaComponent = 'response_schema';

  /// Дополнительно оценённые токены (провайдер их не посчитал).
  final int estimatedExtraTokens;

  /// Какие компоненты оценены дополнительно (`images`, `response_schema`, …).
  final List<String> estimatedComponents;

  /// Источник (`count_tokens:anthropic-messages`, …).
  final String source;

  /// true, если все учитываемые компоненты посчитаны нативно.
  bool get isFullyNative =>
      estimatedExtraTokens == 0 && estimatedComponents.isEmpty;

  /// Точность по этому подсчёту.
  InputAccuracy get accuracy =>
      isFullyNative ? InputAccuracy.exact : InputAccuracy.estimated;

  @override
  String toString() =>
      'NativeInputCount($tokens, extra: $estimatedExtraTokens, '
      '${estimatedComponents.join(',')}, $source)';
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
    this.nativeInputTokens,
    this.estimatedExtraTokens = 0,
    this.estimatedComponents = const <String>[],
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
    NativeInputCount? nativeCount,
  }) {
    final int fixed = math.max(0, fixedTokens);
    final int material = math.max(0, materialTokens);
    // Три источника числа: результат провайдера (+ то, что он не посчитал),
    // прежний «готовый» подсчёт и оценка P+D. Точность определяется фактом:
    // mixed-результат (native + оценённая добавка) — не exact (§3).
    final InputAccuracy effectiveAccuracy;
    final int counted;
    final int estimatedExtra;
    if (nativeCount != null) {
      counted = math.max(0, nativeCount.tokens);
      estimatedExtra = math.max(0, nativeCount.estimatedExtraTokens);
      effectiveAccuracy = nativeCount.isFullyNative
          ? InputAccuracy.exact
          : InputAccuracy.estimated;
    } else {
      counted = countedInputTokens ?? (fixed + material);
      estimatedExtra = 0;
      effectiveAccuracy = accuracy;
    }
    final double marginRate = config.margin(
      exact: effectiveAccuracy == InputAccuracy.exact,
    );
    final int marginTokens = ((counted + estimatedExtra) * marginRate).ceil();
    final int inputTokens = counted + estimatedExtra + marginTokens;

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
      accuracy: effectiveAccuracy,
      contextExceeded: contextExceeded,
      payloadExceeded: payloadExceeded,
      contextTokens: contextTokens,
      roomTokens: roomTokens,
      maxInputTokensLimit: maxInputTokens,
      maxRequestBytesLimit: maxRequestBytes,
      nativeInputTokens: nativeCount != null ? counted : countedInputTokens,
      estimatedExtraTokens: estimatedExtra,
      estimatedComponents: nativeCount?.estimatedComponents ?? const <String>[],
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

  /// Фактическое число токенов, возвращённое `count_tokens` (`null` — не было).
  final int? nativeInputTokens;

  /// Дополнительно оценённые токены, которых нативный подсчёт не видел.
  final int estimatedExtraTokens;

  /// Компоненты, оценённые дополнительно (`response_schema`, …).
  final List<String> estimatedComponents;

  /// Плановый бюджет входа (`inputTokens`) — не число провайдера.
  int get effectiveBudgetTokens => inputTokens;

  /// true, если результат провайдера виден отдельно от бюджета.
  bool get hasNativeCount => nativeInputTokens != null;

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
