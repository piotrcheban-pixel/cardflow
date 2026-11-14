/// Drift-репозиторий заданий генерации (SPEC A5 `generation_jobs`, ADR-015).
library;

import 'dart:convert';

import 'package:drift/drift.dart';

import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/db/epoch.dart';
import 'package:cardflow/domain/generation/generation_job.dart';

/// Хранилище заданий поверх drift-БД.
///
/// `generation_jobs` обновляется на каждом шаге пайплайна (A8.5 шаг 12):
/// `files_json` содержит **только имена** файлов, материалы и ключи сюда не
/// попадают (SPEC 3.4/A8.6).
class DriftGenerationJobRepository implements GenerationJobRepository {
  /// Создаёт репозиторий поверх БД.
  DriftGenerationJobRepository(this.database);

  /// БД приложения.
  final AppDatabase database;

  @override
  Future<void> save(GenerationJob job) async {
    await database
        .into(database.generationJobs)
        .insertOnConflictUpdate(
          GenerationJobsCompanion.insert(
            id: job.id,
            status: job.status.wireName,
            createdAt: toEpochMs(job.createdAt),
            provider: Value<String?>(job.provider),
            model: Value<String?>(job.model),
            tokensUsed: Value<int?>(job.tokensUsed),
            promptVersion: Value<String?>(job.promptVersion),
            errorCode: Value<String?>(job.errorCode),
            cardsCount: Value<int?>(job.cardsCount),
            chunkCount: Value<int?>(job.chunkCount),
            filesJson: Value<String?>(
              job.files.isEmpty ? null : jsonEncode(job.files),
            ),
            resultDeckId: Value<String?>(job.resultDeckId),
          ),
        );
  }

  @override
  Future<GenerationJob?> jobById(String id) async {
    final GenerationJobRow? row = await (database.select(
      database.generationJobs,
    )..where((table) => table.id.equals(id))).getSingleOrNull();
    if (row == null) return null;
    return GenerationJob(
      id: row.id,
      status: GenerationJobStatus.fromWire(row.status),
      createdAt: fromEpochMs(row.createdAt),
      provider: row.provider,
      model: row.model,
      tokensUsed: row.tokensUsed,
      promptVersion: row.promptVersion,
      errorCode: row.errorCode,
      cardsCount: row.cardsCount,
      chunkCount: row.chunkCount,
      files: _decodeFiles(row.filesJson),
      resultDeckId: row.resultDeckId,
    );
  }

  /// Имена файлов из `files_json`; пусто/битое значение — пустой список.
  List<String> _decodeFiles(String? raw) {
    if (raw == null || raw.isEmpty) return const <String>[];
    try {
      final Object? decoded = jsonDecode(raw);
      if (decoded is! List) return const <String>[];
      return <String>[
        for (final Object? value in decoded)
          if (value is String) value,
      ];
    } on FormatException {
      return const <String>[];
    }
  }
}
