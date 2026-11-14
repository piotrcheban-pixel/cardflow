/// Задание генерации карточек (SPEC A5 `generation_jobs`, A8.5 шаг 12, ADR-015).
///
/// Задание не хранит материалы и ключи: только имена файлов и машинные коды.
/// Домен не зависит от Flutter и БД.
library;

/// Статус задания генерации.
enum GenerationJobStatus {
  /// Идёт генерация.
  running('running'),

  /// Все фрагменты обработаны без ошибок.
  done('done'),

  /// Часть фрагментов упала, но карточки получены.
  partial('partial'),

  /// Карточек нет, задание завершилось ошибкой.
  error('error'),

  /// Пользователь отменил генерацию.
  cancelled('cancelled');

  const GenerationJobStatus(this.wireName);

  /// Имя в БД (`generation_jobs.status`).
  final String wireName;

  /// Разбирает статус из строки БД.
  static GenerationJobStatus fromWire(String value) {
    for (final status in values) {
      if (status.wireName == value) return status;
    }
    throw FormatException('Неизвестный статус задания: $value');
  }
}

/// Неизменяемое задание генерации.
class GenerationJob {
  /// Создаёт задание.
  const GenerationJob({
    required this.id,
    required this.status,
    required this.createdAt,
    this.provider,
    this.model,
    this.tokensUsed,
    this.promptVersion,
    this.errorCode,
    this.cardsCount,
    this.chunkCount,
    this.files = const <String>[],
    this.resultDeckId,
  });

  /// Идентификатор задания.
  final String id;

  /// Статус.
  final GenerationJobStatus status;

  /// Момент создания.
  final DateTime createdAt;

  /// Провайдер (`GenerationProvider.wireName`).
  final String? provider;

  /// Модель.
  final String? model;

  /// Израсходовано токенов.
  final int? tokensUsed;

  /// Версия системного промпта.
  final String? promptVersion;

  /// Машинный код ошибки (`GenerationErrorCode.name`).
  final String? errorCode;

  /// Сколько карточек получено (логических, до разворота reversed).
  final int? cardsCount;

  /// Сколько фрагментов обработано.
  final int? chunkCount;

  /// Имена прикреплённых файлов (не материалы).
  final List<String> files;

  /// Колода, в которую импортированы карточки.
  final String? resultDeckId;

  /// Копия с изменёнными полями.
  ///
  /// [clearErrorCode] сбрасывает `error_code` в `null` (нужно после успешного
  /// повтора упавших фрагментов).
  GenerationJob copyWith({
    GenerationJobStatus? status,
    String? provider,
    String? model,
    int? tokensUsed,
    String? promptVersion,
    String? errorCode,
    bool clearErrorCode = false,
    int? cardsCount,
    int? chunkCount,
    List<String>? files,
    String? resultDeckId,
  }) {
    return GenerationJob(
      id: id,
      status: status ?? this.status,
      createdAt: createdAt,
      provider: provider ?? this.provider,
      model: model ?? this.model,
      tokensUsed: tokensUsed ?? this.tokensUsed,
      promptVersion: promptVersion ?? this.promptVersion,
      errorCode: clearErrorCode ? null : (errorCode ?? this.errorCode),
      cardsCount: cardsCount ?? this.cardsCount,
      chunkCount: chunkCount ?? this.chunkCount,
      files: files ?? this.files,
      resultDeckId: resultDeckId ?? this.resultDeckId,
    );
  }
}

/// Хранилище заданий генерации.
abstract interface class GenerationJobRepository {
  /// Создаёт или обновляет задание.
  Future<void> save(GenerationJob job);

  /// Задание по id; `null` — не найдено.
  Future<GenerationJob?> jobById(String id);
}
