/// Иллюстрации из статей Wikipedia для сгенерированных карточек (ADR-028,
/// итерация 7.12).
///
/// Commons ищет по именам файлов, поэтому русские словоформы («спайность
/// минерала») дают 0 результатов. Wikipedia ищет статью по запросу и отдаёт её
/// превью (`prop=pageimages`) — для предметных русских запросов это заметно
/// надёжнее. API не требует ключа; любая ошибка сети/API → `null`, генерация
/// продолжается без иллюстрации.
library;

import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'package:cardflow/api/generation/generation_diagnostics.dart';
import 'package:cardflow/domain/generation/card_image_finder.dart';
import 'package:cardflow/domain/generation/generated_card_image.dart';
import 'package:cardflow/domain/generation/generation_attachment.dart';

/// Поиск иллюстраций через Wikipedia (ru, затем en).
class WikipediaImageSearchService implements CardImageFinder {
  /// Создаёт сервис.
  WikipediaImageSearchService({
    required this.dio,
    this.languages = const <String>['ru', 'en'],
    this.maxResults = 3,
    this.maxImageBytes = 5 * 1024 * 1024,
    this.thumbWidth = 800,
    this.userAgent =
        'CardFlow/1.0 (https://github.com/piotrcheban-pixel/cardflow)',
    GenerationDiagnostics? diagnostics,
  }) : diagnostics = diagnostics ?? const GenerationDiagnostics();

  /// HTTP-клиент (Dio с таймаутами и redaction в production-проводке).
  final Dio dio;

  /// Debug-диагностика поиска картинок (ADR-024).
  final GenerationDiagnostics diagnostics;

  /// Языки Wikipedia в порядке приоритета.
  final List<String> languages;

  /// Сколько статей просматривать на одном языке.
  final int maxResults;

  /// Максимальный размер скачанной картинки.
  final int maxImageBytes;

  /// Ширина превью, которую просим у Wikipedia.
  final int thumbWidth;

  /// User-Agent: Wikimedia просит осмысленный UA для анонимных запросов.
  final String userAgent;

  /// Таймаут одного запроса поиска/скачивания.
  static const Duration _timeout = Duration(seconds: 8);

  @override
  Future<GeneratedCardImage?> findImage(String query) async {
    final String normalized = query.trim();
    if (normalized.isEmpty) return null;
    for (final String language in languages) {
      final GeneratedCardImage? image = await _searchInLanguage(
        language,
        normalized,
      );
      if (image != null) return image;
    }
    return null;
  }

  /// Ищет превью статьи в Wikipedia языка [language].
  Future<GeneratedCardImage?> _searchInLanguage(
    String language,
    String query,
  ) async {
    final String lang = language.trim().toLowerCase();
    if (lang.isEmpty) return null;
    try {
      final Response<Map<String, Object?>> response = await dio
          .getUri<Map<String, Object?>>(
            _searchUri(lang, query),
            options: Options(
              responseType: ResponseType.json,
              receiveTimeout: _timeout,
              headers: <String, String>{
                'User-Agent': userAgent,
                'Accept': 'application/json',
              },
            ),
          );
      final List<_WikipediaImage> images = _imagesOf(response.data);
      for (final _WikipediaImage image in images) {
        final String url = image.url;
        if (url.isEmpty) continue;
        final Uint8List? bytes = await _download(url);
        if (bytes == null) continue;
        final AttachmentMediaType? mediaType = _mediaTypeOf(bytes);
        if (mediaType == null) continue;
        diagnostics.imageSearch(
          query: query,
          outcome:
              'Wikipedia ($lang): статья «${image.title}», скачано '
              '${bytes.length} Б, ${mediaType.name}',
        );
        return GeneratedCardImage(
          bytes: bytes,
          mediaType: mediaType,
          query: query,
          sourceUrl: url,
          attribution: image.attribution,
        );
      }
      diagnostics.imageSearch(
        query: query,
        outcome:
            'Wikipedia ($lang): нет статьи с картинкой среди '
            '${images.length} результатов',
      );
    } on Object catch (error) {
      diagnostics.imageSearch(
        query: query,
        outcome: 'Wikipedia ($lang): ошибка запроса: $error',
      );
      return null;
    }
    return null;
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

  /// Разбирает `query.pages` (formatversion=2 — список, v1 — карта).
  static List<_WikipediaImage> _imagesOf(Map<String, Object?>? data) {
    final Object? query = data?['query'];
    if (query is! Map) return const <_WikipediaImage>[];
    final Object? pages = query['pages'];
    final Iterable<Object?> entries;
    if (pages is List) {
      entries = pages;
    } else if (pages is Map) {
      entries = pages.values;
    } else {
      return const <_WikipediaImage>[];
    }
    final List<_WikipediaImage> result = <_WikipediaImage>[];
    for (final Object? raw in entries) {
      if (raw is! Map) continue;
      final String? title = _asString(raw['title']);
      final Object? thumbnail = raw['thumbnail'];
      String? url;
      if (thumbnail is Map) {
        url = _asString(thumbnail['source']);
      }
      if (url == null) continue;
      result.add(
        _WikipediaImage(
          title: title ?? 'Wikipedia',
          url: url,
          attribution: title == null ? null : '$title · Wikipedia',
        ),
      );
    }
    return result;
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

/// Одна статья Wikipedia с превью.
class _WikipediaImage {
  const _WikipediaImage({
    required this.title,
    required this.url,
    required this.attribution,
  });

  final String title;
  final String url;
  final String? attribution;
}
