/// Openverse: кандидаты с CC-лицензиями (итерация 7.14).
///
/// Openverse API не требует ключа, отдаёт только CC-лицензии и хорош для схем
/// и иллюстраций. Анонимный лимит ~1 запрос/с; провайдер только ищет, поэтому
/// троттлинг делает цепочка (последовательные запросы карточек).
library;

import 'package:dio/dio.dart';

import 'package:cardflow/api/images/image_json.dart';
import 'package:cardflow/api/images/image_provider.dart';

/// Провайдер Openverse.
class OpenverseImageProvider implements ImageProvider {
  /// Создаёт провайдер.
  OpenverseImageProvider({
    required this.dio,
    Uri? endpoint,
    this.maxResults = 5,
    this.userAgent = 'CardFlow/1.0',
    this.timeout = const Duration(seconds: 6),
  }) : endpoint = endpoint ?? Uri.parse('https://api.openverse.org/v1/images/');

  /// HTTP-клиент.
  final Dio dio;

  /// Базовый адрес поиска.
  final Uri endpoint;

  /// Сколько результатов просматривать.
  final int maxResults;

  /// User-Agent для Openverse (анонимный доступ).
  final String userAgent;

  /// Таймаут запроса поиска.
  final Duration timeout;

  /// Лицензии, которые разрешены к скачиванию (атрибуция — в источнике).
  static const String _licenses = 'cc0,pdm,by,by-sa';

  @override
  String get name => 'openverse';

  @override
  Future<List<ImageCandidate>> search(ImageProviderQuery query) async {
    final String text = query.query.trim();
    if (text.isEmpty) return const <ImageCandidate>[];
    final Response<Map<String, Object?>> response = await dio
        .getUri<Map<String, Object?>>(
          _searchUri(text),
          options: Options(
            responseType: ResponseType.json,
            receiveTimeout: timeout,
            headers: <String, String>{
              'User-Agent': userAgent,
              'Accept': 'application/json',
            },
          ),
        );
    final Object? results = response.data?['results'];
    if (results is! List) return const <ImageCandidate>[];
    final List<ImageCandidate> candidates = <ImageCandidate>[];
    for (final Object? raw in results.take(maxResults)) {
      if (raw is! Map) continue;
      final String? url = asString(raw['thumbnail']) ?? asString(raw['url']);
      if (url == null) continue;
      final String? creator = asString(raw['creator']);
      // Аудит 2.0 (P1-04): заголовок и теги — сигналы релевантности.
      final String? title = asString(raw['title']);
      final Object? tags = raw['tags'];
      final String? description = tags is List
          ? tags
                .map((Object? tag) => tag is Map ? asString(tag['name']) : null)
                .whereType<String>()
                .join(' ')
          : null;
      final String? license = asString(raw['license']);
      final String? licenseVersion = asString(raw['license_version']);
      final String? licenseName = _licenseName(license, licenseVersion);
      candidates.add(
        ImageCandidate(
          provider: name,
          url: url,
          width: asPositiveInt(raw['width']),
          height: asPositiveInt(raw['height']),
          author: creator,
          license: licenseName,
          title: title,
          description: description,
          attribution:
              asString(raw['attribution']) ??
              joinAttribution(<String?>[creator, licenseName]),
        ),
      );
    }
    return candidates;
  }

  /// Читаемое имя лицензии: `by-sa` + 2.0 → `CC BY-SA 2.0`.
  static String? _licenseName(String? license, String? version) {
    if (license == null) return null;
    final String upper = license.toUpperCase();
    final String name = switch (upper) {
      'CC0' => 'CC0',
      'PDM' => 'Public Domain Mark',
      _ => 'CC $upper',
    };
    return version == null ? name : '$name $version';
  }

  /// URI поиска Openverse с фильтрами лицензий и размером страницы.
  Uri _searchUri(String query) {
    return endpoint.replace(
      queryParameters: <String, String>{
        ...endpoint.queryParameters,
        'q': query,
        'page_size': '$maxResults',
        'license': _licenses,
        'mature': 'false',
      },
    );
  }
}
