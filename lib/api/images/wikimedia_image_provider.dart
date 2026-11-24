/// Wikimedia Commons: кандидаты картинок по запросу (итерация 7.14).
///
/// Commons не требует ключа и хорошо ищет по конкретным английским запросам
/// (`gen-ru-v6` пишет запросы на английском). Провайдер только ищет: отдаёт
/// URL превью/оригинала, MIME и атрибуцию из `extmetadata`; скачивание,
/// фильтры формата/размера и ретраи — в `ImageSearchService`.
library;

import 'package:dio/dio.dart';

import 'package:cardflow/api/images/image_json.dart';
import 'package:cardflow/api/images/image_provider.dart';

/// Провайдер Wikimedia Commons (namespace 6 — файлы).
class WikimediaImageProvider implements ImageProvider {
  /// Создаёт провайдер.
  WikimediaImageProvider({
    required this.dio,
    Uri? endpoint,
    this.maxResults = 5,
    this.thumbWidth = 800,
    this.userAgent =
        'CardFlow/1.0 (https://github.com/piotrcheban-pixel/cardflow)',
    this.timeout = const Duration(seconds: 6),
  }) : endpoint =
           endpoint ?? Uri.parse('https://commons.wikimedia.org/w/api.php');

  /// HTTP-клиент.
  final Dio dio;

  /// Базовый адрес API Commons.
  final Uri endpoint;

  /// Сколько результатов просматривать.
  final int maxResults;

  /// Ширина превью, которое просим у Commons.
  final int thumbWidth;

  /// User-Agent: Wikimedia просит осмысленный UA для анонимных запросов.
  final String userAgent;

  /// Таймаут запроса поиска.
  final Duration timeout;

  /// MIME-типы, которые принимаем (в Commons много PDF/DJVU/SVG).
  static const Set<String> _allowedMime = <String>{'image/jpeg', 'image/png'};

  @override
  String get name => 'wikimedia';

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
    return _candidatesOf(response.data);
  }

  /// URI поиска Commons с фильтром файлов пространства имён 6.
  Uri _searchUri(String query) {
    return endpoint.replace(
      queryParameters: <String, String>{
        ...endpoint.queryParameters,
        'action': 'query',
        'format': 'json',
        'generator': 'search',
        'gsrsearch': query,
        'gsrnamespace': '6',
        'gsrlimit': '$maxResults',
        'prop': 'imageinfo',
        'iiprop': 'url|mime|size|extmetadata',
        'iiurlwidth': '$thumbWidth',
      },
    );
  }

  /// Разбирает `query.pages` в порядке поисковой выдачи.
  ///
  /// API по умолчанию отдаёт `pages` объектом (`formatversion=1`), но
  /// `formatversion=2` и часть прокси — списком: поддерживаются обе формы.
  List<ImageCandidate> _candidatesOf(Map<String, Object?>? data) {
    final Object? query = data?['query'];
    if (query is! Map) return const <ImageCandidate>[];
    final Object? pages = query['pages'];
    final Iterable<Object?> entries;
    if (pages is Map) {
      entries = pages.values;
    } else if (pages is List) {
      entries = pages;
    } else {
      return const <ImageCandidate>[];
    }
    final List<({int index, ImageCandidate candidate})> found =
        <({int index, ImageCandidate candidate})>[];
    for (final Object? raw in entries) {
      if (raw is! Map) continue;
      final Object? info = raw['imageinfo'];
      if (info is! List || info.isEmpty) continue;
      final Object? first = info.first;
      if (first is! Map) continue;
      final String? mime = asString(first['mime']);
      if (mime == null || !_allowedMime.contains(mime.toLowerCase())) continue;
      final String? url = asString(first['thumburl']) ?? asString(first['url']);
      if (url == null) continue;
      final String? title = asString(raw['title']);
      final Object? metadata = first['extmetadata'];
      final String? artist = _metaValue(
        metadata is Map ? metadata['Artist'] : null,
      );
      final String? license = _metaValue(
        metadata is Map ? metadata['LicenseShortName'] : null,
      );
      // Аудит 2.0 (P1-04): заголовок и описание файла — сигналы релевантности
      // для отсева «фото здания по запросу о надёжности теста».
      final String? description = _metaValue(
        metadata is Map ? metadata['ImageDescription'] : null,
      );
      final Object? index = raw['index'];
      found.add((
        index: index is int ? index : found.length,
        candidate: ImageCandidate(
          provider: name,
          url: url,
          width: asPositiveInt(first['thumbwidth'] ?? first['width']),
          height: asPositiveInt(first['thumbheight'] ?? first['height']),
          author: artist,
          license: license,
          title: title,
          description: description,
          attribution: joinAttribution(<String?>[title, artist, license]),
        ),
      ));
    }
    found.sort(
      (
        ({int index, ImageCandidate candidate}) a,
        ({int index, ImageCandidate candidate}) b,
      ) => a.index.compareTo(b.index),
    );
    return <ImageCandidate>[
      for (final ({int index, ImageCandidate candidate}) entry in found)
        entry.candidate,
    ];
  }

  /// Значение `extmetadata`: объект с полем `value` (иногда строка).
  static String? _metaValue(Object? node) {
    if (node is Map) return asString(stripHtml(node['value']));
    return asString(stripHtml(node));
  }
}
