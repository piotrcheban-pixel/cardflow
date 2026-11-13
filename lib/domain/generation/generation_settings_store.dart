/// Контракт настроек OpenAI-совместимого сервера (ADR-013).
///
/// Адрес и модель хранятся в `app_settings` (SPEC A5); ключ API — отдельно,
/// только в `ApiKeyStore` (secure storage, SPEC 3.4).
library;

import 'package:cardflow/domain/generation/openai_compatible_settings.dart';

/// Хранилище настроек OpenAI-совместимого сервера.
abstract interface class GenerationSettingsStore {
  /// Читает настройки; если они не заданы/повреждены — пустые значения.
  Future<OpenAiCompatibleSettings> readOpenAiCompatible();

  /// Сохраняет настройки (перезапись единственной записи).
  Future<void> writeOpenAiCompatible(OpenAiCompatibleSettings settings);
}
