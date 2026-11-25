/// Причины отказа записи пользовательских настроек (ADR-047).
///
/// Контракт хранения ([AppSettingsStore.write]) бросает
/// [AppSettingsWriteException]; UI маппит [AppSettingsWriteFailure] в строку
/// ARB. Текст исключения (drift/SQLite/`dart:io`) пользователю не показывается.
library;

/// Причина отказа записи настроек.
enum AppSettingsWriteFailure {
  /// Операционная система запретила запись в каталог данных приложения:
  /// `SQLITE_READONLY` (код 8), «attempt to write a readonly database»,
  /// отказ доступа к файлу. Лечится не повтором, а правами на папку.
  writeDenied,

  /// Прочие ошибки записи (неизвестная причина) — общая строка ARB.
  unknown,
}

/// Ошибка записи настроек с машинной причиной.
class AppSettingsWriteException implements Exception {
  /// Создаёт ошибку с причиной [failure].
  const AppSettingsWriteException(this.failure, {this.details});

  /// Причина для маппинга в UI.
  final AppSettingsWriteFailure failure;

  /// Технические детали для логов/тестов (пользователю не показываются).
  final String? details;

  @override
  String toString() =>
      'AppSettingsWriteException(${failure.name}): $details';
}

/// Классифицирует ошибку записи настроек (заглушка красной фазы).
AppSettingsWriteFailure classifyAppSettingsWriteFailure(Object error) {
  return AppSettingsWriteFailure.unknown;
}
