import 'dart:convert';
import 'dart:typed_data';

import 'package:archive/archive.dart' hide ArchiveException;
import 'package:cardflow/data/transfer/zip_deck_archive_codec.dart';
import 'package:cardflow/domain/cards/card.dart';
import 'package:cardflow/domain/transfer/deck_archive.dart';
import 'package:flutter_test/flutter_test.dart';

/// Тесты публичного `.zip`-формата колоды v1 (SPEC 0.4.4, A6.9; ADR-006).
///
/// Проверяют проводной контракт (имена записей, поля JSON, типы), валидацию
/// импорта и roundtrip без потерь.

const ZipDeckArchiveCodec _codec = ZipDeckArchiveCodec();

final DateTime _exportedAt = DateTime.utc(2026, 11, 12, 10, 30, 5, 123);
final DateTime _deckCreatedAt = DateTime.utc(2026, 11, 1, 8);
final DateTime _deckUpdatedAt = DateTime.utc(2026, 11, 10, 21, 15, 30, 500);
final DateTime _cardCreatedAt = DateTime.utc(2026, 11, 2, 10);
final DateTime _cardUpdatedAt = DateTime.utc(2026, 11, 9, 18, 40, 12, 250);
final DateTime _due = DateTime.utc(2026, 11, 20, 9);
final DateTime _buriedUntil = DateTime.utc(2026, 11, 13, 9);

final Map<String, Object?> _settings = <String, Object?>{
  'retention': 0.9,
  'new_per_day': 20,
  'nested': <String, Object?>{
    'list': <Object?>[1, 'два', true],
  },
};

/// Собирает запись медиа с переопределяемыми полями.
ArchiveMedia _media({
  String id = 'media-1',
  String cardId = 'card-1',
  String path = 'media/media-1.png',
  String mimeType = 'image/png',
  List<int> bytes = const <int>[1, 2, 3],
}) => ArchiveMedia(
  id: id,
  cardId: cardId,
  path: path,
  mimeType: mimeType,
  bytes: Uint8List.fromList(bytes),
);

/// Собирает доменную карточку с переопределяемыми полями.
Card _card({
  String id = 'card-1',
  String deckId = 'deck-1',
  String front = 'Вопрос',
  String back = 'Ответ',
  String? hint,
  CardType cardType = CardType.basic,
  List<String> tags = const <String>[],
  List<String> mediaIds = const <String>[],
  String? latex,
  String? occlusionJson,
  String? sourceDocId,
  String? sourceExcerpt,
  CardState state = CardState.newCard,
  String? fsrsJson,
  DateTime? due,
  bool suspended = false,
  DateTime? buriedUntil,
  bool flagged = false,
  String? siblingId,
  String? contentHash,
  DateTime? createdAt,
  DateTime? updatedAt,
}) => Card(
  id: id,
  deckId: deckId,
  front: front,
  back: back,
  hint: hint,
  cardType: cardType,
  tags: tags,
  mediaIds: mediaIds,
  latex: latex,
  occlusionJson: occlusionJson,
  sourceDocId: sourceDocId,
  sourceExcerpt: sourceExcerpt,
  state: state,
  fsrsJson: fsrsJson,
  due: due,
  suspended: suspended,
  buriedUntil: buriedUntil,
  flagged: flagged,
  siblingId: siblingId,
  contentHash: contentHash,
  createdAt: createdAt ?? _cardCreatedAt,
  updatedAt: updatedAt ?? _cardUpdatedAt,
);

/// Карточка со всеми заполненными полями.
final Card _fullCard = _card(
  id: 'card-1',
  front: 'Что такое интервальное повторение?',
  back: 'Метод повторения с возрастающими интервалами',
  hint: 'Подумай о кривой забывания',
  cardType: CardType.basic,
  tags: const <String>['память', 'fsrs'],
  mediaIds: const <String>['media-1'],
  latex: r'$E = mc^2$',
  sourceDocId: 'doc-1',
  sourceExcerpt: '«Цитата из документа»',
  state: CardState.review,
  fsrsJson: '{"stability":12.5}',
  due: _due,
  suspended: true,
  buriedUntil: _buriedUntil,
  flagged: true,
  siblingId: 'card-3',
  contentHash: 'deadbeef',
);

/// Cloze-карточка: почти все опциональные поля пусты, медиа — пустой файл.
final Card _nullCard = _card(
  id: 'card-2',
  front: 'Пропуск {{c1::ответ}}',
  back: 'ответ',
  cardType: CardType.cloze,
  mediaIds: const <String>['media-2'],
  occlusionJson: '{"masks":[]}',
  state: CardState.newCard,
);

/// Reversed-карточка без медиа.
final Card _reversedCard = _card(
  id: 'card-3',
  front: 'Обратная сторона',
  back: 'Лицевая сторона',
  cardType: CardType.basicReversed,
  tags: const <String>['тег'],
  state: CardState.learning,
  due: _due,
  siblingId: 'card-1',
);

final List<Card> _sampleCards = <Card>[_fullCard, _nullCard, _reversedCard];

final ArchiveMedia _imageMedia = _media(
  bytes: const <int>[137, 80, 78, 71, 13, 10, 26, 10, 0, 1, 2, 255],
);
final ArchiveMedia _emptyMedia = _media(
  id: 'media-2',
  cardId: 'card-2',
  path: 'media/media-2.bin',
  mimeType: 'application/octet-stream',
  bytes: const <int>[],
);

/// Описание колоды для тестовых архивов.
ArchiveDeck _deck({
  String id = 'deck-1',
  String name = 'Колода «Кириллица»',
  Map<String, Object?>? settings,
  DateTime? createdAt,
  DateTime? updatedAt,
  DateTime? archivedAt,
}) => ArchiveDeck(
  id: id,
  name: name,
  settings: settings ?? _settings,
  createdAt: createdAt ?? _deckCreatedAt,
  updatedAt: updatedAt ?? _deckUpdatedAt,
  archivedAt: archivedAt,
);

/// Полный тестовый архив (3 карточки, 2 медиа).
DeckArchive _sampleArchive({
  List<Card>? cards,
  List<ArchiveMedia>? media,
  ArchiveDeck? deck,
  int formatVersion = deckArchiveFormatVersion,
  DateTime? exportedAt,
}) => DeckArchive(
  formatVersion: formatVersion,
  exportedAt: exportedAt ?? _exportedAt,
  deck: deck ?? _deck(),
  cards: cards ?? _sampleCards,
  media: media ?? <ArchiveMedia>[_imageMedia, _emptyMedia],
);

/// Собирает zip из готовых байтов записей (порядок сохраняется).
Uint8List _zipEntries(Map<String, List<int>> entries) {
  final archive = Archive();
  entries.forEach((name, bytes) {
    archive.add(ArchiveFile.bytes(name, bytes));
  });
  return ZipEncoder().encodeBytes(archive);
}

/// Собирает zip с переопределяемыми/отсутствующими raw-записями.
Uint8List _zipOf({
  String? metaRaw,
  String? cardsRaw,
  Map<String, List<int>> media = const <String, List<int>>{},
  Map<String, List<int>> extra = const <String, List<int>>{},
}) {
  final entries = <String, List<int>>{};
  if (metaRaw != null) {
    entries[DeckArchiveEntries.meta] = utf8.encode(metaRaw);
  }
  if (cardsRaw != null) {
    entries[DeckArchiveEntries.cards] = utf8.encode(cardsRaw);
  }
  entries.addAll(media);
  entries.addAll(extra);
  return _zipEntries(entries);
}

/// Валидный zip: meta + cards + медиа; счётчики в meta выводятся из содержимого.
Uint8List _validZip({
  Map<String, Object?>? meta,
  List<Map<String, Object?>> cards = const <Map<String, Object?>>[],
  Map<String, List<int>> media = const <String, List<int>>{},
  Map<String, List<int>> extra = const <String, List<int>>{},
}) => _zipOf(
  metaRaw: jsonEncode(
    meta ?? _metaMap(cardsCount: cards.length, mediaCount: media.length),
  ),
  cardsRaw: jsonEncode(<String, Object?>{'cards': cards}),
  media: media,
  extra: extra,
);

/// Map для `meta.json`.
Map<String, Object?> _metaMap({
  Object? formatVersion = deckArchiveFormatVersion,
  Object? app = deckArchiveAppName,
  Object? exportedAt = '2026-11-12T10:30:05.123Z',
  Object? deck,
  Object? cardsCount = 0,
  Object? mediaCount = 0,
  Set<String> omit = const <String>{},
}) {
  final map = <String, Object?>{
    'format_version': formatVersion,
    'app': app,
    'exported_at': exportedAt,
    'deck': deck ?? _deckMap(),
    'cards_count': cardsCount,
    'media_count': mediaCount,
  };
  map.removeWhere((key, _) => omit.contains(key));
  return map;
}

/// Map для `deck` в `meta.json`.
Map<String, Object?> _deckMap({
  Object? id = 'deck-1',
  Object? name = 'Колода',
  Object? settings = const <String, Object?>{'retention': 0.9},
  Object? createdAt = 1762942205000,
  Object? updatedAt = 1762942205000,
  Object? archivedAt,
  Set<String> omit = const <String>{},
}) {
  final map = <String, Object?>{
    'id': id,
    'name': name,
    'settings': settings,
    'created_at': createdAt,
    'updated_at': updatedAt,
    'archived_at': archivedAt,
  };
  map.removeWhere((key, _) => omit.contains(key));
  return map;
}

/// Map для карточки в `cards.json`.
Map<String, Object?> _cardMap({
  Object? id = 'card-1',
  Object? deckId = 'deck-1',
  Object? front = 'Вопрос',
  Object? back = 'Ответ',
  Object? hint,
  Object? cardType = 'basic',
  Object? tags = const <String>['тег'],
  Object? media = const <Object?>[],
  Object? latex,
  Object? occlusion,
  Object? sourceDocId,
  Object? sourceExcerpt,
  Object? state = 'new',
  Object? fsrs,
  Object? due,
  Object? suspended = false,
  Object? buriedUntil,
  Object? flagged = false,
  Object? siblingId,
  Object? contentHash,
  Object? createdAt = 1762942205000,
  Object? updatedAt = 1762942205000,
  Set<String> omit = const <String>{},
}) {
  final map = <String, Object?>{
    'id': id,
    'deck_id': deckId,
    'front': front,
    'back': back,
    'hint': hint,
    'card_type': cardType,
    'tags': tags,
    'media': media,
    'latex': latex,
    'occlusion': occlusion,
    'source_doc_id': sourceDocId,
    'source_excerpt': sourceExcerpt,
    'state': state,
    'fsrs': fsrs,
    'due': due,
    'suspended': suspended,
    'buried_until': buriedUntil,
    'flagged': flagged,
    'sibling_id': siblingId,
    'content_hash': contentHash,
    'created_at': createdAt,
    'updated_at': updatedAt,
  };
  map.removeWhere((key, _) => omit.contains(key));
  return map;
}

/// Map-описание медиа для карточки в `cards.json`.
Map<String, Object?> _mediaRef({
  Object? id = 'media-1',
  Object? cardId = 'card-1',
  Object? path = 'media/media-1.png',
  Object? mimeType = 'image/png',
  Set<String> omit = const <String>{},
}) {
  final map = <String, Object?>{
    'id': id,
    'card_id': cardId,
    'path': path,
    'mime_type': mimeType,
  };
  map.removeWhere((key, _) => omit.contains(key));
  return map;
}

/// Матчер `ArchiveException` с конкретным машинным кодом.
Matcher _throwsArchiveError(ArchiveErrorCode code) => throwsA(
  isA<ArchiveException>().having(
    (ArchiveException error) => error.code,
    'code',
    code,
  ),
);

/// Проверяет, что медиа совпадает по всем полям.
void _expectMedia(ArchiveMedia actual, ArchiveMedia expected) {
  expect(actual.id, expected.id);
  expect(actual.cardId, expected.cardId);
  expect(actual.path, expected.path);
  expect(actual.mimeType, expected.mimeType);
  expect(actual.bytes, expected.bytes);
}

void main() {
  group('ZipDeckArchiveCodec: encode — публичный формат v1', () {
    test(
      'пишет meta.json, cards.json и media/<id> в детерминированном порядке',
      () {
        final archive = ZipDecoder().decodeBytes(
          _codec.encode(_sampleArchive()),
        );

        expect(
          archive.files.map((ArchiveFile file) => file.name).toList(),
          <String>['meta.json', 'cards.json', 'media/media-1', 'media/media-2'],
        );
      },
    );

    test('meta.json содержит только поля v1, время — ISO-8601 UTC', () {
      final archive = ZipDecoder().decodeBytes(_codec.encode(_sampleArchive()));
      final meta = jsonDecode(
        utf8.decode(archive.find('meta.json')!.readBytes()!),
      ) as Map<String, dynamic>;

      expect(meta.keys.toSet(), <String>{
        'format_version',
        'app',
        'exported_at',
        'deck',
        'cards_count',
        'media_count',
      });
      expect(meta['format_version'], 1);
      expect(meta['app'], 'CardFlow');
      expect(DateTime.parse(meta['exported_at'] as String), _exportedAt);
      expect(meta['cards_count'], 3);
      expect(meta['media_count'], 2);

      final deck = meta['deck'] as Map<String, dynamic>;
      expect(deck.keys.toSet(), <String>{
        'id',
        'name',
        'settings',
        'created_at',
        'updated_at',
        'archived_at',
      });
      expect(deck['id'], 'deck-1');
      expect(deck['name'], 'Колода «Кириллица»');
      expect(deck['settings'], _settings);
      expect(deck['created_at'], _deckCreatedAt.millisecondsSinceEpoch);
      expect(deck['created_at'], isA<int>());
      expect(deck['updated_at'], _deckUpdatedAt.millisecondsSinceEpoch);
      expect(deck['archived_at'], isNull);
    });

    test('cards.json содержит все поля карточки без лишних ключей', () {
      final archive = ZipDecoder().decodeBytes(_codec.encode(_sampleArchive()));
      final cardsJson = jsonDecode(
        utf8.decode(archive.find('cards.json')!.readBytes()!),
      ) as Map<String, dynamic>;

      expect(cardsJson.keys.toSet(), <String>{'cards'});
      final cards = cardsJson['cards'] as List<dynamic>;
      expect(cards, hasLength(3));

      final card = cards.first as Map<String, dynamic>;
      expect(card.keys.toSet(), <String>{
        'id',
        'deck_id',
        'front',
        'back',
        'hint',
        'card_type',
        'tags',
        'media',
        'latex',
        'occlusion',
        'source_doc_id',
        'source_excerpt',
        'state',
        'fsrs',
        'due',
        'suspended',
        'buried_until',
        'flagged',
        'sibling_id',
        'content_hash',
        'created_at',
        'updated_at',
      });
      expect(card['id'], 'card-1');
      expect(card['deck_id'], 'deck-1');
      expect(card['front'], _fullCard.front);
      expect(card['back'], _fullCard.back);
      expect(card['hint'], _fullCard.hint);
      expect(card['card_type'], 'basic');
      expect(card['state'], 'review');
      expect(card['tags'], <String>['память', 'fsrs']);
      expect(card['latex'], r'$E = mc^2$');
      expect(card['occlusion'], isNull);
      expect(card['source_doc_id'], 'doc-1');
      expect(card['source_excerpt'], '«Цитата из документа»');
      expect(card['fsrs'], '{"stability":12.5}');
      expect(card['due'], _due.millisecondsSinceEpoch);
      expect(card['suspended'], isTrue);
      expect(card['buried_until'], _buriedUntil.millisecondsSinceEpoch);
      expect(card['flagged'], isTrue);
      expect(card['sibling_id'], 'card-3');
      expect(card['content_hash'], 'deadbeef');
      expect(card['created_at'], _cardCreatedAt.millisecondsSinceEpoch);
      expect(card['updated_at'], _cardUpdatedAt.millisecondsSinceEpoch);
      expect((card['media'] as List<dynamic>).single, <String, Object?>{
        'id': 'media-1',
        'card_id': 'card-1',
        'path': 'media/media-1.png',
        'mime_type': 'image/png',
      });

      final cloze = cards[1] as Map<String, dynamic>;
      expect(cloze['card_type'], 'cloze');
      expect(cloze['state'], 'new');
      expect(cloze['hint'], isNull);
      expect(cloze['due'], isNull);
      expect(cloze['suspended'], isFalse);
      expect(cloze['flagged'], isFalse);
      expect(cloze['content_hash'], isNull);
      expect((cloze['media'] as List<dynamic>).single, <String, Object?>{
        'id': 'media-2',
        'card_id': 'card-2',
        'path': 'media/media-2.bin',
        'mime_type': 'application/octet-stream',
      });

      final reversed = cards[2] as Map<String, dynamic>;
      expect(reversed['card_type'], 'basic_reversed');
      expect(reversed['state'], 'learning');
      expect(reversed['media'], isEmpty);
    });

    test('повторный encode даёт идентичные байты', () {
      final first = _codec.encode(_sampleArchive());
      final second = _codec.encode(_sampleArchive());

      expect(first, second);
    });

    test('архив с архивной колодой сохраняет archived_at', () {
      final bytes = _codec.encode(
        _sampleArchive(
          deck: _deck(archivedAt: DateTime.utc(2026, 11, 11, 23, 59, 59)),
        ),
      );
      final decoded = _codec.decode(bytes);

      expect(decoded.deck.archivedAt, DateTime.utc(2026, 11, 11, 23, 59, 59));
    });

    test('неизвестная версия формата при encode → unsupportedVersion', () {
      expect(
        () => _codec.encode(_sampleArchive(formatVersion: 2)),
        _throwsArchiveError(ArchiveErrorCode.unsupportedVersion),
      );
    });

    test('карточка ссылается на отсутствующую запись медиа → mediaMissing', () {
      expect(
        () => _codec.encode(
          _sampleArchive(
            cards: <Card>[
              _card(mediaIds: const <String>['media-нет']),
            ],
            media: const <ArchiveMedia>[],
          ),
        ),
        _throwsArchiveError(ArchiveErrorCode.mediaMissing),
      );
    });

    test('media.card_id не совпадает с карточкой → invalidCards', () {
      expect(
        () => _codec.encode(
          _sampleArchive(
            cards: <Card>[
              _card(mediaIds: const <String>['media-1']),
            ],
            media: <ArchiveMedia>[_media(cardId: 'card-чужой')],
          ),
        ),
        _throwsArchiveError(ArchiveErrorCode.invalidCards),
      );
    });

    test('media-запись без карточки-владельца → invalidCards', () {
      expect(
        () => _codec.encode(
          _sampleArchive(
            cards: <Card>[_card()],
            media: <ArchiveMedia>[_media()],
          ),
        ),
        _throwsArchiveError(ArchiveErrorCode.invalidCards),
      );
    });

    test('дубликат media.id в архиве → invalidCards', () {
      expect(
        () => _codec.encode(
          _sampleArchive(
            cards: <Card>[
              _card(mediaIds: const <String>['media-1']),
            ],
            media: <ArchiveMedia>[_media(), _media()],
          ),
        ),
        _throwsArchiveError(ArchiveErrorCode.invalidCards),
      );
    });

    test('суммарный размер больше maxUncompressedBytes → tooLarge', () {
      final codec = ZipDeckArchiveCodec(maxUncompressedBytes: 10);

      expect(
        () => codec.encode(_sampleArchive()),
        _throwsArchiveError(ArchiveErrorCode.tooLarge),
      );
    });

    test('JSON-запись больше maxJsonEntryBytes → tooLarge', () {
      final codec = ZipDeckArchiveCodec(maxJsonEntryBytes: 10);

      expect(
        () => codec.encode(_sampleArchive()),
        _throwsArchiveError(ArchiveErrorCode.tooLarge),
      );
    });
  });

  group('ZipDeckArchiveCodec: roundtrip без потерь', () {
    test('encode→decode сохраняет колоду, карточки, медиа и кириллицу', () {
      final decoded = _codec.decode(_codec.encode(_sampleArchive()));

      expect(decoded.formatVersion, deckArchiveFormatVersion);
      expect(decoded.exportedAt, _exportedAt);

      expect(decoded.deck.id, 'deck-1');
      expect(decoded.deck.name, 'Колода «Кириллица»');
      expect(decoded.deck.settings, _settings);
      expect(decoded.deck.createdAt, _deckCreatedAt);
      expect(decoded.deck.updatedAt, _deckUpdatedAt);
      expect(decoded.deck.archivedAt, isNull);

      expect(decoded.cards, _sampleCards);

      expect(decoded.media, hasLength(2));
      _expectMedia(decoded.media[0], _imageMedia);
      _expectMedia(decoded.media[1], _emptyMedia);
    });

    test('пустая колода (0 карточек) валидна', () {
      final archive = _sampleArchive(
        cards: const <Card>[],
        media: const <ArchiveMedia>[],
      );
      final bytes = _codec.encode(archive);
      final decoded = _codec.decode(bytes);

      expect(decoded.cards, isEmpty);
      expect(decoded.media, isEmpty);
      expect(decoded.deck.id, 'deck-1');

      final meta = jsonDecode(
        utf8.decode(
          ZipDecoder().decodeBytes(bytes).find('meta.json')!.readBytes()!,
        ),
      ) as Map<String, dynamic>;
      expect(meta['cards_count'], 0);
      expect(meta['media_count'], 0);
    });
  });

  group('ZipDeckArchiveCodec: decode — ошибки целостности zip', () {
    test('пустые байты → corruptZip', () {
      expect(
        () => _codec.decode(Uint8List(0)),
        _throwsArchiveError(ArchiveErrorCode.corruptZip),
      );
    });

    test('не zip-данные → corruptZip', () {
      expect(
        () => _codec.decode(Uint8List.fromList(<int>[0xde, 0xad, 0xbe, 0xef])),
        _throwsArchiveError(ArchiveErrorCode.corruptZip),
      );
    });

    test('обрезанный zip → corruptZip', () {
      final full = _codec.encode(_sampleArchive());
      final truncated = Uint8List.sublistView(full, 0, full.length ~/ 2);

      expect(
        () => _codec.decode(truncated),
        _throwsArchiveError(ArchiveErrorCode.corruptZip),
      );
    });

    test('валидный zip без записей → missingEntry', () {
      final emptyZip = ZipEncoder().encodeBytes(Archive());

      expect(
        () => _codec.decode(emptyZip),
        _throwsArchiveError(ArchiveErrorCode.missingEntry),
      );
    });

    test('нет meta.json → missingEntry', () {
      final bytes = _zipOf(
        cardsRaw: jsonEncode(<String, Object?>{'cards': []}),
      );

      expect(
        () => _codec.decode(bytes),
        _throwsArchiveError(ArchiveErrorCode.missingEntry),
      );
    });

    test('нет cards.json → missingEntry', () {
      final bytes = _zipOf(metaRaw: jsonEncode(_metaMap()));

      expect(
        () => _codec.decode(bytes),
        _throwsArchiveError(ArchiveErrorCode.missingEntry),
      );
    });
  });

  group('ZipDeckArchiveCodec: decode — meta.json', () {
    test('format_version != 1 → unsupportedVersion', () {
      final bytes = _validZip(meta: _metaMap(formatVersion: 2));

      expect(
        () => _codec.decode(bytes),
        _throwsArchiveError(ArchiveErrorCode.unsupportedVersion),
      );
    });

    test('format_version не целое → invalidMeta', () {
      final bytes = _validZip(meta: _metaMap(formatVersion: '1'));

      expect(
        () => _codec.decode(bytes),
        _throwsArchiveError(ArchiveErrorCode.invalidMeta),
      );
    });

    test('meta.json не JSON-объект → invalidMeta', () {
      final bytes = _zipOf(
        metaRaw: jsonEncode(<Object?>[1, 2, 3]),
        cardsRaw: jsonEncode(<String, Object?>{'cards': []}),
      );

      expect(
        () => _codec.decode(bytes),
        _throwsArchiveError(ArchiveErrorCode.invalidMeta),
      );
    });

    test('meta.json — битый JSON → invalidMeta', () {
      final bytes = _zipOf(
        metaRaw: '{не json',
        cardsRaw: jsonEncode(<String, Object?>{'cards': []}),
      );

      expect(
        () => _codec.decode(bytes),
        _throwsArchiveError(ArchiveErrorCode.invalidMeta),
      );
    });

    test('нет обязательного поля format_version → invalidMeta', () {
      final bytes = _validZip(meta: _metaMap(omit: <String>{'format_version'}));

      expect(
        () => _codec.decode(bytes),
        _throwsArchiveError(ArchiveErrorCode.invalidMeta),
      );
    });

    test('нет exported_at → invalidMeta', () {
      final bytes = _validZip(meta: _metaMap(omit: <String>{'exported_at'}));

      expect(
        () => _codec.decode(bytes),
        _throwsArchiveError(ArchiveErrorCode.invalidMeta),
      );
    });

    test('нет app → invalidMeta', () {
      final bytes = _validZip(meta: _metaMap(omit: <String>{'app'}));

      expect(
        () => _codec.decode(bytes),
        _throwsArchiveError(ArchiveErrorCode.invalidMeta),
      );
    });

    test('app не "CardFlow" → invalidMeta', () {
      final bytes = _validZip(meta: _metaMap(app: 'OtherApp'));

      expect(
        () => _codec.decode(bytes),
        _throwsArchiveError(ArchiveErrorCode.invalidMeta),
      );
    });

    test('exported_at не ISO-8601 → invalidMeta', () {
      final bytes = _validZip(meta: _metaMap(exportedAt: 'вчера'));

      expect(
        () => _codec.decode(bytes),
        _throwsArchiveError(ArchiveErrorCode.invalidMeta),
      );
    });

    test('нет deck → invalidMeta', () {
      final bytes = _validZip(meta: _metaMap(omit: <String>{'deck'}));

      expect(
        () => _codec.decode(bytes),
        _throwsArchiveError(ArchiveErrorCode.invalidMeta),
      );
    });

    test('deck.id не строка → invalidMeta', () {
      final bytes = _validZip(meta: _metaMap(deck: _deckMap(id: 42)));

      expect(
        () => _codec.decode(bytes),
        _throwsArchiveError(ArchiveErrorCode.invalidMeta),
      );
    });

    test('deck.settings не объект → invalidMeta', () {
      final bytes = _validZip(
        meta: _metaMap(deck: _deckMap(settings: 'not-a-map')),
      );

      expect(
        () => _codec.decode(bytes),
        _throwsArchiveError(ArchiveErrorCode.invalidMeta),
      );
    });

    test('deck.created_at не целое → invalidMeta', () {
      final bytes = _validZip(
        meta: _metaMap(deck: _deckMap(createdAt: '2026-11-01')),
      );

      expect(
        () => _codec.decode(bytes),
        _throwsArchiveError(ArchiveErrorCode.invalidMeta),
      );
    });

    test('неизвестные ключи meta игнорируются (forward-compat)', () {
      final meta = _metaMap()..['future_field'] = <String, Object?>{'a': 1};

      expect(_codec.decode(_validZip(meta: meta)).deck.id, 'deck-1');
    });

    test('cards_count не совпадает с cards.json → invalidMeta', () {
      final bytes = _validZip(
        meta: _metaMap(cardsCount: 5),
        cards: <Map<String, Object?>>[_cardMap()],
      );

      expect(
        () => _codec.decode(bytes),
        _throwsArchiveError(ArchiveErrorCode.invalidMeta),
      );
    });

    test('media_count не совпадает с media/ → invalidMeta', () {
      final bytes = _validZip(
        meta: _metaMap(cardsCount: 1, mediaCount: 2),
        cards: <Map<String, Object?>>[
          _cardMap(media: <Object?>[_mediaRef()]),
        ],
        media: <String, List<int>>{
          'media/media-1': <int>[1],
        },
      );

      expect(
        () => _codec.decode(bytes),
        _throwsArchiveError(ArchiveErrorCode.invalidMeta),
      );
    });
  });

  group('ZipDeckArchiveCodec: decode — cards.json', () {
    test('cards.json не JSON-объект → invalidCards', () {
      final bytes = _zipOf(
        metaRaw: jsonEncode(_metaMap()),
        cardsRaw: jsonEncode(<Object?>[1, 2, 3]),
      );

      expect(
        () => _codec.decode(bytes),
        _throwsArchiveError(ArchiveErrorCode.invalidCards),
      );
    });

    test('cards не список → invalidCards', () {
      final bytes = _zipOf(
        metaRaw: jsonEncode(_metaMap()),
        cardsRaw: jsonEncode(<String, Object?>{'cards': <String, Object?>{}}),
      );

      expect(
        () => _codec.decode(bytes),
        _throwsArchiveError(ArchiveErrorCode.invalidCards),
      );
    });

    test('битый JSON cards.json → invalidCards', () {
      final bytes = _zipOf(
        metaRaw: jsonEncode(_metaMap()),
        cardsRaw: '{"cards": [',
      );

      expect(
        () => _codec.decode(bytes),
        _throwsArchiveError(ArchiveErrorCode.invalidCards),
      );
    });

    test('карточка без обязательного front → invalidCards', () {
      final bytes = _validZip(
        cards: <Map<String, Object?>>[
          _cardMap(omit: <String>{'front'}),
        ],
      );

      expect(
        () => _codec.decode(bytes),
        _throwsArchiveError(ArchiveErrorCode.invalidCards),
      );
    });

    test('пустой front → invalidCards (docs/archive-format.md)', () {
      final bytes = _validZip(
        cards: <Map<String, Object?>>[_cardMap(front: '')],
      );

      expect(
        () => _codec.decode(bytes),
        _throwsArchiveError(ArchiveErrorCode.invalidCards),
      );
    });

    test('больше трёх тегов → invalidCards (docs/archive-format.md)', () {
      final bytes = _validZip(
        cards: <Map<String, Object?>>[
          _cardMap(tags: <String>['один', 'два', 'три', 'четыре']),
        ],
      );

      expect(
        () => _codec.decode(bytes),
        _throwsArchiveError(ArchiveErrorCode.invalidCards),
      );
    });

    test('отсутствует обязательное nullable-поле hint → invalidCards', () {
      final bytes = _validZip(
        cards: <Map<String, Object?>>[
          _cardMap(omit: <String>{'hint'}),
        ],
      );

      expect(
        () => _codec.decode(bytes),
        _throwsArchiveError(ArchiveErrorCode.invalidCards),
      );
    });

    test('неизвестный card_type → invalidCards', () {
      final bytes = _validZip(
        cards: <Map<String, Object?>>[_cardMap(cardType: 'image_occlusion')],
      );

      expect(
        () => _codec.decode(bytes),
        _throwsArchiveError(ArchiveErrorCode.invalidCards),
      );
    });

    test('неизвестный state → invalidCards', () {
      final bytes = _validZip(
        cards: <Map<String, Object?>>[_cardMap(state: 'archived')],
      );

      expect(
        () => _codec.decode(bytes),
        _throwsArchiveError(ArchiveErrorCode.invalidCards),
      );
    });

    test('дубликат id карточек → invalidCards', () {
      final bytes = _validZip(
        cards: <Map<String, Object?>>[_cardMap(), _cardMap()],
      );

      expect(
        () => _codec.decode(bytes),
        _throwsArchiveError(ArchiveErrorCode.invalidCards),
      );
    });

    test('wrong type: suspended не bool → invalidCards', () {
      final bytes = _validZip(
        cards: <Map<String, Object?>>[_cardMap(suspended: 'да')],
      );

      expect(
        () => _codec.decode(bytes),
        _throwsArchiveError(ArchiveErrorCode.invalidCards),
      );
    });

    test('wrong type: due не целое → invalidCards', () {
      final bytes = _validZip(
        cards: <Map<String, Object?>>[_cardMap(due: '2026-11-20')],
      );

      expect(
        () => _codec.decode(bytes),
        _throwsArchiveError(ArchiveErrorCode.invalidCards),
      );
    });

    test('wrong type: tags не список строк → invalidCards', () {
      final bytes = _validZip(
        cards: <Map<String, Object?>>[
          _cardMap(tags: <Object?>[1, 2]),
        ],
      );

      expect(
        () => _codec.decode(bytes),
        _throwsArchiveError(ArchiveErrorCode.invalidCards),
      );
    });

    test('media-ссылка на чужую карточку → invalidCards', () {
      final bytes = _validZip(
        cards: <Map<String, Object?>>[
          _cardMap(media: <Object?>[_mediaRef(cardId: 'card-2')]),
        ],
        media: <String, List<int>>{
          'media/media-1': <int>[1],
        },
      );

      expect(
        () => _codec.decode(bytes),
        _throwsArchiveError(ArchiveErrorCode.invalidCards),
      );
    });
  });

  group('ZipDeckArchiveCodec: decode — имена записей и zip-slip', () {
    for (final String name in <String>[
      '../evil.json',
      '/абс/evil.json',
      'media/../evil',
      'media/a/b',
      'extra.txt',
      'cards.json.bak',
      'extra/',
    ]) {
      test('недопустимая запись "$name" → invalidEntryName', () {
        final bytes = _zipOf(
          metaRaw: jsonEncode(_metaMap()),
          cardsRaw: jsonEncode(<String, Object?>{'cards': []}),
          extra: <String, List<int>>{
            name: <int>[1, 2, 3],
          },
        );

        expect(
          () => _codec.decode(bytes),
          _throwsArchiveError(ArchiveErrorCode.invalidEntryName),
        );
      });
    }

    test('медиа-запись без владельца → invalidEntryName', () {
      final bytes = _validZip(
        media: <String, List<int>>{
          'media/orphan': <int>[1, 2, 3],
        },
      );

      expect(
        () => _codec.decode(bytes),
        _throwsArchiveError(ArchiveErrorCode.invalidEntryName),
      );
    });

    test('запись-каталог media/ игнорируется (сторонние архиваторы)', () {
      final bytes = _zipOf(
        metaRaw: jsonEncode(_metaMap()),
        cardsRaw: jsonEncode(<String, Object?>{'cards': []}),
        extra: <String, List<int>>{'media/': <int>[]},
      );

      final decoded = _codec.decode(bytes);

      expect(decoded.cards, isEmpty);
      expect(decoded.media, isEmpty);
      expect(decoded.deck.id, 'deck-1');
    });
  });

  group('ZipDeckArchiveCodec: decode — лимиты и медиа', () {
    test('вход больше maxImportBytes → tooLarge', () {
      final bytes = _validZip();
      final codec = ZipDeckArchiveCodec(maxImportBytes: bytes.length - 1);

      expect(
        () => codec.decode(bytes),
        _throwsArchiveError(ArchiveErrorCode.tooLarge),
      );
    });

    test('суммарный распакованный размер больше лимита → tooLarge', () {
      final codec = ZipDeckArchiveCodec(maxUncompressedBytes: 10);

      expect(
        () => codec.decode(_validZip()),
        _throwsArchiveError(ArchiveErrorCode.tooLarge),
      );
    });

    test('meta.json/cards.json больше maxJsonEntryBytes → tooLarge', () {
      final codec = ZipDeckArchiveCodec(maxJsonEntryBytes: 10);

      expect(
        () => codec.decode(_validZip()),
        _throwsArchiveError(ArchiveErrorCode.tooLarge),
      );
    });

    test('карточка ссылается на отсутствующую запись медиа → mediaMissing', () {
      final bytes = _validZip(
        cards: <Map<String, Object?>>[
          _cardMap(media: <Object?>[_mediaRef()]),
        ],
      );

      expect(
        () => _codec.decode(bytes),
        _throwsArchiveError(ArchiveErrorCode.mediaMissing),
      );
    });

    test('дубликат media.id между карточками → invalidCards', () {
      final bytes = _validZip(
        cards: <Map<String, Object?>>[
          _cardMap(id: 'card-1', media: <Object?>[_mediaRef()]),
          _cardMap(
            id: 'card-2',
            media: <Object?>[_mediaRef(cardId: 'card-2')],
          ),
        ],
        media: <String, List<int>>{
          'media/media-1': <int>[1, 2, 3],
        },
      );

      expect(
        () => _codec.decode(bytes),
        _throwsArchiveError(ArchiveErrorCode.invalidCards),
      );
    });

    test('пустой медиафайл допустим', () {
      final bytes = _validZip(
        cards: <Map<String, Object?>>[
          _cardMap(media: <Object?>[_mediaRef()]),
        ],
        media: <String, List<int>>{'media/media-1': <int>[]},
      );
      final decoded = _codec.decode(bytes);

      expect(decoded.media.single.bytes, isEmpty);
    });
  });

  group('ZipDeckArchiveCodec: decode — ручной архив', () {
    test('разбирает валидный архив, собранный вручную', () {
      final meta = _metaMap(cardsCount: 1, mediaCount: 1);
      final cards = <String, Object?>{
        'cards': <Map<String, Object?>>[
          _cardMap(
            front: 'Вопрос вручную',
            hint: 'подсказка',
            tags: <String>['тег'],
            state: 'review',
            due: 1763638800000,
            media: <Object?>[_mediaRef()],
          ),
        ],
      };
      final bytes = _zipOf(
        metaRaw: jsonEncode(meta),
        cardsRaw: jsonEncode(cards),
        media: <String, List<int>>{
          'media/media-1': <int>[1, 2, 3],
        },
      );

      final decoded = _codec.decode(bytes);

      expect(decoded.formatVersion, 1);
      expect(decoded.exportedAt, DateTime.utc(2026, 11, 12, 10, 30, 5, 123));
      expect(decoded.deck.id, 'deck-1');
      expect(
        decoded.deck.createdAt,
        DateTime.fromMillisecondsSinceEpoch(1762942205000, isUtc: true),
      );
      expect(decoded.cards.single.front, 'Вопрос вручную');
      expect(decoded.cards.single.hint, 'подсказка');
      expect(decoded.cards.single.tags, <String>['тег']);
      expect(decoded.cards.single.state, CardState.review);
      expect(
        decoded.cards.single.due,
        DateTime.fromMillisecondsSinceEpoch(1763638800000, isUtc: true),
      );
      expect(decoded.cards.single.mediaIds, <String>['media-1']);
      expect(decoded.media.single.cardId, 'card-1');
      expect(decoded.media.single.path, 'media/media-1.png');
      expect(decoded.media.single.mimeType, 'image/png');
      expect(decoded.media.single.bytes, <int>[1, 2, 3]);
    });
  });
}
