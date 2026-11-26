import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/generation/drift_generation_job_repository.dart';
import 'package:cardflow/domain/generation/generation_error.dart';
import 'package:cardflow/domain/generation/generation_failure_reason.dart';
import 'package:cardflow/domain/generation/generation_job.dart';

void main() {
  late AppDatabase db;
  late DriftGenerationJobRepository repository;

  setUp(() {
    db = AppDatabase.inMemory();
    repository = DriftGenerationJobRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('save → jobById: все поля задания, включая имена файлов', () async {
    final created = DateTime.utc(2026, 11, 14, 10);
    final job = GenerationJob(
      id: 'job-1',
      status: GenerationJobStatus.running,
      createdAt: created,
      provider: 'openai',
      model: 'gpt-4o',
      promptVersion: 'gen-ru-v2',
      files: const <String>['лекция.docx', 'слайды.pptx'],
      chunkCount: 0,
    );
    await repository.save(job);

    final restored = await repository.jobById('job-1');
    expect(restored, isNotNull);
    expect(restored!.id, 'job-1');
    expect(restored.status, GenerationJobStatus.running);
    expect(restored.createdAt, created);
    expect(restored.provider, 'openai');
    expect(restored.model, 'gpt-4o');
    expect(restored.promptVersion, 'gen-ru-v2');
    expect(restored.files, <String>['лекция.docx', 'слайды.pptx']);
    expect(restored.chunkCount, 0);
  });

  test('повторный save обновляет статус, расход, счётчики и колоду', () async {
    final job = GenerationJob(
      id: 'job-1',
      status: GenerationJobStatus.running,
      createdAt: DateTime.utc(2026),
      files: const <String>['a.txt'],
    );
    await repository.save(job);
    await repository.save(
      job.copyWith(
        status: GenerationJobStatus.done,
        tokensUsed: 123,
        cardsCount: 4,
        chunkCount: 2,
        resultDeckId: 'deck-1',
      ),
    );

    final restored = (await repository.jobById('job-1'))!;
    expect(restored.status, GenerationJobStatus.done);
    expect(restored.tokensUsed, 123);
    expect(restored.cardsCount, 4);
    expect(restored.chunkCount, 2);
    expect(restored.resultDeckId, 'deck-1');
    expect(restored.files, <String>['a.txt']);
  });

  test('несуществующее задание — null', () async {
    expect(await repository.jobById('нет'), isNull);
  });

  test('частичный успех и ошибки сохраняются машинным кодом', () async {
    final job = GenerationJob(
      id: 'job-1',
      status: GenerationJobStatus.partial,
      createdAt: DateTime.utc(2026),
      errorCode: 'network',
      files: const <String>[],
    );
    await repository.save(job);
    final restored = (await repository.jobById('job-1'))!;
    expect(restored.status, GenerationJobStatus.partial);
    expect(restored.errorCode, 'network');
    expect(restored.files, isEmpty);
  });

  test(
    'сбой БД — GenerationException(storageUnavailable), не сырое исключение',
    () async {
      // Итерация «Диагностика и фикс пайплайна генерации»: недоступная БД
      // раньше доходила до UI произвольным исключением и общей строкой
      // «Не удалось получить карточки». Настоящая readonly-БД воспроизводит
      // SQLITE_READONLY без моков.
      final Directory dir = Directory.systemTemp.createTempSync(
        'cardflow_jobs_readonly_',
      );
      final File file = File('${dir.path}${Platform.pathSeparator}jobs.sqlite');
      addTearDown(() {
        if (dir.existsSync()) dir.deleteSync(recursive: true);
      });
      final AppDatabase seed = AppDatabase(NativeDatabase(file));
      await seed.select(seed.generationJobs).get();
      await seed.close();

      final Database readOnly = sqlite3.open(
        file.path,
        mode: OpenMode.readOnly,
      );
      final AppDatabase readOnlyDb = AppDatabase(
        NativeDatabase.opened(readOnly),
      );
      final DriftGenerationJobRepository readOnlyRepository =
          DriftGenerationJobRepository(readOnlyDb);
      addTearDown(() async {
        await readOnlyDb.close();
      });

      final job = GenerationJob(
        id: 'job-storage',
        status: GenerationJobStatus.running,
        createdAt: DateTime.utc(2026),
      );
      Object? saveError;
      try {
        await readOnlyRepository.save(job);
      } on Object catch (error) {
        saveError = error;
      }

      expect(saveError, isA<GenerationException>());
      final GenerationException failure = saveError! as GenerationException;
      expect(failure.code, GenerationErrorCode.storageUnavailable);
      expect(failure.reason, GenerationFailureReason.storage);
      // details — только для логов, без ключей и текстов материалов.
      expect(failure.details, isNotNull);
      expect(failure.details, contains('readonly'));
      expect(failure.details, isNot(contains('sk-')));
    },
  );
}
