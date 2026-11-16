/// Цепочка провайдеров картинок для сгенерированных карточек (итерация 7.14).
///
/// Порядок: картинка из файла (её подставляет пайплайн до вызова цепочки) →
/// Wikimedia Commons → Wikipedia (семейство Wikimedia, ADR-028) → Openverse →
/// Pixabay/Pexels (только если задан ключ). Запрос сначала основной, затем
/// `fallback_query` модели. На каждый провайдер — таймаут, на карточку —
/// общий бюджет времени.
///
/// Скачивание и фильтры (JPEG/PNG/WebP, короткая сторона ≥ 400 px,
/// соотношение 1:3…3:1, безопасный поиск, дубли URL) — здесь, а не в
/// провайдерах: один набор правил для всех источников. 429/5xx — один ретрай
/// с backoff, затем следующий провайдер. Никакой исход не роняет генерацию.
library;

import 'dart:async';
import 'dart:collection';
import 'dart:typed_data';

import 'package:dio/dio.dart';

import 'package:cardflow/api/generation/generation_diagnostics.dart';
import 'package:cardflow/api/images/image_dimensions.dart';
import 'package:cardflow/api/images/image_provider.dart';
import 'package:cardflow/domain/generation/card_image_finder.dart';
import 'package:cardflow/domain/generation/card_image_kind.dart';
import 'package:cardflow/domain/generation/generated_card_image.dart';
import 'package:cardflow/domain/generation/generation_attachment.dart';

/// Цепочка провайдеров с таймаутами, фильтрами и кэшем.
class ImageSearchService implements CardImageFinder {
  /// Создаёт цепочку.
  ImageSearchService({
    required this.dio,
    required this.providers,
    this.providerTimeout = const Duration(seconds: 6),
    this.cardBudget = const Duration(seconds: 20),
    this.downloadTimeout = const Duration(seconds: 6),
    this.maxImageBytes = 5 * 1024 * 1024,
    this.maxConcurrentDownloads = 4,
    this.retryBackoff = const Duration(milliseconds: 300),
    this.cacheMaxEntries = 32,
    GenerationDiagnostics? diagnostics,
    DateTime Function()? now,
    Future<void> Function(Duration duration)? sleep,
  }) : diagnostics = diagnostics ?? const GenerationDiagnostics(),
       now = now ?? DateTime.now,
       sleep = sleep ?? _defaultSleep,
       _limiter = _DownloadLimiter(maxConcurrentDownloads);

  /// HTTP-клиент для скачивания кандидатов.
  final Dio dio;

  /// Провайдеры в порядке приоритета.
  final List<ImageProvider> providers;

  /// Таймаут на одного провайдера (поиск + скачивание его кандидатов).
  final Duration providerTimeout;

  /// Общий бюджет времени на одну карточку.
  final Duration cardBudget;

  /// Таймаут одного скачивания.
  final Duration downloadTimeout;

  /// Максимальный размер скачанной картинки.
  final int maxImageBytes;

  /// Максимум одновременных скачиваний.
  final int maxConcurrentDownloads;

  /// Пауза перед повтором после 429/5xx.
  final Duration retryBackoff;

  /// Сколько успешных результатов держать в кэше «запрос → картинка».
  final int cacheMaxEntries;

  /// Debug-диагностика (ADR-024).
  final GenerationDiagnostics diagnostics;

  /// Часы (инжектируются в тестах).
  final DateTime Function() now;

  /// Пауза (инжектируется в тестах, чтобы не ждать backoff).
  final Future<void> Function(Duration duration) sleep;

  final _DownloadLimiter _limiter;

  /// Кэш успешных результатов: запрос + вид → картинка.
  final LinkedHashMap<String, GeneratedCardImage> _cache =
      LinkedHashMap<String, GeneratedCardImage>();

  /// Имена провайдеров цепочки (для тестов и диагностики).
  List<String> get providerNames => <String>[
    for (final ImageProvider provider in providers) provider.name,
  ];

  @override
  Future<GeneratedCardImage?> findImage(
    String query, {
    String? fallbackQuery,
    GeneratedCardImageKind kind = GeneratedCardImageKind.photo,
    Set<String>? excludedSourceUrls,
  }) async {
    final String primary = query.trim();
    final List<String> queries = <String>[
      if (primary.isNotEmpty) primary,
      if (fallbackQuery != null &&
          fallbackQuery.trim().isNotEmpty &&
          fallbackQuery.trim() != primary)
        fallbackQuery.trim(),
    ];
    if (queries.isEmpty) return null;
    final DateTime deadline = now().add(cardBudget);
    for (final String text in queries) {
      final String cacheKey = '${kind.wireName}\u0000$text';
      final GeneratedCardImage? cached = _cache[cacheKey];
      if (cached != null) {
        // Кэш не нарушает правило «одна картинка на колоду»: URL занят другой
        // карточкой — ищем дальше.
        if (!(excludedSourceUrls?.contains(cached.sourceUrl) ?? false)) {
          return cached;
        }
      }
      for (final ImageProvider provider in providers) {
        if (!now().isBefore(deadline)) {
          diagnostics.imageSearch(
            query: text,
            outcome: 'пропущен: бюджет времени карточки исчерпан',
          );
          return null;
        }
        final GeneratedCardImage? image = await _tryProvider(
          provider: provider,
          query: text,
          kind: kind,
          deadline: deadline,
          excludedSourceUrls: excludedSourceUrls,
        );
        if (image == null) continue;
        _remember(cacheKey, image);
        // Набор занятых URL ведёт вызывающий (пайплайн): цепочка только
        // пропускает уже занятые, чтобы не путать «свой» набор с чужим.
        return image;
      }
    }
    return null;
  }

  /// Пробует одного провайдера с таймаутом и одним ретраем на 429/5xx.
  Future<GeneratedCardImage?> _tryProvider({
    required ImageProvider provider,
    required String query,
    required GeneratedCardImageKind kind,
    required DateTime deadline,
    required Set<String>? excludedSourceUrls,
  }) async {
    final Duration remaining = deadline.difference(now());
    final Duration timeout = _minDuration(providerTimeout, remaining);
    if (timeout <= Duration.zero) return null;
    try {
      return await _attemptProvider(
        provider: provider,
        query: query,
        kind: kind,
        excludedSourceUrls: excludedSourceUrls,
      ).timeout(timeout);
    } on TimeoutException {
      diagnostics.imageSearch(
        query: query,
        outcome: '${provider.name}: таймаут ${timeout.inMilliseconds} мс',
      );
      return null;
    } on Object catch (error) {
      if (!_isRetryable(error)) {
        diagnostics.imageSearch(
          query: query,
          outcome: '${provider.name}: ошибка запроса: $error',
        );
        return null;
      }
      diagnostics.imageSearch(
        query: query,
        outcome: '${provider.name}: $error, повтор через backoff',
      );
      await sleep(retryBackoff);
      final Duration afterRetry = deadline.difference(now());
      final Duration retryTimeout = _minDuration(providerTimeout, afterRetry);
      if (retryTimeout <= Duration.zero) return null;
      try {
        return await _attemptProvider(
          provider: provider,
          query: query,
          kind: kind,
          excludedSourceUrls: excludedSourceUrls,
        ).timeout(retryTimeout);
      } on Object catch (retryError) {
        diagnostics.imageSearch(
          query: query,
          outcome: '${provider.name}: повтор не удался: $retryError',
        );
        return null;
      }
    }
  }

  /// Поиск + скачивание первого подходящего кандидата.
  Future<GeneratedCardImage?> _attemptProvider({
    required ImageProvider provider,
    required String query,
    required GeneratedCardImageKind kind,
    required Set<String>? excludedSourceUrls,
  }) async {
    final List<ImageCandidate> candidates = await provider.search(
      ImageProviderQuery(query: query, kind: kind),
    );
    for (final ImageCandidate candidate in candidates) {
      if (excludedSourceUrls?.contains(candidate.url) ?? false) continue;
      if (candidate.hasKnownSize &&
          !ImageDimensions(candidate.width!, candidate.height!).isUsable) {
        continue;
      }
      final Uint8List? bytes = await _download(candidate.url);
      if (bytes == null) continue;
      final AttachmentMediaType? mediaType = mediaTypeOfImageBytes(bytes);
      if (mediaType == null) continue;
      final ImageDimensions? dimensions = ImageDimensions.read(bytes);
      if (dimensions == null || !dimensions.isUsable) continue;
      diagnostics.imageSearch(
        query: query,
        outcome:
            '${provider.name}: скачано ${bytes.length} Б, ${mediaType.name}, '
            '${dimensions.width}x${dimensions.height}',
      );
      return GeneratedCardImage(
        bytes: bytes,
        mediaType: mediaType,
        query: query,
        kind: kind,
        sourceUrl: candidate.url,
        provider: provider.name,
        author: candidate.author,
        license: candidate.license,
        attribution: candidate.attribution,
      );
    }
    diagnostics.imageSearch(
      query: query,
      outcome:
          '${provider.name}: нет подходящей картинки среди '
          '${candidates.length} кандидатов',
    );
    return null;
  }

  /// Скачивает кандидата через ограничитель параллелизма.
  Future<Uint8List?> _download(String rawUrl) async {
    final Uri? uri = Uri.tryParse(rawUrl);
    if (uri == null || (uri.scheme != 'http' && uri.scheme != 'https')) {
      return null;
    }
    return _limiter.run(() async {
      try {
        final Response<List<int>> response = await dio.getUri<List<int>>(
          uri,
          options: Options(
            responseType: ResponseType.bytes,
            receiveTimeout: downloadTimeout,
          ),
        );
        final List<int>? data = response.data;
        if (data == null || data.isEmpty || data.length > maxImageBytes) {
          return null;
        }
        return Uint8List.fromList(data);
      } on Object catch (error) {
        if (_isRetryable(error)) rethrow;
        return null;
      }
    });
  }

  /// Кладёт результат в кэш, вытесняя самый старый (простая LRU-политика).
  void _remember(String key, GeneratedCardImage image) {
    if (cacheMaxEntries <= 0) return;
    _cache.remove(key);
    _cache[key] = image;
    while (_cache.length > cacheMaxEntries) {
      _cache.remove(_cache.keys.first);
    }
  }

  /// 429 и 5xx — повторяем один раз; остальное — сразу следующий провайдер.
  static bool _isRetryable(Object error) {
    if (error is! DioException) return false;
    final int? status = error.response?.statusCode;
    return status == 429 || (status != null && status >= 500);
  }

  static Duration _minDuration(Duration a, Duration b) => a < b ? a : b;

  static Future<void> _defaultSleep(Duration duration) =>
      Future<void>.delayed(duration);
}

/// MIME-тип картинки по магическим байтам: JPEG, PNG или WebP.
AttachmentMediaType? mediaTypeOfImageBytes(List<int> bytes) {
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
  if (bytes.length >= 12 &&
      _startsWith(bytes, const <int>[0x52, 0x49, 0x46, 0x46]) &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x45 &&
      bytes[10] == 0x42 &&
      bytes[11] == 0x50) {
    return AttachmentMediaType.webp;
  }
  return null;
}

bool _startsWith(List<int> bytes, List<int> prefix) {
  if (bytes.length < prefix.length) return false;
  for (var index = 0; index < prefix.length; index++) {
    if (bytes[index] != prefix[index]) return false;
  }
  return true;
}

/// Ограничитель одновременных скачиваний (не больше `maxConcurrent`).
class _DownloadLimiter {
  _DownloadLimiter(this.maxConcurrent);

  final int maxConcurrent;
  var _active = 0;
  final Queue<Completer<void>> _waiters = Queue<Completer<void>>();

  Future<T> run<T>(Future<T> Function() action) async {
    // Пока слот занят, ждём; после пробуждения перепроверяем лимит: новый
    // вызывающий мог занять освободившийся слот раньше нас.
    while (_active >= maxConcurrent) {
      final Completer<void> waiter = Completer<void>();
      _waiters.add(waiter);
      await waiter.future;
    }
    _active++;
    try {
      return await action();
    } finally {
      _active--;
      if (_waiters.isNotEmpty) {
        _waiters.removeFirst().complete();
      }
    }
  }
}
