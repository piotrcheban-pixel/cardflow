/// Диагностика целостности изображений карточек (итерация 7.19).
///
/// Проверяет цепочку «карточка → media-строка → файл → байты → MIME» и находит
/// то, что раньше маскировалось: отсутствующий файл, пустой файл, MIME не по
/// сигнатуре, заглушку, чужого владельца медиа и одинаковые байты у разных
/// карточек. Отчёт содержит только метаданные (id, размер, MIME, провайдер,
/// SHA-256 в hex) — **никаких** бинарных данных.
///
/// Используется тестами и `tool/media_integrity_report.dart`.
library;

import 'package:crypto/crypto.dart';

import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/transfer/media_store.dart';
import 'package:cardflow/domain/cards/card_media_json.dart';
import 'package:cardflow/domain/cards/media_metadata.dart';
import 'package:cardflow/domain/generation/image_bytes.dart';

/// Состояние одной связи «карточка → медиа».
enum MediaIntegrityStatus {
  /// Файл и строка `media` на месте, MIME совпадает, байты — изображение.
  ok,

  /// `media_json` ссылается на id, которого нет в `media`.
  missingRow,

  /// Строка `media` есть, файла в `MediaStore` нет.
  missingFile,

  /// Файл нулевого размера.
  emptyFile,

  /// Байты не являются поддерживаемым изображением (сигнатура неизвестна).
  unsupportedFormat,

  /// MIME в `media` не совпадает с сигнатурой файла.
  mimeMismatch,

  /// Медиа помечено как нарисованная заглушка (`isPlaceholder`).
  placeholder,

  /// `media.card_id` указывает на другую карточку.
  foreignOwner,

  /// Те же байты привязаны к другой карточке.
  duplicateBytes,

  /// Строка `media` существует, но ни одна карточка на неё не ссылается.
  orphanRow,
}

/// Одна запись отчёта.
class MediaIntegrityEntry {
  /// Создаёт запись.
  const MediaIntegrityEntry({
    required this.cardId,
    required this.mediaId,
    required this.side,
    required this.status,
    this.provider,
    this.size,
    this.mimeType,
    this.digest,
    this.path,
  });

  /// Карточка-владелец ссылки (`''` — медиа-сирота).
  final String cardId;

  /// `media.id`.
  final String mediaId;

  /// Сторона, из которой пришла ссылка (`null` — сирота).
  final CardMediaSide? side;

  /// Итоговое состояние.
  final MediaIntegrityStatus status;

  /// Провайдер из метаданных (`file`, `wikimedia`, `placeholder`, …).
  final String? provider;

  /// Размер файла в байтах (`null` — файла нет).
  final int? size;

  /// MIME из строки `media`.
  final String? mimeType;

  /// SHA-256 в hex (только для существующих файлов).
  final String? digest;

  /// Относительный путь медиа (для диагностики).
  final String? path;

  @override
  String toString() =>
      'MediaIntegrityEntry(card: $cardId, media: $mediaId, '
      'side: ${side?.wireName ?? '-'}, status: ${status.name}, '
      'provider: $provider, size: $size, mime: $mimeType, '
      'digest: $digest)';
}

/// Отчёт диагностики.
class MediaIntegrityReport {
  /// Создаёт отчёт.
  const MediaIntegrityReport(this.entries);

  /// Все проверенные связи (включая `ok`), детерминированный порядок.
  final List<MediaIntegrityEntry> entries;

  /// Ошибок нет.
  bool get isClean => entries.every(
    (MediaIntegrityEntry entry) => entry.status == MediaIntegrityStatus.ok,
  );

  /// Записи-проблемы (кроме `ok`).
  List<MediaIntegrityEntry> get problems => <MediaIntegrityEntry>[
    for (final MediaIntegrityEntry entry in entries)
      if (entry.status != MediaIntegrityStatus.ok) entry,
  ];

  /// Состояние медиа [mediaId] (первая запись).
  MediaIntegrityStatus? statusOf(String mediaId) {
    for (final MediaIntegrityEntry entry in entries) {
      if (entry.mediaId == mediaId) return entry.status;
    }
    return null;
  }

  /// Число записей с состоянием [status].
  int count(MediaIntegrityStatus status) => entries
      .where((MediaIntegrityEntry entry) => entry.status == status)
      .length;

  /// Markdown-таблица для журнала/диагностики (без бинарных данных).
  String toMarkdownTable() {
    final StringBuffer buffer = StringBuffer()
      ..writeln(
        '| Карточка | Image ID | Сторона | Source | Размер | MIME | '
        'Результат |',
      )
      ..writeln('|---|---|---|---|---|---|---|');
    for (final MediaIntegrityEntry entry in entries) {
      buffer.writeln(
        '| ${_short(entry.cardId)} | ${_short(entry.mediaId)} | '
        '${entry.side?.wireName ?? '-'} | ${entry.provider ?? '-'} | '
        '${entry.size ?? '-'} | ${entry.mimeType ?? '-'} | '
        '${entry.status.name} |',
      );
    }
    return buffer.toString();
  }

  @override
  String toString() =>
      'MediaIntegrityReport(entries: ${entries.length}, '
      'problems: ${problems.length})';

  static String _short(String value) =>
      value.length <= 8 ? value : value.substring(0, 8);
}

/// Проверка целостности медиа поверх drift-БД и `MediaStore`.
class MediaIntegrityChecker {
  /// Создаёт проверку.
  MediaIntegrityChecker(this.database, this.mediaStore);

  /// БД приложения.
  final AppDatabase database;

  /// Файловое хранилище медиа.
  final MediaStore mediaStore;

  /// Собирает отчёт по всем карточкам и строкам `media`.
  Future<MediaIntegrityReport> check() async {
    final List<CardRow> cards = await database.select(database.cards).get();
    final List<MediaRow> rows = await database.select(database.media).get();
    final Map<String, MediaRow> rowById = <String, MediaRow>{
      for (final MediaRow row in rows) row.id: row,
    };
    final Map<String, MediaMetadata?> metadataByPath =
        <String, MediaMetadata?>{};
    final Map<String, ({int? size, String? digest, ImageFormat format})>
    fileFacts = <String, ({int? size, String? digest, ImageFormat format})>{};
    final Map<String, int> digestCards = <String, int>{};

    Future<({int? size, String? digest, ImageFormat format})> factsOf(
      MediaRow row,
    ) async {
      final cached = fileFacts[row.path];
      if (cached != null) return cached;
      final List<int>? bytes = await mediaStore.readMedia(row.path);
      final ({int? size, String? digest, ImageFormat format}) facts =
          bytes == null
          ? (size: null, digest: null, format: ImageFormat.unknown)
          : (
              size: bytes.length,
              digest: bytes.isEmpty ? null : sha256.convert(bytes).toString(),
              format: sniffImageFormat(bytes),
            );
      fileFacts[row.path] = facts;
      return facts;
    }

    for (final MediaRow row in rows) {
      final facts = await factsOf(row);
      if (facts.digest != null) {
        digestCards[facts.digest!] = (digestCards[facts.digest!] ?? 0) + 1;
      }
    }

    final List<MediaIntegrityEntry> entries = <MediaIntegrityEntry>[];
    final Set<String> referenced = <String>{};

    for (final CardRow card in cards) {
      final CardMediaSides? sides = CardMediaSides.tryDecode(card.mediaJson);
      if (sides == null) continue;
      for (final (CardMediaSide side, List<String> ids)
          in <(CardMediaSide, List<String>)>[
            (CardMediaSide.question, sides.question),
            (CardMediaSide.answer, sides.answer),
          ]) {
        for (final String mediaId in ids) {
          referenced.add(mediaId);
          final MediaRow? row = rowById[mediaId];
          if (row == null) {
            entries.add(
              MediaIntegrityEntry(
                cardId: card.id,
                mediaId: mediaId,
                side: side,
                status: MediaIntegrityStatus.missingRow,
              ),
            );
            continue;
          }
          final metadataByPathValue = metadataByPath.containsKey(row.path)
              ? metadataByPath[row.path]
              : (metadataByPath[row.path] = await mediaStore.readMetadata(
                  row.path,
                ));
          final facts = await factsOf(row);
          entries.add(
            MediaIntegrityEntry(
              cardId: card.id,
              mediaId: mediaId,
              side: side,
              provider: metadataByPathValue?.provider,
              size: facts.size,
              mimeType: row.mimeType,
              digest: facts.digest,
              path: row.path,
              status: _statusOf(
                row: row,
                cardId: card.id,
                metadata: metadataByPathValue,
                facts: facts,
                digestCards: digestCards,
              ),
            ),
          );
        }
      }
    }

    // Медиа-сироты: строки `media`, на которые не ссылается ни одна карточка.
    for (final MediaRow row in rows) {
      if (referenced.contains(row.id)) continue;
      final facts = await factsOf(row);
      entries.add(
        MediaIntegrityEntry(
          cardId: row.cardId,
          mediaId: row.id,
          side: null,
          status: MediaIntegrityStatus.orphanRow,
          size: facts.size,
          mimeType: row.mimeType,
          digest: facts.digest,
          path: row.path,
        ),
      );
    }

    entries.sort((MediaIntegrityEntry a, MediaIntegrityEntry b) {
      final int byCard = a.cardId.compareTo(b.cardId);
      if (byCard != 0) return byCard;
      final int byMedia = a.mediaId.compareTo(b.mediaId);
      if (byMedia != 0) return byMedia;
      return (a.side?.wireName ?? '').compareTo(b.side?.wireName ?? '');
    });
    return MediaIntegrityReport(
      List<MediaIntegrityEntry>.unmodifiable(entries),
    );
  }

  MediaIntegrityStatus _statusOf({
    required MediaRow row,
    required String cardId,
    required MediaMetadata? metadata,
    required ({int? size, String? digest, ImageFormat format}) facts,
    required Map<String, int> digestCards,
  }) {
    if (metadata?.isPlaceholder ?? false) {
      return MediaIntegrityStatus.placeholder;
    }
    if (metadata?.provider == 'placeholder') {
      return MediaIntegrityStatus.placeholder;
    }
    if (row.cardId != cardId) return MediaIntegrityStatus.foreignOwner;
    if (facts.size == null) return MediaIntegrityStatus.missingFile;
    if (facts.size == 0) return MediaIntegrityStatus.emptyFile;
    final String? digest = facts.digest;
    final ImageFormat format = facts.format;
    if (format == ImageFormat.unknown || format == ImageFormat.gif) {
      return MediaIntegrityStatus.unsupportedFormat;
    }
    if (row.mimeType != _mimeOf(format)) {
      return MediaIntegrityStatus.mimeMismatch;
    }
    if (digest != null && (digestCards[digest] ?? 0) > 1) {
      return MediaIntegrityStatus.duplicateBytes;
    }
    return MediaIntegrityStatus.ok;
  }

  static String _mimeOf(ImageFormat format) => switch (format) {
    ImageFormat.jpeg => 'image/jpeg',
    ImageFormat.png => 'image/png',
    ImageFormat.webp => 'image/webp',
    ImageFormat.gif => 'image/gif',
    ImageFormat.unknown => '',
  };
}
