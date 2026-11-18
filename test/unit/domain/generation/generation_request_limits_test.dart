import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/domain/generation/generation_request_limits.dart';
import 'package:cardflow/domain/generation/model_capabilities.dart';

/// TASK 03: fallback «8 image-частей» — явное допущение, а не факт модели.
void main() {
  GenerationRequestLimits resolve({
    int? maxImages,
    int? maxImageBytes,
    int? maxImageBytesRequest,
    int? maxRequestBytes,
    CapabilitySource source = CapabilitySource.user,
  }) {
    return resolveGenerationRequestLimits(
      ModelCapabilities(
        maxImagesPerRequest: maxImages,
        maxImageBytesPerImage: maxImageBytes,
        maxImageBytesPerRequest: maxImageBytesRequest,
        maxRequestBytes: maxRequestBytes,
        imageSource: source,
      ),
      assumedMaxImagesPerRequest: 8,
      assumedMaxImageBytesPerImage: 10 * 1024 * 1024,
      assumedMaxImageBytesPerChunk: 24 * 1024 * 1024,
      assumedMaxRequestBytes: 32 * 1024 * 1024,
    );
  }

  test('значение аккаунта — источник user', () {
    final GenerationRequestLimits limits = resolve(
      maxImages: 20,
      maxImageBytes: 5 * 1024 * 1024,
      maxImageBytesRequest: 50 * 1024 * 1024,
      maxRequestBytes: 64 * 1024 * 1024,
    );
    expect(limits.maxImagesPerRequest, 20);
    expect(limits.maxImageBytesPerImage, 5 * 1024 * 1024);
    expect(limits.maxImageBytesPerRequest, 50 * 1024 * 1024);
    expect(limits.maxRequestBytes, 64 * 1024 * 1024);
    expect(limits.imagesSource, CapabilitySource.user);
    expect(limits.imageBytesSource, CapabilitySource.user);
    expect(limits.imageBytesRequestSource, CapabilitySource.user);
    expect(limits.requestBytesSource, CapabilitySource.user);
    expect(limits.hasAssumption, isFalse);
    expect(limits.assumptionFields, isEmpty);
  });

  test('неизвестный лимит — консервативное допущение с явным источником', () {
    final GenerationRequestLimits limits = resolve();
    expect(limits.maxImagesPerRequest, 8);
    expect(limits.imagesSource, CapabilitySource.unknown);
    expect(limits.imagesAssumed, isTrue);
    expect(limits.hasAssumption, isTrue);
    expect(
      limits.assumptionFields,
      containsAll(<String>[
        'max_images_per_request',
        'max_image_bytes',
        'max_request_bytes',
      ]),
    );
  });

  test('никогда не подставляет 0 для неизвестного лимита', () {
    final GenerationRequestLimits limits = resolve();
    expect(limits.maxImagesPerRequest, greaterThan(0));
    expect(limits.maxImageBytesPerImage, greaterThan(0));
    expect(limits.maxImageBytesPerRequest, greaterThan(0));
    expect(limits.maxRequestBytes, greaterThan(0));
  });

  test('частично заданные лимиты сохраняют источник по каждому значению', () {
    final GenerationRequestLimits limits = resolve(maxImages: 3);
    expect(limits.maxImagesPerRequest, 3);
    expect(limits.imagesSource, CapabilitySource.user);
    expect(limits.imageBytesSource, CapabilitySource.unknown);
    expect(limits.imageBytesRequestSource, CapabilitySource.unknown);
    expect(limits.requestBytesSource, CapabilitySource.unknown);
    expect(limits.assumptionFields, isNot(contains('max_images_per_request')));
    expect(limits.assumptionFields, contains('max_image_bytes'));
  });

  test('может быть источник preset, если так решил резолвер возможностей', () {
    final GenerationRequestLimits limits = resolve(
      maxImages: 12,
      source: CapabilitySource.preset,
    );
    expect(limits.imagesSource, CapabilitySource.preset);
    expect(limits.hasAssumption, isTrue, reason: 'байты всё ещё неизвестны');
  });
}
