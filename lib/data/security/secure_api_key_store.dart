/// Хранение ключей API в защищённом хранилище платформы (SPEC 3.4, A8.6).
///
/// Ключи никогда не попадают в БД, экспорт, логи и `generation_jobs`.
/// Android Auto Backup отключён в manifest (`allowBackup="false"`).
library;

import 'package:flutter_secure_storage/flutter_secure_storage.dart';

import 'package:cardflow/domain/generation/api_key_store.dart';
import 'package:cardflow/domain/generation/generation_provider.dart';

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

  /// Ключ в secure storage для [provider].
  static String storageKey(GenerationProvider provider) =>
      'cardflow.api_key.${provider.wireName}';

  @override
  Future<String?> read(GenerationProvider provider) async {
    final value = await store.read(storageKey(provider));
    if (value == null) return null;
    final normalized = value.trim();
    return normalized.isEmpty ? null : normalized;
  }

  @override
  Future<void> write(GenerationProvider provider, String apiKey) {
    final normalized = apiKey.trim();
    if (normalized.isEmpty) {
      throw ArgumentError.value(
        apiKey,
        'apiKey',
        'Ключ API не может быть пустым',
      );
    }
    return store.write(storageKey(provider), normalized);
  }

  @override
  Future<void> delete(GenerationProvider provider) =>
      store.delete(storageKey(provider));
}
