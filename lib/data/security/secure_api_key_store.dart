/// Хранение ключей API в защищённом хранилище платформы (SPEC 3.4, A8.6).
///
/// Ключи никогда не попадают в БД, экспорт, логи и `generation_jobs`.
/// Android Auto Backup отключён в manifest (`allowBackup="false"`).
/// Имя ключа хранилища — `cardflow.api_key.<id аккаунта>`; legacy-имена
/// (`openai`, `gemini`, `anthropic`, `openai_compatible`) совпадают с id
/// аккаунтов, мигрируемых из старых настроек (ADR-020 §4).
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:cardflow/domain/generation/api_key_store.dart';

/// Узкий контракт safe-storage (для тестов и подмены платформы).
abstract interface class SecureKeyValueStore {
  /// Читает значение по ключу хранилища.
  Future<String?> read(String key);

  /// Записывает значение по ключу хранилища.
  Future<void> write(String key, String value);

  /// Удаляет значение по ключу хранилища.
  Future<void> delete(String key);
}

/// Реализация [SecureKeyValueStore] поверх `flutter_secure_storage`.
class FlutterSecureKeyValueStore implements SecureKeyValueStore {
  /// Создаёт обёртку; [storage] инжектируется в тестах.
  FlutterSecureKeyValueStore({FlutterSecureStorage? storage})
    : storage = storage ?? const FlutterSecureStorage();

  /// Плагин secure storage (инжектируется в тестах).
  final FlutterSecureStorage storage;

  @override
  Future<String?> read(String key) => storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => storage.delete(key: key);
}

/// Хранилище ключей API CardFlow в secure storage.
class SecureApiKeyStore implements ApiKeyStore {
  /// Создаёт хранилище поверх [store].
  SecureApiKeyStore(this.store);

  /// Бэкенд secure storage.
  final SecureKeyValueStore store;

  /// Ключ в secure storage для аккаунта [providerId].
  static String storageKey(String providerId) => 'cardflow.api_key.$providerId';

  @override
  Future<String?> read(String providerId) async {
    final value = await store.read(storageKey(providerId));
    if (value == null) return null;
    final normalized = value.trim();
    return normalized.isEmpty ? null : normalized;
  }

  @override
  Future<void> write(String providerId, String apiKey) {
    final normalized = apiKey.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(
        apiKey,
        'apiKey',
        'Ключ API не может быть пустым',
      );
    }
    return store.write(storageKey(providerId), normalized);
  }

  @override
  Future<void> delete(String providerId) =>
      store.delete(storageKey(providerId));
}
