import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/domain/generation/generation_job.dart';

void main() {
  test('статусы задания: wire-имена SPEC A5', () {
    expect(GenerationJobStatus.running.wireName, 'running');
    expect(GenerationJobStatus.done.wireName, 'done');
    expect(GenerationJobStatus.partial.wireName, 'partial');
    expect(GenerationJobStatus.error.wireName, 'error');
    expect(GenerationJobStatus.cancelled.wireName, 'cancelled');
  });

  test('fromWire разбирает статусы и бросает FormatException на мусоре', () {
    expect(
      GenerationJobStatus.fromWire('partial'),
      GenerationJobStatus.partial,
    );
    expect(
      () => GenerationJobStatus.fromWire('unknown'),
      throwsFormatException,
    );
  });

  test('copyWith меняет только заданные поля и сохраняет id/createdAt', () {
    final created = DateTime.utc(2026, 11, 14, 10);
    final job = GenerationJob(
      id: 'job-1',
      status: GenerationJobStatus.running,
      createdAt: created,
      provider: 'openai',
      model: 'gpt-4o',
      files: const <String>['a.txt'],
    );
    final updated = job.copyWith(
      status: GenerationJobStatus.partial,
      tokensUsed: 30,
      chunkCount: 2,
      cardsCount: 5,
      errorCode: 'network',
    );
    expect(updated.id, 'job-1');
    expect(updated.createdAt, created);
    expect(updated.status, GenerationJobStatus.partial);
    expect(updated.provider, 'openai');
    expect(updated.model, 'gpt-4o');
    expect(updated.tokensUsed, 30);
    expect(updated.chunkCount, 2);
    expect(updated.cardsCount, 5);
    expect(updated.errorCode, 'network');
    expect(updated.files, <String>['a.txt']);
  });

  test('новое задание не хранит материалы/ключи — только имена файлов', () {
    final job = GenerationJob(
      id: 'job-1',
      status: GenerationJobStatus.running,
      createdAt: DateTime.utc(2026),
      files: const <String>['лекция.docx', 'слайды.pptx'],
    );
    expect(job.files, <String>['лекция.docx', 'слайды.pptx']);
    expect(
      job.toString(),
      isNot(contains('sk-')),
      reason: 'toString не должен содержать секретов',
    );
  });
}
