import 'dart:typed_data';

import 'package:cardflow/domain/cards/card.dart';

/// Версия публичного формата `.zip`-экспорта (SPEC 0.4.4: менять только с
/// повышением версии). Контракт — ADR-006 и `docs/archive-format.md`.
const int deckArchiveFormatVersion = 1;

/// Имя приложения в `meta.json`.
const String deckArchiveAppName = 'CardFlow';

/// Имена файлов/каталогов архива (SPEC 0.4.4, A6.9).
abstract final class DeckArchiveEntries {
  /// Метаданные архива/колоды.
  static const String meta = 'meta.json';

  /// Карточки архива.
  static const String cards = 'cards.json';

  /// Каталог медиафайлов (`media/<id>`).
  static const String mediaDir = 'media/';
}

/// Пределы размеров при импорте (защита от zip-bomb и зависаний UI).
abstract final class DeckArchiveLimits {
  /// Максимальный размер входного `.zip`-файла, байт (100 МБ).
  static const int maxImportBytes = 100 * 1024 * 1024;

  /// Максимальный суммарный размер распакованных данных, байт (300 МБ).
  static const int maxUncompressedBytes = 300 * 1024 * 1024;

  /// Максимальный размер `meta.json`/`cards.json`, байт (32 МБ).
  static const int maxJsonEntryBytes = 32 * 1024 * 1024;
}

/// Колода в составе архива (`meta.json`).
class ArchiveDeck {
  /// Создаёт описание колоды.
  const ArchiveDeck({
    required this.id,
    required this.name,
    required this.settings,
    required this.createdAt,
    required this.updatedAt,
    this.archivedAt,
  });

  /// Исходный id колоды (при импорте может быть заменён новым).
  final String id;

  /// Имя колоды.
  final String name;

  /// Настройки планировщика.
  final Map<String, Object?> settings;

  /// Момент создания.
  final DateTime createdAt;

  /// Момент последнего изменения.
  final DateTime updatedAt;

  /// Архивность колоды (экспорт архивной колоды сохраняет признак).
  final DateTime? archivedAt;

  @override
  bool operator ==(Object other) {
    return other is ArchiveDeck &&
        other.id == id &&
        other.name == name &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt &&
        other.archivedAt == archivedAt;
  }

  @override
  int get hashCode => Object.hash(id, name, createdAt, updatedAt, archivedAt);
}

/// Медиафайл в составе архива (`media/`).
class ArchiveMedia {
  /// Создаёт запись медиа.
  const ArchiveMedia({
    required this.id,
    required this.cardId,
    required this.path,
    required this.mimeType,
    required this.bytes,
  });

  /// Идентификатор медиа (в архиве — имя файла `media/<id>`).
  final String id;

  /// Карточка-владелец.
  final String cardId;

  /// Относительный путь в медиа-хранилище приложения (`media.path`).
  final String path;

  /// MIME-тип.
  final String mimeType;

  /// Содержимое файла.
  final Uint8List bytes;
}

/// Разобранный архив колоды (до/после записи в БД).
class DeckArchive {
  /// Создаёт архив.
  const DeckArchive({
    required this.formatVersion,
    required this.exportedAt,
    required this.deck,
    required this.cards,
    this.media = const <ArchiveMedia>[],
  });

  /// Версия формата (сейчас — [deckArchiveFormatVersion]).
  final int formatVersion;

  /// Момент экспорта.
  final DateTime exportedAt;

  /// Описание колоды.
  final ArchiveDeck deck;

  /// Карточки архива.
  final List<Card> cards;

  /// Медиафайлы архива.
  final List<ArchiveMedia> media;
}

/// Предпросмотр импорта для диалога подтверждения (SPEC A6.9).
class ImportPreview {
  /// Создаёт предпросмотр.
  const ImportPreview({
    required this.deckName,
    required this.formatVersion,
    required this.cardsCount,
    required this.duplicatesCount,
    required this.mediaCount,
  });

  /// Имя импортируемой колоды.
  final String deckName;

  /// Версия формата.
  final int formatVersion;

  /// Сколько карточек будет импортировано.
  final int cardsCount;

  /// Сколько дубликатов будет пропущено (по `content_hash` внутри архива).
  final int duplicatesCount;

  /// Сколько медиафайлов будет импортировано.
  final int mediaCount;

  @override
  bool operator ==(Object other) {
    return other is ImportPreview &&
        other.deckName == deckName &&
        other.formatVersion == formatVersion &&
        other.cardsCount == cardsCount &&
        other.duplicatesCount == duplicatesCount &&
        other.mediaCount == mediaCount;
  }

  @override
  int get hashCode => Object.hash(
    deckName,
    formatVersion,
    cardsCount,
    duplicatesCount,
    mediaCount,
  );
}

/// Результат импорта.
class ImportResult {
  /// Создаёт результат.
  const ImportResult({
    required this.deckId,
    required this.importedCards,
    required this.skippedDuplicates,
    required this.importedMedia,
  });

  /// Id созданной колоды.
  final String deckId;

  /// Сколько карточек импортировано.
  final int importedCards;

  /// Сколько дубликатов пропущено.
  final int skippedDuplicates;

  /// Сколько медиафайлов импортировано.
  final int importedMedia;
}

/// Машинные коды ошибок архива (UI маппит их в строки ARB).
enum ArchiveErrorCode {
  /// Версия формата не поддерживается.
  unsupportedVersion,

  /// Файл не является корректным zip-архивом.
  corruptZip,

  /// В архиве нет обязательного файла.
  missingEntry,

  /// `meta.json` некорректен.
  invalidMeta,

  /// `cards.json`/карточки некорректны.
  invalidCards,

  /// Архив/файл слишком велик.
  tooLarge,

  /// Медиафайл отсутствует при экспорте.
  mediaMissing,

  /// Колода для экспорта не найдена.
  deckNotFound,

  /// Недопустимое имя записи в архиве (zip-slip и т.п.).
  invalidEntryName,
}

/// Ошибка импорта/экспорта `.zip` (сообщение пользователю — только из ARB).
class ArchiveException implements Exception {
  /// Создаёт ошибку с машинным [code].
  const ArchiveException(this.code, {this.details});

  /// Код для маппинга в ARB.
  final ArchiveErrorCode code;

  /// Технические детали для логов/тестов (пользователю не показываются).
  final String? details;

  @override
  String toString() => 'ArchiveException(${code.name}): $details';
}
