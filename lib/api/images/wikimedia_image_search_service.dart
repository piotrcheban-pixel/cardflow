/// Поиск иллюстраций в Wikimedia Commons для сгенерированных карточек
/// (ADR-026, итерация 7.11).
///
/// Commons API не требует ключа и хорошо ищет по русским запросам: `image_query`
/// модели часто сформулирован по-русски, а Openverse на такие запросы отвечает
/// заметно хуже и на практике таймаутил (L61). Сервис скачивает thumbnail,
/// проверяет MIME и сигнатуру JPEG/PNG и размер. Любая ошибка сети/API → `null`:
/// генерация карточек продолжается без иллюстрации.
library;

import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'package:cardflow/api/generation/generation_diagnostics.dart';
import 'package:cardflow/domain/generation/card_image_finder.dart';
import 'package:cardflow/domain/generation/generated_card_image.dart';
import 'package:cardflow/domain/generation/generation_attachment.dart';

/// Поиск картинок через открытый API Wikimedia Commons.
class WikimediaImageSearchService implements CardImageFinder {
  /// Создаёт сервис.
  WikimediaImageSearchService({
    required this.dio,
    Uri? endpoint,
    this.maxResults = 5,
    this.maxImageBytes = 5 * 1024 * 1024,
    this.thumbWidth = 800,
    this.userAgent =
        'CardFlow/1.0 (https://github.com/piotrcheban-pixel/cardflow)',
    GenerationDiagnostics? diagnostics,
  }) : endpoint =
           endpoint ?? Uri.parse('https://commons.wikimedia.org/w/api.php'),
       diagnostics = diagnostics ?? const GenerationDiagnostics();

  /// HTTP-клиент (Dio с таймаутами и redaction в production-проводке).
  final Dio dio;

  /// Debug-диагностика поиска картинок (ADR-024).
  final GenerationDiagnostics diagnostics;

  /// Базовый адрес API Commons.
  final Uri endpoint;

  /// Сколько результатов просматривать.
  final int maxResults;

  /// Максимальный размер скачанной картинки.
  final int maxImageBytes;

  /// Ширина thumbnail, которую просим у Commons.
  final int thumbWidth;

  /// User-Agent: Wikimedia просит осмысленный UA для анонимных запросов.
  final String userAgent;

  /// Таймаут одного запроса поиска/скачивания.
  static const Duration _timeout = Duration(seconds: 8);

  /// MIME-типы, которые принимаем (в Commons много PDF/DJVU/SVG).
  static const Set<String> _allowedMime = <String>{'image/jpeg', 'image/png'};

  @override
  Future<GeneratedCardImage?> findImage(String query) async {
    final String normalized = query.trim();
    if (normalized.isEmpty) return null;
    try {
      final Response<Map<String, Object?>> response = await dio
          .getUri<Map<String, Object?>>(
            _searchUri(normalized),
            options: Options(
              responseType: ResponseType.json,
              receiveTimeout: _timeout,
              headers: <String, String>{
                'User-Agent': userAgent,
                'Accept': 'application/json',
              },
            ),
          );
      final List<_CommonsImage> images = _imagesOf(response.data);
      for (final _CommonsImage image in images) {
        final String? url = image.thumbUrl ?? image.url;
        if (url == null) continue;
        final Uint8List? bytes = await _download(url);
        if (bytes == null) continue;
        final AttachmentMediaType? mediaType = _mediaTypeOf(bytes);
        if (mediaType == null) continue;
        diagnostics.imageSearch(
          query: normalized,
          outcome:
              'Wikimedia Commons: скачано ${bytes.length} Б, ${mediaType.name}',
        );
        return GeneratedCardImage(
          bytes: bytes,
          mediaType: mediaType,
          query: normalized,
          sourceUrl: url,
          attribution: image.attribution,
        );
      }
      diagnostics.imageSearch(
        query: normalized,
        outcome:
            'Wikimedia Commons: нет подходящей картинки среди '
            '${images.length} результатов',
      );
    } on Object catch (error) {
      // Сеть/API недоступны: генерация продолжится без иллюстрации.
      diagnostics.imageSearch(
        query: normalized,
        outcome: 'Wikimedia Commons: ошибка запроса: $error',
      );
      return null;
    }
    return null;
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
        'iiprop': 'url|mime|extmetadata',
        'iiurlwidth': '$thumbWidth',
      },
    );
  }

  /// Скачивает картинку; `null` — ошибка, не картинка или больше лимита.
  Future<Uint8List?> _download(String rawUrl) async {
    final Uri? uri = Uri.tryParse(rawUrl);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return null;
    }
    try {
      final Response<List<int>> response = await dio.getUri<List<int>>(
        uri,
        options: Options(
          responseType: ResponseType.bytes,
          receiveTimeout: _timeout,
          headers: <String, String>{'User-Agent': userAgent},
        ),
      );
      final List<int>? data = response.data;
      if (data == null || data.isEmpty || data.length > maxImageBytes) {
        return null;
      }
      return Uint8List.fromList(data);
    } on Object {
      return null;
    }
  }

  /// Разбирает `query.pages` ответа Commons в порядке поисковой выдачи.
  static List<_CommonsImage> _imagesOf(Map<String, Object?>? data) {
    final Object? query = data?['query'];
    if (query is! Map) return const <_CommonsImage>[];
    final Object? pages = query['pages'];
    if (pages is! Map) return const <_CommonsImage>[];
    final List<({int index, _CommonsImage image})> found =
        <({int index, _CommonsImage image})>[];
    for (final Object? raw in pages.values) {
      if (raw is! Map) continue;
      final Object? info = raw['imageinfo'];
      if (info is! List || info.isEmpty) continue;
      final Object? first = info.first;
      if (first is! Map) continue;
      final _CommonsImage? image = _imageOf(raw, first);
      if (image == null) continue;
      final Object? index = raw['index'];
      found.add((index: index is int ? index : found.length, image: image));
    }
    found.sort(
      (
        ({int index, _CommonsImage image}) a,
        ({int index, _CommonsImage image}) b,
      ) => a.index.compareTo(b.index),
    );
    return <_CommonsImage>[
      for (final ({int index, _CommonsImage image}) entry in found) entry.image,
    ];
  }

  static _CommonsImage? _imageOf(
    Map<dynamic, dynamic> page,
    Map<dynamic, dynamic> info,
  ) {
    final Object? mime = info['mime'];
    if (mime is! String || !_allowedMime.contains(mime.toLowerCase())) {
      return null;
    }
    return _CommonsImage(
      url: _asString(info['url']),
      thumbUrl: _asString(info['thumburl']),
      attribution: _attributionOf(
        title: _asString(page['title']),
        metadata: info['extmetadata'],
      ),
    );
  }

  /// Атрибуция из `extmetadata`: лицензия и автор без HTML-разметки.
  static String? _attributionOf({
    required String? title,
    required Object? metadata,
  }) {
    String? license;
    String? artist;
    if (metadata is Map) {
      license = _metadataValue(metadata['LicenseShortName']);
      artist = _metadataValue(metadata['Artist']);
    }
    final List<String> parts = <String>[
      ?title,
      if (artist != null && artist.isNotEmpty) artist,
      if (license != null && license.isNotEmpty) license,
    ];
    if (parts.isEmpty) return null;
    return parts.join(' · ');
  }

  static String? _metadataValue(Object? value) {
    if (value is! Map) return null;
    return _asString(_stripHtml(value['value']));
  }

  /// Убирает HTML-теги и раскрывает основные сущности (атрибуция из Commons).
  static String? _stripHtml(Object? value) {
    if (value is! String) return null;
    final String text = value
        .replaceAll(RegExp(r'<[^>]*>'), ' ')
        .replaceAll('&amp;', '&')
        .replaceAll('&quot;', '"')
        .replaceAll('&#039;', "'")
        .replaceAll('&apos;', "'")
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&nbsp;', ' ')
        .replaceAll(RegExp(r'\s+'), ' ')
        .trim();
    return text.isEmpty ? null : text;
  }

  /// MIME-тип по магическим байтам: только JPEG/PNG.
  static AttachmentMediaType? _mediaTypeOf(List<int> bytes) {
    if (_startsWith(bytes, const <int>[0xFF, 0xD8, 0xFF])) {
      return AttachmentMediaType.jpeg;
    }
    if (_startsWith(bytes, const <int>[
      0x89,
      0x50,
      0x4E,
      0x47,
      0x0D,
      0x0A,
      0x1A,
      0x0A,
    ])) {
      return AttachmentMediaType.png;
    }
    return null;
  }

  static bool _startsWith(List<int> bytes, List<int> prefix) {
    if (bytes.length < prefix.length) return false;
    for (var index = 0; index < prefix.length; index++) {
      if (bytes[index] != prefix[index]) return false;
    }
    return true;
  }

  static String? _asString(Object? value) {
    if (value is! String) return null;
    final String trimmed = value.trim();
    return trimmed.isEmpty ? null : trimmed;
  }
}

/// Один файл выдачи Commons.
class _CommonsImage {
  const _CommonsImage({
    required this.url,
    required this.thumbUrl,
    required this.attribution,
  });

  final String? url;
  final String? thumbUrl;
  final String? attribution;
}
