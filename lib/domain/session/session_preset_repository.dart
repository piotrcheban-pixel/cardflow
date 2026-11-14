/// Порт хранения пресетов конструктора (SPEC A5/A6.7, ADR-018).
library;

import 'package:cardflow/domain/session/session_config.dart';
import 'package:cardflow/domain/session/session_preset.dart';

/// Чтение и запись `session_presets`.
abstract interface class SessionPresetRepository {
  /// Все пресеты в порядке создания (старые раньше).
  ///
  /// Строки с невалидным `config_json` пропускаются: один битый пресет не
  /// должен ломать экран конструктора.
  Future<List<SessionPreset>> presets();

  /// Сохраняет пресет; id генерирует реализация (uuid v4).
  Future<SessionPreset> savePreset({
    required String name,
    required SessionConfig config,
    required DateTime createdAt,
  });

  /// Удаляет пресет по id (остальные не трогает).
  Future<void> deletePreset(String presetId);
}
