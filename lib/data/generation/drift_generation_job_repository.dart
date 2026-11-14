/// Drift-репозиторий заданий генерации (SPEC A5 `generation_jobs`, ADR-015).
library;

import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/domain/generation/generation_job.dart';

/// Хранилище заданий поверх drift-БД.
class DriftGenerationJobRepository implements GenerationJobRepository {
  /// Создаёт репозиторий поверх БД.
  DriftGenerationJobRepository(this.database);

  /// БД приложения.
  final AppDatabase database;

  @override
  Future<void> save(GenerationJob job) {
    throw UnimplementedError('DriftGenerationJobRepository.save');
  }

  @override
  Future<GenerationJob?> jobById(String id) {
    throw UnimplementedError('DriftGenerationJobRepository.jobById');
  }
}
