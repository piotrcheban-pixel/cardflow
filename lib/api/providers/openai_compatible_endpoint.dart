/// Разбор и нормализация базового адреса OpenAI-совместимого сервера
/// (ADR-013): `<base_url>` → полный endpoint Chat Completions.
library;

/// Причина, по которой `base_url` не принят.
enum OpenAiCompatibleEndpointError {
  /// Пустая строка (сервер не настроен).
  empty,

  /// URI не абсолютный, без хоста, с query/fragment и т.п.
  invalid,

  /// Схема не `http`/`https`.
  unsupportedScheme,

  /// В URL переданы логин/пароль (`user:password@host`) — запрещено.
  credentials,
}

/// Результат разбора `base_url`: либо готовый endpoint, либо причина отказа.
class OpenAiCompatibleEndpoint {
  const OpenAiCompatibleEndpoint._({this.uri, this.error});

  /// Полный URI запроса `POST <base_url>/chat/completions`, если разбор успешен.
  final Uri? uri;

  /// Причина отказа, если разбор неуспешен.
  final OpenAiCompatibleEndpointError? error;

  /// true, если [uri] задан.
  bool get isValid => uri != null;

  /// Путь Chat Completions, который добавляется к базовому адресу.
  static const String chatCompletionsPath = '/chat/completions';

  /// Разбирает [input] как базовый адрес сервера.
  ///
  /// Правила (ADR-013):
  /// - пробелы по краям обрезаются;
  /// - схема только `http`/`https` (локальные серверы — по http);
  /// - userinfo, query и fragment запрещены (ключ — только заголовком);
  /// - завершающие слеши убираются, `/chat/completions` добавляется один раз;
  /// - `/v1` и другие префиксы пути сохраняются.
  static OpenAiCompatibleEndpoint parse(String input) {
    final String trimmed = input.trim();
    if (trimmed.isEmpty) {
      return const OpenAiCompatibleEndpoint._(
        error: OpenAiCompatibleEndpointError.empty,
      );
    }
    final Uri? parsed = Uri.tryParse(trimmed);
    if (parsed == null) {
      return const OpenAiCompatibleEndpoint._(
        error: OpenAiCompatibleEndpointError.invalid,
      );
    }
    final String scheme = parsed.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') {
      return const OpenAiCompatibleEndpoint._(
        error: OpenAiCompatibleEndpointError.unsupportedScheme,
      );
    }
    if (parsed.userInfo.isNotEmpty) {
      return const OpenAiCompatibleEndpoint._(
        error: OpenAiCompatibleEndpointError.credentials,
      );
    }
    if (parsed.host.isEmpty || parsed.hasQuery || parsed.hasFragment) {
      return const OpenAiCompatibleEndpoint._(
        error: OpenAiCompatibleEndpointError.invalid,
      );
    }

    var path = parsed.path;
    while (path.length > 1 && path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    final String fullPath = path.endsWith(chatCompletionsPath)
        ? path
        : '${path == '/' ? '' : path}$chatCompletionsPath';

    return OpenAiCompatibleEndpoint._(
      uri: Uri(
        scheme: scheme,
        host: parsed.host,
        port: parsed.hasPort ? parsed.port : null,
        path: fullPath,
      ),
    );
  }
}
