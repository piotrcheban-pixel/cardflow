import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/domain/generation/generation_path.dart';
import 'package:cardflow/domain/settings/app_settings.dart';

/// Срез 17, часть 2, п. 11: путь генерации — не булев флаг в настройках, а
/// **режим** `auto / v3 / legacy`; `auto` решает функцию от материала
/// (`selectGenerationPath`). Ручное переопределение остаётся явным значением
/// режима, поэтому пользователь видит выбор, а не скрытый флаг.
///
/// Тест фиксирует **значение по умолчанию** и совместимость со старым JSON:
/// смена дефолта обязана быть видна в диффе, а не проходить молча.
void main() {
  test('по умолчанию авто, и авто по данным S17 = legacy', () {
    expect(AppSettings.defaults.generationPathMode, GenerationPathMode.auto);
    expect(const AppSettings().generationPathMode, GenerationPathMode.auto);
    expect(
      selectGenerationPath(
        mode: AppSettings.defaults.generationPathMode,
        materialUnits: 33,
      ).path,
      GenerationPath.legacy,
    );
  });

  test('ручное переопределение сохраняется в JSON и читается обратно', () {
    for (final GenerationPathMode mode in <GenerationPathMode>[
      GenerationPathMode.v3,
      GenerationPathMode.legacy,
    ]) {
      final AppSettings settings = AppSettings.defaults.copyWith(
        generationPathMode: mode,
      );
      final Map<String, Object?> json = settings.toJson();
      expect(json['generation_path_mode'], mode.wireName);
      expect(json['version'], AppSettings.version);
      expect(AppSettings.fromJson(json).generationPathMode, mode);
      expect(AppSettings.fromJson(json), settings);
    }
  });

  test('старый JSON с generation_pipeline_v3 читается как режим', () {
    final Map<String, Object?> on = AppSettings.defaults.toJson()
      ..remove('generation_path_mode')
      ..['generation_pipeline_v3'] = true;
    final Map<String, Object?> off = AppSettings.defaults.toJson()
      ..remove('generation_path_mode')
      ..['generation_pipeline_v3'] = false;
    expect(
      AppSettings.fromJson(on).generationPathMode,
      GenerationPathMode.v3,
      reason: 'раньше включённый флаг означал путь v3',
    );
    expect(
      AppSettings.fromJson(off).generationPathMode,
      GenerationPathMode.legacy,
      reason: 'раньше выключенный флаг означал legacy-путь',
    );
  });

  test('старый JSON без обоих ключей читается как авто', () {
    final Map<String, Object?> legacy = AppSettings.defaults.toJson()
      ..remove('generation_path_mode')
      ..remove('generation_pipeline_v3');
    expect(
      AppSettings.fromJson(legacy).generationPathMode,
      GenerationPathMode.auto,
    );
  });

  test('copyWith без режима его не меняет', () {
    final AppSettings v3 = AppSettings.defaults.copyWith(
      generationPathMode: GenerationPathMode.v3,
    );
    expect(
      v3.copyWith(dailyNewLimit: 5).generationPathMode,
      GenerationPathMode.v3,
    );
    expect(
      v3
          .copyWith(generationPathMode: GenerationPathMode.legacy)
          .generationPathMode,
      GenerationPathMode.legacy,
    );
  });
}
