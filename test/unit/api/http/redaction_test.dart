import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/api/http/log_redaction.dart';
import 'package:cardflow/api/http/redacting_log_interceptor.dart';

import '../../../helpers/fake_http_adapter.dart';

/// Красная фаза итерации 3b: логи без ключей и материалов (SPEC 3.4, A8.6).
void main() {
  group('redactHeadersForLog', () {
    test('секретные заголовки заменяются, регистр не важен', () {
      final redacted = redactHeadersForLog(<String, String>{
        'Authorization': 'Bearer SECRET-VALUE',
        'x-api-key': 'SECRET-VALUE',
        'X-Goog-Api-Key': 'SECRET-VALUE',
        'Content-Type': 'application/json',
      });
      expect(redacted['Authorization'], redactedValue);
      expect(redacted['x-api-key'], redactedValue);
      expect(redacted['X-Goog-Api-Key'], redactedValue);
      expect(redacted['Content-Type'], 'application/json');
      expect(redacted.values.join(), isNot(contains('SECRET-VALUE')));
    });

    test('обычные заголовки не меняются', () {
      final redacted = redactHeadersForLog(<String, String>{
        'content-type': 'application/json',
        'anthropic-version': '2023-06-01',
      });
      expect(redacted, <String, String>{
        'content-type': 'application/json',
        'anthropic-version': '2023-06-01',
      });
    });
  });

  group('redactUriForLog', () {
    test(
      'query key/api_key/apikey заменяются, остальные параметры остаются',
      () {
        for (final parameter in <String>[
          'key',
          'api_key',
          'apikey',
          'API_KEY',
        ]) {
          final result = redactUriForLog(
            Uri.parse('https://api.test/v1?$parameter=SECRET-VALUE&model=test'),
          );
          expect(result, isNot(contains('SECRET-VALUE')), reason: parameter);
          expect(result, contains('model=test'), reason: parameter);
          expect(result, contains('***'), reason: parameter);
        }
      },
    );

    test('userinfo в URL редактируется', () {
      final result = redactUriForLog(
        Uri.parse('https://user:SECRET-VALUE@api.test/v1'),
      );
      expect(result, isNot(contains('SECRET-VALUE')));
    });

    test('обычный URI не меняется', () {
      expect(
        redactUriForLog(Uri.parse('https://api.test/v1/chat?model=test')),
        'https://api.test/v1/chat?model=test',
      );
    });
  });

  group('redactSecretsInText', () {
    test('редактирует токены известных форматов', () {
      final text =
          'key1=sk-${'A' * 24} key2=AIza${'B' * 30} '
          'key3=gsk_${'C' * 20} key4=xai-${'D' * 20} '
          'key5=nvapi-${'E' * 20}';
      final redacted = redactSecretsInText(text);
      for (final fragment in <String>[
        'sk-',
        'AIza',
        'gsk_',
        'xai-',
        'nvapi-',
      ]) {
        expect(redacted, isNot(contains(fragment)), reason: fragment);
      }
      expect(redacted, contains(redactedValue));
    });

    test('редактирует заголовки и Bearer-значения', () {
      final redacted = redactSecretsInText(
        'Authorization: Bearer SECRET-TOKEN-123, '
        'x-api-key: SECRET-HEADER, x-goog-api-key=SECRET-GOOG',
      );
      expect(redacted.toLowerCase(), contains('authorization'));
      expect(redacted.toLowerCase(), contains('x-api-key'));
      expect(redacted, isNot(contains('SECRET-TOKEN-123')));
      expect(redacted, isNot(contains('SECRET-HEADER')));
      expect(redacted, isNot(contains('SECRET-GOOG')));
      expect(redacted, isNot(contains('Bearer SECRET')));
    });

    test('редактирует секретные query-параметры, не трогая остальное', () {
      final redacted = redactSecretsInText(
        'GET https://pixabay.com/api/?key=SECRET-PIX&q=cat&api_key=SECRET2 '
        'и https://api.test/v1?model=test',
      );
      expect(redacted, isNot(contains('SECRET-PIX')));
      expect(redacted, isNot(contains('SECRET2')));
      expect(redacted, contains('?key=$redactedValue'));
      expect(redacted, contains('q=cat'));
      expect(redacted, contains('model=test'));
    });

    test('без секретов текст не меняется', () {
      const text = 'HTTP 429, повторите через 30 секунд; ответ модели пуст';
      expect(redactSecretsInText(text), text);
      expect(redactSecretsInText(''), '');
    });
  });

  group('RedactingLogInterceptor', () {
    test('логирует метод/URI/статус, но не ключи и не тела', () async {
      final logs = <String>[];
      final dio = dioWithAdapter(
        FakeHttpAdapter(
          (options) => jsonResponse(<String, Object?>{'cards': <Object?>[]}),
        ),
      );
      dio.interceptors.add(RedactingLogInterceptor(sink: logs.add));

      await dio.post<dynamic>(
        'https://api.openai.com/v1/chat/completions?key=SECRET-QUERY',
        data: <String, Object?>{'materials': 'СЕКРЕТНЫЙ-МАТЕРИАЛ'},
        options: Options(
          headers: <String, Object>{
            'Authorization': 'Bearer SECRET-HEADER',
            'x-api-key': 'SECRET-HEADER',
          },
        ),
      );

      final joined = logs.join('\n');
      expect(logs, isNotEmpty);
      expect(joined, contains('POST'));
      expect(joined, contains('api.openai.com'));
      expect(joined.toLowerCase(), contains('authorization'));
      expect(joined, contains(redactedValue));
      expect(joined, isNot(contains('SECRET-HEADER')));
      expect(joined, isNot(contains('SECRET-QUERY')));
      expect(joined, isNot(contains('СЕКРЕТНЫЙ-МАТЕРИАЛ')));
      expect(joined, isNot(contains('cards')));
    });

    test('ошибка HTTP логируется без тела ответа и секретов', () async {
      final logs = <String>[];
      final dio = dioWithAdapter(
        FakeHttpAdapter(
          (options) => jsonResponse(<String, Object?>{
            'error': 'СЕКРЕТНЫЙ-ОТВЕТ',
          }, statusCode: 500),
        ),
      );
      dio.interceptors.add(RedactingLogInterceptor(sink: logs.add));

      await expectLater(
        dio.post<dynamic>(
          'https://api.anthropic.com/v1/messages',
          data: <String, Object?>{'materials': 'СЕКРЕТНЫЙ-МАТЕРИАЛ'},
          options: Options(
            headers: <String, Object>{'x-api-key': 'SECRET-HEADER'},
          ),
        ),
        throwsA(isA<DioException>()),
      );

      final joined = logs.join('\n');
      expect(logs, isNotEmpty);
      expect(joined, contains('500'));
      expect(joined, isNot(contains('SECRET-HEADER')));
      expect(joined, isNot(contains('СЕКРЕТНЫЙ-МАТЕРИАЛ')));
      expect(joined, isNot(contains('СЕКРЕТНЫЙ-ОТВЕТ')));
    });

    test('перехватчик прозрачен: ответ доходит до вызывающего', () async {
      final logs = <String>[];
      final dio = dioWithAdapter(
        FakeHttpAdapter(
          (options) => jsonResponse(<String, Object?>{'ok': true}),
        ),
      );
      dio.interceptors.add(RedactingLogInterceptor(sink: logs.add));
      final response = await dio.get<dynamic>('https://api.test/v1');
      expect(response.statusCode, 200);
      expect(logs, hasLength(2));
    });
  });
}
