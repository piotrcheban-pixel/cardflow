/// Единые лимиты запроса для планировщика и исполнителя (TASK 03, раздел 3).
///
/// Раньше «8 image-частей» и «24 МБ» жили в двух местах с разными значениями по
/// умолчанию: `GenerationChunkPlannerConfig` (план) и константы
/// `generation_images.dart` (сервис). Теперь обе стороны получают значения из
/// одного резолвера, а каждое значение несёт источник:
/// - [CapabilitySource.userConfigured] — значение задано в настройках аккаунта
///   (`max_images_per_request`/`max_image_bytes`/`max_request_bytes` JSON v2);
/// - [CapabilitySource.unknown] — подтверждённого значения нет, применяется
///   **конфигурационное консервативное допущение приложения**
///   ([GenerationChunkPlannerConfig]); это не характеристика модели.
///
/// Неизвестная характеристика никогда не превращается в 0. Если безопасное
/// планирование без значения невозможно, вызывающий код получает явную
/// причину (невалидный план/ошибку), а не произвольное число без пометки.
/// Домен не зависит от Flutter.
library;

import 'package:cardflow/domain/generation/model_capabilities.dart';

/// Лимиты одного запроса с указанием источника каждого значения.
class GenerationRequestLimits {
  /// Создаёт лимиты запроса.
  const GenerationRequestLimits({
    required this.maxImagesPerRequest,
    required this.maxImageBytesPerImage,
    required this.maxImageBytesPerRequest,
    required this.maxRequestBytes,
    required this.imagesSource,
    required this.imageBytesSource,
    required this.imageBytesRequestSource,
    required this.requestBytesSource,
  }) : assert(maxImagesPerRequest > 0),
       assert(maxImageBytesPerImage > 0),
       assert(maxImageBytesPerRequest > 0),
       assert(maxRequestBytes > 0);

  /// Максимум image-частей в одном запросе.
  final int maxImagesPerRequest;

  /// Максимум байт одного изображения.
  final int maxImageBytesPerImage;

  /// Максимум суммарных байт изображений запроса.
  final int maxImageBytesPerRequest;

  /// Максимум байт тела запроса.
  final int maxRequestBytes;

  /// Источник лимита числа image-частей.
  final CapabilitySource imagesSource;

  /// Источник лимита байт одного изображения.
  final CapabilitySource imageBytesSource;

  /// Источник лимита суммарных байт изображений запроса.
  final CapabilitySource imageBytesRequestSource;

  /// Источник лимита тела запроса.
  final CapabilitySource requestBytesSource;

  /// true, если хотя бы одно значение — допущение приложения.
  bool get hasAssumption =>
      imagesSource == CapabilitySource.unknown ||
      imageBytesSource == CapabilitySource.unknown ||
      imageBytesRequestSource == CapabilitySource.unknown ||
      requestBytesSource == CapabilitySource.unknown;

  /// true, если число image-частей не подтверждено моделью.
  bool get imagesAssumed => imagesSource == CapabilitySource.unknown;

  /// Ключи допущений для `unknownFields` плана/диагностики.
  List<String> get assumptionFields => <String>[
    if (imagesSource == CapabilitySource.unknown) 'max_images_per_request',
    if (imageBytesSource == CapabilitySource.unknown ||
        imageBytesRequestSource == CapabilitySource.unknown)
      'max_image_bytes',
    if (requestBytesSource == CapabilitySource.unknown) 'max_request_bytes',
  ];

  @override
  String toString() =>
      'GenerationRequestLimits(images: $maxImagesPerRequest '
      '${imagesSource.wireName}, imageBytes: $maxImageBytesPerImage/'
      '$maxImageBytesPerRequest ${imageBytesSource.wireName}, '
      'requestBytes: $maxRequestBytes ${requestBytesSource.wireName})';
}

/// Собирает лимиты запроса из возможностей модели и конфигурации приложения.
///
/// [assumedMaxImagesPerRequest], [assumedMaxImageBytesPerImage],
/// [assumedMaxImageBytesPerChunk], [assumedMaxRequestBytes] — значения
/// [GenerationChunkPlannerConfig]; передаются параметрами, чтобы не создавать
/// цикл импортов «планировщик ↩ лимиты».
GenerationRequestLimits resolveGenerationRequestLimits(
  ModelCapabilities capabilities, {
  required int assumedMaxImagesPerRequest,
  required int assumedMaxImageBytesPerImage,
  required int assumedMaxImageBytesPerChunk,
  required int assumedMaxRequestBytes,
  CapabilitySource defaultSource = CapabilitySource.userConfigured,
}) {
  assert(assumedMaxImagesPerRequest > 0);
  assert(assumedMaxImageBytesPerImage > 0);
  assert(assumedMaxImageBytesPerChunk > 0);
  assert(assumedMaxRequestBytes > 0);

  final int? maxImages = capabilities.maxImagesPerRequest;
  final int? maxImageBytes = capabilities.maxImageBytesPerImage;
  final int? maxImageBytesRequest = capabilities.maxImageBytesPerRequest;
  final int? maxRequestBytes = capabilities.maxRequestBytes;

  CapabilitySource sourceOf(Object? value, CapabilitySource groupSource) {
    if (value == null) return CapabilitySource.unknown;
    // Групповой источник (imageSource) несёт информацию о происхождении
    // лимитов изображений; неизвестный групповой источник означает, что
    // значение пришло из аккаунта без явной подписи — defaultSource.
    return groupSource == CapabilitySource.unknown
        ? defaultSource
        : groupSource;
  }

  return GenerationRequestLimits(
    maxImagesPerRequest: maxImages ?? assumedMaxImagesPerRequest,
    maxImageBytesPerImage: maxImageBytes ?? assumedMaxImageBytesPerImage,
    maxImageBytesPerRequest:
        maxImageBytesRequest ?? assumedMaxImageBytesPerChunk,
    maxRequestBytes: maxRequestBytes ?? assumedMaxRequestBytes,
    imagesSource: sourceOf(maxImages, capabilities.imageSource),
    imageBytesSource: sourceOf(maxImageBytes, capabilities.imageSource),
    imageBytesRequestSource: sourceOf(
      maxImageBytesRequest,
      capabilities.imageSource,
    ),
    requestBytesSource: sourceOf(maxRequestBytes, capabilities.imageSource),
  );
}
