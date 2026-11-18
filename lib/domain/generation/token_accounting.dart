/// Учёт и калибровка токенов генерации (раздел G аудита TASK 01, TASK 03).
///
/// Главное правило: **оценка не выдаётся за точное значение**. У каждой
/// величины есть вид:
/// - [TokenValueKind.exact] — провайдер сообщил факт (`usage`) или это
///   структурное число (например, `limit` карточек), а не токены;
/// - [TokenValueKind.estimate] — консервативная эвристика приложения;
/// - [TokenValueKind.reserve] — бюджетный резерв (сколько разрешено, а не
///   сколько будет потрачено);
/// - [TokenValueKind.unknown] — данных нет; `tokens == null`, не 0.
///
/// Фактический `usage` одного запроса **не** является гарантией для другого:
/// калибровка только собирает отношения «оценка/факт» и показывает разброс.
/// Домен не зависит от Flutter.
library;

/// Вид значения токенов.
enum TokenValueKind {
  /// Точное значение (структурное число или `usage` провайдера).
  exact,

  /// Оценка эвристикой приложения (консервативная сверху).
  estimate,

  /// Бюджетный резерв: верхняя граница, а не ожидаемый расход.
  reserve,

  /// Значение неизвестно; `tokens == null`.
  unknown,
}

/// Значение токенов с видом и источником.
class TokenValue {
  /// Точное/оценочное/резервное значение.
  const TokenValue({
    required int tokens,
    required this.kind,
    required this.source,
  }) : tokens = tokens,
       assert(tokens >= 0, 'Токены не могут быть отрицательными'),
       assert(
         kind != TokenValueKind.unknown,
         'Неизвестное значение — TokenValue.unknown',
       ),
       assert(source != '', 'У значения обязан быть источник');

  /// Значение неизвестно (не 0).
  const TokenValue.unknown({required this.source})
    : tokens = null,
      kind = TokenValueKind.unknown,
      assert(source != '');

  /// Оценка эвристикой.
  const TokenValue.estimate(int tokens, {required this.source})
    : tokens = tokens,
      kind = TokenValueKind.estimate,
      assert(tokens >= 0),
      assert(source != '');

  /// Бюджетный резерв.
  const TokenValue.reserve(int tokens, {required this.source})
    : tokens = tokens,
      kind = TokenValueKind.reserve,
      assert(tokens >= 0),
      assert(source != '');

  /// Точное значение (например, `usage.prompt_tokens`).
  const TokenValue.exact(int tokens, {required this.source})
    : tokens = tokens,
      kind = TokenValueKind.exact,
      assert(tokens >= 0),
      assert(source != '');

  /// Количество токенов; `null` — неизвестно.
  final int? tokens;

  /// Вид значения.
  final TokenValueKind kind;

  /// Источник (`provider_usage`, `heuristic/1`, `plan.maxOutputTokens`, …).
  final String source;

  /// true, если значение известно (в том числе 0).
  bool get isKnown => tokens != null;

  /// true, если это оценка (не факт).
  bool get isEstimate => kind == TokenValueKind.estimate;

  /// Значение или 0 (только для сумм; не заменяет «неизвестно»).
  int get valueOrZero => tokens ?? 0;

  /// Сумма значений: неизвестное слагаемое делает сумму неизвестной.
  static TokenValue sum(Iterable<TokenValue> values, {required String source}) {
    var total = 0;
    var unknown = false;
    var hasReserve = false;
    for (final TokenValue value in values) {
      if (!value.isKnown) {
        unknown = true;
        continue;
      }
      total += value.tokens!;
      hasReserve = hasReserve || value.kind == TokenValueKind.reserve;
    }
    if (unknown) return TokenValue.unknown(source: source);
    return TokenValue(
      tokens: total,
      kind: hasReserve ? TokenValueKind.reserve : TokenValueKind.estimate,
      source: source,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is TokenValue &&
          other.tokens == tokens &&
          other.kind == kind &&
          other.source == source;

  @override
  int get hashCode => Object.hash(tokens, kind, source);

  @override
  String toString() =>
      'TokenValue(${tokens ?? 'unknown'}, ${kind.name}, $source)';
}

/// Один запрос для калибровки: оценка плана, оценка собранного запроса и факт.
///
/// `plannedInput` — что заложил план в бюджет фрагмента (оценка),
/// `requestInput` — что посчитал исполнитель по фактически собранному
/// `userContent` (та же эвристика), `actualInput`/`actualOutput` — `usage`
/// провайдера (точное значение) или [TokenValueKind.unknown].
class TokenCalibrationSample {
  /// Создаёт сэмпл калибровки.
  const TokenCalibrationSample({
    required this.chunkIndex,
    required this.attempt,
    required this.recovered,
    required this.plannedInput,
    required this.requestInput,
    required this.actualInput,
    required this.actualOutput,
    required this.reservedOutput,
    required this.estimatorVersion,
  }) : assert(chunkIndex >= 1),
       assert(attempt >= 1),
       assert(estimatorVersion != '');

  /// Номер фрагмента (с 1).
  final int chunkIndex;

  /// Попытка фрагмента (1 — первичный запрос, > 1 — восстановление/повтор).
  final int attempt;

  /// true, если запрос отправлен в рамках восстановления.
  final bool recovered;

  /// Оценка входа по плану.
  final TokenValue plannedInput;

  /// Оценка входа по собранному запросу (тем же оценщиком).
  final TokenValue requestInput;

  /// Фактический вход из `usage`; `unknown` — провайдер не сообщил.
  final TokenValue actualInput;

  /// Фактический выход из `usage`; `unknown` — провайдер не сообщил.
  final TokenValue actualOutput;

  /// Резерв вывода (сколько разрешено).
  final TokenValue reservedOutput;

  /// Версия оценщика (для калибровки коэффициентов).
  final String estimatorVersion;

  /// true, если провайдер вернул и вход, и выход.
  bool get hasCompleteUsage => actualInput.isKnown && actualOutput.isKnown;

  /// true, если провайдер не вернул ни одного значения.
  bool get usageAbsent => !actualInput.isKnown && !actualOutput.isKnown;

  /// Отношение «факт/оценка запроса» по входу; `null` — нельзя посчитать.
  double? get inputRatio => _ratio(actualInput, requestInput);

  /// Отношение «факт/резерв» по выходу; `null` — нельзя посчитать.
  double? get outputRatio => _ratio(actualOutput, reservedOutput);

  static double? _ratio(TokenValue actual, TokenValue estimate) {
    final int? fact = actual.tokens;
    final int? estimateValue = estimate.tokens;
    if (fact == null || estimateValue == null || estimateValue <= 0) {
      return null;
    }
    return fact / estimateValue;
  }

  @override
  String toString() =>
      'TokenCalibrationSample(#$chunkIndex/$attempt, '
      'planned: ${plannedInput.valueOrZero}, '
      'request: ${requestInput.valueOrZero}, '
      'actual: ${actualInput.tokens ?? 'unknown'}/'
      '${actualOutput.tokens ?? 'unknown'})';
}

/// Сводка калибровки за запуск (или серию запусков).
///
/// Не делает выводов о «точности модели»: показывает выборку, отношения и
/// количество запросов без `usage`, которые калибровать нельзя.
class TokenCalibrationReport {
  /// Создаёт отчёт.
  const TokenCalibrationReport({
    required this.samples,
    required this.failedRequests,
  });

  /// Пустой отчёт (нет запросов).
  const TokenCalibrationReport.empty()
    : samples = const <TokenCalibrationSample>[],
      failedRequests = 0;

  /// Сэмплы успешно разобранных ответов (с `usage` или без).
  final List<TokenCalibrationSample> samples;

  /// Запросы, завершившиеся ошибкой (ответа/`usage` нет) — калибровать нельзя.
  final int failedRequests;

  /// Число запросов, для которых есть факт входа.
  int get inputSamples => samples.where((s) => s.actualInput.isKnown).length;

  /// Число запросов, для которых есть факт выхода.
  int get outputSamples => samples.where((s) => s.actualOutput.isKnown).length;

  /// Число ответов без `usage` (провайдер не сообщает расход).
  int get samplesWithoutUsage => samples
      .where((TokenCalibrationSample sample) => sample.usageAbsent)
      .length;

  /// Среднее отношение «факт/оценка запроса» по входу; `null` — нет данных.
  double? get meanInputRatio =>
      _mean(samples.map((TokenCalibrationSample sample) => sample.inputRatio));

  /// Среднее отношение «факт/резерв» по выходу; `null` — нет данных.
  double? get meanOutputRatio =>
      _mean(samples.map((TokenCalibrationSample sample) => sample.outputRatio));

  /// Минимальное/максимальное отношение входа (для разброса).
  double? get minInputRatio => _extreme(
    samples.map((TokenCalibrationSample sample) => sample.inputRatio),
    min: true,
  );

  /// Максимальное отношение входа.
  double? get maxInputRatio => _extreme(
    samples.map((TokenCalibrationSample sample) => sample.inputRatio),
    min: false,
  );

  /// true, если есть что калибровать (хотя бы один факт).
  bool get hasFacts => inputSamples > 0 || outputSamples > 0;

  /// Короткая строка для debug-диагностики.
  @override
  String toString() =>
      'TokenCalibrationReport(samples: ${samples.length}, '
      'facts: $inputSamples/$outputSamples, '
      'withoutUsage: $samplesWithoutUsage, failed: $failedRequests, '
      'inputRatio: ${meanInputRatio?.toStringAsFixed(2) ?? 'n/a'})';

  static double? _mean(Iterable<double?> values) {
    var total = 0.0;
    var count = 0;
    for (final double? value in values) {
      if (value == null) continue;
      total += value;
      count++;
    }
    return count == 0 ? null : total / count;
  }

  static double? _extreme(Iterable<double?> values, {required bool min}) {
    double? result;
    for (final double? value in values) {
      if (value == null) continue;
      if (result == null || (min ? value < result : value > result)) {
        result = value;
      }
    }
    return result;
  }
}
