import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/generation/drift_token_calibration_store.dart';
import 'package:cardflow/domain/generation/token_calibration.dart';

/// Калибровка `tokensPerCard` в `generation.calibration` (ADR-040 §9).
void main() {
  late AppDatabase db;
  late DriftTokenCalibrationStore store;
  final DateTime now = DateTime.utc(2026, 11, 20, 12);

  setUp(() {
    db = AppDatabase.inMemory();
    store = DriftTokenCalibrationStore(db, now: () => now);
  });

  tearDown(() async {
    await db.close();
  });

  test('пустое хранилище — нет калибровки', () async {
    expect(await store.readAll(), isEmpty);
    expect(
      await store.read(accountId: 'deepseek', model: 'deepseek-flash'),
      isNull,
    );
  });

  test('первый замер запоминается, но не применяется', () async {
    final TokenCalibration first = await store.record(
      accountId: 'deepseek',
      model: 'deepseek-flash',
      observedTokensPerCard: 400,
    );
    expect(first.samples, 1);
    expect(first.isApplicable, isFalse);
    expect(first.tokensPerCard, 400);
    expect(first.updatedAt, now);
  });

  test('после двух замеров — EMA и применение', () async {
    await store.record(
      accountId: 'deepseek',
      model: 'deepseek-flash',
      observedTokensPerCard: 400,
    );
    final TokenCalibration second = await store.record(
      accountId: 'deepseek',
      model: 'deepseek-flash',
      observedTokensPerCard: 200,
    );
    expect(second.samples, 2);
    expect(second.isApplicable, isTrue);
    expect(
      second.tokensPerCard,
      closeTo(400 * 0.7 + 200 * 0.3, 1e-9),
      reason: 'EMA с весом нового замера 0.3',
    );
  });

  test('мусорные замеры клампятся в разумные границы', () async {
    final TokenCalibration low = await store.record(
      accountId: 'a',
      model: 'm',
      observedTokensPerCard: 1,
    );
    expect(low.tokensPerCard, kMinCalibrationTokensPerCard);
    final TokenCalibration high = await store.record(
      accountId: 'b',
      model: 'm',
      observedTokensPerCard: 100000,
    );
    expect(high.tokensPerCard, kMaxCalibrationTokensPerCard);
  });

  test('записи изолированы по аккаунту и модели', () async {
    await store.record(
      accountId: 'deepseek',
      model: 'deepseek-flash',
      observedTokensPerCard: 300,
    );
    await store.record(
      accountId: 'deepseek',
      model: 'deepseek-chat',
      observedTokensPerCard: 500,
    );
    expect(
      (await store.read(
        accountId: 'deepseek',
        model: 'deepseek-flash',
      ))!.tokensPerCard,
      300,
    );
    expect(
      (await store.read(
        accountId: 'deepseek',
        model: 'deepseek-chat',
      ))!.tokensPerCard,
      500,
    );
    expect(await store.readAll(), hasLength(2));
  });

  test('JSON v1, без ключей и текстов карточек', () async {
    await store.record(
      accountId: 'deepseek',
      model: 'deepseek-flash',
      observedTokensPerCard: 320,
    );
    final AppSettingRow row = (await db.select(db.appSettings).get()).single;
    expect(row.key, 'generation.calibration');
    final Map<String, Object?> json =
        jsonDecode(row.valueJson) as Map<String, Object?>;
    expect(json['version'], 1);
    expect(row.valueJson, isNot(contains('api_key')));
    expect(row.valueJson, isNot(contains('front')));
  });

  test('битый JSON — пустая калибровка, без исключения', () async {
    await db
        .into(db.appSettings)
        .insertOnConflictUpdate(
          AppSettingsCompanion.insert(
            key: DriftTokenCalibrationStore.settingKey,
            valueJson: '{oops',
          ),
        );
    expect(await store.readAll(), isEmpty);
  });
}
