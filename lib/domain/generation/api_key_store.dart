/// Контракт хранилища ключей API (SPEC 3.4, A8.6, ADR-020).
///
/// Ключ хранится по идентификатору аккаунта провайдера
/// (`ProviderAccount.id`), а не по enum протокола: у пользователя может быть
/// несколько аккаунтов одного протокола (два ключа DeepSeek, OpenAI и т.п.).
/// Реализация — `lib/data/security/` поверх `flutter_secure_storage`.
library;

/// Хранилище ключей API по аккаунтам провайдеров.
abstract interface class ApiKeyStore {
  /// Возвращает ключ аккаунта или `null`, если ключ не задан.
  Future<String?> read(String providerId);

  /// Сохраняет ключ аккаунта.
  Future<void> write(String providerId, String apiKey);

  /// Удаляет ключ аккаунта.
  Future<void> delete(String providerId);
}
