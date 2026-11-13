import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/api/http/generation_http_client.dart';
import 'package:cardflow/api/http/retry_policy.dart';
import 'package:cardflow/api/providers/generation_provider_adapter.dart';
import 'package:cardflow/domain/generation/generation_error.dart';

import '../../../helpers/fake_http_adapter.dart';

/// Красная фаза итерации 3b: HTTP-цикл генерации и классификация ошибок
/// (SPEC A8.6, ADR-012 §1–2).
void main() {
  final request = ProviderRequest(
    uri: Uri.parse('https://provider.test/v1/generate'),
    headers: <String, String>{
      'Content-Type': 'application/json',
      'Authorization': 'Bearer test-key',
    },
    body: <String, Object?>{'model': 'test-model'},
  );

  Matcher throwsGeneration(GenerationErrorCode code) => throwsA(
    isA<GenerationException>().having(
      (exception) => exception.code,
      'code',
      code,
    ),
  );

  GenerationHttpClient clientWith(
    Dio dio, {
    List<Duration>? delays,
    RetryPolicy? policy,
  }) {
    return GenerationHttpClient(
      dio: dio,
      retryPolicy: policy ?? RetryPolicy(jitter: () => 1.0),
      delay: (Duration duration) async {
        delays?.add(duration);
      },
    );
  }

  test(
    'успешный ответ: один POST, JSON-объект, тело/заголовки на месте',
    () async {
      final adapter = FakeHttpAdapter(
        (options) => jsonResponse(<String, Object?>{'cards': <Object?>[]}),
      );
      final dio = dioWithAdapter(adapter);
      final delays = <Duration>[];
      final client = clientWith(dio, delays: delays);

      final result = await client.postJson(request);

      expect(result, <String, Object?>{'cards': <Object?>[]});
      expect(adapter.requests, hasLength(1));
      expect(delays, isEmpty);
      final sent = adapter.requests.single;
      expect(sent.method, 'POST');
      expect(sent.uri.toString(), request.uri.toString());
      expect(sent.headers['Authorization'], 'Bearer test-key');
      expect(sent.data, jsonEncode(request.body));
    },
  );

  test(
    '429 с Retry-After: повтор после указанной паузы, затем успех',
    () async {
      var call = 0;
      final adapter = FakeHttpAdapter((options) {
        call++;
        if (call == 1) {
          return jsonResponse(
            <String, Object?>{'error': 'rate limit'},
            statusCode: 429,
            headers: <String, List<String>>{
              Headers.contentTypeHeader: <String>[Headers.jsonContentType],
              'retry-after': <String>['2'],
            },
          );
        }
        return jsonResponse(<String, Object?>{'cards': <Object?>[]});
      });
      final delays = <Duration>[];
      final client = clientWith(dioWithAdapter(adapter), delays: delays);

      final result = await client.postJson(request);

      expect(result, <String, Object?>{'cards': <Object?>[]});
      expect(adapter.requests, hasLength(2));
      expect(delays, <Duration>[const Duration(seconds: 2)]);
    },
  );

  test('5xx: 4 попытки, backoff 1s/2s/4s, затем serverUnavailable', () async {
    final adapter = FakeHttpAdapter(
      (options) => jsonResponse(<String, Object?>{'e': 1}, statusCode: 500),
    );
    final delays = <Duration>[];
    final client = clientWith(dioWithAdapter(adapter), delays: delays);

    await expectLater(
      client.postJson(request),
      throwsGeneration(GenerationErrorCode.serverUnavailable),
    );
    expect(adapter.requests, hasLength(4));
    expect(delays, <Duration>[
      const Duration(seconds: 1),
      const Duration(seconds: 2),
      const Duration(seconds: 4),
    ]);
  });

  test('401 не повторяется и даёт invalidApiKey', () async {
    final adapter = FakeHttpAdapter(
      (options) => jsonResponse(<String, Object?>{'e': 1}, statusCode: 401),
    );
    final delays = <Duration>[];
    final client = clientWith(dioWithAdapter(adapter), delays: delays);

    await expectLater(
      client.postJson(request),
      throwsGeneration(GenerationErrorCode.invalidApiKey),
    );
    expect(adapter.requests, hasLength(1));
    expect(delays, isEmpty);
  });

  test('403 не повторяется; 400 — badRequest без повторов', () async {
    for (final status in <int>[403, 400]) {
      final adapter = FakeHttpAdapter(
        (options) =>
            jsonResponse(<String, Object?>{'e': 1}, statusCode: status),
      );
      final delays = <Duration>[];
      final client = clientWith(dioWithAdapter(adapter), delays: delays);
      await expectLater(
        client.postJson(request),
        throwsGeneration(
          status == 403
              ? GenerationErrorCode.invalidApiKey
              : GenerationErrorCode.badRequest,
        ),
      );
      expect(adapter.requests, hasLength(1), reason: 'status=$status');
      expect(delays, isEmpty, reason: 'status=$status');
    }
  });

  test('таймаут: ретраи и итоговый код timeout', () async {
    final adapter = FakeHttpAdapter(
      (options) => throw DioException(
        requestOptions: options,
        type: DioExceptionType.receiveTimeout,
      ),
    );
    final delays = <Duration>[];
    final client = clientWith(dioWithAdapter(adapter), delays: delays);

    await expectLater(
      client.postJson(request),
      throwsGeneration(GenerationErrorCode.timeout),
    );
    expect(adapter.requests, hasLength(4));
    expect(delays, hasLength(3));
  });

  test('таймаут, затем успех: второй попытки достаточно', () async {
    var call = 0;
    final adapter = FakeHttpAdapter((options) {
      call++;
      if (call == 1) {
        throw DioException(
          requestOptions: options,
          type: DioExceptionType.connectionTimeout,
        );
      }
      return jsonResponse(<String, Object?>{'cards': <Object?>[]});
    });
    final delays = <Duration>[];
    final client = clientWith(dioWithAdapter(adapter), delays: delays);

    final result = await client.postJson(request);
    expect(result, containsPair('cards', isA<List<Object?>>()));
    expect(adapter.requests, hasLength(2));
    expect(delays, hasLength(1));
  });

  test('сетевая ошибка соединения → network после попыток', () async {
    final adapter = FakeHttpAdapter(
      (options) => throw DioException(
        requestOptions: options,
        type: DioExceptionType.connectionError,
      ),
    );
    final client = clientWith(dioWithAdapter(adapter));
    await expectLater(
      client.postJson(request),
      throwsGeneration(GenerationErrorCode.network),
    );
    expect(adapter.requests, hasLength(4));
  });

  test('отмена не повторяется и даёт cancelled', () async {
    final adapter = FakeHttpAdapter(
      (options) => throw DioException(
        requestOptions: options,
        type: DioExceptionType.cancel,
      ),
    );
    final delays = <Duration>[];
    final client = clientWith(dioWithAdapter(adapter), delays: delays);

    await expectLater(
      client.postJson(request),
      throwsGeneration(GenerationErrorCode.cancelled),
    );
    expect(adapter.requests, hasLength(1));
    expect(delays, isEmpty);
  });

  test('не-JSON и JSON-не-объект → invalidResponse без повторов', () async {
    for (final body in <Object>['<html>ошибка</html>', '[1, 2, 3]']) {
      final adapter = FakeHttpAdapter(
        (options) => body is String && body.startsWith('<')
            ? textResponse(body)
            : jsonResponse(<Object?>[1, 2, 3]),
      );
      final delays = <Duration>[];
      final client = clientWith(dioWithAdapter(adapter), delays: delays);
      await expectLater(
        client.postJson(request),
        throwsGeneration(GenerationErrorCode.invalidResponse),
      );
      expect(adapter.requests, hasLength(1), reason: 'body=$body');
      expect(delays, isEmpty, reason: 'body=$body');
    }
  });

  test(
    '429 с большим Retry-After: одна попытка и rateLimited с паузой',
    () async {
      final adapter = FakeHttpAdapter(
        (options) => jsonResponse(
          <String, Object?>{'e': 1},
          statusCode: 429,
          headers: <String, List<String>>{
            Headers.contentTypeHeader: <String>[Headers.jsonContentType],
            'retry-after': <String>['120'],
          },
        ),
      );
      final delays = <Duration>[];
      final client = clientWith(dioWithAdapter(adapter), delays: delays);

      await expectLater(
        client.postJson(request),
        throwsA(
          isA<GenerationException>()
              .having(
                (exception) => exception.code,
                'code',
                GenerationErrorCode.rateLimited,
              )
              .having(
                (exception) => exception.retryAfter,
                'retryAfter',
                const Duration(seconds: 120),
              ),
        ),
      );
      expect(adapter.requests, hasLength(1));
      expect(delays, isEmpty);
    },
  );

  test('ключ не попадает в details исключения', () async {
    final adapter = FakeHttpAdapter(
      (options) => jsonResponse(<String, Object?>{'e': 1}, statusCode: 401),
    );
    final client = clientWith(dioWithAdapter(adapter));
    try {
      await client.postJson(request);
      fail('Ожидалась GenerationException');
    } on GenerationException catch (exception) {
      expect(exception.toString(), isNot(contains('test-key')));
      expect(exception.details ?? '', isNot(contains('test-key')));
    }
  });
}
