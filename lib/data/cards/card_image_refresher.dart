/// Повторный поиск картинки карточки (итерация 7.14, шаг 3).
///
/// Операция «Найти картинку заново» для конкретного медиа (кнопка в
/// редакторе). Метаданные (`<путь>.meta.json`) хранят исходный запрос модели и
/// вид иллюстрации, поэтому повтор не требует новых токенов генерации. При
/// успехе файл заменяется на месте, строка `media` обновляется. Ошибка/пустая
/// выдача — тихий `notFound`, карточка не страдает.
///
/// С 7.19 (ADR-041) заглушек нет: фонового ретрая заглушек больше не
/// существует, а существующие заглушки удаляет `PlaceholderMediaPurger`.
library;

import 'package:drift/drift.dart';

import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/transfer/media_store.dart';
import 'package:cardflow/domain/cards/card_image_refresh_result.dart';
import 'package:cardflow/domain/cards/media_metadata.dart';
import 'package:cardflow/domain/generation/card_image_finder.dart';
import 'package:cardflow/domain/generation/card_image_kind.dart';
import 'package:cardflow/domain/generation/generated_card_image.dart';

/// Повторный поиск картинок поверх drift-БД и `MediaStore`.
class CardImageRefresher {
  /// Создаёт сервис.
  CardImageRefresher({
    required this.database,
    required this.mediaStore,
    required this.imageFinder,
  });

  /// БД приложения.
  final AppDatabase database;

  /// Файловое хранилище медиа.
  final MediaStore mediaStore;

  /// Цепочка поиска картинок.
  final CardImageFinder imageFinder;

  /// Ищет картинку заново для медиа [mediaId].
  Future<CardImageRefreshResult> refreshMedia(String mediaId) async {
    final MediaRow? row = await (database.select(
      database.media,
    )..where((table) => table.id.equals(mediaId))).getSingleOrNull();
    if (row == null) return CardImageRefreshResult.missing;
    final MediaMetadata? metadata = await mediaStore.readMetadata(row.path);
    final String? query = metadata?.query?.trim();
    if (metadata == null || query == null || query.isEmpty) {
      return CardImageRefreshResult.noQuery;
    }
    return _refresh(row, metadata, query);
  }

  /// Общий путь обновления: поиск → запись файла → строка `media` → метаданные.
  Future<CardImageRefreshResult> _refresh(
    MediaRow row,
    MediaMetadata metadata,
    String query,
  ) async {
    final GeneratedCardImage? image;
    try {
      image = await imageFinder.findImage(
        query,
        fallbackQuery: metadata.fallbackQuery,
        kind: metadata.kind ?? GeneratedCardImageKind.photo,
      );
    } on Object {
      return CardImageRefreshResult.notFound;
    }
    if (image == null) return CardImageRefreshResult.notFound;
    final String newPath = 'media/${row.id}.${image.fileExtension}';
    await mediaStore.writeMedia(relativePath: newPath, bytes: image.bytes);
    if (newPath != row.path) {
      await mediaStore.deleteMedia(row.path);
    }
    await (database.update(
      database.media,
    )..where((table) => table.id.equals(row.id))).write(
      MediaCompanion(
        path: Value<String>(newPath),
        mimeType: Value<String>(image.mimeType),
        size: Value<int>(image.bytes.length),
      ),
    );
    await mediaStore.writeMetadata(
      relativePath: newPath,
      metadata: MediaMetadata(
        provider: image.provider,
        sourceUrl: image.sourceUrl,
        author: image.author,
        license: image.license,
        query: image.query.trim().isEmpty ? query : image.query,
        fallbackQuery: image.fallbackQuery ?? metadata.fallbackQuery,
        kind: image.kind,
      ),
    );
    return CardImageRefreshResult.updated;
  }
}
