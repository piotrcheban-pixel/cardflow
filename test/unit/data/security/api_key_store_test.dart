import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:cardflow/data/security/secure_api_key_store.dart';

class _MockFlutterSecureStorage extends Mock implements FlutterSecureStorage {}

/// In-memory реализация узкого контракта secure storage.
class _FakeSecureKeyValueStore implements SecureKeyValueStore {
  final Map<String, String> values = <String, String>{};
  final List<String> deleted = <String>[];
  final List<String> written = <String>[];

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    written.add(key);
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    deleted.add(key);
    values.remove(key);
  }
}

/// Итерация 3b + 7.5 (ADR-020): ключи API только в secure storage (SPEC 3.4).
///
/// Диагностика D3 итерации 7.5: «запись → чтение → значение совпадает» — этот
/// контракт проверяется здесь и Windows-integration-тестом на реальном
/// плагине (`integration_test/secure_api_key_store_windows_test.dart`).
void main() {
  group('SecureApiKeyStore', () {
    test('ключ хранилища — cardflow.api_key.<id аккаунта>', () {
      expect(
        SecureApiKeyStore.storageKey('deepseek'),
        'cardflow.api_key.deepseek',
      );
      expect(SecureApiKeyStore.storageKey('openai'), 'cardflow.api_key.openai');
      expect(
        SecureApiKeyStore.storageKey('openai_compatible'),
        'cardflow.api_key.openai_compatible',
        reason: 'id мигрируемого legacy-аккаунта совпадает со старой записью',
      );
    });

    test('запись → чтение → значение совпадает (round-trip)', () async {
      final backend = _FakeSecureKeyValueStore();
      final store = SecureApiKeyStore(backend);

      expect(await store.read('deepseek'), isNull);

      await store.write('deepseek', 'sk-deepseek-key');
      final String? stored = await store.read('deepseek');

      expect(stored, 'sk-deepseek-key');
      expect(stored, equals('sk-deepseek-key'));
      expect(backend.values, <String, String>{
        'cardflow.api_key.deepseek': 'sk-deepseek-key',
      });
    });

    test('write → read → delete по аккаунту', () async {
      final backend = _FakeSecureKeyValueStore();
      final store = SecureApiKeyStore(backend);

      await store.write('openai', 'test-key-123');
      expect(await store.read('openai'), 'test-key-123');
      expect(backend.values, <String, String>{
        'cardflow.api_key.openai': 'test-key-123',
      });

      await store.delete('openai');
      expect(await store.read('openai'), isNull);
      expect(backend.deleted, <String>['cardflow.api_key.openai']);
    });

    test('перезапись заменяет значение', () async {
      final store = SecureApiKeyStore(_FakeSecureKeyValueStore());
      await store.write('deepseek', 'old');
      await store.write('deepseek', 'new');
      expect(await store.read('deepseek'), 'new');
    });

    test('ключи аккаунтов независимы', () async {
      final backend = _FakeSecureKeyValueStore();
      final store = SecureApiKeyStore(backend);
      await store.write('openai', 'key-openai');
      await store.write('gemini', 'key-gemini');
      await store.write('gemini-2', 'key-gemini-2');

      expect(await store.read('openai'), 'key-openai');
      expect(await store.read('gemini'), 'key-gemini');
      expect(await store.read('gemini-2'), 'key-gemini-2');
      await store.delete('gemini');
      expect(await store.read('openai'), 'key-openai');
      expect(await store.read('gemini'), isNull);
      expect(await store.read('gemini-2'), 'key-gemini-2');
    });

    test('ключ с пробелами по краям нормализуется', () async {
      final backend = _FakeSecureKeyValueStore();
      final store = SecureApiKeyStore(backend);
      await store.write('deepseek', '  sk-key  ');
      expect(await store.read('deepseek'), 'sk-key');
      expect(backend.values['cardflow.api_key.deepseek'], 'sk-key');
    });

    test('пустой ключ не записывается (ArgumentError)', () async {
      final store = SecureApiKeyStore(_FakeSecureKeyValueStore());
      for (final value in <String>['', '   ']) {
        expect(() => store.write('deepseek', value), throwsArgumentError);
      }
    });

    test('пустая строка из хранилища читается как отсутствие ключа', () async {
      final backend = _FakeSecureKeyValueStore()
        ..values['cardflow.api_key.openai'] = '   ';
      final store = SecureApiKeyStore(backend);
      expect(await store.read('openai'), isNull);
    });
  });

  group('FlutterSecureKeyValueStore', () {
    test('делегирует read/write/delete плагину', () async {
      final storage = _MockFlutterSecureStorage();
      final store = FlutterSecureKeyValueStore(storage: storage);

      when(() => storage.read(key: any(named: 'key'))).thenAnswer(
        (invocation) async =>
            invocation.namedArguments[#key] == 'k' ? 'v' : null,
      );
      when(
        () => storage.write(
          key: any(named: 'key'),
          value: any(named: 'value'),
        ),
      ).thenAnswer((_) async {});
      when(() => storage.delete(key: any(named: 'key')))
          .thenAnswer((_) async {});

      expect(await store.read('k'), 'v');
      await store.write('k', 'v2');
      await store.delete('k');

      verify(() => storage.read(key: 'k')).called(1);
      verify(() => storage.write(key: 'k', value: 'v2')).called(1);
      verify(() => storage.delete(key: 'k')).called(1);
    });
  });
}
