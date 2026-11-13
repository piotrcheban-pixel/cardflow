import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:cardflow/data/security/secure_api_key_store.dart';
import 'package:cardflow/domain/generation/generation_provider.dart';

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

/// Красная фаза итерации 3b: ключи API только в secure storage (SPEC 3.4).
void main() {
  group('SecureApiKeyStore', () {
    test('ключи хранилища — по провайдеру', () {
      expect(
        SecureApiKeyStore.storageKey(GenerationProvider.openai),
        'cardflow.api_key.openai',
      );
      expect(
        SecureApiKeyStore.storageKey(GenerationProvider.gemini),
        'cardflow.api_key.gemini',
      );
      expect(
        SecureApiKeyStore.storageKey(GenerationProvider.anthropic),
        'cardflow.api_key.anthropic',
      );
    });

    test('write → read → delete по провайдеру', () async {
      final backend = _FakeSecureKeyValueStore();
      final store = SecureApiKeyStore(backend);

      expect(await store.read(GenerationProvider.openai), isNull);
      await store.write(GenerationProvider.openai, 'test-key-123');
      expect(await store.read(GenerationProvider.openai), 'test-key-123');
      expect(backend.values, <String, String>{
        'cardflow.api_key.openai': 'test-key-123',
      });

      await store.delete(GenerationProvider.openai);
      expect(await store.read(GenerationProvider.openai), isNull);
      expect(backend.deleted, <String>['cardflow.api_key.openai']);
    });

    test('ключи провайдеров независимы', () async {
      final backend = _FakeSecureKeyValueStore();
      final store = SecureApiKeyStore(backend);
      await store.write(GenerationProvider.openai, 'key-openai');
      await store.write(GenerationProvider.gemini, 'key-gemini');
      await store.write(GenerationProvider.anthropic, 'key-anthropic');

      expect(await store.read(GenerationProvider.openai), 'key-openai');
      expect(await store.read(GenerationProvider.gemini), 'key-gemini');
      expect(await store.read(GenerationProvider.anthropic), 'key-anthropic');
    });

    test('пустой ключ не записывается (ArgumentError)', () async {
      final store = SecureApiKeyStore(_FakeSecureKeyValueStore());
      for (final value in <String>['', '   ']) {
        expect(
          () => store.write(GenerationProvider.openai, value),
          throwsArgumentError,
        );
      }
    });

    test('пустая строка из хранилища читается как отсутствие ключа', () async {
      final backend = _FakeSecureKeyValueStore()
        ..values['cardflow.api_key.openai'] = '   ';
      final store = SecureApiKeyStore(backend);
      expect(await store.read(GenerationProvider.openai), isNull);
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
