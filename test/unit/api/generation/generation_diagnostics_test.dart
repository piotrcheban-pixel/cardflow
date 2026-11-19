import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/api/generation/generation_diagnostics.dart';
import 'package:cardflow/api/http/log_redaction.dart';
import 'package:cardflow/domain/generation/token_accounting.dart';

/// TASK 04: диагностика ответов провайдера не выносит секреты и материалы.
///
/// Проверяется единый санитайзер (`redactSecretsInText`): префиксы ключей,
/// `Bearer`, заголовки, секретные query-параметры. Тело **запроса** сюда не
/// попадает никогда — это не тестируется «удачей», а гарантируется вызовом
/// диагностики только для ответов.
void main() {
  group('redactedDiagnosticText', () {
    test('редактирует ключ в теле ответа провайдера', () {
      final text =
          'HTTP 400, ответ: {"error":"bad key '
          'sk-${'A' * 32}"}';
      final redacted = redactedDiagnosticText(text);
      expect(redacted, isNot(contains('sk-${'A' * 32}')));
      expect(redacted, contains('bad key'));
      expect(redacted, contains(redactedValue));
    });

    test('редактирует Pixabay-подобный ключ в query и заголовок', () {
      final redacted = redactedDiagnosticText(
        'GET https://pixabay.com/api/?key=SECRET-PIX&q=cat '
        'headers: {Authorization: SECRET-PEXELS}',
      );
      expect(redacted, isNot(contains('SECRET-PIX')));
      expect(redacted, isNot(contains('SECRET-PEXELS')));
      expect(redacted, contains('q=cat'));
    });

    test('схлопывает управляющие символы и ограничивает длину', () {
      final redacted = redactedDiagnosticText('a\u0000b\u0007c', maxLength: 4);
      expect(redacted, 'a b …');
    });

    test('без секретов текст сохраняется', () {
      expect(
        redactedDiagnosticText('ответ модели: {"cards": []}'),
        'ответ модели: {"cards": []}',
      );
    });
  });

  group('GenerationDiagnostics', () {
    test('выключенная диагностика — no-op для всех методов', () {
      final messages = <String>[];
      final diagnostics = GenerationDiagnostics(
        enabled: false,
        sink: messages.add,
      );

      diagnostics.apiError(statusCode: 500, body: 'SECRET-ANSWER');
      diagnostics.modelResponse('{"cards":[]}');
      diagnostics.imageSearch(query: 'кот', outcome: 'найдено');
      diagnostics.tokenCalibration(const TokenCalibrationReport.empty());
      diagnostics.imageParticipation(outcome: 'передано');
      diagnostics.fragmentFailure(
        chunkIndex: 1,
        chunkCount: 2,
        errorCode: 'invalidResponse',
        reason: 'json_parse',
      );

      expect(messages, isEmpty);
    });

    test('включённая диагностика пишет тело ошибки без ключа', () {
      final messages = <String>[];
      final diagnostics = GenerationDiagnostics(
        enabled: true,
        sink: messages.add,
      );

      diagnostics.apiError(
        statusCode: 401,
        body: '{"error":"invalid key sk-${'D' * 24}"}',
      );

      expect(messages, hasLength(1));
      expect(messages.single, contains('HTTP 401'));
      expect(messages.single, contains('invalid key'));
      expect(messages.single, isNot(contains('sk-${'D' * 24}')));
    });

    test('сводка калибровки содержит только числа и версию оценщика', () {
      final messages = <String>[];
      final diagnostics = GenerationDiagnostics(
        enabled: true,
        sink: messages.add,
      );

      diagnostics.tokenCalibration(
        const TokenCalibrationReport(
          samples: <TokenCalibrationSample>[
            TokenCalibrationSample(
              chunkIndex: 1,
              attempt: 1,
              recovered: false,
              plannedInput: TokenValue.estimate(100, source: 'plan'),
              requestInput: TokenValue.estimate(120, source: 'request'),
              actualInput: TokenValue.exact(250, source: 'usage'),
              actualOutput: TokenValue.exact(40, source: 'usage'),
              reservedOutput: TokenValue.reserve(1000, source: 'request'),
              estimatorVersion: 'heuristic/1',
            ),
          ],
          failedRequests: 0,
        ),
      );

      expect(messages, hasLength(1));
      expect(messages.single, contains('калибровка токенов'));
      expect(messages.single, contains('фрагмент 1'));
      expect(messages.single, contains('факт 250'));
      expect(messages.single, isNot(contains('карточк')));
    });
  });
}
