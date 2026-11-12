// Drift-таблицы схемы SQLite CardFlow — SPEC A5 (10 таблиц, schemaVersion=1).
//
// Имена таблиц/колонок — snake_case как в SPEC: drift по умолчанию переводит
// имена геттеров в snake_case (`deckId` → `deck_id`). Data-классы переименованы
// (`@DataClassName('DeckRow')` и т.п.), чтобы не конфликтовать с доменными
// сущностями `Deck`/`Card` из `lib/domain/`.
//
// Время хранится как INTEGER epoch **миллисекунды** (UTC), bool — как 0/1:
// маппинг в `DateTime`/`bool` делают репозитории (`lib/data/db/epoch.dart`),
// а не drift, чтобы формат в БД был ровно по SPEC A5.
import 'package:drift/drift.dart';

/// Колоды (SPEC A5: `decks`).
@DataClassName('DeckRow')
class Decks extends Table {
  /// Уникальный идентификатор (`TEXT PRIMARY KEY`).
  TextColumn get id => text()();

  /// Отображаемое имя.
  TextColumn get name => text()();

  /// Настройки планировщика, JSON-объект (`DEFAULT '{}'`).
  TextColumn get settingsJson => text().withDefault(const Constant('{}'))();

  /// Момент архивации (epoch ms), `NULL` — колода активна.
  IntColumn get archivedAt => integer().nullable()();

  /// Момент создания (epoch ms).
  IntColumn get createdAt => integer()();

  /// Момент последнего изменения (epoch ms).
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Карточки (SPEC A5: `cards`).
///
/// `basic_reversed` — две строки с взаимными `sibling_id`; `ON DELETE CASCADE`
/// удаляет карточки вместе с колодой (FK включаются в `beforeOpen`).
@DataClassName('CardRow')
@TableIndex(name: 'idx_cards_deck_due', columns: {#deckId, #due})
@TableIndex(name: 'idx_cards_hash', columns: {#deckId, #contentHash})
class Cards extends Table {
  /// Уникальный идентификатор (`TEXT PRIMARY KEY`).
  TextColumn get id => text()();

  /// Колода-владелец.
  TextColumn get deckId =>
      text().references(Decks, #id, onDelete: KeyAction.cascade)();

  /// Лицевая сторона (вопрос).
  TextColumn get front => text()();

  /// Обратная сторона (ответ).
  TextColumn get back => text()();

  /// Подсказка без раскрытия ответа.
  TextColumn get hint => text().nullable()();

  /// Тип: `basic | basic_reversed | cloze`.
  TextColumn get cardType => text()();

  /// Теги, JSON-массив строк (`DEFAULT '[]'`).
  TextColumn get tagsJson => text().withDefault(const Constant('[]'))();

  /// Идентификаторы медиа, JSON-массив строк (`DEFAULT '[]'`).
  TextColumn get mediaJson => text().withDefault(const Constant('[]'))();

  /// LaTeX-разметка, если есть.
  TextColumn get latex => text().nullable()();

  /// JSON масок Image Occlusion, если есть.
  TextColumn get occlusionJson => text().nullable()();

  /// Ссылка на исходный документ (`source_docs.id`), если есть.
  TextColumn get sourceDocId => text().nullable()();

  /// Цитата для кнопки «Почему?», если есть.
  TextColumn get sourceExcerpt => text().nullable()();

  /// Состояние уровня приложения: `new | learning | review | relearning`.
  TextColumn get state => text()();

  /// Состояние FSRS (сырой JSON адаптера), если карточка планировалась.
  TextColumn get fsrsJson => text().nullable()();

  /// Денормализованный `due` (epoch ms), если запланирована.
  IntColumn get due => integer().nullable()();

  /// Приостановлена: 0/1 (`DEFAULT 0`).
  IntColumn get suspended => integer().withDefault(const Constant(0))();

  /// Отложена до момента (epoch ms), если есть.
  IntColumn get buriedUntil => integer().nullable()();

  /// Флаг пользователя: 0/1 (`DEFAULT 0`).
  IntColumn get flagged => integer().withDefault(const Constant(0))();

  /// Парная карточка `basic_reversed`.
  TextColumn get siblingId => text().nullable()();

  /// Хеш дедупликации `front + "\u0000" + back`, если посчитан.
  TextColumn get contentHash => text().nullable()();

  /// Момент создания (epoch ms).
  IntColumn get createdAt => integer()();

  /// Момент последнего изменения (epoch ms).
  IntColumn get updatedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Журнал повторений (SPEC A5: `review_logs`).
@DataClassName('ReviewLogRow')
@TableIndex(name: 'idx_review_logs_card', columns: {#cardId})
class ReviewLogs extends Table {
  /// Уникальный идентификатор.
  TextColumn get id => text()();

  /// Карточка, к которой относится повторение.
  TextColumn get cardId => text()();

  /// Оценка: 1 Again, 2 Hard, 3 Good, 4 Easy (SPEC A5).
  IntColumn get rating => integer()();

  /// Момент повторения (epoch ms).
  IntColumn get reviewedAt => integer()();

  /// Режим повторения.
  TextColumn get mode => text()();

  /// Флаг распознавания: 0/1 (`DEFAULT 0`).
  IntColumn get recognitionFlag => integer().withDefault(const Constant(0))();

  /// Запланированный интервал, дни.
  RealColumn get scheduledDays => real().nullable()();

  /// Фактический интервал, дни.
  RealColumn get actualDays => real().nullable()();

  /// Длительность ответа, мс.
  IntColumn get elapsedMs => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Лог практических тренировок (SPEC A5: `practice_logs`).
@DataClassName('PracticeLogRow')
class PracticeLogs extends Table {
  /// Уникальный идентификатор.
  TextColumn get id => text()();

  /// Карточка, к которой относится тренировка.
  TextColumn get cardId => text()();

  /// Режим тренировки.
  TextColumn get mode => text()();

  /// Момент тренировки (epoch ms).
  IntColumn get reviewedAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Медиа-файлы карточек (SPEC A5: `media`).
@DataClassName('MediaRow')
class Media extends Table {
  /// Уникальный идентификатор.
  TextColumn get id => text()();

  /// Карточка-владелец.
  TextColumn get cardId => text()();

  /// Путь к файлу в каталоге медиа.
  TextColumn get path => text()();

  /// MIME-тип.
  TextColumn get mimeType => text()();

  /// Размер файла, байт.
  IntColumn get size => integer()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Исходные документы для генерации (SPEC A5: `source_docs`).
@DataClassName('SourceDocRow')
class SourceDocs extends Table {
  /// Уникальный идентификатор.
  TextColumn get id => text()();

  /// Колода, к которой привязан документ.
  TextColumn get deckId => text()();

  /// Путь к файлу.
  TextColumn get path => text()();

  /// Отображаемое название.
  TextColumn get title => text()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Метаданные синхронизации (SPEC A5: `sync_meta`).
///
/// Post-MVP: таблица создаётся заранее по SPEC A9, логика не пишется.
@DataClassName('SyncMetaRow')
class SyncMeta extends Table {
  /// Идентификатор устройства.
  TextColumn get deviceId => text().nullable()();

  /// Последняя синхронизация в HLC (Hybrid Logical Clock).
  TextColumn get lastSyncHlc => text().nullable()();
}

/// Задания генерации карточек через API (SPEC A5: `generation_jobs`).
@DataClassName('GenerationJobRow')
class GenerationJobs extends Table {
  /// Уникальный идентификатор.
  TextColumn get id => text()();

  /// Статус: `running | done | partial | error | cancelled`.
  TextColumn get status => text()();

  /// Момент создания (epoch ms).
  IntColumn get createdAt => integer()();

  /// Провайдер API.
  TextColumn get provider => text().nullable()();

  /// Модель провайдера.
  TextColumn get model => text().nullable()();

  /// Израсходовано токенов.
  IntColumn get tokensUsed => integer().nullable()();

  /// Версия встроенного системного промпта.
  TextColumn get promptVersion => text().nullable()();

  /// Машинный код ошибки для retry-логики.
  TextColumn get errorCode => text().nullable()();

  /// Сколько карточек получено.
  IntColumn get cardsCount => integer().nullable()();

  /// Сколько фрагментов обработано.
  IntColumn get chunkCount => integer().nullable()();

  /// JSON со списком файлов.
  TextColumn get filesJson => text().nullable()();

  /// Колода, куда импортированы карточки.
  TextColumn get resultDeckId => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Пользовательские настройки (SPEC A5: `app_settings`).
@DataClassName('AppSettingRow')
class AppSettings extends Table {
  /// Ключ настройки.
  TextColumn get key => text()();

  /// Значение, JSON.
  TextColumn get valueJson => text()();

  @override
  Set<Column> get primaryKey => {key};
}

/// Пресеты конструктора сессии (SPEC A5: `session_presets`, A6.7).
@DataClassName('SessionPresetRow')
class SessionPresets extends Table {
  /// Уникальный идентификатор.
  TextColumn get id => text()();

  /// Название пресета.
  TextColumn get name => text()();

  /// Конфигурация сессии, JSON.
  TextColumn get configJson => text()();

  /// Момент создания (epoch ms).
  IntColumn get createdAt => integer()();

  @override
  Set<Column> get primaryKey => {id};
}
