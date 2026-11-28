import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/domain/settings/app_settings.dart';

/// Срез 14: критерий флага выполнен (`journal/generation-v3/verify-s14.md`),
/// поэтому путь v3 включён по умолчанию, а legacy включается выключением флага.
void main() {
  test('по умолчанию включён: новый путь — основной, legacy — флагом', () {
    expect(AppSettings.defaults.generationPipelineV3, isTrue);
    expect(const AppSettings().generationPipelineV3, isTrue);
  });

  test('JSON round-trip сохраняет выключенный флаг (legacy доступен)', () {
    final AppSettings settings = AppSettings.defaults.copyWith(
      generationPipelineV3: false,
    );
    final Map<String, Object?> json = settings.toJson();
    expect(json['generation_pipeline_v3'], isFalse);
    expect(json['version'], AppSettings.version);
    expect(AppSettings.fromJson(json).generationPipelineV3, isFalse);
    expect(AppSettings.fromJson(json), settings);
  });

  test('старый JSON без ключа читается как «включено» (ADR-019 §1)', () {
    final Map<String, Object?> legacy = AppSettings.defaults.toJson()
      ..remove('generation_pipeline_v3');
    expect(AppSettings.fromJson(legacy).generationPipelineV3, isTrue);
  });

  test('copyWith без флага его не меняет', () {
    final AppSettings off = AppSettings.defaults.copyWith(
      generationPipelineV3: false,
    );
    expect(off.copyWith(dailyNewLimit: 5).generationPipelineV3, isFalse);
    expect(
      off.copyWith(generationPipelineV3: true).generationPipelineV3,
      isTrue,
    );
  });
}
