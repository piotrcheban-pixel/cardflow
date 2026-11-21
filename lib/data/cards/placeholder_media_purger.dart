/// Удаление нарисованных заглушек из данных приложения (итерация 7.19).
///
/// До 7.19 `GenerationPipeline` при неудаче поиска изображения рисовал
/// декоративный PNG (`PlaceholderImageGenerator`) и сохранял его как обычное
/// медиа карточки. Такие файлы не являются исходными изображениями: они не
/// должны ни показываться, ни экспортироваться.
///
/// `PlaceholderMediaPurger` при старте удаляет строки `media` с метаданными
/// `provider = placeholder` / `isPlaceholder = true`, их файлы и
/// `<path>.meta.json`, а также убирает их id из `media_json` всех карточек
/// (v2 и legacy). Настоящие изображения не трогаются. Схема БД не меняется.
library;

import 'package:drift/drift.dart';

import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/transfer/media_store.dart';
import 'package:cardflow/domain/cards/card_media_json.dart';
import 'package:cardflow/domain/cards/media_metadata.dart';

/// Пурж синтезированных заглушек из `media`, `media_json` и `MediaStore`.
class PlaceholderMediaPurger {
  /// Создаёт пурж поверх БД и файлового хранилища.
  PlaceholderMediaPurger(this.database, this.mediaStore);

  /// БД приложения.
  final AppDatabase database;

  /// Файловое хранилище медиа.
  final MediaStore mediaStore;

  /// Удаляет все заглушки; возвращает число удалённых медиа-записей.
  Future<int> purge() async {
    final List<MediaRow> rows = await database.select(database.media).get();
    if (rows.isEmpty) return 0;

    final List<MediaRow> placeholders = <MediaRow>[];
    for (final MediaRow row in rows) {
      final MediaMetadata? metadata = await mediaStore.readMetadata(row.path);
      if (metadata == null) continue;
      if (metadata.isPlaceholder || metadata.provider == 'placeholder') {
        placeholders.add(row);
      }
    }
    if (placeholders.isEmpty) return 0;

    final Set<String> removedIds = <String>{
      for (final MediaRow row in placeholders) row.id,
    };
    final List<String> removedPaths = <String>[
      for (final MediaRow row in placeholders) row.path,
    ];

    await database.transaction<void>(() async {
      for (final MediaRow row in placeholders) {
        await (database.delete(
          database.media,
        )..where((table) => table.id.equals(row.id))).go();
      }
      // Карточки, ссылающиеся на заглушки (в том числе парные `basic_reversed`):
      // убираем id из обеих сторон. Битую карточку не перезаписываем.
      final List<CardRow> cards = await database.select(database.cards).get();
      for (final CardRow card in cards) {
        final CardMediaSides? decoded = CardMediaSides.tryDecode(
          card.mediaJson,
        );
        if (decoded == null) continue;
        // Legacy-массив не знает стороны: безопасная политика ADR-042
        // (occlusion/cloze — стимул вопроса, остальное — ответ).
        final bool legacy = card.mediaJson.trimLeft().startsWith('[');
        final CardMediaSides sides = legacy
            ? CardMediaSides.fromLegacy(
                decoded.question,
                stimulus:
                    card.occlusionJson != null || card.cardType == 'cloze',
              )
            : decoded;
        final bool changed =
            sides.question.any(removedIds.contains) ||
            sides.answer.any(removedIds.contains);
        if (!changed) continue;
        final CardMediaSides updated = CardMediaSides(
          question: List<String>.unmodifiable(
            sides.question.where((String id) => !removedIds.contains(id)),
          ),
          answer: List<String>.unmodifiable(
            sides.answer.where((String id) => !removedIds.contains(id)),
          ),
        );
        await (database.update(database.cards)
              ..where((table) => table.id.equals(card.id)))
            .write(CardsCompanion(mediaJson: Value<String>(updated.encode())));
      }
    });

    // Файлы удаляются после фиксации БД: недоступный файл не откатывает данные,
    // а сирота будет удалён консервативным GC при следующем старте.
    for (final String path in removedPaths) {
      try {
        await mediaStore.deleteMedia(path);
      } on Object {
        // См. комментарий выше.
      }
    }
    return placeholders.length;
  }
}
