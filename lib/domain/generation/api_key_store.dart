/// Контракт хранилища ключей API (SPEC 3.4, A8.6).
///
/// Ключи хранятся только в защищённом хранилище платформы
/// (`flutter_secure_storage`); реализация — `lib/data/security/`.
library;

import 'package:cardflow/domain/generation/generation_provider.dart';

/// Хранилище ключей API по провайдерам.
abstract interface class ApiKeyStore {
  /// Возвращает ключ провайдера или `null`, если ключ не задан.
  Future<String?> read(GenerationProvider provider);

  /// Сохраняет ключ провайдера.
  Future<void> write(GenerationProvider provider, String apiKey);

  /// Удаляет ключ провайдера.
  Future<void> delete(GenerationProvider provider);
}
