import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/generation/drift_generation_settings_store.dart';
import 'package:cardflow/domain/generation/openai_compatible_settings.dart';

/// Репозиторий настроек OpenAI-совместимого сервера поверх `app_settings`
/// (SPEC A5, ADR-013). Ключ API в БД не пишется.
void main() {
  late AppDatabase db;
  late DriftGenerationSettingsStore store;

  setUp(() {
    db = AppDatabase.inMemory();
    store = DriftGenerationSettingsStore(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('по умолчанию — пустые настройки', () async {
    final settings = await store.readOpenAiCompatible();
    expect(settings, const OpenAiCompatibleSettings());
  });

  test('write → read: адрес и модель сохраняются и перезаписываются', () async {
    const settings = OpenAiCompatibleSettings(
      baseUrl: 'http://localhost:11434/v1',
      model: 'qwen2.5',
    );
    await store.writeOpenAiCompatible(settings);
    expect(await store.readOpenAiCompatible(), settings);

    const updated = OpenAiCompatibleSettings(
      baseUrl: 'https://api.deepseek.com',
      model: 'deepseek-chat',
    );
    await store.writeOpenAiCompatible(updated);
    expect(await store.readOpenAiCompatible(), updated);

    final rows = await db.select(db.appSettings).get();
    expect(rows, hasLength(1));
    expect(rows.single.key, 'generation.openai_compatible');
    final decoded = jsonDecode(rows.single.valueJson) as Map<String, Object?>;
    expect(decoded.keys.toSet(), <String>{'baseUrl', 'model'});
    expect(jsonEncode(decoded), isNot(contains('apiKey')));
  });

  test(
    'битый JSON в строке настроек — пустые настройки, без исключения',
    () async {
      await db
          .into(db.appSettings)
          .insert(
            AppSettingsCompanion.insert(
              key: 'generation.openai_compatible',
              valueJson: 'не json',
            ),
          );

      expect(
        await store.readOpenAiCompatible(),
        const OpenAiCompatibleSettings(),
      );
    },
  );

  test('JSON-объект с нестроковыми полями — терпим, поля пустые', () async {
    await db
        .into(db.appSettings)
        .insert(
          AppSettingsCompanion.insert(
            key: 'generation.openai_compatible',
            valueJson: '{"baseUrl": 1, "model": null}',
          ),
        );

    expect(
      await store.readOpenAiCompatible(),
      const OpenAiCompatibleSettings(),
    );
  });
}
