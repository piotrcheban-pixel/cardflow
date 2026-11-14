import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'package:cardflow/data/security/secure_api_key_store.dart';

/// Диагностика D3 итерации 7.5 (L28): реальное платформенное хранилище.
///
/// На Windows `flutter_secure_storage` шифрует значения DPAPI и пишет их в
/// файл `flutter_secure_storage.dat`; в обычном `flutter test` плагин не
/// зарегистрирован, поэтому здесь проверяется именно живой путь плагина:
/// запись → чтение → совпадение значения → удаление.
///
/// Запуск (только Windows-хост, в CI не входит):
///   fvm flutter test integration_test/secure_api_key_store_windows_test.dart -d windows
/// Значение пробного ключа не является настоящим секретом: это маркер
/// round-trip, он удаляется в tearDown.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('реальный secure storage: запись → чтение → удаление', (
    WidgetTester tester,
  ) async {
    final SecureApiKeyStore store = SecureApiKeyStore(
      FlutterSecureKeyValueStore(),
    );
    const String probeId = 'integration_probe';
    const String probeKey = 'cf-integration-probe-1';

    addTearDown(() => store.delete(probeId));

    expect(await store.read(probeId), isNull);

    await store.write(probeId, probeKey);
    final String? stored = await store.read(probeId);
    expect(
      stored,
      probeKey,
      reason:
          'ожидалось: ключ сохранён и прочитан (DPAPI/wincred), '
          'получено: $stored',
    );

    // Второй аккаунт не пересекается с первым.
    await store.write('${probeId}_2', 'cf-integration-probe-2');
    expect(await store.read(probeId), probeKey);
    expect(await store.read('${probeId}_2'), 'cf-integration-probe-2');
    await store.delete('${probeId}_2');

    await store.delete(probeId);
    expect(await store.read(probeId), isNull);
  });
}
