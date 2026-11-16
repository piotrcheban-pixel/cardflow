/// Pexels: кандидаты только при заданном API-ключе (итерация 7.14).
///
/// Ключ уходит в заголовке `Authorization` (не в query), поэтому не попадает
/// даже в URL. Без ключа провайдера нет в цепочке.
library;

import 'package:dio/dio.dart';

import 'package:cardflow/api/images/image_json.dart';
import 'package:cardflow/api/images/image_provider.dart';

/// Провайдер Pexels.
class PexelsImageProvider implements ImageProvider {
  /// Создаёт провайдер с ключом.
  PexelsImageProvider({
    required this.dio,
    required String apiKey,
    Uri? endpoint,
    this.maxResults = 5,
    this.timeout = const Duration(seconds: 6),
  }) : apiKey = apiKey.trim(),
       endpoint = endpoint ?? Uri.parse('https://api.pexels.com/v1/search');

  /// HTTP-клиент.
  final Dio dio;

  /// API-ключ (только заголовок, значение не логируется).
  final String apiKey;

  /// Базовый адрес API.
  final Uri endpoint;

  /// Сколько результатов просматривать.
  final int maxResults;

  /// Таймаут запроса поиска.
  final Duration timeout;

  @override
  String get name => 'pexels';

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
              'Authorization': apiKey,
              'Accept': 'application/json',
            },
          ),
        );
    final Object? photos = response.data?['photos'];
    if (photos is! List) return const <ImageCandidate>[];
    final List<ImageCandidate> candidates = <ImageCandidate>[];
    for (final Object? raw in photos.take(maxResults)) {
      if (raw is! Map) continue;
      final Object? src = raw['src'];
      final String? url = src is Map
          ? asString(src['large']) ?? asString(src['medium'])
          : null;
      if (url == null) continue;
      final String? author = asString(raw['photographer']);
      candidates.add(
        ImageCandidate(
          provider: name,
          url: url,
          width: asPositiveInt(raw['width']),
          height: asPositiveInt(raw['height']),
          author: author,
          license: 'Pexels License',
          attribution: joinAttribution(<String?>[author, 'Pexels License']),
        ),
      );
    }
    return candidates;
  }

  /// URI поиска Pexels.
  Uri _searchUri(String query) {
    return endpoint.replace(
      queryParameters: <String, String>{
        ...endpoint.queryParameters,
        'query': query,
        'per_page': '$maxResults',
        'orientation': 'landscape',
      },
    );
  }
}
