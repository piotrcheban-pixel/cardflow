import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/generation/drift_generation_job_repository.dart';
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
}
