/// Pixabay: кандидаты только при заданном API-ключе (итерация 7.14).
///
/// Провайдер включается, если ключ передан в конструктор (production-проводка
/// берёт его из `--dart-define`/окружения). Без ключа его просто нет в цепочке
/// — это проверяется тестом.
library;

import 'package:dio/dio.dart';

import 'package:cardflow/api/images/image_json.dart';
import 'package:cardflow/api/images/image_provider.dart';

/// Провайдер Pixabay.
class PixabayImageProvider implements ImageProvider {
  /// Создаёт провайдер с ключом.
  PixabayImageProvider({
    required this.dio,
    required String apiKey,
    Uri? endpoint,
    this.maxResults = 5,
    this.timeout = const Duration(seconds: 6),
  }) : apiKey = apiKey.trim(),
       endpoint = endpoint ?? Uri.parse('https://pixabay.com/api/');

  /// HTTP-клиент.
  final Dio dio;

  /// API-ключ (в логах редактируется `key`).
  final String apiKey;

  /// Базовый адрес API.
  final Uri endpoint;

  /// Сколько результатов просматривать.
  final int maxResults;

  /// Таймаут запроса поиска.
  final Duration timeout;

  @override
  String get name => 'pixabay';

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
            headers: const <String, String>{'Accept': 'application/json'},
          ),
        );
    final Object? hits = response.data?['hits'];
    if (hits is! List) return const <ImageCandidate>[];
    final List<ImageCandidate> candidates = <ImageCandidate>[];
    for (final Object? raw in hits.take(maxResults)) {
      if (raw is! Map) continue;
      final String? url =
          asString(raw['largeImageURL']) ?? asString(raw['webformatURL']);
      if (url == null) continue;
      final String? author = asString(raw['user']);
      candidates.add(
        ImageCandidate(
          provider: name,
          url: url,
          width: asPositiveInt(raw['imageWidth']),
          height: asPositiveInt(raw['imageHeight']),
          author: author,
          license: 'Pixabay License',
          attribution: joinAttribution(<String?>[author, 'Pixabay License']),
        ),
      );
    }
    return candidates;
  }

  /// URI поиска: английский интерфейс, фото, safe search.
  Uri _searchUri(String query) {
    return endpoint.replace(
      queryParameters: <String, String>{
        ...endpoint.queryParameters,
        'key': apiKey,
        'q': query,
        'lang': 'en',
        'image_type': 'photo',
        'safesearch': 'true',
        'per_page': '$maxResults',
      },
    );
  }
}
