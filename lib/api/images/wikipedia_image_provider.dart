/// Wikipedia (ru → en): кандидат-превью статьи (итерация 7.14).
///
/// Commons ищет по именам файлов, поэтому русские словоформы («спайность
/// минерала») часто дают 0 результатов. Wikipedia ищет статью по запросу и
/// отдаёт её превью (`prop=pageimages`) — для предметных запросов это надёжнее.
/// API не требует ключа; провайдер только ищет, скачивание — в цепочке.
library;

import 'package:dio/dio.dart';

import 'package:cardflow/api/images/image_json.dart';
import 'package:cardflow/api/images/image_provider.dart';

/// Провайдер превью статей Wikipedia.
class WikipediaImageProvider implements ImageProvider {
  /// Создаёт провайдер.
  WikipediaImageProvider({
    required this.dio,
    this.languages = const <String>['ru', 'en'],
    this.maxResults = 3,
    this.thumbWidth = 800,
    this.userAgent =
        'CardFlow/1.0 (https://github.com/piotrcheban-pixel/cardflow)',
    this.timeout = const Duration(seconds: 6),
  });

  /// HTTP-клиент.
  final Dio dio;

  /// Языки Wikipedia в порядке приоритета.
  final List<String> languages;

  /// Сколько статей просматривать на одном языке.
  final int maxResults;

  /// Ширина превью, которое просим у Wikipedia.
  final int thumbWidth;

  /// User-Agent для Wikimedia API.
  final String userAgent;

  /// Таймаут одного запроса поиска.
  final Duration timeout;

  @override
  String get name => 'wikipedia';

  @override
  Future<List<ImageCandidate>> search(ImageProviderQuery query) async {
    final String text = query.query.trim();
    if (text.isEmpty) return const <ImageCandidate>[];
    for (final String language in languages) {
      final String lang = language.trim().toLowerCase();
      if (lang.isEmpty) continue;
      final Response<Map<String, Object?>> response = await dio
          .getUri<Map<String, Object?>>(
            _searchUri(lang, text),
            options: Options(
              responseType: ResponseType.json,
              receiveTimeout: timeout,
              headers: <String, String>{
                'User-Agent': userAgent,
                'Accept': 'application/json',
              },
            ),
          );
      final List<ImageCandidate> candidates = _candidatesOf(response.data);
      if (candidates.isNotEmpty) return candidates;
    }
    return const <ImageCandidate>[];
  }

  /// URI поиска статей с превью.
  Uri _searchUri(String language, String query) {
    return Uri.https('$language.wikipedia.org', '/w/api.php', <String, String>{
      'action': 'query',
      'format': 'json',
      'formatversion': '2',
      'generator': 'search',
      'gsrsearch': query,
      'gsrnamespace': '0',
      'gsrlimit': '$maxResults',
      'prop': 'pageimages',
      'piprop': 'thumbnail',
      'pithumbsize': '$thumbWidth',
    });
  }

  /// Разбирает `query.pages` (formatversion=2 — список, v1 — карта).
  List<ImageCandidate> _candidatesOf(Map<String, Object?>? data) {
    final Object? query = data?['query'];
    if (query is! Map) return const <ImageCandidate>[];
    final Object? pages = query['pages'];
    final Iterable<Object?> entries;
    if (pages is List) {
      entries = pages;
    } else if (pages is Map) {
      entries = pages.values;
    } else {
      return const <ImageCandidate>[];
    }
    final List<ImageCandidate> result = <ImageCandidate>[];
    for (final Object? raw in entries) {
      if (raw is! Map) continue;
      final String? title = asString(raw['title']);
      final Object? thumbnail = raw['thumbnail'];
      if (thumbnail is! Map) continue;
      final String? url = asString(thumbnail['source']);
      if (url == null) continue;
      result.add(
        ImageCandidate(
          provider: name,
          url: url,
          width: asPositiveInt(thumbnail['width']),
          height: asPositiveInt(thumbnail['height']),
          author: title,
          title: title,
          description: asString(raw['description']),
          attribution: title == null ? null : '$title · Wikipedia',
        ),
      );
    }
    return result;
  }
}
