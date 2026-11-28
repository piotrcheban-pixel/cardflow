// Устойчивость открытия файловой БД (ADR-005 §5, ADR-057).
//
// Проверяется поведение production-пути `openAppDatabaseWithRecovery` на
// **реальном файле**, а не на `SchemaVerifier`-соединении:
//  - старая БД v1 (полная схема SPEC A5) мигрирует до v3 с сохранением данных,
//    копией `.bak` и включёнными внешними ключами;
//  - мусорный файл не «кирпичит» запуск: он откладывается в
//    `cardflow.sqlite.corrupted_<дата>`, создаётся новая БД;
//  - понижение версии остаётся fail-fast: файл не переименовывается.
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:sqlite3/sqlite3.dart';

import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/db/database_opener.dart';

import 'migrations/generated/schema_v1.dart' as v1;
import 'test_support.dart';

/// Каталог данных приложения `<base>/cardflow`.
Directory _dataDirectory(Directory base) =>
    Directory('${base.path}${Platform.pathSeparator}$appDataDirectoryName');

/// Файл БД `<base>/cardflow/cardflow.sqlite`.
File _databaseFile(Directory base) => File(
  '${_dataDirectory(base).path}${Platform.pathSeparator}$appDatabaseFileName',
);

/// Готовит временный каталог с подкаталогом данных.
Future<Directory> _tempBase(String prefix) async {
  final Directory base = await Directory.systemTemp.createTemp(prefix);
  _dataDirectory(base).createSync(recursive: true);
  return base;
}

/// Сеет полную БД версии 1 (схема SPEC A5 из снимка `drift_schema_v1.json`).
Future<void> _seedSchemaV1(File file) async {
  final v1.DatabaseAtV1 database = v1.DatabaseAtV1(NativeDatabase(file));
  // Первый запрос создаёт схему v1 и ставит `PRAGMA user_version = 1`.
  await database.customSelect('SELECT 1').get();
  await database.customStatement('''
    INSERT INTO decks (id, name, settings_json, created_at, updated_at)
    VALUES ('deck-1', 'Колода версии 1', '{}', 1000, 2000)
  ''');
  await database.customStatement('''
    INSERT INTO cards (
      id, deck_id, front, back, card_type, tags_json, media_json, state,
      fsrs_json, due, created_at, updated_at
    ) VALUES (
      'card-1', 'deck-1', 'Вопрос', 'Ответ', 'basic', '[]', '[]', 'review',
      '{"stability":1.0}', 5000, 1000, 2000
    )
  ''');
  await database.customStatement('''
    INSERT INTO review_logs (id, card_id, rating, reviewed_at, mode,
      recognition_flag, scheduled_days, actual_days, elapsed_ms)
    VALUES ('log-1', 'card-1', 3, 3000, 'classic', 0, 2.0, 1.0, 4200)
  ''');
  await database.customStatement('''
    INSERT INTO media (id, card_id, path, mime_type, size)
    VALUES ('media-1', 'card-1', 'media/media-1.png', 'image/png', 10)
  ''');
  await database.close();
}

void main() {
  group('openAppDatabaseWithRecovery (ADR-057)', () {
    test(
      'БД v1 полной схемы мигрирует до v3, данные и .bak на месте',
      () async {
        final Directory base = await _tempBase('cardflow-rec-v1');
        addTearDown(() async {
          await base.delete(recursive: true);
        });
        final File file = _databaseFile(base);
        await _seedSchemaV1(file);

        final OpenedDatabase opened = await openAppDatabaseWithRecovery(
          baseDirectory: base,
        );
        addTearDown(opened.database.close);
        expect(opened.corruptedFile, isNull, reason: 'файл не повреждён');

        // Версия схемы и внешние ключи — production-путь с `beforeOpen`.
        final QueryRow version = await opened.database
            .customSelect('PRAGMA user_version')
            .getSingle();
        expect(
          version.read<int>('user_version'),
          AppDatabase.currentSchemaVersion,
        );
        final QueryRow foreignKeys = await opened.database
            .customSelect('PRAGMA foreign_keys')
            .getSingle();
        expect(foreignKeys.read<int>('foreign_keys'), 1);

        // Данные v1 не потерялись.
        final List<DeckRow> decks = await opened.database
            .select(opened.database.decks)
            .get();
        expect(decks.map((DeckRow deck) => deck.name), <String>[
          'Колода версии 1',
        ]);
        final List<CardRow> cards = await opened.database
            .select(opened.database.cards)
            .get();
        expect(cards.map((CardRow card) => card.front), <String>['Вопрос']);
        final List<ReviewLogRow> logs = await opened.database
            .select(opened.database.reviewLogs)
            .get();
        expect(logs, hasLength(1));
        final List<MediaRow> media = await opened.database
            .select(opened.database.media)
            .get();
        expect(media, hasLength(1));

        // Новые таблицы схемы v2/v3 созданы миграцией.
        final List<QueryRow> generationRuns = await opened.database
            .customSelect(
              "SELECT name FROM sqlite_master WHERE type = 'table' "
              "AND name = 'generation_runs'",
            )
            .get();
        expect(generationRuns, hasLength(1));
        final List<QueryRow> dedupColumn = await opened.database
            .customSelect('PRAGMA table_info(card_drafts)')
            .get();
        expect(
          dedupColumn.map((QueryRow row) => row.read<String>('name')),
          containsAll(<String>['is_duplicate_of', 'dedup_level']),
        );

        // Копия «как было» лежит рядом и хранит версию 1.
        final File backup = File('${file.path}$appDatabaseBackupSuffix');
        expect(backup.existsSync(), isTrue, reason: 'копия до миграции');
        expect(backup.lengthSync(), greaterThan(0));
      },
    );

    test(
      'мусорный файл: имя копии с датой, запуск продолжается на новой БД',
      () async {
        final Directory base = await _tempBase('cardflow-rec-garbage');
        addTearDown(() async {
          await base.delete(recursive: true);
        });
        final File file = _databaseFile(base);
        const String garbage = 'не база данных';
        file.writeAsStringSync(garbage);

        final OpenedDatabase opened = await openAppDatabaseWithRecovery(
          baseDirectory: base,
          clock: () => DateTime(2026, 11, 28, 20, 40, 5),
        );
        addTearDown(opened.database.close);

        expect(opened.corruptedFile, isNotNull);
        expect(
          opened.corruptedFile!.path,
          '${file.path}${appDatabaseCorruptedSuffix}20261128_204005',
        );
        expect(opened.corruptedFile!.readAsStringSync(), garbage);
        expect(
          await opened.database.select(opened.database.decks).get(),
          isEmpty,
        );
        expect(file.existsSync(), isTrue, reason: 'на месте создана новая БД');

        // Восстановленная БД — обычная рабочая: данные переживают переоткрытие.
        await insertDeckRow(
          opened.database,
          id: 'deck-new',
          name: 'После восстановления',
          createdAt: 1,
          updatedAt: 1,
        );
        await opened.database.close();

        final OpenedDatabase reopened = await openAppDatabaseWithRecovery(
          baseDirectory: base,
        );
        addTearDown(reopened.database.close);
        expect(reopened.corruptedFile, isNull);
        expect(
          (await reopened.database.select(reopened.database.decks).get()).map(
            (DeckRow deck) => deck.name,
          ),
          <String>['После восстановления'],
        );
      },
    );

    test('повторное восстановление не перетирает прошлую копию', () async {
      final Directory base = await _tempBase('cardflow-rec-twice');
      addTearDown(() async {
        await base.delete(recursive: true);
      });
      final File file = _databaseFile(base);
      file.writeAsStringSync('первый мусор');
      final OpenedDatabase first = await openAppDatabaseWithRecovery(
        baseDirectory: base,
        clock: () => DateTime(2026, 11, 28, 10, 0, 0),
      );
      await first.database.close();
      file.writeAsStringSync('второй мусор');
      final OpenedDatabase second = await openAppDatabaseWithRecovery(
        baseDirectory: base,
        clock: () => DateTime(2026, 11, 28, 10, 0, 0),
      );
      addTearDown(second.database.close);

      final List<File> quarantined = _dataDirectory(base)
          .listSync()
          .whereType<File>()
          .where(
            (File entry) => entry.path.contains(appDatabaseCorruptedSuffix),
          )
          .toList();
      expect(quarantined, hasLength(2), reason: 'обе копии сохранены');
      expect(
        quarantined.map((File entry) => entry.readAsStringSync()).toSet(),
        <String>{'первый мусор', 'второй мусор'},
      );
    });

    test('понижение версии — fail-fast, файл не переименовывается', () async {
      final Directory base = await _tempBase('cardflow-rec-newer');
      addTearDown(() async {
        await base.delete(recursive: true);
      });
      final File file = _databaseFile(base);
      final v1.DatabaseAtV1 seed = v1.DatabaseAtV1(NativeDatabase(file));
      await seed.customSelect('SELECT 1').get();
      await seed.customStatement('PRAGMA user_version = 99');
      await seed.close();

      await expectLater(
        openAppDatabaseWithRecovery(baseDirectory: base),
        throwsA(anything),
      );
      expect(file.existsSync(), isTrue, reason: 'файл пользователя не отложен');
      final List<File> quarantined = _dataDirectory(base)
          .listSync()
          .whereType<File>()
          .where(
            (File entry) => entry.path.contains(appDatabaseCorruptedSuffix),
          )
          .toList();
      expect(quarantined, isEmpty);
    });
  });

  group('классификация сбоев', () {
    SqliteException sqlite(int code) =>
        SqliteException(extendedResultCode: code, message: 'сбой $code');

    test('повреждение файла: SQLITE_CORRUPT и SQLITE_NOTADB', () {
      expect(isCorruptedDatabaseError(sqlite(SqlError.SQLITE_NOTADB)), isTrue);
      expect(isCorruptedDatabaseError(sqlite(SqlError.SQLITE_CORRUPT)), isTrue);
      expect(isCorruptedDatabaseError(sqlite(SqlError.SQLITE_ERROR)), isFalse);
      expect(isCorruptedDatabaseError(StateError('версия')), isFalse);
    });

    test('нет доступа: права, readonly, cantopen и файловые исключения', () {
      expect(isDatabaseAccessFailure(sqlite(SqlError.SQLITE_CANTOPEN)), isTrue);
      expect(isDatabaseAccessFailure(sqlite(SqlError.SQLITE_READONLY)), isTrue);
      expect(isDatabaseAccessFailure(sqlite(SqlError.SQLITE_PERM)), isTrue);
      expect(isDatabaseAccessFailure(const FileSystemException('нет')), isTrue);
      expect(isDatabaseAccessFailure(sqlite(SqlError.SQLITE_BUSY)), isFalse);
      expect(isDatabaseAccessFailure(StateError('версия')), isFalse);
    });
  });
}
