/// Поиск иллюстраций в Openverse для сгенерированных карточек (итерация 7.9).
///
/// Openverse API не требует ключа (анонимный лимит ~1 запрос/с), отдаёт только
/// CC-лицензии. Сервис ищет картинку по `image_query`, скачивает thumbnail
/// (fallback — оригинал), проверяет сигнатуру JPEG/PNG и размер. Любая ошибка
/// сети/API → `null`: генерация карточек продолжается без иллюстрации.
library;

import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'package:cardflow/api/generation/generation_diagnostics.dart';
import 'package:cardflow/domain/generation/card_image_finder.dart';
import 'package:cardflow/domain/generation/generated_card_image.dart';
import 'package:cardflow/domain/generation/generation_attachment.dart';

/// Поиск картинок через открытый API Openverse.
class ImageSearchService implements CardImageFinder {
  /// Создаёт сервис.
  ImageSearchService({
    required this.dio,
    Uri? endpoint,
    this.maxResults = 5,
    this.maxImageBytes = 5 * 1024 * 1024,
    this.minSearchInterval = const Duration(seconds: 1),
    this.userAgent = 'CardFlow/1.0',
    GenerationDiagnostics? diagnostics,
  }) : endpoint = endpoint ?? Uri.parse('https://api.openverse.org/v1/images/'),
       diagnostics = diagnostics ?? const GenerationDiagnostics();

  /// HTTP-клиент (Dio с таймаутами и redaction в production-проводке).
  final Dio dio;

  /// Debug-диагностика поиска картинок (ADR-024).
  final GenerationDiagnostics diagnostics;

  /// Базовый адрес поиска.
  final Uri endpoint;

  /// Сколько результатов просматривать.
  final int maxResults;

  /// Максимальный размер скачанной картинки.
  final int maxImageBytes;

  /// Минимальная пауза между поисковыми запросами (анонимный лимит Openverse
  /// ~1 запрос/с).
  final Duration minSearchInterval;

  /// User-Agent для Openverse (анонимный доступ).
  final String userAgent;

  /// Время последнего поискового запроса (для троттлинга).
  DateTime? _lastSearchAt;

  /// Лицензии, которые разрешены к скачиванию (атрибуция — в источнике).
  static const String _licenses = 'cc0,pdm,by,by-sa';

  /// Таймаут одного запроса поиска/скачивания.
  ///
  /// Openverse отвечает не всегда: при недоступности бюджета времени 8 с
  /// оставляют генерации шанс продолжить, а резервный источник (Wikimedia,
  /// ADR-026) закроет потребность в иллюстрации.
  static const Duration _timeout = Duration(seconds: 8);

  @override
  Future<GeneratedCardImage?> findImage(String query) async {
    final String normalized = query.trim();
    if (normalized.isEmpty) return null;
    try {
      await _throttleSearch();
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
      final Object? results = response.data?['results'];
      if (results is! List) return null;
      for (final Object? raw in results.take(maxResults)) {
        if (raw is! Map) continue;
        final String? url =
            _asString(raw['thumbnail']) ?? _asString(raw['url']);
        if (url == null) continue;
        final Uint8List? bytes = await _download(url);
        if (bytes == null) continue;
        final AttachmentMediaType? mediaType = _mediaTypeOf(bytes);
        if (mediaType == null) continue;
        diagnostics.imageSearch(
          query: normalized,
          outcome: 'скачано ${bytes.length} Б, ${mediaType.name}',
        );
        return GeneratedCardImage(
          bytes: bytes,
          mediaType: mediaType,
          query: normalized,
          sourceUrl: url,
          attribution: _asString(raw['attribution']),
        );
      }
      diagnostics.imageSearch(
        query: normalized,
        outcome:
            'нет подходящей картинки среди '
            '${results.length < maxResults ? results.length : maxResults} '
            'результатов',
      );
    } on Object catch (error) {
      // Сеть/API недоступны: генерация продолжится без иллюстрации.
      diagnostics.imageSearch(
        query: normalized,
        outcome: 'ошибка запроса: $error',
      );
      return null;
    }
    return null;
  }

  /// Выдерживает паузу между поисковыми запросами Openverse.
  Future<void> _throttleSearch() async {
    final DateTime? last = _lastSearchAt;
    if (last != null) {
      final Duration elapsed = DateTime.now().difference(last);
      if (elapsed < minSearchInterval) {
        await Future<void>.delayed(minSearchInterval - elapsed);
      }
    }
    _lastSearchAt = DateTime.now();
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
