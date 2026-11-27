import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/domain/settings/app_settings.dart';

/// Срез 9: флаг пути генерации v3 живёт в `app_settings` и по умолчанию выключен.
void main() {
  test('по умолчанию выключен: старый путь остаётся рабочим', () {
    expect(AppSettings.defaults.generationPipelineV3, isFalse);
    expect(const AppSettings().generationPipelineV3, isFalse);
  });

  test('JSON round-trip сохраняет включённый флаг', () {
    final AppSettings settings = AppSettings.defaults.copyWith(
      generationPipelineV3: true,
    );
    final Map<String, Object?> json = settings.toJson();
    expect(json['generation_pipeline_v3'], isTrue);
    expect(json['version'], AppSettings.version);
    expect(AppSettings.fromJson(json).generationPipelineV3, isTrue);
    expect(AppSettings.fromJson(json), settings);
  });

  test('старый JSON без ключа читается как «выключено» (ADR-019 §1)', () {
    final Map<String, Object?> legacy = AppSettings.defaults.toJson()
      ..remove('generation_pipeline_v3');
    expect(AppSettings.fromJson(legacy).generationPipelineV3, isFalse);
  });

  test('copyWith без флага его не меняет', () {
    final AppSettings on = AppSettings.defaults.copyWith(
      generationPipelineV3: true,
    );
    expect(on.copyWith(dailyNewLimit: 5).generationPipelineV3, isTrue);
    expect(
      on.copyWith(generationPipelineV3: false).generationPipelineV3,
      isFalse,
    );
  });
}
