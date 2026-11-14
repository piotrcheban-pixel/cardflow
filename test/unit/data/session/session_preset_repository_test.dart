import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/session/drift_session_preset_repository.dart';
import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/session/session_config.dart';
import 'package:cardflow/domain/session/session_preset.dart';

/// Красная фаза итерации 6: пресеты конструктора в `session_presets`
/// (SPEC A5, A6.7, ADR-018) — сохранение, порядок, JSON-конфиг, удаление,
/// устойчивость к битой строке.
void main() {
  late AppDatabase db;
  late DriftSessionPresetRepository repository;
  final DateTime now = DateTime.utc(2026, 11, 14, 12);

  const SessionConfig morning = SessionConfig(
    deckIds: <String>['deck-1', 'deck-2'],
    tags: <String>{'даты'},
    states: <SessionStateFilter>{SessionStateFilter.review},
    mode: SessionMode.feed,
    limit: SessionLimit.minutes(15),
    shuffle: true,
    interleave: true,
  );

  setUp(() {
    db = AppDatabase.inMemory();
    repository = DriftSessionPresetRepository(db);
  });

  tearDown(() async {
    await db.close();
  });

  test('сохранение: id, имя, конфиг и время создания', () async {
    final SessionPreset saved = await repository.savePreset(
      name: 'Утренняя сессия',
      config: morning,
      createdAt: now,
    );

    expect(saved.id, isNotEmpty);
    expect(saved.name, 'Утренняя сессия');
    expect(saved.config, morning);
    expect(saved.createdAt, now);

    final List<SessionPreset> presets = await repository.presets();
    expect(presets, hasLength(1));
    expect(presets.single, saved);
    expect(presets.single.config.limit.kind, SessionLimitKind.minutes);
    expect(presets.single.config.mode, SessionMode.feed);
  });

  test('список упорядочен по времени создания (старые раньше)', () async {
    await repository.savePreset(
      name: 'Вторая',
      config: morning,
      createdAt: now.add(const Duration(minutes: 1)),
    );
    await repository.savePreset(
      name: 'Первая',
      config: morning,
      createdAt: now,
    );

    final List<SessionPreset> presets = await repository.presets();

    expect(presets.map((SessionPreset preset) => preset.name), <String>[
      'Первая',
      'Вторая',
    ]);
  });

  test('round-trip классического конфига с лимитом карточек', () async {
    const SessionConfig classic = SessionConfig(
      deckIds: <String>['deck-1'],
      cardTypes: <CardType>{CardType.basicReversed, CardType.cloze},
      states: <SessionStateFilter>{
        SessionStateFilter.newCards,
        SessionStateFilter.inProgress,
        SessionStateFilter.leeches,
      },
      limit: SessionLimit.cards(30),
      warmup: true,
    );

    await repository.savePreset(name: 'База', config: classic, createdAt: now);
    final List<SessionPreset> presets = await repository.presets();

    expect(presets.single.config, classic);
    expect(presets.single.config.cardTypes, classic.cardTypes);
    expect(presets.single.config.states, classic.states);
  });

  test('удаление пресета не трогает остальные', () async {
    final SessionPreset first = await repository.savePreset(
      name: 'Первая',
      config: morning,
      createdAt: now,
    );
    final SessionPreset second = await repository.savePreset(
      name: 'Вторая',
      config: morning,
      createdAt: now.add(const Duration(minutes: 1)),
    );

    await repository.deletePreset(first.id);

    final List<SessionPreset> presets = await repository.presets();
    expect(presets.map((SessionPreset preset) => preset.id), <String>[
      second.id,
    ]);
  });

  test('битая строка presets пропускается, валидные остаются', () async {
    await repository.savePreset(name: 'Валидная', config: morning, createdAt: now);
    await db
        .into(db.sessionPresets)
        .insert(
          SessionPresetsCompanion.insert(
            id: 'broken-preset',
            name: 'Битая',
            configJson: '{"version": 99}',
            createdAt: now.millisecondsSinceEpoch,
          ),
        );
    await db
        .into(db.sessionPresets)
        .insert(
          SessionPresetsCompanion.insert(
            id: 'garbage-preset',
            name: 'Мусор',
            configJson: 'не json',
            createdAt: now.millisecondsSinceEpoch + 1,
          ),
        );

    final List<SessionPreset> presets = await repository.presets();

    expect(presets.map((SessionPreset preset) => preset.name), <String>[
      'Валидная',
    ]);
  });

  test('записанный config_json — JSON-объект с версией 1', () async {
    await repository.savePreset(name: 'JSON', config: morning, createdAt: now);

    final SessionPresetRow row = await db.select(db.sessionPresets).getSingle();
    final Object? decoded = jsonDecode(row.configJson);

    expect(decoded, isA<Map<String, dynamic>>());
    final Map<String, dynamic> config = decoded! as Map<String, dynamic>;
    expect(config['version'], 1);
    expect(config['mode'], 'feed');
    expect(row.createdAt, now.millisecondsSinceEpoch);
    expect(row.name, 'JSON');
  });

  test('id генерируется репозиторием и уникален', () async {
    final SessionPreset first = await repository.savePreset(
      name: 'A',
      config: morning,
      createdAt: now,
    );
    final SessionPreset second = await repository.savePreset(
      name: 'B',
      config: morning.copyWith(limit: const SessionLimit.cards(5)),
      createdAt: now,
    );

    expect(first.id, isNot(second.id));
    expect(first.id, hasLength(36), reason: 'uuid v4 как decks/review_logs');
  });
}
