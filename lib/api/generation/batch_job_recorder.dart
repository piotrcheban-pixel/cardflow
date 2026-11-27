/// Запись версии промпта в задание генерации (DoD среза 5).
///
/// Версия системного промпта — часть контракта ответа: `generation_jobs`
/// хранит её в `prompt_version` (SPEC A5). Новый путь генерации пишет туда
/// `gen-cards-v3` до первого запроса, поэтому по журналу видно, каким
/// промптом получены карточки (и не спутать с прежним `gen-ru-v9`).
///
/// Статус задания здесь **не меняется** (`partial`/`done` — этап Completion,
/// `docs/generation/BACKLOG.md` S9).
library;

import 'package:cardflow/api/prompts/cards_prompt.dart';
import 'package:cardflow/domain/generation/generation_job.dart';

/// Пишет версию промпта этапа Generation в существующее задание.
class BatchJobRecorder {
  /// Создаёт рекордер.
  const BatchJobRecorder({
    required this.repository,
    this.promptVersion = cardsPromptVersion,
  });

  /// Хранилище заданий (`generation_jobs`).
  final GenerationJobRepository repository;

  /// Версия промпта, которая пойдёт в `prompt_version`.
  final String promptVersion;

  /// Записывает [promptVersion] в задание [jobId]; `null` — задания нет.
  ///
  /// Задание читается целиком и сохраняется изменённой копией: остальные поля
  /// (провайдер, модель, файлы) не перезаписываются.
  Future<GenerationJob?> record(String jobId) async {
    final GenerationJob? job = await repository.jobById(jobId);
    if (job == null) return null;
    final GenerationJob updated = job.copyWith(promptVersion: promptVersion);
    await repository.save(updated);
    return updated;
  }
}
