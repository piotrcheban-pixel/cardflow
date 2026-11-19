/// Debug-диагностика ответов провайдеров генерации (ADR-024, итерация 7.10).
///
/// Тела запросов не логируются никогда; тело **ответа** пишется только в
/// debug/профиле, только по запросу диагностики (ошибка провайдера или разбор
/// ответа модели) и только через sink. В release-сборке методы — no-op.
/// Значения ключей и секретоподобные фрагменты редактируются, длина ограничена.
library;

import 'dart:convert';
import 'dart:developer' as developer;

import 'package:cardflow/api/http/log_redaction.dart';
import 'package:cardflow/domain/generation/token_accounting.dart';

/// Включена ли диагностика по умолчанию (выключена в release).
const bool kGenerationDiagnosticsEnabled = !bool.fromEnvironment(
  'dart.vm.product',
);

/// Максимальная длина диагностического сообщения.
const int kGenerationDiagnosticsMaxLength = 2000;

/// Редактирует и обрезает диагностический текст.
///
/// Управляющие символы схлопываются в пробелы, секретоподобные значения
/// редактируются единым санитайзером `redactSecretsInText` (заголовки
/// `Authorization`/`x-api-key`, `Bearer`-значения, токены известных форматов,
/// секретные query-параметры `?key=`), длина ограничивается. Тело запроса
/// здесь оказаться не должно: оно не логируется вообще.
String redactedDiagnosticText(
  String text, {
  int maxLength = kGenerationDiagnosticsMaxLength,
}) {
  var value = text
      .replaceAll(RegExp(r'[\u0000-\u001F\u007F]+'), ' ')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
  value = redactSecretsInText(value);
  if (value.length <= maxLength) return value;
  return '${value.substring(0, maxLength)}…';
}

/// Приёмник диагностических строк.
typedef GenerationDiagnosticsSink = void Function(String message);

/// Диагностика ответов провайдеров (debug-only, ADR-024).
class GenerationDiagnostics {
  /// Создаёт диагностику.
  const GenerationDiagnostics({
    this.enabled = kGenerationDiagnosticsEnabled,
    this.sink,
  });

  /// Включена ли запись (в release всегда `false`).
  final bool enabled;

  /// Приёмник сообщений; `null` — `dart:developer.log`.
  final GenerationDiagnosticsSink? sink;

  /// Тело ошибки провайдера (статус + редактированный фрагмент ответа).
  void apiError({int? statusCode, Object? body}) {
    if (!enabled) return;
    final String status = statusCode == null
        ? 'HTTP без статуса'
        : 'HTTP $statusCode';
    final String? text = _bodyText(body);
    _write(
      text == null
          ? 'Генерация: ошибка провайдера ($status)'
          : 'Генерация: ошибка провайдера ($status), ответ: $text',
    );
  }

  /// Сырой ответ модели (JSON карточек) — для проверки полей вроде `image_query`.
  void modelResponse(String rawJson) {
    if (!enabled) return;
    final String trimmed = rawJson.trim();
    if (trimmed.isEmpty) return;
    _write('Генерация: ответ модели: ${redactedDiagnosticText(trimmed)}');
  }

  /// Итог поиска иллюстрации по `image_query` (итерация 7.10).
  void imageSearch({required String query, required String outcome}) {
    if (!enabled) return;
    final String safeQuery = redactedDiagnosticText(query, maxLength: 120);
    _write(
      'Генерация: картинка по запросу "$safeQuery": '
      '${redactedDiagnosticText(outcome, maxLength: 300)}',
    );
  }

  /// Сводка калибровки токенов (TASK 03): оценка vs фактический `usage`.
  ///
  /// Пишутся только числа/отношения и версия оценщика; тексты материалов и
  /// ключи сюда не попадают. `usage` одного запроса не экстраполируется.
  void tokenCalibration(TokenCalibrationReport report) {
    if (!enabled) return;
    final StringBuffer buffer = StringBuffer(
      'Генерация: калибровка токенов: $report',
    );
    for (final TokenCalibrationSample sample in report.samples) {
      final double? ratio = sample.inputRatio;
      if (ratio == null) continue;
      // Подробности только при заметном расхождении: не засорять консоль.
      if (ratio >= 0.8 && ratio <= 1.2) continue;
      buffer.write(
        '\n  фрагмент ${sample.chunkIndex}, попытка ${sample.attempt}: '
        'план ${sample.plannedInput.tokens ?? '?'}, '
        'запрос ${sample.requestInput.tokens ?? '?'}, '
        'факт ${sample.actualInput.tokens ?? '?'} '
        '(x${ratio.toStringAsFixed(2)})',
      );
    }
    _write(buffer.toString());
  }

  /// Участие изображения в запросе (TASK 03, раздел 6): передано/только каталог.
  void imageParticipation({required String outcome}) {
    if (!enabled) return;
    _write(
      'Генерация: изображения: '
      '${redactedDiagnosticText(outcome, maxLength: 400)}',
    );
  }

  /// Причина падения фрагмента (fix-gen, Д6): только машинные коды, без
  /// текста материалов, без ключей.
  void fragmentFailure({
    required int chunkIndex,
    required int chunkCount,
    required String errorCode,
    required String reason,
    bool retryable = true,
  }) {
    if (!enabled) return;
    _write(
      'Генерация: фрагмент $chunkIndex из $chunkCount упал: '
      'code=$errorCode, reason=$reason, retryable=$retryable',
    );
  }

  /// Записывает сообщение в приёмник (лейзи-`dart:developer.log`).
  void _write(String message) {
    final GenerationDiagnosticsSink? target = sink;
    if (target != null) {
      target(message);
      return;
    }
    developer.log(message, name: 'cardflow.generation');
  }

  /// Текст тела ответа: строка как есть, объект — JSON; `null` — пусто.
  static String? _bodyText(Object? body) {
    if (body == null) return null;
    String text;
    if (body is String) {
      text = body;
    } else {
      try {
        text = jsonEncode(body);
      } on Object {
        text = body.toString();
      }
    }
    final String redacted = redactedDiagnosticText(text);
    return redacted.isEmpty ? null : redacted;
  }
}
