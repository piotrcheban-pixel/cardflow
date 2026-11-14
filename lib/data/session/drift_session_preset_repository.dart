// Drift-реализация пресетов конструктора (SPEC A5, A6.7, ADR-018).
//
// КРАСНАЯ ФАЗА итерации 6: заглушка контракта; чтение/запись ещё не
// реализованы — тесты падают по ожиданиям.
import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/domain/session/session_config.dart';
import 'package:cardflow/domain/session/session_preset.dart';
import 'package:cardflow/domain/session/session_preset_repository.dart';

/// Репозиторий пресетов поверх drift-БД (`session_presets`).
class DriftSessionPresetRepository implements SessionPresetRepository {
  /// Создаёт репозиторий поверх БД.
  DriftSessionPresetRepository(this.database);

  /// БД приложения.
  final AppDatabase database;

  @override
  Future<List<SessionPreset>> presets() async => const <SessionPreset>[];

  @override
  Future<SessionPreset> savePreset({
    required String name,
    required SessionConfig config,
    required DateTime createdAt,
  }) async {
    return SessionPreset(
      id: '',
      name: name,
      config: config,
      createdAt: createdAt,
    );
  }

  @override
  Future<void> deletePreset(String presetId) async {}
}
