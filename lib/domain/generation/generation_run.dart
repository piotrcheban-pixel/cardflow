/// Модели запуска пайплайна генерации (SPEC A8.5, ADR-015, ADR-020).
///
/// Домен не зависит от Flutter, Dio и БД: отмена и HTTP-транспорт живут в
/// `lib/api/generation/`.
library;

import 'package:cardflow/domain/generation/generated_card.dart';
import 'package:cardflow/domain/generation/generation_attachment.dart';
import 'package:cardflow/domain/generation/generation_error.dart';
import 'package:cardflow/domain/generation/generation_job.dart';
import 'package:cardflow/domain/generation/provider_account.dart';
import 'package:cardflow/domain/text/parsed_document.dart';

/// Запрос на генерацию карточек из разобранных документов.
class GenerationRunRequest {
  /// Создаёт запрос.
  const GenerationRunRequest({
    required this.documents,
    required this.account,
    required this.deckName,
    this.wishes,
    this.targetDeckId,
    this.images = const <GenerationAttachment>[],
  });

  /// Разобранные документы (порядок прикрепления).
  final List<ParsedDocument> documents;

  /// Изображения и PDF-сканы (порядок прикрепления).
  final List<GenerationAttachment> images;

  /// Провайдер: протокол, адрес, модель и id ключа (ADR-020).
  final ProviderAccount account;

  /// Имя колоды (при `targetDeckId == null` — имя новой колоды).
  final String deckName;

  /// Необязательные пожелания по содержанию.
  final String? wishes;

  /// Существующая колода; `null` — создать новую.
  final String? targetDeckId;
}

/// Фаза прогресса генерации.
enum GenerationProgressPhase {
  /// Нарезка материалов.
  chunking,

  /// Отправка фрагмента.
  sending,

  /// Получение и разбор ответа.
  receiving,
}

/// Прогресс генерации для UI.
class GenerationProgress {
  /// Создаёт прогресс.
  const GenerationProgress({
    required this.phase,
    this.chunkIndex,
    this.chunkCount,
  });

  /// Фаза.
  final GenerationProgressPhase phase;

  /// Номер текущего фрагмента (с 1).
  final int? chunkIndex;

  /// Всего фрагментов.
  final int? chunkCount;
}

/// Колбэк прогресса.
typedef GenerationProgressCallback = void Function(GenerationProgress progress);

/// Ошибка одного фрагмента (частичный успех, A6.8).
class GenerationChunkFailure {
  /// Создаёт ошибку фрагмента.
  const GenerationChunkFailure({
    required this.chunkIndex,
    required this.code,
    required this.materialsText,
    required this.limit,
    this.sourceFiles = const <String>[],
    this.retryable = true,
    this.splitAttempted = false,
    this.providerReason,
    this.images = const <GenerationAttachment>[],
  });

  /// Номер фрагмента (с 1).
  final int chunkIndex;

  /// Код ошибки.
  final GenerationErrorCode code;

  /// Текст фрагмента для повтора (в UI не показывается).
  final String materialsText;

  /// Лимит карточек фрагмента для повтора.
  final int limit;

  /// Имена файлов фрагмента.
  final List<String> sourceFiles;

  /// Можно ли повторить фрагмент кнопкой «Повторить неудавшиеся».
  final bool retryable;

  /// Фрагмент уже дробился до этой ошибки (повтор не должен дробить снова
  /// без нового разрешения A8.5 шаг 8).
  final bool splitAttempted;

  /// Безопасная причина отказа провайдера (HTTP 400) для сообщения UI.
  final String? providerReason;

  /// Вложения фрагмента (для повтора image-запроса).
  final List<GenerationAttachment> images;
}

/// Результат генерации (он же данные предпросмотра).
class GenerationRunResult {
  /// Создаёт результат.
  const GenerationRunResult({
    required this.jobId,
    required this.status,
    required this.cards,
    required this.failures,
    required this.tokensUsed,
    required this.estimatedTokens,
    required this.duplicatesRemoved,
    required this.chunkCount,
    required this.cancelled,
    this.fatalErrorCode,
    this.fatalProviderReason,
  });

  /// Идентификатор задания `generation_jobs`.
  final String jobId;

  /// Итоговый статус задания.
  final GenerationJobStatus status;

  /// Полученные карточки (дедуплицированные, в порядке ответов).
  final List<GeneratedCard> cards;

  /// Ошибки фрагментов.
  final List<GenerationChunkFailure> failures;

  /// Фактический расход токенов.
  final int tokensUsed;

  /// Оценка до отправки (для UI).
  final int estimatedTokens;

  /// Сколько дублей отсеяно.
  final int duplicatesRemoved;

  /// Сколько фрагментов обработано.
  final int chunkCount;

  /// Пользователь отменил генерацию.
  final bool cancelled;

  /// Fatal-код, после которого пайплайн остановился, но карточки уже получены
  /// (например, ключ отозван после первого фрагмента). Сообщение показывается
  /// пользователю, предпросмотр остаётся доступным.
  final GenerationErrorCode? fatalErrorCode;

  /// Безопасная причина отказа провайдера для [fatalErrorCode].
  final String? fatalProviderReason;
}
