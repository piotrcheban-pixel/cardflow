/// Полный адрес запроса провайдера по протоколу и базовому адресу (ADR-020).
///
/// Один резолвер для всех протоколов: аккаунт хранит базовый адрес, а путь
/// (`/chat/completions`, `/v1/messages`, `/v1beta/models/{model}:generateContent`)
/// добавляет протокол. Пустой адрес заменяется адресом по умолчанию протокола
/// (у OpenAI-совместимого его нет — адрес обязателен). Схема только `http`/
/// `https`, userinfo/query/fragment запрещены: ключ передаётся только заголовком.
library;

import 'package:cardflow/api/providers/openai_compatible_endpoint.dart';
import 'package:cardflow/domain/generation/provider_protocol.dart';

/// Причина, по которой базовый адрес не принят.
enum ProviderEndpointError {
  /// Пустая строка и нет адреса по умолчанию.
  empty,

  /// URI некорректный, без хоста, с query/fragment/логином-паролем.
  invalid,
}

/// Результат: готовый URI запроса либо причина отказа.
class ProviderEndpoint {
  const ProviderEndpoint._({this.uri, this.error});

  /// Полный URI запроса, если разбор успешен.
  final Uri? uri;

  /// Причина отказа, если разбор неуспешен.
  final ProviderEndpointError? error;

  /// true, если [uri] задан.
  bool get isValid => uri != null;

  /// Путь Anthropic Messages.
  static const String anthropicMessagesPath = '/v1/messages';

  /// Путь OpenAI Chat Completions (для нативного протокола).
  static const String openAiChatCompletionsPath = '/chat/completions';

  /// Разбирает базовый адрес [baseUrl] и достраивает путь протокола.
  ///
  /// [model] нужен протоколу Gemini: модель входит в путь запроса.
  static ProviderEndpoint parse({
    required ProviderProtocol protocol,
    required String baseUrl,
    required String model,
  }) {
    var raw = baseUrl.trim();
    if (raw.isEmpty) raw = protocol.defaultBaseUrl;
    if (raw.isEmpty) {
      return const ProviderEndpoint._(error: ProviderEndpointError.empty);
    }

    if (protocol == ProviderProtocol.openaiCompletions) {
      final OpenAiCompatibleEndpoint endpoint = OpenAiCompatibleEndpoint.parse(
        raw,
      );
      if (endpoint.isValid) {
        return ProviderEndpoint._(uri: endpoint.uri);
      }
      return ProviderEndpoint._(
        error: endpoint.error == OpenAiCompatibleEndpointError.empty
            ? ProviderEndpointError.empty
            : ProviderEndpointError.invalid,
      );
    }

    final Uri? parsed = Uri.tryParse(raw);
    if (parsed == null) {
      return const ProviderEndpoint._(error: ProviderEndpointError.invalid);
    }
    final String scheme = parsed.scheme.toLowerCase();
    if (scheme != 'http' && scheme != 'https') {
      return const ProviderEndpoint._(error: ProviderEndpointError.invalid);
    }
    if (parsed.userInfo.isNotEmpty ||
        parsed.host.isEmpty ||
        parsed.hasQuery ||
        parsed.hasFragment) {
      return const ProviderEndpoint._(error: ProviderEndpointError.invalid);
    }

    var path = parsed.path;
    while (path.length > 1 && path.endsWith('/')) {
      path = path.substring(0, path.length - 1);
    }
    if (path == '/') path = '';

    final String suffix = switch (protocol) {
      ProviderProtocol.openai => openAiChatCompletionsPath,
      ProviderProtocol.anthropicMessages => anthropicMessagesPath,
      ProviderProtocol.geminiGenerateContent =>
        '/v1beta/models/${model.trim()}:generateContent',
      ProviderProtocol.openaiCompletions => openAiChatCompletionsPath,
    };
    final String fullPath = path.endsWith(suffix) ? path : '$path$suffix';

    return ProviderEndpoint._(
      uri: Uri(
        scheme: scheme,
        host: parsed.host,
        port: parsed.hasPort ? parsed.port : null,
        path: fullPath,
      ),
    );
  }
}
