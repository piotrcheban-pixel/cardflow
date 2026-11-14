/// Контракт хранения пользовательских настроек (SPEC A6.6, ADR-019).
///
/// Значение — одна строка `app_settings` с ключом `app.settings`; схема БД
/// не меняется. Ключи API здесь не хранятся (SPEC 3.4).
library;

import 'package:cardflow/domain/settings/app_settings.dart';

/// Хранилище настроек приложения.
abstract interface class AppSettingsStore {
  /// Читает настройки; если их нет или значение повреждено — значения
  /// по умолчанию ([AppSettings.defaults]).
  Future<AppSettings> read();

  /// Перезаписывает настройки одной строкой.
  Future<void> write(AppSettings settings);
}
