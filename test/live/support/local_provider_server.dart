/// Локальный тестовый HTTP-endpoint провайдера (TASK 04, раздел 7-F).
///
/// Нужен, чтобы проверить **реальные** HTTP-контракты (413/429/`Retry-After`/
/// таймаут/переполнение контекста/битый JSON/обрезанный ответ) через сокет,
/// не обращаясь ни к одному платному API: сервер слушает `127.0.0.1`,
/// ответы задаются очередью. Тело запроса читается и сохраняется только для
/// проверок размера; ключи в ответы не попадают.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

/// Сценарий ответа локального сервера.
class LocalProviderResponse {
  /// Создаёт ответ.
  const LocalProviderResponse({
    required this.statusCode,
    this.body = '',
    this.headers = const <String, String>{},
    this.delay = Duration.zero,
    this.closeWithoutReply = false,
  });

  /// HTTP-статус.
  final int statusCode;

  /// Тело ответа (JSON-строка или мусор).
  final String body;

  /// Дополнительные заголовки (например, `retry-after`).
  final Map<String, String> headers;

  /// Задержка перед отправкой (для проверки таймаутов).
  final Duration delay;

  /// Закрыть соединение без ответа (обрыв сети).
  final bool closeWithoutReply;
}

/// Локальный сервер-заглушка провайдера.
class LocalProviderServer {
  LocalProviderServer._(this._server) {
    _server.listen(_handle);
  }

  final HttpServer _server;
  final List<LocalProviderResponse> _responses = <LocalProviderResponse>[];

  /// Тела полученных запросов (для проверки размера/полей; без ключей).
  final List<String> requestBodies = <String>[];

  /// Сколько запросов получено.
  int get requestCount => requestBodies.length;

  /// Порт сервера.
  int get port => _server.port;

  /// Базовый адрес OpenAI-совместимого сервера (`…/v1`).
  Uri get baseUrl => Uri.parse('http://127.0.0.1:$port/v1');

  /// Поднимает сервер на свободном порту loopback.
  static Future<LocalProviderServer> start() async {
    final HttpServer server = await HttpServer.bind(
      InternetAddress.loopbackIPv4,
      0,
    );
    return LocalProviderServer._(server);
  }

  /// Добавляет ответ в очередь.
  void enqueue(LocalProviderResponse response) => _responses.add(response);

  /// Добавляет JSON-ответ.
  void enqueueJson({
    required int statusCode,
    required Map<String, Object?> body,
    Map<String, String> headers = const <String, String>{},
    Duration delay = Duration.zero,
  }) {
    enqueue(
      LocalProviderResponse(
        statusCode: statusCode,
        body: jsonEncode(body),
        headers: headers,
        delay: delay,
      ),
    );
  }

  /// Останавливает сервер.
  Future<void> close() => _server.close(force: true);

  Future<void> _handle(HttpRequest request) async {
    String body = '';
    try {
      body = await utf8.decoder.bind(request).join();
    } on Object {
      body = '';
    }
    requestBodies.add(body);
    final LocalProviderResponse response = _responses.isEmpty
        ? const LocalProviderResponse(
            statusCode: 500,
            body: '{"error":"no scripted response"}',
          )
        : _responses.removeAt(0);
    if (response.delay > Duration.zero) {
      await Future<void>.delayed(response.delay);
    }
    if (response.closeWithoutReply) {
      try {
        await request.response.close();
      } on Object {
        // Обрыв соединения — ожидаемое поведение для теста.
      }
      return;
    }
    try {
      request.response.statusCode = response.statusCode;
      for (final MapEntry<String, String> header in response.headers.entries) {
        request.response.headers.set(header.key, header.value);
      }
      request.response.headers.contentType = ContentType.json;
      request.response.write(response.body);
      await request.response.close();
    } on Object {
      // Клиент уже закрыл соединение (таймаут) — это тоже ожидаемый сценарий.
    }
  }
}
