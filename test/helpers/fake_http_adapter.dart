import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:dio/dio.dart';

/// Подменный транспорт Dio для тестов HTTP-слоя (спайк S3, итерация 3b).
///
/// Dio сам применяет `validateStatus` и бросает `DioException` для не-2xx,
/// поэтому fake-адаптер позволяет проверять ретраи/429/5xx/401/отмену без сети.
class FakeHttpAdapter implements HttpClientAdapter {
  /// Создаёт адаптер с обработчиком [handler].
  FakeHttpAdapter(this.handler);

  /// Что вернуть/бросить на очередной запрос.
  final FutureOr<ResponseBody> Function(RequestOptions options) handler;

  /// Все запросы в порядке отправки (заголовки, тело, метод).
  final List<RequestOptions> requests = <RequestOptions>[];

  /// Был ли адаптер закрыт.
  bool closed = false;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    requests.add(options);
    return handler(options);
  }

  @override
  void close({bool force = false}) {
    closed = true;
  }
}

/// JSON-ответ провайдера.
ResponseBody jsonResponse(
  Object? json, {
  int statusCode = 200,
  Map<String, List<String>>? headers,
}) {
  return ResponseBody.fromString(
    jsonEncode(json),
    statusCode,
    headers:
        headers ??
        <String, List<String>>{
          Headers.contentTypeHeader: <String>[Headers.jsonContentType],
        },
  );
}

/// Текстовый ответ (например, HTML страницы ошибки).
ResponseBody textResponse(String text, {int statusCode = 200}) {
  return ResponseBody.fromString(
    text,
    statusCode,
    headers: <String, List<String>>{
      Headers.contentTypeHeader: <String>['text/plain'],
    },
  );
}

/// Dio с подменным транспортом для тестов.
Dio dioWithAdapter(HttpClientAdapter adapter) {
  final dio = Dio();
  dio.httpClientAdapter = adapter;
  return dio;
}

/// Строит `DioException` указанного типа без сети.
DioException dioException(
  RequestOptions options,
  DioExceptionType type, {
  Response<dynamic>? response,
}) {
  return DioException(
    requestOptions: options,
    type: type,
    response: response,
    error: 'fake transport error',
  );
}
