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
  return <String, String>{
    for (final entry in headers.entries)
      entry.key: sensitiveHeaderNames.contains(entry.key.trim().toLowerCase())
          ? redactedValue
          : entry.value,
  };
}

/// Возвращает URI для лога: секретные query-значения и userinfo заменены.
String redactUriForLog(Uri uri) {
  final text = uri.toString();
  return _redactQuery(_redactUserInfo(text));
}

/// Заменяет userinfo (`user:password@`) в authority на [redactedValue].
String _redactUserInfo(String text) {
  final schemeIndex = text.indexOf('://');
  if (schemeIndex < 0) return text;

  final authorityStart = schemeIndex + 3;
  var authorityEnd = text.length;
  for (final delimiter in const <String>['/', '?', '#']) {
    final index = text.indexOf(delimiter, authorityStart);
    if (index >= 0 && index < authorityEnd) authorityEnd = index;
  }

  final authority = text.substring(authorityStart, authorityEnd);
  final atIndex = authority.lastIndexOf('@');
  if (atIndex < 0) return text;

  return '${text.substring(0, authorityStart)}$redactedValue@'
      '${text.substring(authorityStart + atIndex + 1)}';
}

/// Заменяет значения секретных query-параметров, сохраняя остальную query.
String _redactQuery(String text) {
  final fragmentIndex = text.indexOf('#');
  final queryIndex = text.indexOf('?');
  if (queryIndex < 0 || (fragmentIndex >= 0 && fragmentIndex < queryIndex)) {
    return text;
  }

  final queryEnd = fragmentIndex >= 0 ? fragmentIndex : text.length;
  final query = text.substring(queryIndex + 1, queryEnd);
  final redactedQuery = query.split('&').map(_redactQueryPart).join('&');
  return '${text.substring(0, queryIndex + 1)}$redactedQuery'
      '${text.substring(queryEnd)}';
}

/// Заменяет значение одного параметра query, если его имя секретное.
String _redactQueryPart(String part) {
  final separator = part.indexOf('=');
  if (separator < 0) return part;

  final rawName = part.substring(0, separator);
  if (!sensitiveQueryParameterNames.contains(_decodedName(rawName))) {
    return part;
  }
  return '$rawName=$redactedValue';
}

/// Декодирует имя параметра для сравнения без учёта регистра.
String _decodedName(String rawName) {
  try {
    return Uri.decodeQueryComponent(rawName).toLowerCase();
  } on FormatException {
    return rawName.toLowerCase();
  }
}

/// Секретоподобные префиксы ключей известных провайдеров.
///
/// OpenAI/DeepSeek/Moonshot/Anthropic/OpenRouter — `sk-…`; Google — `AIza…`;
/// Groq — `gsk_…`; xAI — `xai-…`; NVIDIA — `nvapi-…`. Список расширяется
/// только под подтверждённый формат: маскировать «любую длинную строку»
/// нельзя — это испортит диагностические тексты без пользы для безопасности.
final RegExp _secretTokenPattern = RegExp(
  r'sk-[A-Za-z0-9_\-]{8,}'
  r'|AIza[0-9A-Za-z_\-]{8,}'
  r'|gsk_[A-Za-z0-9_\-]{8,}'
  r'|xai-[A-Za-z0-9_\-]{8,}'
  r'|nvapi-[A-Za-z0-9_\-]{8,}',
);

/// Заголовок вида `Authorization: …`/`x-api-key=…` в свободном тексте.
///
/// Значение забирается до конца строки/списка заголовков: в нём может быть
/// `Bearer <ключ>` (пробел внутри значения), а частично отредактированный
/// заголовок оставил бы ключ в тексте.
final RegExp _secretHeaderPattern = RegExp(
  r'''(x-api-key|x-goog-api-key|authorization|proxy-authorization)'''
  r'''\s*[:=]\s*[^\n,;"']+''',
  caseSensitive: false,
);

/// `Bearer <значение>` в свободном тексте.
final RegExp _bearerPattern = RegExp(
  r'Bearer\s+[A-Za-z0-9._\-]+',
  caseSensitive: false,
);

/// Секретные query-параметры в свободном тексте (`?key=…`, `&api_key=…`).
final RegExp _secretQueryPattern = RegExp(
  r'''([?&;])(key|api_key|apikey|access_token|token)=[^&;\s"'`]+''',
  caseSensitive: false,
);

/// Редактирует секретоподобные значения в **свободном тексте**.
///
/// Используется диагностикой и причинами ошибок провайдера: текст приходит от
/// третьей стороны (тело ответа, сообщение исключения) и может содержать
/// ключ — в заголовке, в `Bearer`-значении, в URL с `?key=` или отдельным
/// токеном известного формата. Тела запросов генерации сюда не попадают.
///
/// Это последний рубеж, а не разрешение логировать секреты: тело запроса не
/// должно логироваться вообще.
String redactSecretsInText(String text) {
  if (text.isEmpty) return text;
  var value = text.replaceAllMapped(_secretHeaderPattern, (Match match) {
    final String name = match.group(1)!;
    return '$name: $redactedValue';
  });
  value = value.replaceAll(_bearerPattern, 'Bearer $redactedValue');
  value = value.replaceAll(_secretTokenPattern, redactedValue);
  value = value.replaceAllMapped(_secretQueryPattern, (Match match) {
    return '${match.group(1)}${match.group(2)}=$redactedValue';
  });
  return value;
}
