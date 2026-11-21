import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart' hide ArchiveException;

import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/transfer/archive_codec.dart';
import 'package:cardflow/domain/transfer/deck_archive.dart';

/// Реализация кодека публичного `.zip`-формата колоды v1 (SPEC 0.4.4, A6.9).
///
/// Проводной контракт (ADR-006, `docs/archive-format.md`):
/// - zip-записи ровно `meta.json`, `cards.json`, `media/<media_id>`;
/// - `meta.json` — UTF-8 JSON: `format_version`, `app`, `exported_at`
///   (ISO-8601 UTC), `deck` (id, name, settings, created_at, updated_at,
///   archived_at), `cards_count`, `media_count`;
/// - `cards.json` — UTF-8 JSON `{"cards": [...]}`: все поля карточки, моменты
///   времени — epoch ms; медиа-ссылки карточки — объекты
///   `{id, card_id, path, mime_type}`;
/// - байты медиа — в записи `media/<id>` без расширения (MIME — в `cards.json`).
///
/// Инварианты реализации:
/// - порядок записей при encode детерминирован: `meta.json`, `cards.json`,
///   медиа по возрастанию id;
/// - JSON кодируется без лишних полей, только поля v1;
/// - decode валидирует лимиты, имена записей (zip-slip) и типы, наружу
///   отдаёт только [ArchiveException] с машинным кодом.
class ZipDeckArchiveCodec implements DeckArchiveCodec {
  /// Создаёт кодек.
  ///
  /// Лимиты инжектируются для тестов; по умолчанию — [DeckArchiveLimits].
  const ZipDeckArchiveCodec({
    this.maxImportBytes = DeckArchiveLimits.maxImportBytes,
    this.maxUncompressedBytes = DeckArchiveLimits.maxUncompressedBytes,
    this.maxJsonEntryBytes = DeckArchiveLimits.maxJsonEntryBytes,
    this.maxEntries = DeckArchiveLimits.maxEntries,
  });

  /// Максимальный размер входного zip-файла, байт.
  final int maxImportBytes;

  /// Максимальный суммарный размер распакованных данных, байт.
  final int maxUncompressedBytes;

  /// Максимальный размер `meta.json`/`cards.json`, байт.
  final int maxJsonEntryBytes;

  /// Максимальное количество записей в zip-архиве.
  final int maxEntries;

  @override
  Uint8List encode(DeckArchive archive) {
    if (archive.formatVersion != deckArchiveFormatVersion) {
      throw ArchiveException(
        ArchiveErrorCode.unsupportedVersion,
        details: 'encode: format_version=${archive.formatVersion}',
      );
    }

    final mediaById = _validateArchiveMedia(archive.media);
    final cardsJson = <Map<String, Object?>>[];
    final referencedMedia = <String>{};
    final cardIds = <String>{};
    for (final card in archive.cards) {
      if (!cardIds.add(card.id)) {
        throw ArchiveException(
          ArchiveErrorCode.invalidCards,
          details: 'encode: дубликат id карточки ${card.id}',
        );
      }
      final cardMedia = <ArchiveMedia>[];
      for (final mediaId in card.mediaIds) {
        final media = mediaById[mediaId];
        if (media == null) {
          throw ArchiveException(
            ArchiveErrorCode.mediaMissing,
            details: 'encode: нет медиа $mediaId для карточки ${card.id}',
          );
        }
        if (media.cardId != card.id) {
          throw ArchiveException(
            ArchiveErrorCode.invalidCards,
            details:
                'encode: media ${media.id} принадлежит '
                '${media.cardId}, а не ${card.id}',
          );
        }
        if (!referencedMedia.add(media.id)) {
          throw ArchiveException(
            ArchiveErrorCode.invalidCards,
            details: 'encode: media ${media.id} привязан к двум карточкам',
          );
        }
        cardMedia.add(media);
      }
      cardsJson.add(_cardToJson(card, cardMedia));
    }
    for (final mediaId in mediaById.keys) {
      if (!referencedMedia.contains(mediaId)) {
        throw ArchiveException(
          ArchiveErrorCode.invalidCards,
          details: 'encode: media $mediaId не привязан ни к одной карточке',
        );
      }
    }

    final metaBytes = _encodeJson(
      _metaToJson(archive),
      ArchiveErrorCode.invalidMeta,
    );
    final cardsBytes = _encodeJson(<String, Object?>{
      'cards': cardsJson,
    }, ArchiveErrorCode.invalidCards);
    _checkEncodeSizes(metaBytes, cardsBytes, archive.media);

    final zipArchive = Archive()
      ..add(ArchiveFile.bytes(DeckArchiveEntries.meta, metaBytes))
      ..add(ArchiveFile.bytes(DeckArchiveEntries.cards, cardsBytes));
    final sortedMedia = <ArchiveMedia>[...archive.media]
      ..sort((ArchiveMedia a, ArchiveMedia b) => a.id.compareTo(b.id));
    for (final media in sortedMedia) {
      zipArchive.add(
        ArchiveFile.bytes(
          '${DeckArchiveEntries.mediaDir}${media.id}',
          media.bytes,
        ),
      );
    }
    try {
      return ZipEncoder().encodeBytes(
        zipArchive,
        modified: archive.exportedAt.toUtc(),
      );
    } finally {
      zipArchive.clearSync();
    }
  }

  @override
  DeckArchive decode(Uint8List zipBytes) {
    if (zipBytes.isEmpty) {
      throw const ArchiveException(
        ArchiveErrorCode.corruptZip,
        details: 'decode: пустой файл',
      );
    }
    if (zipBytes.length > maxImportBytes) {
      throw ArchiveException(
        ArchiveErrorCode.tooLarge,
        details: 'decode: вход ${zipBytes.length} > $maxImportBytes байт',
      );
    }

    final rawArchive = _decodeZip(zipBytes);
    // Лимит количества записей (M8): проверяется до валидации содержимого,
    // чтобы архив из миллионов записей не съел память/время.
    if (rawArchive.files.length > maxEntries) {
      throw ArchiveException(
        ArchiveErrorCode.tooLarge,
        details: 'decode: записей ${rawArchive.files.length} > $maxEntries',
      );
    }
    final entries = _validateEntries(rawArchive);
    final metaFile = entries[DeckArchiveEntries.meta];
    if (metaFile == null) {
      throw const ArchiveException(
        ArchiveErrorCode.missingEntry,
        details: 'decode: нет meta.json',
      );
    }
    final metaBytes = _readEntry(metaFile);
    _checkJsonEntrySize(metaBytes, DeckArchiveEntries.meta);
    final meta = _decodeJsonMap(
      metaBytes,
      ArchiveErrorCode.invalidMeta,
      DeckArchiveEntries.meta,
    );
    final formatVersion = _decodeFormatVersion(meta);
    _decodeApp(meta);
    final exportedAt = _decodeExportedAt(meta);
    final deck = _deckFromJson(
      _requiredMap(meta, 'deck', ArchiveErrorCode.invalidMeta, 'meta'),
    );
    final declaredCardsCount = _decodeCount(meta, 'cards_count');
    final declaredMediaCount = _decodeCount(meta, 'media_count');
    final mediaFiles = <String, ArchiveFile>{};
    for (final entry in entries.entries) {
      if (entry.key.startsWith(DeckArchiveEntries.mediaDir)) {
        mediaFiles[entry.key.substring(DeckArchiveEntries.mediaDir.length)] =
            entry.value;
      }
    }

    final cardsFile = entries[DeckArchiveEntries.cards];
    if (cardsFile == null) {
      throw const ArchiveException(
        ArchiveErrorCode.missingEntry,
        details: 'decode: нет cards.json',
      );
    }
    final cardsBytes = _readEntry(cardsFile);
    _checkJsonEntrySize(cardsBytes, DeckArchiveEntries.cards);
    final cardsRoot = _decodeJsonMap(
      cardsBytes,
      ArchiveErrorCode.invalidCards,
      DeckArchiveEntries.cards,
    );
    final cardsRaw = cardsRoot['cards'];
    if (cardsRaw is! List) {
      throw const ArchiveException(
        ArchiveErrorCode.invalidCards,
        details: 'cards.json: cards не список',
      );
    }

    final cardIds = <String>{};
    final mediaRefs = <_MediaRef>[];
    final cards = <Card>[];
    for (var index = 0; index < cardsRaw.length; index++) {
      final path = 'cards[$index]';
      final cardJson = _jsonMap(
        cardsRaw[index],
        ArchiveErrorCode.invalidCards,
        path,
      );
      cards.add(_cardFromJson(cardJson, path, cardIds, mediaRefs));
    }

    final referencedMedia = <String>{};
    final media = <ArchiveMedia>[];
    for (final ref in mediaRefs) {
      if (!referencedMedia.add(ref.id)) {
        throw ArchiveException(
          ArchiveErrorCode.invalidCards,
          details: 'cards.json: дубликат media.id ${ref.id}',
        );
      }
      final mediaFile = mediaFiles[ref.id];
      if (mediaFile == null) {
        throw ArchiveException(
          ArchiveErrorCode.mediaMissing,
          details: 'decode: нет записи media/${ref.id}',
        );
      }
      media.add(
        ArchiveMedia(
          id: ref.id,
          cardId: ref.cardId,
          path: ref.path,
          mimeType: ref.mimeType,
          bytes: _readEntry(mediaFile),
        ),
      );
    }
    final orphanMedia = mediaFiles.keys
        .where((String id) => !referencedMedia.contains(id))
        .toList();
    if (orphanMedia.isNotEmpty) {
      throw ArchiveException(
        ArchiveErrorCode.invalidEntryName,
        details: 'decode: медиа без владельца: ${orphanMedia.join(', ')}',
      );
    }
    // docs/archive-format.md: cards_count/media_count справочные, но при
    // импорте проверяются на соответствие содержимому архива.
    if (declaredCardsCount != cards.length) {
      throw ArchiveException(
        ArchiveErrorCode.invalidMeta,
        details:
            'meta.cards_count=$declaredCardsCount, '
            'в cards.json ${cards.length}',
      );
    }
    if (declaredMediaCount != media.length) {
      throw ArchiveException(
        ArchiveErrorCode.invalidMeta,
        details:
            'meta.media_count=$declaredMediaCount, '
            'в media/ ${media.length}',
      );
    }

    return DeckArchive(
      formatVersion: formatVersion,
      exportedAt: exportedAt,
      deck: deck,
      cards: cards,
      media: media,
    );
  }

  // --- encode ---

  Map<String, ArchiveMedia> _validateArchiveMedia(List<ArchiveMedia> media) {
    final mediaById = <String, ArchiveMedia>{};
    for (final item in media) {
      final id = item.id;
      if (id.isEmpty ||
          id.contains('/') ||
          id.contains('\\') ||
          id == '.' ||
          id == '..') {
        throw ArchiveException(
          ArchiveErrorCode.invalidCards,
          details: 'encode: недопустимый media.id "$id"',
        );
      }
      if (mediaById.containsKey(id)) {
        throw ArchiveException(
          ArchiveErrorCode.invalidCards,
          details: 'encode: дубликат media.id $id',
        );
      }
      mediaById[id] = item;
    }
    return mediaById;
  }

  Map<String, Object?> _metaToJson(DeckArchive archive) => <String, Object?>{
    'format_version': deckArchiveFormatVersion,
    'app': deckArchiveAppName,
    'exported_at': archive.exportedAt.toUtc().toIso8601String(),
    'deck': _deckToJson(archive.deck),
    'cards_count': archive.cards.length,
    'media_count': archive.media.length,
  };

  Map<String, Object?> _deckToJson(ArchiveDeck deck) => <String, Object?>{
    'id': deck.id,
    'name': deck.name,
    'settings': deck.settings,
    'created_at': _epochMillis(deck.createdAt),
    'updated_at': _epochMillis(deck.updatedAt),
    'archived_at': deck.archivedAt == null
        ? null
        : _epochMillis(deck.archivedAt!),
  };

  Map<String, Object?> _cardToJson(Card card, List<ArchiveMedia> media) =>
      <String, Object?>{
        'id': card.id,
        'deck_id': card.deckId,
        'front': card.front,
        'back': card.back,
        'hint': card.hint,
        'card_type': card.cardType.wireName,
        'tags': card.tags,
        'media': <Map<String, Object?>>[
          for (final item in media)
            <String, Object?>{
              'id': item.id,
              'card_id': item.cardId,
              'path': item.path,
              'mime_type': item.mimeType,
            },
        ],
        // 7.19 (ADR-042): стороны изображений; старые архивы без этих ключей
        // читаются как «всё на стороне вопроса».
        'question_media_ids': card.questionMediaIds,
        'answer_media_ids': card.answerMediaIds,
        'latex': card.latex,
        'occlusion': card.occlusionJson,
        'source_doc_id': card.sourceDocId,
        'source_excerpt': card.sourceExcerpt,
        'state': card.state.wireName,
        'fsrs': card.fsrsJson,
        'due': card.due == null ? null : _epochMillis(card.due!),
        'suspended': card.suspended,
        'buried_until': card.buriedUntil == null
            ? null
            : _epochMillis(card.buriedUntil!),
        'flagged': card.flagged,
        'sibling_id': card.siblingId,
        'content_hash': card.contentHash,
        'created_at': _epochMillis(card.createdAt),
        'updated_at': _epochMillis(card.updatedAt),
      };

  Uint8List _encodeJson(Object? value, ArchiveErrorCode code) {
    try {
      return utf8.encode(jsonEncode(value));
    } catch (error) {
      throw ArchiveException(
        code,
        details: 'encode: JSON не сериализуется ($error)',
      );
    }
  }

  void _checkEncodeSizes(
    Uint8List metaBytes,
    Uint8List cardsBytes,
    List<ArchiveMedia> media,
  ) {
    if (metaBytes.length > maxJsonEntryBytes) {
      throw ArchiveException(
        ArchiveErrorCode.tooLarge,
        details: 'encode: meta.json ${metaBytes.length} > $maxJsonEntryBytes',
      );
    }
    if (cardsBytes.length > maxJsonEntryBytes) {
      throw ArchiveException(
        ArchiveErrorCode.tooLarge,
        details: 'encode: cards.json ${cardsBytes.length} > $maxJsonEntryBytes',
      );
    }
    var total = metaBytes.length + cardsBytes.length;
    for (final item in media) {
      total += item.bytes.length;
    }
    if (total > maxUncompressedBytes) {
      throw ArchiveException(
        ArchiveErrorCode.tooLarge,
        details: 'encode: распакованный размер $total > $maxUncompressedBytes',
      );
    }
  }

  // --- decode ---

  Archive _decodeZip(Uint8List bytes) {
    try {
      return ZipDecoder().decodeBytes(bytes, verify: true, throwOnError: true);
    } catch (error) {
      throw ArchiveException(
        ArchiveErrorCode.corruptZip,
        details: 'decode: zip не читается ($error)',
      );
    }
  }

  Map<String, ArchiveFile> _validateEntries(Archive archive) {
    final entries = <String, ArchiveFile>{};
    var totalSize = 0;
    for (final file in archive.files) {
      final name = file.name;
      if (!file.isFile && name == DeckArchiveEntries.mediaDir) {
        // Некоторые архиваторы (например, darwin) пишут явную запись-каталог
        // `media/`; данных в ней нет — игнорируем (ADR-006).
        continue;
      }
      _validateEntryName(name);
      if (!file.isFile) {
        throw ArchiveException(
          ArchiveErrorCode.invalidEntryName,
          details: 'decode: запись "$name" — каталог, ожидался файл',
        );
      }
      if (entries.containsKey(name)) {
        throw ArchiveException(
          ArchiveErrorCode.invalidEntryName,
          details: 'decode: дубликат записи "$name"',
        );
      }
      entries[name] = file;
      final size = file.size;
      if (size < 0 || size > maxUncompressedBytes) {
        throw ArchiveException(
          ArchiveErrorCode.tooLarge,
          details: 'decode: запись "$name" размером $size байт',
        );
      }
      if ((name == DeckArchiveEntries.meta ||
              name == DeckArchiveEntries.cards) &&
          size > maxJsonEntryBytes) {
        throw ArchiveException(
          ArchiveErrorCode.tooLarge,
          details: 'decode: "$name" размером $size байт',
        );
      }
      totalSize += size;
    }
    if (totalSize > maxUncompressedBytes) {
      throw ArchiveException(
        ArchiveErrorCode.tooLarge,
        details: 'decode: распакованный размер $totalSize байт',
      );
    }
    return entries;
  }

  void _validateEntryName(String name) {
    final isJson =
        name == DeckArchiveEntries.meta || name == DeckArchiveEntries.cards;
    if (isJson) {
      return;
    }
    final invalid =
        name.isEmpty ||
        name.contains('\\') ||
        name.startsWith('/') ||
        name.endsWith('/') ||
        _windowsDrive.hasMatch(name) ||
        !name.startsWith(DeckArchiveEntries.mediaDir);
    if (invalid) {
      throw ArchiveException(
        ArchiveErrorCode.invalidEntryName,
        details: 'decode: недопустимое имя записи "$name"',
      );
    }
    final mediaId = name.substring(DeckArchiveEntries.mediaDir.length);
    if (mediaId.isEmpty ||
        mediaId.contains('/') ||
        mediaId == '.' ||
        mediaId == '..') {
      throw ArchiveException(
        ArchiveErrorCode.invalidEntryName,
        details: 'decode: недопустимое имя медиа "$name"',
      );
    }
  }

  static final RegExp _windowsDrive = RegExp(r'^[A-Za-z]:');

  Uint8List _readEntry(ArchiveFile file) {
    Uint8List bytes;
    try {
      bytes = file.readBytes() ?? Uint8List(0);
    } catch (error) {
      throw ArchiveException(
        ArchiveErrorCode.corruptZip,
        details: 'decode ${file.name}: данные не читаются ($error)',
      );
    }
    if (bytes.length != file.size) {
      throw ArchiveException(
        ArchiveErrorCode.corruptZip,
        details:
            'decode ${file.name}: фактический размер ${bytes.length} '
            'не совпадает с заявленным ${file.size}',
      );
    }
    return bytes;
  }

  void _checkJsonEntrySize(Uint8List bytes, String name) {
    if (bytes.length > maxJsonEntryBytes) {
      throw ArchiveException(
        ArchiveErrorCode.tooLarge,
        details: 'decode: "$name" размером ${bytes.length} байт',
      );
    }
  }

  Map<String, Object?> _decodeJsonMap(
    Uint8List bytes,
    ArchiveErrorCode code,
    String entryName,
  ) {
    Object? decoded;
    try {
      decoded = jsonDecode(utf8.decode(bytes));
    } on FormatException catch (error) {
      throw ArchiveException(
        code,
        details: '$entryName: некорректный UTF-8/JSON (${error.message})',
      );
    }
    return _jsonMap(decoded, code, entryName);
  }

  Map<String, Object?> _jsonMap(
    Object? value,
    ArchiveErrorCode code,
    String path,
  ) {
    if (value is! Map) {
      throw ArchiveException(code, details: '$path: ожидался JSON-объект');
    }
    final result = <String, Object?>{};
    for (final entry in value.entries) {
      final key = entry.key;
      if (key is! String) {
        throw ArchiveException(code, details: '$path: ключ не строка');
      }
      result[key] = entry.value;
    }
    return result;
  }

  int _decodeFormatVersion(Map<String, Object?> meta) {
    final value = meta['format_version'];
    if (value is! int) {
      throw const ArchiveException(
        ArchiveErrorCode.invalidMeta,
        details: 'meta.format_version: ожидалось целое',
      );
    }
    if (value != deckArchiveFormatVersion) {
      throw ArchiveException(
        ArchiveErrorCode.unsupportedVersion,
        details: 'meta.format_version=$value',
      );
    }
    return value;
  }

  /// Проверяет обязательное поле `app` (docs/archive-format.md: всегда
  /// `"CardFlow"`).
  void _decodeApp(Map<String, Object?> meta) {
    final value = meta['app'];
    if (value is! String) {
      throw const ArchiveException(
        ArchiveErrorCode.invalidMeta,
        details: 'meta.app: ожидалась строка',
      );
    }
    if (value != deckArchiveAppName) {
      throw ArchiveException(
        ArchiveErrorCode.invalidMeta,
        details: 'meta.app="$value", ожидалось "$deckArchiveAppName"',
      );
    }
  }

  DateTime _decodeExportedAt(Map<String, Object?> meta) {
    final value = meta['exported_at'];
    if (value is! String) {
      throw const ArchiveException(
        ArchiveErrorCode.invalidMeta,
        details: 'meta.exported_at: ожидалась ISO-8601 строка',
      );
    }
    final parsed = DateTime.tryParse(value);
    if (parsed == null) {
      throw const ArchiveException(
        ArchiveErrorCode.invalidMeta,
        details: 'meta.exported_at: некорректная дата',
      );
    }
    return parsed;
  }

  int _decodeCount(Map<String, Object?> meta, String key) {
    final value = meta[key];
    if (value is! int || value < 0) {
      throw ArchiveException(
        ArchiveErrorCode.invalidMeta,
        details: 'meta.$key: ожидалось неотрицательное целое',
      );
    }
    return value;
  }

  ArchiveDeck _deckFromJson(Map<String, Object?> json) {
    const code = ArchiveErrorCode.invalidMeta;
    final id = _requiredString(json, 'id', code, 'meta.deck');
    if (id.isEmpty) {
      throw const ArchiveException(
        code,
        details: 'meta.deck.id: пустая строка',
      );
    }
    final name = _requiredString(json, 'name', code, 'meta.deck');
    // M10: пустое/пробельное имя колоды недопустимо.
    if (name.trim().isEmpty) {
      throw const ArchiveException(
        code,
        details: 'meta.deck.name: пустое имя колоды',
      );
    }
    return ArchiveDeck(
      id: id,
      name: name,
      settings: _requiredMap(json, 'settings', code, 'meta.deck'),
      createdAt: _requiredDateTimeMs(json, 'created_at', code, 'meta.deck'),
      updatedAt: _requiredDateTimeMs(json, 'updated_at', code, 'meta.deck'),
      archivedAt: _requiredNullableDateTimeMs(
        json,
        'archived_at',
        code,
        'meta.deck',
      ),
    );
  }

  Card _cardFromJson(
    Map<String, Object?> json,
    String path,
    Set<String> cardIds,
    List<_MediaRef> mediaRefs,
  ) {
    const code = ArchiveErrorCode.invalidCards;
    final id = _requiredString(json, 'id', code, path);
    if (id.isEmpty) {
      throw ArchiveException(code, details: '$path.id: пустая строка');
    }
    if (!cardIds.add(id)) {
      throw ArchiveException(code, details: '$path: дубликат id карточки $id');
    }
    final front = _requiredString(json, 'front', code, path);
    if (front.isEmpty) {
      throw ArchiveException(code, details: '$path.front: пустая строка');
    }
    final tags = _requiredStringList(json, 'tags', code, path);
    // docs/archive-format.md: тегов не больше трёх (SPEC A5).
    if (tags.length > 3) {
      throw ArchiveException(
        code,
        details: '$path.tags: ${tags.length}, допустимо не больше 3',
      );
    }
    final cardType = _enumFromWire(
      _requiredString(json, 'card_type', code, path),
      CardType.fromWire,
      code,
      '$path.card_type',
    );
    final state = _enumFromWire(
      _requiredString(json, 'state', code, path),
      CardState.fromWire,
      code,
      '$path.state',
    );

    final mediaRaw = json['media'];
    if (mediaRaw is! List) {
      throw ArchiveException(code, details: '$path.media: ожидался список');
    }
    final mediaIds = <String>[];
    for (var index = 0; index < mediaRaw.length; index++) {
      final ref = _mediaRefFromJson(
        _jsonMap(mediaRaw[index], code, '$path.media[$index]'),
        '$path.media[$index]',
        id,
      );
      mediaIds.add(ref.id);
      mediaRefs.add(ref);
    }

    final bool hasSides =
        json.containsKey('question_media_ids') ||
        json.containsKey('answer_media_ids');
    final List<String> questionMediaIds = hasSides
        ? _sideMediaIds(
            json['question_media_ids'],
            mediaIds: mediaIds,
            code: code,
            path: '$path.question_media_ids',
          )
        : mediaIds;
    final List<String> answerMediaIds = hasSides
        ? _sideMediaIds(
            json['answer_media_ids'],
            mediaIds: mediaIds,
            code: code,
            path: '$path.answer_media_ids',
          )
        : const <String>[];
    if (hasSides) {
      final Set<String> union = <String>{
        ...questionMediaIds,
        ...answerMediaIds,
      };
      if (union.length != mediaIds.length || !union.containsAll(mediaIds)) {
        throw ArchiveException(
          code,
          details: '$path: стороны не покрывают список media',
        );
      }
    }

    return Card(
      id: id,
      deckId: _requiredString(json, 'deck_id', code, path),
      front: front,
      back: _requiredString(json, 'back', code, path),
      hint: _requiredNullableString(json, 'hint', code, path),
      cardType: cardType,
      tags: tags,
      questionMediaIds: questionMediaIds,
      answerMediaIds: answerMediaIds,
      latex: _requiredNullableString(json, 'latex', code, path),
      occlusionJson: _requiredNullableString(json, 'occlusion', code, path),
      sourceDocId: _requiredNullableString(json, 'source_doc_id', code, path),
      sourceExcerpt: _requiredNullableString(
        json,
        'source_excerpt',
        code,
        path,
      ),
      state: state,
      fsrsJson: _requiredNullableString(json, 'fsrs', code, path),
      due: _requiredNullableDateTimeMs(json, 'due', code, path),
      suspended: _requiredBool(json, 'suspended', code, path),
      buriedUntil: _requiredNullableDateTimeMs(
        json,
        'buried_until',
        code,
        path,
      ),
      flagged: _requiredBool(json, 'flagged', code, path),
      siblingId: _requiredNullableString(json, 'sibling_id', code, path),
      contentHash: _requiredNullableString(json, 'content_hash', code, path),
      createdAt: _requiredDateTimeMs(json, 'created_at', code, path),
      updatedAt: _requiredDateTimeMs(json, 'updated_at', code, path),
    );
  }

  /// Список id стороны архива: только id из `media` карточки, без повторов.
  List<String> _sideMediaIds(
    Object? raw, {
    required List<String> mediaIds,
    required ArchiveErrorCode code,
    required String path,
  }) {
    if (raw == null) return const <String>[];
    if (raw is! List) {
      throw ArchiveException(code, details: '$path: ожидался список');
    }
    final Set<String> available = mediaIds.toSet();
    final List<String> result = <String>[];
    for (var index = 0; index < raw.length; index++) {
      final Object? value = raw[index];
      if (value is! String || value.isEmpty) {
        throw ArchiveException(
          code,
          details: '$path[$index]: ожидался непустой id',
        );
      }
      if (!available.contains(value)) {
        throw ArchiveException(
          code,
          details: '$path[$index]: id $value отсутствует в media карточки',
        );
      }
      if (result.contains(value)) {
        throw ArchiveException(
          code,
          details: '$path[$index]: повтор id $value',
        );
      }
      result.add(value);
    }
    return List<String>.unmodifiable(result);
  }

  _MediaRef _mediaRefFromJson(
    Map<String, Object?> json,
    String path,
    String cardId,
  ) {
    const code = ArchiveErrorCode.invalidCards;
    final id = _requiredString(json, 'id', code, path);
    if (id.isEmpty) {
      throw ArchiveException(code, details: '$path.id: пустая строка');
    }
    final ownerId = _requiredString(json, 'card_id', code, path);
    if (ownerId != cardId) {
      throw ArchiveException(
        code,
        details: '$path.card_id: $ownerId, ожидалось $cardId',
      );
    }
    final mediaPath = _requiredString(json, 'path', code, path);
    if (mediaPath.isEmpty) {
      throw ArchiveException(code, details: '$path.path: пустая строка');
    }
    final mimeType = _requiredString(json, 'mime_type', code, path);
    if (mimeType.isEmpty) {
      throw ArchiveException(code, details: '$path.mime_type: пустая строка');
    }
    return _MediaRef(
      id: id,
      cardId: ownerId,
      path: mediaPath,
      mimeType: mimeType,
    );
  }

  T _enumFromWire<T>(
    String wire,
    T Function(String) parse,
    ArchiveErrorCode code,
    String path,
  ) {
    try {
      return parse(wire);
    } on FormatException catch (error) {
      throw ArchiveException(code, details: '$path: ${error.message}');
    }
  }

  String _requiredString(
    Map<String, Object?> json,
    String key,
    ArchiveErrorCode code,
    String path,
  ) {
    final value = json[key];
    if (value is! String) {
      throw ArchiveException(code, details: '$path.$key: ожидалась строка');
    }
    return value;
  }

  /// Обязательный по контракту ключ, значение которого может быть `null`.
  String? _requiredNullableString(
    Map<String, Object?> json,
    String key,
    ArchiveErrorCode code,
    String path,
  ) {
    if (!json.containsKey(key)) {
      throw ArchiveException(
        code,
        details: '$path.$key: отсутствует обязательное поле',
      );
    }
    final value = json[key];
    if (value == null) {
      return null;
    }
    if (value is! String) {
      throw ArchiveException(code, details: '$path.$key: ожидалась строка');
    }
    return value;
  }

  bool _requiredBool(
    Map<String, Object?> json,
    String key,
    ArchiveErrorCode code,
    String path,
  ) {
    final value = json[key];
    if (value is! bool) {
      throw ArchiveException(code, details: '$path.$key: ожидалось true/false');
    }
    return value;
  }

  List<String> _requiredStringList(
    Map<String, Object?> json,
    String key,
    ArchiveErrorCode code,
    String path,
  ) {
    final value = json[key];
    if (value is! List) {
      throw ArchiveException(code, details: '$path.$key: ожидался список');
    }
    final result = <String>[];
    for (final item in value) {
      if (item is! String) {
        throw ArchiveException(
          code,
          details: '$path.$key: ожидался список строк',
        );
      }
      result.add(item);
    }
    return result;
  }

  Map<String, Object?> _requiredMap(
    Map<String, Object?> json,
    String key,
    ArchiveErrorCode code,
    String path,
  ) {
    final value = json[key];
    if (value is! Map) {
      throw ArchiveException(code, details: '$path.$key: ожидался объект');
    }
    return _jsonMap(value, code, '$path.$key');
  }

  DateTime _requiredDateTimeMs(
    Map<String, Object?> json,
    String key,
    ArchiveErrorCode code,
    String path,
  ) {
    final value = json[key];
    if (value is! int) {
      throw ArchiveException(
        code,
        details: '$path.$key: ожидалось целое (epoch ms)',
      );
    }
    return _dateTimeFromMs(value);
  }

  /// Обязательный по контракту ключ, значение которого может быть `null`.
  DateTime? _requiredNullableDateTimeMs(
    Map<String, Object?> json,
    String key,
    ArchiveErrorCode code,
    String path,
  ) {
    if (!json.containsKey(key)) {
      throw ArchiveException(
        code,
        details: '$path.$key: отсутствует обязательное поле',
      );
    }
    final value = json[key];
    if (value == null) {
      return null;
    }
    if (value is! int) {
      throw ArchiveException(
        code,
        details: '$path.$key: ожидалось целое (epoch ms)',
      );
    }
    return _dateTimeFromMs(value);
  }

  int _epochMillis(DateTime value) => value.toUtc().millisecondsSinceEpoch;

  DateTime _dateTimeFromMs(int milliseconds) =>
      DateTime.fromMillisecondsSinceEpoch(milliseconds, isUtc: true);
}

/// Ссылка карточки на медиафайл из `cards.json`.
class _MediaRef {
  const _MediaRef({
    required this.id,
    required this.cardId,
    required this.path,
    required this.mimeType,
  });

  final String id;
  final String cardId;
  final String path;
  final String mimeType;
}
