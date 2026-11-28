import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/domain/settings/app_settings.dart';

/// Срез 15, часть 0: флаг `generationPipelineV3` снова **выключен** по
/// умолчанию. Причина — в `journal/STATE.md`: критерий среза 14 выведен из
/// `coverage`, а не измерен пер-юнитными данными (L230); вернуть после
/// честного замера среза 15.
///
/// Тест фиксирует **значение по умолчанию**: смена дефолта обязана быть видна
/// в диффе, а не проходить молча.
void main() {
  test('по умолчанию выключен: v3 включается только после замера', () {
    expect(AppSettings.defaults.generationPipelineV3, isFalse);
    expect(const AppSettings().generationPipelineV3, isFalse);
  });

  test('explicit true включает v3 (флаг работает в обе стороны)', () {
    final AppSettings on = AppSettings.defaults.copyWith(
      generationPipelineV3: true,
    );
    expect(on.generationPipelineV3, isTrue);
    expect(AppSettings.fromJson(on.toJson()).generationPipelineV3, isTrue);
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

  test('старый JSON без ключа читается как значение по умолчанию', () {
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
