/// Санитайзеры логов API-слоя (SPEC 3.4, A8.6; ADR-012 §3).
///
/// Правило: значения ключей не попадают в логи ни в заголовках, ни в query.
/// Тела запросов/ответов не логируются вовсе — в них материалы пользователя
/// и ответ модели.
library;

/// Замена секретного значения в логах.
const String redactedValue = '***';

/// Заголовки, значение которых в логах заменяется (регистр не важен).
const Set<String> sensitiveHeaderNames = <String>{
  'authorization',
  'x-api-key',
  'x-goog-api-key',
  'proxy-authorization',
};

/// Query-параметры, значение которых в логах заменяется (регистр не важен).
const Set<String> sensitiveQueryParameterNames = <String>{
  'key',
  'api_key',
  'apikey',
};

/// Заменяет значения секретных заголовков на [redactedValue].
Map<String, String> redactHeadersForLog(Map<String, String> headers) {
  throw UnimplementedError('redactHeadersForLog');
}

/// Возвращает URI для лога: секретные query-значения и userinfo заменены.
String redactUriForLog(Uri uri) {
  throw UnimplementedError('redactUriForLog');
}
