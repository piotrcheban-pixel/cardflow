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
  Future<String?> read(String key) {
    throw UnimplementedError('FlutterSecureKeyValueStore.read');
  }

  @override
  Future<void> write(String key, String value) {
    throw UnimplementedError('FlutterSecureKeyValueStore.write');
  }

  @override
  Future<void> delete(String key) {
    throw UnimplementedError('FlutterSecureKeyValueStore.delete');
  }
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
  Future<String?> read(GenerationProvider provider) {
    throw UnimplementedError('SecureApiKeyStore.read');
  }

  @override
  Future<void> write(GenerationProvider provider, String apiKey) {
    throw UnimplementedError('SecureApiKeyStore.write');
  }

  @override
  Future<void> delete(GenerationProvider provider) {
    throw UnimplementedError('SecureApiKeyStore.delete');
  }
}
