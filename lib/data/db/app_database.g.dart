// GENERATED CODE - DO NOT MODIFY BY HAND

part of 'app_database.dart';

// ignore_for_file: type=lint
class $DecksTable extends Decks with TableInfo<$DecksTable, DeckRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $DecksTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _settingsJsonMeta = const VerificationMeta(
    'settingsJson',
  );
  @override
  late final GeneratedColumn<String> settingsJson = GeneratedColumn<String>(
    'settings_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('{}'),
  );
  static const VerificationMeta _archivedAtMeta = const VerificationMeta(
    'archivedAt',
  );
  @override
  late final GeneratedColumn<int> archivedAt = GeneratedColumn<int>(
    'archived_at',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    name,
    settingsJson,
    archivedAt,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'decks';
  @override
  VerificationContext validateIntegrity(
    Insertable<DeckRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('settings_json')) {
      context.handle(
        _settingsJsonMeta,
        settingsJson.isAcceptableOrUnknown(
          data['settings_json']!,
          _settingsJsonMeta,
        ),
      );
    }
    if (data.containsKey('archived_at')) {
      context.handle(
        _archivedAtMeta,
        archivedAt.isAcceptableOrUnknown(data['archived_at']!, _archivedAtMeta),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  DeckRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return DeckRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      settingsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}settings_json'],
      )!,
      archivedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}archived_at'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $DecksTable createAlias(String alias) {
    return $DecksTable(attachedDatabase, alias);
  }
}

class DeckRow extends DataClass implements Insertable<DeckRow> {
  /// Уникальный идентификатор (`TEXT PRIMARY KEY`).
  final String id;

  /// Отображаемое имя.
  final String name;

  /// Настройки планировщика, JSON-объект (`DEFAULT '{}'`).
  final String settingsJson;

  /// Момент архивации (epoch ms), `NULL` — колода активна.
  final int? archivedAt;

  /// Момент создания (epoch ms).
  final int createdAt;

  /// Момент последнего изменения (epoch ms).
  final int updatedAt;
  const DeckRow({
    required this.id,
    required this.name,
    required this.settingsJson,
    this.archivedAt,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['settings_json'] = Variable<String>(settingsJson);
    if (!nullToAbsent || archivedAt != null) {
      map['archived_at'] = Variable<int>(archivedAt);
    }
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  DecksCompanion toCompanion(bool nullToAbsent) {
    return DecksCompanion(
      id: Value(id),
      name: Value(name),
      settingsJson: Value(settingsJson),
      archivedAt: archivedAt == null && nullToAbsent
          ? const Value.absent()
          : Value(archivedAt),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory DeckRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return DeckRow(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      settingsJson: serializer.fromJson<String>(json['settingsJson']),
      archivedAt: serializer.fromJson<int?>(json['archivedAt']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'settingsJson': serializer.toJson<String>(settingsJson),
      'archivedAt': serializer.toJson<int?>(archivedAt),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  DeckRow copyWith({
    String? id,
    String? name,
    String? settingsJson,
    Value<int?> archivedAt = const Value.absent(),
    int? createdAt,
    int? updatedAt,
  }) => DeckRow(
    id: id ?? this.id,
    name: name ?? this.name,
    settingsJson: settingsJson ?? this.settingsJson,
    archivedAt: archivedAt.present ? archivedAt.value : this.archivedAt,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  DeckRow copyWithCompanion(DecksCompanion data) {
    return DeckRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      settingsJson: data.settingsJson.present
          ? data.settingsJson.value
          : this.settingsJson,
      archivedAt: data.archivedAt.present
          ? data.archivedAt.value
          : this.archivedAt,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('DeckRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('settingsJson: $settingsJson, ')
          ..write('archivedAt: $archivedAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode =>
      Object.hash(id, name, settingsJson, archivedAt, createdAt, updatedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is DeckRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.settingsJson == this.settingsJson &&
          other.archivedAt == this.archivedAt &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class DecksCompanion extends UpdateCompanion<DeckRow> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> settingsJson;
  final Value<int?> archivedAt;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int> rowid;
  const DecksCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.settingsJson = const Value.absent(),
    this.archivedAt = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  DecksCompanion.insert({
    required String id,
    required String name,
    this.settingsJson = const Value.absent(),
    this.archivedAt = const Value.absent(),
    required int createdAt,
    required int updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<DeckRow> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? settingsJson,
    Expression<int>? archivedAt,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (settingsJson != null) 'settings_json': settingsJson,
      if (archivedAt != null) 'archived_at': archivedAt,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  DecksCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String>? settingsJson,
    Value<int?>? archivedAt,
    Value<int>? createdAt,
    Value<int>? updatedAt,
    Value<int>? rowid,
  }) {
    return DecksCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      settingsJson: settingsJson ?? this.settingsJson,
      archivedAt: archivedAt ?? this.archivedAt,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (settingsJson.present) {
      map['settings_json'] = Variable<String>(settingsJson.value);
    }
    if (archivedAt.present) {
      map['archived_at'] = Variable<int>(archivedAt.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('DecksCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('settingsJson: $settingsJson, ')
          ..write('archivedAt: $archivedAt, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $CardsTable extends Cards with TableInfo<$CardsTable, CardRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $CardsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deckIdMeta = const VerificationMeta('deckId');
  @override
  late final GeneratedColumn<String> deckId = GeneratedColumn<String>(
    'deck_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
    defaultConstraints: GeneratedColumn.constraintIsAlways(
      'REFERENCES decks (id) ON DELETE CASCADE',
    ),
  );
  static const VerificationMeta _frontMeta = const VerificationMeta('front');
  @override
  late final GeneratedColumn<String> front = GeneratedColumn<String>(
    'front',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _backMeta = const VerificationMeta('back');
  @override
  late final GeneratedColumn<String> back = GeneratedColumn<String>(
    'back',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _hintMeta = const VerificationMeta('hint');
  @override
  late final GeneratedColumn<String> hint = GeneratedColumn<String>(
    'hint',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _cardTypeMeta = const VerificationMeta(
    'cardType',
  );
  @override
  late final GeneratedColumn<String> cardType = GeneratedColumn<String>(
    'card_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _tagsJsonMeta = const VerificationMeta(
    'tagsJson',
  );
  @override
  late final GeneratedColumn<String> tagsJson = GeneratedColumn<String>(
    'tags_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _mediaJsonMeta = const VerificationMeta(
    'mediaJson',
  );
  @override
  late final GeneratedColumn<String> mediaJson = GeneratedColumn<String>(
    'media_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
    defaultValue: const Constant('[]'),
  );
  static const VerificationMeta _latexMeta = const VerificationMeta('latex');
  @override
  late final GeneratedColumn<String> latex = GeneratedColumn<String>(
    'latex',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _occlusionJsonMeta = const VerificationMeta(
    'occlusionJson',
  );
  @override
  late final GeneratedColumn<String> occlusionJson = GeneratedColumn<String>(
    'occlusion_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sourceDocIdMeta = const VerificationMeta(
    'sourceDocId',
  );
  @override
  late final GeneratedColumn<String> sourceDocId = GeneratedColumn<String>(
    'source_doc_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _sourceExcerptMeta = const VerificationMeta(
    'sourceExcerpt',
  );
  @override
  late final GeneratedColumn<String> sourceExcerpt = GeneratedColumn<String>(
    'source_excerpt',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _stateMeta = const VerificationMeta('state');
  @override
  late final GeneratedColumn<String> state = GeneratedColumn<String>(
    'state',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _fsrsJsonMeta = const VerificationMeta(
    'fsrsJson',
  );
  @override
  late final GeneratedColumn<String> fsrsJson = GeneratedColumn<String>(
    'fsrs_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _dueMeta = const VerificationMeta('due');
  @override
  late final GeneratedColumn<int> due = GeneratedColumn<int>(
    'due',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _suspendedMeta = const VerificationMeta(
    'suspended',
  );
  @override
  late final GeneratedColumn<int> suspended = GeneratedColumn<int>(
    'suspended',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _buriedUntilMeta = const VerificationMeta(
    'buriedUntil',
  );
  @override
  late final GeneratedColumn<int> buriedUntil = GeneratedColumn<int>(
    'buried_until',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _flaggedMeta = const VerificationMeta(
    'flagged',
  );
  @override
  late final GeneratedColumn<int> flagged = GeneratedColumn<int>(
    'flagged',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _siblingIdMeta = const VerificationMeta(
    'siblingId',
  );
  @override
  late final GeneratedColumn<String> siblingId = GeneratedColumn<String>(
    'sibling_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _contentHashMeta = const VerificationMeta(
    'contentHash',
  );
  @override
  late final GeneratedColumn<String> contentHash = GeneratedColumn<String>(
    'content_hash',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _updatedAtMeta = const VerificationMeta(
    'updatedAt',
  );
  @override
  late final GeneratedColumn<int> updatedAt = GeneratedColumn<int>(
    'updated_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    deckId,
    front,
    back,
    hint,
    cardType,
    tagsJson,
    mediaJson,
    latex,
    occlusionJson,
    sourceDocId,
    sourceExcerpt,
    state,
    fsrsJson,
    due,
    suspended,
    buriedUntil,
    flagged,
    siblingId,
    contentHash,
    createdAt,
    updatedAt,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'cards';
  @override
  VerificationContext validateIntegrity(
    Insertable<CardRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('deck_id')) {
      context.handle(
        _deckIdMeta,
        deckId.isAcceptableOrUnknown(data['deck_id']!, _deckIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deckIdMeta);
    }
    if (data.containsKey('front')) {
      context.handle(
        _frontMeta,
        front.isAcceptableOrUnknown(data['front']!, _frontMeta),
      );
    } else if (isInserting) {
      context.missing(_frontMeta);
    }
    if (data.containsKey('back')) {
      context.handle(
        _backMeta,
        back.isAcceptableOrUnknown(data['back']!, _backMeta),
      );
    } else if (isInserting) {
      context.missing(_backMeta);
    }
    if (data.containsKey('hint')) {
      context.handle(
        _hintMeta,
        hint.isAcceptableOrUnknown(data['hint']!, _hintMeta),
      );
    }
    if (data.containsKey('card_type')) {
      context.handle(
        _cardTypeMeta,
        cardType.isAcceptableOrUnknown(data['card_type']!, _cardTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_cardTypeMeta);
    }
    if (data.containsKey('tags_json')) {
      context.handle(
        _tagsJsonMeta,
        tagsJson.isAcceptableOrUnknown(data['tags_json']!, _tagsJsonMeta),
      );
    }
    if (data.containsKey('media_json')) {
      context.handle(
        _mediaJsonMeta,
        mediaJson.isAcceptableOrUnknown(data['media_json']!, _mediaJsonMeta),
      );
    }
    if (data.containsKey('latex')) {
      context.handle(
        _latexMeta,
        latex.isAcceptableOrUnknown(data['latex']!, _latexMeta),
      );
    }
    if (data.containsKey('occlusion_json')) {
      context.handle(
        _occlusionJsonMeta,
        occlusionJson.isAcceptableOrUnknown(
          data['occlusion_json']!,
          _occlusionJsonMeta,
        ),
      );
    }
    if (data.containsKey('source_doc_id')) {
      context.handle(
        _sourceDocIdMeta,
        sourceDocId.isAcceptableOrUnknown(
          data['source_doc_id']!,
          _sourceDocIdMeta,
        ),
      );
    }
    if (data.containsKey('source_excerpt')) {
      context.handle(
        _sourceExcerptMeta,
        sourceExcerpt.isAcceptableOrUnknown(
          data['source_excerpt']!,
          _sourceExcerptMeta,
        ),
      );
    }
    if (data.containsKey('state')) {
      context.handle(
        _stateMeta,
        state.isAcceptableOrUnknown(data['state']!, _stateMeta),
      );
    } else if (isInserting) {
      context.missing(_stateMeta);
    }
    if (data.containsKey('fsrs_json')) {
      context.handle(
        _fsrsJsonMeta,
        fsrsJson.isAcceptableOrUnknown(data['fsrs_json']!, _fsrsJsonMeta),
      );
    }
    if (data.containsKey('due')) {
      context.handle(
        _dueMeta,
        due.isAcceptableOrUnknown(data['due']!, _dueMeta),
      );
    }
    if (data.containsKey('suspended')) {
      context.handle(
        _suspendedMeta,
        suspended.isAcceptableOrUnknown(data['suspended']!, _suspendedMeta),
      );
    }
    if (data.containsKey('buried_until')) {
      context.handle(
        _buriedUntilMeta,
        buriedUntil.isAcceptableOrUnknown(
          data['buried_until']!,
          _buriedUntilMeta,
        ),
      );
    }
    if (data.containsKey('flagged')) {
      context.handle(
        _flaggedMeta,
        flagged.isAcceptableOrUnknown(data['flagged']!, _flaggedMeta),
      );
    }
    if (data.containsKey('sibling_id')) {
      context.handle(
        _siblingIdMeta,
        siblingId.isAcceptableOrUnknown(data['sibling_id']!, _siblingIdMeta),
      );
    }
    if (data.containsKey('content_hash')) {
      context.handle(
        _contentHashMeta,
        contentHash.isAcceptableOrUnknown(
          data['content_hash']!,
          _contentHashMeta,
        ),
      );
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('updated_at')) {
      context.handle(
        _updatedAtMeta,
        updatedAt.isAcceptableOrUnknown(data['updated_at']!, _updatedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_updatedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  CardRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return CardRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      deckId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}deck_id'],
      )!,
      front: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}front'],
      )!,
      back: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}back'],
      )!,
      hint: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}hint'],
      ),
      cardType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}card_type'],
      )!,
      tagsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}tags_json'],
      )!,
      mediaJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}media_json'],
      )!,
      latex: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}latex'],
      ),
      occlusionJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}occlusion_json'],
      ),
      sourceDocId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_doc_id'],
      ),
      sourceExcerpt: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}source_excerpt'],
      ),
      state: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}state'],
      )!,
      fsrsJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}fsrs_json'],
      ),
      due: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}due'],
      ),
      suspended: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}suspended'],
      )!,
      buriedUntil: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}buried_until'],
      ),
      flagged: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}flagged'],
      )!,
      siblingId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}sibling_id'],
      ),
      contentHash: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}content_hash'],
      ),
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      updatedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}updated_at'],
      )!,
    );
  }

  @override
  $CardsTable createAlias(String alias) {
    return $CardsTable(attachedDatabase, alias);
  }
}

class CardRow extends DataClass implements Insertable<CardRow> {
  /// Уникальный идентификатор (`TEXT PRIMARY KEY`).
  final String id;

  /// Колода-владелец.
  final String deckId;

  /// Лицевая сторона (вопрос).
  final String front;

  /// Обратная сторона (ответ).
  final String back;

  /// Подсказка без раскрытия ответа.
  final String? hint;

  /// Тип: `basic | basic_reversed | cloze`.
  final String cardType;

  /// Теги, JSON-массив строк (`DEFAULT '[]'`).
  final String tagsJson;

  /// Идентификаторы медиа, JSON-массив строк (`DEFAULT '[]'`).
  final String mediaJson;

  /// LaTeX-разметка, если есть.
  final String? latex;

  /// JSON масок Image Occlusion, если есть.
  final String? occlusionJson;

  /// Ссылка на исходный документ (`source_docs.id`), если есть.
  final String? sourceDocId;

  /// Цитата для кнопки «Почему?», если есть.
  final String? sourceExcerpt;

  /// Состояние уровня приложения: `new | learning | review | relearning`.
  final String state;

  /// Состояние FSRS (сырой JSON адаптера), если карточка планировалась.
  final String? fsrsJson;

  /// Денормализованный `due` (epoch ms), если запланирована.
  final int? due;

  /// Приостановлена: 0/1 (`DEFAULT 0`).
  final int suspended;

  /// Отложена до момента (epoch ms), если есть.
  final int? buriedUntil;

  /// Флаг пользователя: 0/1 (`DEFAULT 0`).
  final int flagged;

  /// Парная карточка `basic_reversed`.
  final String? siblingId;

  /// Хеш дедупликации `front + "\u0000" + back`, если посчитан.
  final String? contentHash;

  /// Момент создания (epoch ms).
  final int createdAt;

  /// Момент последнего изменения (epoch ms).
  final int updatedAt;
  const CardRow({
    required this.id,
    required this.deckId,
    required this.front,
    required this.back,
    this.hint,
    required this.cardType,
    required this.tagsJson,
    required this.mediaJson,
    this.latex,
    this.occlusionJson,
    this.sourceDocId,
    this.sourceExcerpt,
    required this.state,
    this.fsrsJson,
    this.due,
    required this.suspended,
    this.buriedUntil,
    required this.flagged,
    this.siblingId,
    this.contentHash,
    required this.createdAt,
    required this.updatedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['deck_id'] = Variable<String>(deckId);
    map['front'] = Variable<String>(front);
    map['back'] = Variable<String>(back);
    if (!nullToAbsent || hint != null) {
      map['hint'] = Variable<String>(hint);
    }
    map['card_type'] = Variable<String>(cardType);
    map['tags_json'] = Variable<String>(tagsJson);
    map['media_json'] = Variable<String>(mediaJson);
    if (!nullToAbsent || latex != null) {
      map['latex'] = Variable<String>(latex);
    }
    if (!nullToAbsent || occlusionJson != null) {
      map['occlusion_json'] = Variable<String>(occlusionJson);
    }
    if (!nullToAbsent || sourceDocId != null) {
      map['source_doc_id'] = Variable<String>(sourceDocId);
    }
    if (!nullToAbsent || sourceExcerpt != null) {
      map['source_excerpt'] = Variable<String>(sourceExcerpt);
    }
    map['state'] = Variable<String>(state);
    if (!nullToAbsent || fsrsJson != null) {
      map['fsrs_json'] = Variable<String>(fsrsJson);
    }
    if (!nullToAbsent || due != null) {
      map['due'] = Variable<int>(due);
    }
    map['suspended'] = Variable<int>(suspended);
    if (!nullToAbsent || buriedUntil != null) {
      map['buried_until'] = Variable<int>(buriedUntil);
    }
    map['flagged'] = Variable<int>(flagged);
    if (!nullToAbsent || siblingId != null) {
      map['sibling_id'] = Variable<String>(siblingId);
    }
    if (!nullToAbsent || contentHash != null) {
      map['content_hash'] = Variable<String>(contentHash);
    }
    map['created_at'] = Variable<int>(createdAt);
    map['updated_at'] = Variable<int>(updatedAt);
    return map;
  }

  CardsCompanion toCompanion(bool nullToAbsent) {
    return CardsCompanion(
      id: Value(id),
      deckId: Value(deckId),
      front: Value(front),
      back: Value(back),
      hint: hint == null && nullToAbsent ? const Value.absent() : Value(hint),
      cardType: Value(cardType),
      tagsJson: Value(tagsJson),
      mediaJson: Value(mediaJson),
      latex: latex == null && nullToAbsent
          ? const Value.absent()
          : Value(latex),
      occlusionJson: occlusionJson == null && nullToAbsent
          ? const Value.absent()
          : Value(occlusionJson),
      sourceDocId: sourceDocId == null && nullToAbsent
          ? const Value.absent()
          : Value(sourceDocId),
      sourceExcerpt: sourceExcerpt == null && nullToAbsent
          ? const Value.absent()
          : Value(sourceExcerpt),
      state: Value(state),
      fsrsJson: fsrsJson == null && nullToAbsent
          ? const Value.absent()
          : Value(fsrsJson),
      due: due == null && nullToAbsent ? const Value.absent() : Value(due),
      suspended: Value(suspended),
      buriedUntil: buriedUntil == null && nullToAbsent
          ? const Value.absent()
          : Value(buriedUntil),
      flagged: Value(flagged),
      siblingId: siblingId == null && nullToAbsent
          ? const Value.absent()
          : Value(siblingId),
      contentHash: contentHash == null && nullToAbsent
          ? const Value.absent()
          : Value(contentHash),
      createdAt: Value(createdAt),
      updatedAt: Value(updatedAt),
    );
  }

  factory CardRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return CardRow(
      id: serializer.fromJson<String>(json['id']),
      deckId: serializer.fromJson<String>(json['deckId']),
      front: serializer.fromJson<String>(json['front']),
      back: serializer.fromJson<String>(json['back']),
      hint: serializer.fromJson<String?>(json['hint']),
      cardType: serializer.fromJson<String>(json['cardType']),
      tagsJson: serializer.fromJson<String>(json['tagsJson']),
      mediaJson: serializer.fromJson<String>(json['mediaJson']),
      latex: serializer.fromJson<String?>(json['latex']),
      occlusionJson: serializer.fromJson<String?>(json['occlusionJson']),
      sourceDocId: serializer.fromJson<String?>(json['sourceDocId']),
      sourceExcerpt: serializer.fromJson<String?>(json['sourceExcerpt']),
      state: serializer.fromJson<String>(json['state']),
      fsrsJson: serializer.fromJson<String?>(json['fsrsJson']),
      due: serializer.fromJson<int?>(json['due']),
      suspended: serializer.fromJson<int>(json['suspended']),
      buriedUntil: serializer.fromJson<int?>(json['buriedUntil']),
      flagged: serializer.fromJson<int>(json['flagged']),
      siblingId: serializer.fromJson<String?>(json['siblingId']),
      contentHash: serializer.fromJson<String?>(json['contentHash']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      updatedAt: serializer.fromJson<int>(json['updatedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'deckId': serializer.toJson<String>(deckId),
      'front': serializer.toJson<String>(front),
      'back': serializer.toJson<String>(back),
      'hint': serializer.toJson<String?>(hint),
      'cardType': serializer.toJson<String>(cardType),
      'tagsJson': serializer.toJson<String>(tagsJson),
      'mediaJson': serializer.toJson<String>(mediaJson),
      'latex': serializer.toJson<String?>(latex),
      'occlusionJson': serializer.toJson<String?>(occlusionJson),
      'sourceDocId': serializer.toJson<String?>(sourceDocId),
      'sourceExcerpt': serializer.toJson<String?>(sourceExcerpt),
      'state': serializer.toJson<String>(state),
      'fsrsJson': serializer.toJson<String?>(fsrsJson),
      'due': serializer.toJson<int?>(due),
      'suspended': serializer.toJson<int>(suspended),
      'buriedUntil': serializer.toJson<int?>(buriedUntil),
      'flagged': serializer.toJson<int>(flagged),
      'siblingId': serializer.toJson<String?>(siblingId),
      'contentHash': serializer.toJson<String?>(contentHash),
      'createdAt': serializer.toJson<int>(createdAt),
      'updatedAt': serializer.toJson<int>(updatedAt),
    };
  }

  CardRow copyWith({
    String? id,
    String? deckId,
    String? front,
    String? back,
    Value<String?> hint = const Value.absent(),
    String? cardType,
    String? tagsJson,
    String? mediaJson,
    Value<String?> latex = const Value.absent(),
    Value<String?> occlusionJson = const Value.absent(),
    Value<String?> sourceDocId = const Value.absent(),
    Value<String?> sourceExcerpt = const Value.absent(),
    String? state,
    Value<String?> fsrsJson = const Value.absent(),
    Value<int?> due = const Value.absent(),
    int? suspended,
    Value<int?> buriedUntil = const Value.absent(),
    int? flagged,
    Value<String?> siblingId = const Value.absent(),
    Value<String?> contentHash = const Value.absent(),
    int? createdAt,
    int? updatedAt,
  }) => CardRow(
    id: id ?? this.id,
    deckId: deckId ?? this.deckId,
    front: front ?? this.front,
    back: back ?? this.back,
    hint: hint.present ? hint.value : this.hint,
    cardType: cardType ?? this.cardType,
    tagsJson: tagsJson ?? this.tagsJson,
    mediaJson: mediaJson ?? this.mediaJson,
    latex: latex.present ? latex.value : this.latex,
    occlusionJson: occlusionJson.present
        ? occlusionJson.value
        : this.occlusionJson,
    sourceDocId: sourceDocId.present ? sourceDocId.value : this.sourceDocId,
    sourceExcerpt: sourceExcerpt.present
        ? sourceExcerpt.value
        : this.sourceExcerpt,
    state: state ?? this.state,
    fsrsJson: fsrsJson.present ? fsrsJson.value : this.fsrsJson,
    due: due.present ? due.value : this.due,
    suspended: suspended ?? this.suspended,
    buriedUntil: buriedUntil.present ? buriedUntil.value : this.buriedUntil,
    flagged: flagged ?? this.flagged,
    siblingId: siblingId.present ? siblingId.value : this.siblingId,
    contentHash: contentHash.present ? contentHash.value : this.contentHash,
    createdAt: createdAt ?? this.createdAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );
  CardRow copyWithCompanion(CardsCompanion data) {
    return CardRow(
      id: data.id.present ? data.id.value : this.id,
      deckId: data.deckId.present ? data.deckId.value : this.deckId,
      front: data.front.present ? data.front.value : this.front,
      back: data.back.present ? data.back.value : this.back,
      hint: data.hint.present ? data.hint.value : this.hint,
      cardType: data.cardType.present ? data.cardType.value : this.cardType,
      tagsJson: data.tagsJson.present ? data.tagsJson.value : this.tagsJson,
      mediaJson: data.mediaJson.present ? data.mediaJson.value : this.mediaJson,
      latex: data.latex.present ? data.latex.value : this.latex,
      occlusionJson: data.occlusionJson.present
          ? data.occlusionJson.value
          : this.occlusionJson,
      sourceDocId: data.sourceDocId.present
          ? data.sourceDocId.value
          : this.sourceDocId,
      sourceExcerpt: data.sourceExcerpt.present
          ? data.sourceExcerpt.value
          : this.sourceExcerpt,
      state: data.state.present ? data.state.value : this.state,
      fsrsJson: data.fsrsJson.present ? data.fsrsJson.value : this.fsrsJson,
      due: data.due.present ? data.due.value : this.due,
      suspended: data.suspended.present ? data.suspended.value : this.suspended,
      buriedUntil: data.buriedUntil.present
          ? data.buriedUntil.value
          : this.buriedUntil,
      flagged: data.flagged.present ? data.flagged.value : this.flagged,
      siblingId: data.siblingId.present ? data.siblingId.value : this.siblingId,
      contentHash: data.contentHash.present
          ? data.contentHash.value
          : this.contentHash,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      updatedAt: data.updatedAt.present ? data.updatedAt.value : this.updatedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('CardRow(')
          ..write('id: $id, ')
          ..write('deckId: $deckId, ')
          ..write('front: $front, ')
          ..write('back: $back, ')
          ..write('hint: $hint, ')
          ..write('cardType: $cardType, ')
          ..write('tagsJson: $tagsJson, ')
          ..write('mediaJson: $mediaJson, ')
          ..write('latex: $latex, ')
          ..write('occlusionJson: $occlusionJson, ')
          ..write('sourceDocId: $sourceDocId, ')
          ..write('sourceExcerpt: $sourceExcerpt, ')
          ..write('state: $state, ')
          ..write('fsrsJson: $fsrsJson, ')
          ..write('due: $due, ')
          ..write('suspended: $suspended, ')
          ..write('buriedUntil: $buriedUntil, ')
          ..write('flagged: $flagged, ')
          ..write('siblingId: $siblingId, ')
          ..write('contentHash: $contentHash, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hashAll([
    id,
    deckId,
    front,
    back,
    hint,
    cardType,
    tagsJson,
    mediaJson,
    latex,
    occlusionJson,
    sourceDocId,
    sourceExcerpt,
    state,
    fsrsJson,
    due,
    suspended,
    buriedUntil,
    flagged,
    siblingId,
    contentHash,
    createdAt,
    updatedAt,
  ]);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is CardRow &&
          other.id == this.id &&
          other.deckId == this.deckId &&
          other.front == this.front &&
          other.back == this.back &&
          other.hint == this.hint &&
          other.cardType == this.cardType &&
          other.tagsJson == this.tagsJson &&
          other.mediaJson == this.mediaJson &&
          other.latex == this.latex &&
          other.occlusionJson == this.occlusionJson &&
          other.sourceDocId == this.sourceDocId &&
          other.sourceExcerpt == this.sourceExcerpt &&
          other.state == this.state &&
          other.fsrsJson == this.fsrsJson &&
          other.due == this.due &&
          other.suspended == this.suspended &&
          other.buriedUntil == this.buriedUntil &&
          other.flagged == this.flagged &&
          other.siblingId == this.siblingId &&
          other.contentHash == this.contentHash &&
          other.createdAt == this.createdAt &&
          other.updatedAt == this.updatedAt);
}

class CardsCompanion extends UpdateCompanion<CardRow> {
  final Value<String> id;
  final Value<String> deckId;
  final Value<String> front;
  final Value<String> back;
  final Value<String?> hint;
  final Value<String> cardType;
  final Value<String> tagsJson;
  final Value<String> mediaJson;
  final Value<String?> latex;
  final Value<String?> occlusionJson;
  final Value<String?> sourceDocId;
  final Value<String?> sourceExcerpt;
  final Value<String> state;
  final Value<String?> fsrsJson;
  final Value<int?> due;
  final Value<int> suspended;
  final Value<int?> buriedUntil;
  final Value<int> flagged;
  final Value<String?> siblingId;
  final Value<String?> contentHash;
  final Value<int> createdAt;
  final Value<int> updatedAt;
  final Value<int> rowid;
  const CardsCompanion({
    this.id = const Value.absent(),
    this.deckId = const Value.absent(),
    this.front = const Value.absent(),
    this.back = const Value.absent(),
    this.hint = const Value.absent(),
    this.cardType = const Value.absent(),
    this.tagsJson = const Value.absent(),
    this.mediaJson = const Value.absent(),
    this.latex = const Value.absent(),
    this.occlusionJson = const Value.absent(),
    this.sourceDocId = const Value.absent(),
    this.sourceExcerpt = const Value.absent(),
    this.state = const Value.absent(),
    this.fsrsJson = const Value.absent(),
    this.due = const Value.absent(),
    this.suspended = const Value.absent(),
    this.buriedUntil = const Value.absent(),
    this.flagged = const Value.absent(),
    this.siblingId = const Value.absent(),
    this.contentHash = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.updatedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  CardsCompanion.insert({
    required String id,
    required String deckId,
    required String front,
    required String back,
    this.hint = const Value.absent(),
    required String cardType,
    this.tagsJson = const Value.absent(),
    this.mediaJson = const Value.absent(),
    this.latex = const Value.absent(),
    this.occlusionJson = const Value.absent(),
    this.sourceDocId = const Value.absent(),
    this.sourceExcerpt = const Value.absent(),
    required String state,
    this.fsrsJson = const Value.absent(),
    this.due = const Value.absent(),
    this.suspended = const Value.absent(),
    this.buriedUntil = const Value.absent(),
    this.flagged = const Value.absent(),
    this.siblingId = const Value.absent(),
    this.contentHash = const Value.absent(),
    required int createdAt,
    required int updatedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       deckId = Value(deckId),
       front = Value(front),
       back = Value(back),
       cardType = Value(cardType),
       state = Value(state),
       createdAt = Value(createdAt),
       updatedAt = Value(updatedAt);
  static Insertable<CardRow> custom({
    Expression<String>? id,
    Expression<String>? deckId,
    Expression<String>? front,
    Expression<String>? back,
    Expression<String>? hint,
    Expression<String>? cardType,
    Expression<String>? tagsJson,
    Expression<String>? mediaJson,
    Expression<String>? latex,
    Expression<String>? occlusionJson,
    Expression<String>? sourceDocId,
    Expression<String>? sourceExcerpt,
    Expression<String>? state,
    Expression<String>? fsrsJson,
    Expression<int>? due,
    Expression<int>? suspended,
    Expression<int>? buriedUntil,
    Expression<int>? flagged,
    Expression<String>? siblingId,
    Expression<String>? contentHash,
    Expression<int>? createdAt,
    Expression<int>? updatedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (deckId != null) 'deck_id': deckId,
      if (front != null) 'front': front,
      if (back != null) 'back': back,
      if (hint != null) 'hint': hint,
      if (cardType != null) 'card_type': cardType,
      if (tagsJson != null) 'tags_json': tagsJson,
      if (mediaJson != null) 'media_json': mediaJson,
      if (latex != null) 'latex': latex,
      if (occlusionJson != null) 'occlusion_json': occlusionJson,
      if (sourceDocId != null) 'source_doc_id': sourceDocId,
      if (sourceExcerpt != null) 'source_excerpt': sourceExcerpt,
      if (state != null) 'state': state,
      if (fsrsJson != null) 'fsrs_json': fsrsJson,
      if (due != null) 'due': due,
      if (suspended != null) 'suspended': suspended,
      if (buriedUntil != null) 'buried_until': buriedUntil,
      if (flagged != null) 'flagged': flagged,
      if (siblingId != null) 'sibling_id': siblingId,
      if (contentHash != null) 'content_hash': contentHash,
      if (createdAt != null) 'created_at': createdAt,
      if (updatedAt != null) 'updated_at': updatedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  CardsCompanion copyWith({
    Value<String>? id,
    Value<String>? deckId,
    Value<String>? front,
    Value<String>? back,
    Value<String?>? hint,
    Value<String>? cardType,
    Value<String>? tagsJson,
    Value<String>? mediaJson,
    Value<String?>? latex,
    Value<String?>? occlusionJson,
    Value<String?>? sourceDocId,
    Value<String?>? sourceExcerpt,
    Value<String>? state,
    Value<String?>? fsrsJson,
    Value<int?>? due,
    Value<int>? suspended,
    Value<int?>? buriedUntil,
    Value<int>? flagged,
    Value<String?>? siblingId,
    Value<String?>? contentHash,
    Value<int>? createdAt,
    Value<int>? updatedAt,
    Value<int>? rowid,
  }) {
    return CardsCompanion(
      id: id ?? this.id,
      deckId: deckId ?? this.deckId,
      front: front ?? this.front,
      back: back ?? this.back,
      hint: hint ?? this.hint,
      cardType: cardType ?? this.cardType,
      tagsJson: tagsJson ?? this.tagsJson,
      mediaJson: mediaJson ?? this.mediaJson,
      latex: latex ?? this.latex,
      occlusionJson: occlusionJson ?? this.occlusionJson,
      sourceDocId: sourceDocId ?? this.sourceDocId,
      sourceExcerpt: sourceExcerpt ?? this.sourceExcerpt,
      state: state ?? this.state,
      fsrsJson: fsrsJson ?? this.fsrsJson,
      due: due ?? this.due,
      suspended: suspended ?? this.suspended,
      buriedUntil: buriedUntil ?? this.buriedUntil,
      flagged: flagged ?? this.flagged,
      siblingId: siblingId ?? this.siblingId,
      contentHash: contentHash ?? this.contentHash,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (deckId.present) {
      map['deck_id'] = Variable<String>(deckId.value);
    }
    if (front.present) {
      map['front'] = Variable<String>(front.value);
    }
    if (back.present) {
      map['back'] = Variable<String>(back.value);
    }
    if (hint.present) {
      map['hint'] = Variable<String>(hint.value);
    }
    if (cardType.present) {
      map['card_type'] = Variable<String>(cardType.value);
    }
    if (tagsJson.present) {
      map['tags_json'] = Variable<String>(tagsJson.value);
    }
    if (mediaJson.present) {
      map['media_json'] = Variable<String>(mediaJson.value);
    }
    if (latex.present) {
      map['latex'] = Variable<String>(latex.value);
    }
    if (occlusionJson.present) {
      map['occlusion_json'] = Variable<String>(occlusionJson.value);
    }
    if (sourceDocId.present) {
      map['source_doc_id'] = Variable<String>(sourceDocId.value);
    }
    if (sourceExcerpt.present) {
      map['source_excerpt'] = Variable<String>(sourceExcerpt.value);
    }
    if (state.present) {
      map['state'] = Variable<String>(state.value);
    }
    if (fsrsJson.present) {
      map['fsrs_json'] = Variable<String>(fsrsJson.value);
    }
    if (due.present) {
      map['due'] = Variable<int>(due.value);
    }
    if (suspended.present) {
      map['suspended'] = Variable<int>(suspended.value);
    }
    if (buriedUntil.present) {
      map['buried_until'] = Variable<int>(buriedUntil.value);
    }
    if (flagged.present) {
      map['flagged'] = Variable<int>(flagged.value);
    }
    if (siblingId.present) {
      map['sibling_id'] = Variable<String>(siblingId.value);
    }
    if (contentHash.present) {
      map['content_hash'] = Variable<String>(contentHash.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (updatedAt.present) {
      map['updated_at'] = Variable<int>(updatedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('CardsCompanion(')
          ..write('id: $id, ')
          ..write('deckId: $deckId, ')
          ..write('front: $front, ')
          ..write('back: $back, ')
          ..write('hint: $hint, ')
          ..write('cardType: $cardType, ')
          ..write('tagsJson: $tagsJson, ')
          ..write('mediaJson: $mediaJson, ')
          ..write('latex: $latex, ')
          ..write('occlusionJson: $occlusionJson, ')
          ..write('sourceDocId: $sourceDocId, ')
          ..write('sourceExcerpt: $sourceExcerpt, ')
          ..write('state: $state, ')
          ..write('fsrsJson: $fsrsJson, ')
          ..write('due: $due, ')
          ..write('suspended: $suspended, ')
          ..write('buriedUntil: $buriedUntil, ')
          ..write('flagged: $flagged, ')
          ..write('siblingId: $siblingId, ')
          ..write('contentHash: $contentHash, ')
          ..write('createdAt: $createdAt, ')
          ..write('updatedAt: $updatedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $ReviewLogsTable extends ReviewLogs
    with TableInfo<$ReviewLogsTable, ReviewLogRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $ReviewLogsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cardIdMeta = const VerificationMeta('cardId');
  @override
  late final GeneratedColumn<String> cardId = GeneratedColumn<String>(
    'card_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _ratingMeta = const VerificationMeta('rating');
  @override
  late final GeneratedColumn<int> rating = GeneratedColumn<int>(
    'rating',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _reviewedAtMeta = const VerificationMeta(
    'reviewedAt',
  );
  @override
  late final GeneratedColumn<int> reviewedAt = GeneratedColumn<int>(
    'reviewed_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _modeMeta = const VerificationMeta('mode');
  @override
  late final GeneratedColumn<String> mode = GeneratedColumn<String>(
    'mode',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _recognitionFlagMeta = const VerificationMeta(
    'recognitionFlag',
  );
  @override
  late final GeneratedColumn<int> recognitionFlag = GeneratedColumn<int>(
    'recognition_flag',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
    defaultValue: const Constant(0),
  );
  static const VerificationMeta _scheduledDaysMeta = const VerificationMeta(
    'scheduledDays',
  );
  @override
  late final GeneratedColumn<double> scheduledDays = GeneratedColumn<double>(
    'scheduled_days',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _actualDaysMeta = const VerificationMeta(
    'actualDays',
  );
  @override
  late final GeneratedColumn<double> actualDays = GeneratedColumn<double>(
    'actual_days',
    aliasedName,
    true,
    type: DriftSqlType.double,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _elapsedMsMeta = const VerificationMeta(
    'elapsedMs',
  );
  @override
  late final GeneratedColumn<int> elapsedMs = GeneratedColumn<int>(
    'elapsed_ms',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    cardId,
    rating,
    reviewedAt,
    mode,
    recognitionFlag,
    scheduledDays,
    actualDays,
    elapsedMs,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'review_logs';
  @override
  VerificationContext validateIntegrity(
    Insertable<ReviewLogRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('card_id')) {
      context.handle(
        _cardIdMeta,
        cardId.isAcceptableOrUnknown(data['card_id']!, _cardIdMeta),
      );
    } else if (isInserting) {
      context.missing(_cardIdMeta);
    }
    if (data.containsKey('rating')) {
      context.handle(
        _ratingMeta,
        rating.isAcceptableOrUnknown(data['rating']!, _ratingMeta),
      );
    } else if (isInserting) {
      context.missing(_ratingMeta);
    }
    if (data.containsKey('reviewed_at')) {
      context.handle(
        _reviewedAtMeta,
        reviewedAt.isAcceptableOrUnknown(data['reviewed_at']!, _reviewedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_reviewedAtMeta);
    }
    if (data.containsKey('mode')) {
      context.handle(
        _modeMeta,
        mode.isAcceptableOrUnknown(data['mode']!, _modeMeta),
      );
    } else if (isInserting) {
      context.missing(_modeMeta);
    }
    if (data.containsKey('recognition_flag')) {
      context.handle(
        _recognitionFlagMeta,
        recognitionFlag.isAcceptableOrUnknown(
          data['recognition_flag']!,
          _recognitionFlagMeta,
        ),
      );
    }
    if (data.containsKey('scheduled_days')) {
      context.handle(
        _scheduledDaysMeta,
        scheduledDays.isAcceptableOrUnknown(
          data['scheduled_days']!,
          _scheduledDaysMeta,
        ),
      );
    }
    if (data.containsKey('actual_days')) {
      context.handle(
        _actualDaysMeta,
        actualDays.isAcceptableOrUnknown(data['actual_days']!, _actualDaysMeta),
      );
    }
    if (data.containsKey('elapsed_ms')) {
      context.handle(
        _elapsedMsMeta,
        elapsedMs.isAcceptableOrUnknown(data['elapsed_ms']!, _elapsedMsMeta),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  ReviewLogRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return ReviewLogRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      cardId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}card_id'],
      )!,
      rating: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}rating'],
      )!,
      reviewedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}reviewed_at'],
      )!,
      mode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mode'],
      )!,
      recognitionFlag: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}recognition_flag'],
      )!,
      scheduledDays: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}scheduled_days'],
      ),
      actualDays: attachedDatabase.typeMapping.read(
        DriftSqlType.double,
        data['${effectivePrefix}actual_days'],
      ),
      elapsedMs: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}elapsed_ms'],
      ),
    );
  }

  @override
  $ReviewLogsTable createAlias(String alias) {
    return $ReviewLogsTable(attachedDatabase, alias);
  }
}

class ReviewLogRow extends DataClass implements Insertable<ReviewLogRow> {
  /// Уникальный идентификатор.
  final String id;

  /// Карточка, к которой относится повторение.
  final String cardId;

  /// Оценка: 1 Again, 2 Hard, 3 Good, 4 Easy (SPEC A5).
  final int rating;

  /// Момент повторения (epoch ms).
  final int reviewedAt;

  /// Режим повторения.
  final String mode;

  /// Флаг распознавания: 0/1 (`DEFAULT 0`).
  final int recognitionFlag;

  /// Запланированный интервал, дни.
  final double? scheduledDays;

  /// Фактический интервал, дни.
  final double? actualDays;

  /// Длительность ответа, мс.
  final int? elapsedMs;
  const ReviewLogRow({
    required this.id,
    required this.cardId,
    required this.rating,
    required this.reviewedAt,
    required this.mode,
    required this.recognitionFlag,
    this.scheduledDays,
    this.actualDays,
    this.elapsedMs,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['card_id'] = Variable<String>(cardId);
    map['rating'] = Variable<int>(rating);
    map['reviewed_at'] = Variable<int>(reviewedAt);
    map['mode'] = Variable<String>(mode);
    map['recognition_flag'] = Variable<int>(recognitionFlag);
    if (!nullToAbsent || scheduledDays != null) {
      map['scheduled_days'] = Variable<double>(scheduledDays);
    }
    if (!nullToAbsent || actualDays != null) {
      map['actual_days'] = Variable<double>(actualDays);
    }
    if (!nullToAbsent || elapsedMs != null) {
      map['elapsed_ms'] = Variable<int>(elapsedMs);
    }
    return map;
  }

  ReviewLogsCompanion toCompanion(bool nullToAbsent) {
    return ReviewLogsCompanion(
      id: Value(id),
      cardId: Value(cardId),
      rating: Value(rating),
      reviewedAt: Value(reviewedAt),
      mode: Value(mode),
      recognitionFlag: Value(recognitionFlag),
      scheduledDays: scheduledDays == null && nullToAbsent
          ? const Value.absent()
          : Value(scheduledDays),
      actualDays: actualDays == null && nullToAbsent
          ? const Value.absent()
          : Value(actualDays),
      elapsedMs: elapsedMs == null && nullToAbsent
          ? const Value.absent()
          : Value(elapsedMs),
    );
  }

  factory ReviewLogRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return ReviewLogRow(
      id: serializer.fromJson<String>(json['id']),
      cardId: serializer.fromJson<String>(json['cardId']),
      rating: serializer.fromJson<int>(json['rating']),
      reviewedAt: serializer.fromJson<int>(json['reviewedAt']),
      mode: serializer.fromJson<String>(json['mode']),
      recognitionFlag: serializer.fromJson<int>(json['recognitionFlag']),
      scheduledDays: serializer.fromJson<double?>(json['scheduledDays']),
      actualDays: serializer.fromJson<double?>(json['actualDays']),
      elapsedMs: serializer.fromJson<int?>(json['elapsedMs']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'cardId': serializer.toJson<String>(cardId),
      'rating': serializer.toJson<int>(rating),
      'reviewedAt': serializer.toJson<int>(reviewedAt),
      'mode': serializer.toJson<String>(mode),
      'recognitionFlag': serializer.toJson<int>(recognitionFlag),
      'scheduledDays': serializer.toJson<double?>(scheduledDays),
      'actualDays': serializer.toJson<double?>(actualDays),
      'elapsedMs': serializer.toJson<int?>(elapsedMs),
    };
  }

  ReviewLogRow copyWith({
    String? id,
    String? cardId,
    int? rating,
    int? reviewedAt,
    String? mode,
    int? recognitionFlag,
    Value<double?> scheduledDays = const Value.absent(),
    Value<double?> actualDays = const Value.absent(),
    Value<int?> elapsedMs = const Value.absent(),
  }) => ReviewLogRow(
    id: id ?? this.id,
    cardId: cardId ?? this.cardId,
    rating: rating ?? this.rating,
    reviewedAt: reviewedAt ?? this.reviewedAt,
    mode: mode ?? this.mode,
    recognitionFlag: recognitionFlag ?? this.recognitionFlag,
    scheduledDays: scheduledDays.present
        ? scheduledDays.value
        : this.scheduledDays,
    actualDays: actualDays.present ? actualDays.value : this.actualDays,
    elapsedMs: elapsedMs.present ? elapsedMs.value : this.elapsedMs,
  );
  ReviewLogRow copyWithCompanion(ReviewLogsCompanion data) {
    return ReviewLogRow(
      id: data.id.present ? data.id.value : this.id,
      cardId: data.cardId.present ? data.cardId.value : this.cardId,
      rating: data.rating.present ? data.rating.value : this.rating,
      reviewedAt: data.reviewedAt.present
          ? data.reviewedAt.value
          : this.reviewedAt,
      mode: data.mode.present ? data.mode.value : this.mode,
      recognitionFlag: data.recognitionFlag.present
          ? data.recognitionFlag.value
          : this.recognitionFlag,
      scheduledDays: data.scheduledDays.present
          ? data.scheduledDays.value
          : this.scheduledDays,
      actualDays: data.actualDays.present
          ? data.actualDays.value
          : this.actualDays,
      elapsedMs: data.elapsedMs.present ? data.elapsedMs.value : this.elapsedMs,
    );
  }

  @override
  String toString() {
    return (StringBuffer('ReviewLogRow(')
          ..write('id: $id, ')
          ..write('cardId: $cardId, ')
          ..write('rating: $rating, ')
          ..write('reviewedAt: $reviewedAt, ')
          ..write('mode: $mode, ')
          ..write('recognitionFlag: $recognitionFlag, ')
          ..write('scheduledDays: $scheduledDays, ')
          ..write('actualDays: $actualDays, ')
          ..write('elapsedMs: $elapsedMs')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    cardId,
    rating,
    reviewedAt,
    mode,
    recognitionFlag,
    scheduledDays,
    actualDays,
    elapsedMs,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is ReviewLogRow &&
          other.id == this.id &&
          other.cardId == this.cardId &&
          other.rating == this.rating &&
          other.reviewedAt == this.reviewedAt &&
          other.mode == this.mode &&
          other.recognitionFlag == this.recognitionFlag &&
          other.scheduledDays == this.scheduledDays &&
          other.actualDays == this.actualDays &&
          other.elapsedMs == this.elapsedMs);
}

class ReviewLogsCompanion extends UpdateCompanion<ReviewLogRow> {
  final Value<String> id;
  final Value<String> cardId;
  final Value<int> rating;
  final Value<int> reviewedAt;
  final Value<String> mode;
  final Value<int> recognitionFlag;
  final Value<double?> scheduledDays;
  final Value<double?> actualDays;
  final Value<int?> elapsedMs;
  final Value<int> rowid;
  const ReviewLogsCompanion({
    this.id = const Value.absent(),
    this.cardId = const Value.absent(),
    this.rating = const Value.absent(),
    this.reviewedAt = const Value.absent(),
    this.mode = const Value.absent(),
    this.recognitionFlag = const Value.absent(),
    this.scheduledDays = const Value.absent(),
    this.actualDays = const Value.absent(),
    this.elapsedMs = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  ReviewLogsCompanion.insert({
    required String id,
    required String cardId,
    required int rating,
    required int reviewedAt,
    required String mode,
    this.recognitionFlag = const Value.absent(),
    this.scheduledDays = const Value.absent(),
    this.actualDays = const Value.absent(),
    this.elapsedMs = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       cardId = Value(cardId),
       rating = Value(rating),
       reviewedAt = Value(reviewedAt),
       mode = Value(mode);
  static Insertable<ReviewLogRow> custom({
    Expression<String>? id,
    Expression<String>? cardId,
    Expression<int>? rating,
    Expression<int>? reviewedAt,
    Expression<String>? mode,
    Expression<int>? recognitionFlag,
    Expression<double>? scheduledDays,
    Expression<double>? actualDays,
    Expression<int>? elapsedMs,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (cardId != null) 'card_id': cardId,
      if (rating != null) 'rating': rating,
      if (reviewedAt != null) 'reviewed_at': reviewedAt,
      if (mode != null) 'mode': mode,
      if (recognitionFlag != null) 'recognition_flag': recognitionFlag,
      if (scheduledDays != null) 'scheduled_days': scheduledDays,
      if (actualDays != null) 'actual_days': actualDays,
      if (elapsedMs != null) 'elapsed_ms': elapsedMs,
      if (rowid != null) 'rowid': rowid,
    });
  }

  ReviewLogsCompanion copyWith({
    Value<String>? id,
    Value<String>? cardId,
    Value<int>? rating,
    Value<int>? reviewedAt,
    Value<String>? mode,
    Value<int>? recognitionFlag,
    Value<double?>? scheduledDays,
    Value<double?>? actualDays,
    Value<int?>? elapsedMs,
    Value<int>? rowid,
  }) {
    return ReviewLogsCompanion(
      id: id ?? this.id,
      cardId: cardId ?? this.cardId,
      rating: rating ?? this.rating,
      reviewedAt: reviewedAt ?? this.reviewedAt,
      mode: mode ?? this.mode,
      recognitionFlag: recognitionFlag ?? this.recognitionFlag,
      scheduledDays: scheduledDays ?? this.scheduledDays,
      actualDays: actualDays ?? this.actualDays,
      elapsedMs: elapsedMs ?? this.elapsedMs,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (cardId.present) {
      map['card_id'] = Variable<String>(cardId.value);
    }
    if (rating.present) {
      map['rating'] = Variable<int>(rating.value);
    }
    if (reviewedAt.present) {
      map['reviewed_at'] = Variable<int>(reviewedAt.value);
    }
    if (mode.present) {
      map['mode'] = Variable<String>(mode.value);
    }
    if (recognitionFlag.present) {
      map['recognition_flag'] = Variable<int>(recognitionFlag.value);
    }
    if (scheduledDays.present) {
      map['scheduled_days'] = Variable<double>(scheduledDays.value);
    }
    if (actualDays.present) {
      map['actual_days'] = Variable<double>(actualDays.value);
    }
    if (elapsedMs.present) {
      map['elapsed_ms'] = Variable<int>(elapsedMs.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('ReviewLogsCompanion(')
          ..write('id: $id, ')
          ..write('cardId: $cardId, ')
          ..write('rating: $rating, ')
          ..write('reviewedAt: $reviewedAt, ')
          ..write('mode: $mode, ')
          ..write('recognitionFlag: $recognitionFlag, ')
          ..write('scheduledDays: $scheduledDays, ')
          ..write('actualDays: $actualDays, ')
          ..write('elapsedMs: $elapsedMs, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $PracticeLogsTable extends PracticeLogs
    with TableInfo<$PracticeLogsTable, PracticeLogRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $PracticeLogsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cardIdMeta = const VerificationMeta('cardId');
  @override
  late final GeneratedColumn<String> cardId = GeneratedColumn<String>(
    'card_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _modeMeta = const VerificationMeta('mode');
  @override
  late final GeneratedColumn<String> mode = GeneratedColumn<String>(
    'mode',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _reviewedAtMeta = const VerificationMeta(
    'reviewedAt',
  );
  @override
  late final GeneratedColumn<int> reviewedAt = GeneratedColumn<int>(
    'reviewed_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, cardId, mode, reviewedAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'practice_logs';
  @override
  VerificationContext validateIntegrity(
    Insertable<PracticeLogRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('card_id')) {
      context.handle(
        _cardIdMeta,
        cardId.isAcceptableOrUnknown(data['card_id']!, _cardIdMeta),
      );
    } else if (isInserting) {
      context.missing(_cardIdMeta);
    }
    if (data.containsKey('mode')) {
      context.handle(
        _modeMeta,
        mode.isAcceptableOrUnknown(data['mode']!, _modeMeta),
      );
    } else if (isInserting) {
      context.missing(_modeMeta);
    }
    if (data.containsKey('reviewed_at')) {
      context.handle(
        _reviewedAtMeta,
        reviewedAt.isAcceptableOrUnknown(data['reviewed_at']!, _reviewedAtMeta),
      );
    } else if (isInserting) {
      context.missing(_reviewedAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  PracticeLogRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return PracticeLogRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      cardId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}card_id'],
      )!,
      mode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mode'],
      )!,
      reviewedAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}reviewed_at'],
      )!,
    );
  }

  @override
  $PracticeLogsTable createAlias(String alias) {
    return $PracticeLogsTable(attachedDatabase, alias);
  }
}

class PracticeLogRow extends DataClass implements Insertable<PracticeLogRow> {
  /// Уникальный идентификатор.
  final String id;

  /// Карточка, к которой относится тренировка.
  final String cardId;

  /// Режим тренировки.
  final String mode;

  /// Момент тренировки (epoch ms).
  final int reviewedAt;
  const PracticeLogRow({
    required this.id,
    required this.cardId,
    required this.mode,
    required this.reviewedAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['card_id'] = Variable<String>(cardId);
    map['mode'] = Variable<String>(mode);
    map['reviewed_at'] = Variable<int>(reviewedAt);
    return map;
  }

  PracticeLogsCompanion toCompanion(bool nullToAbsent) {
    return PracticeLogsCompanion(
      id: Value(id),
      cardId: Value(cardId),
      mode: Value(mode),
      reviewedAt: Value(reviewedAt),
    );
  }

  factory PracticeLogRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return PracticeLogRow(
      id: serializer.fromJson<String>(json['id']),
      cardId: serializer.fromJson<String>(json['cardId']),
      mode: serializer.fromJson<String>(json['mode']),
      reviewedAt: serializer.fromJson<int>(json['reviewedAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'cardId': serializer.toJson<String>(cardId),
      'mode': serializer.toJson<String>(mode),
      'reviewedAt': serializer.toJson<int>(reviewedAt),
    };
  }

  PracticeLogRow copyWith({
    String? id,
    String? cardId,
    String? mode,
    int? reviewedAt,
  }) => PracticeLogRow(
    id: id ?? this.id,
    cardId: cardId ?? this.cardId,
    mode: mode ?? this.mode,
    reviewedAt: reviewedAt ?? this.reviewedAt,
  );
  PracticeLogRow copyWithCompanion(PracticeLogsCompanion data) {
    return PracticeLogRow(
      id: data.id.present ? data.id.value : this.id,
      cardId: data.cardId.present ? data.cardId.value : this.cardId,
      mode: data.mode.present ? data.mode.value : this.mode,
      reviewedAt: data.reviewedAt.present
          ? data.reviewedAt.value
          : this.reviewedAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('PracticeLogRow(')
          ..write('id: $id, ')
          ..write('cardId: $cardId, ')
          ..write('mode: $mode, ')
          ..write('reviewedAt: $reviewedAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, cardId, mode, reviewedAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is PracticeLogRow &&
          other.id == this.id &&
          other.cardId == this.cardId &&
          other.mode == this.mode &&
          other.reviewedAt == this.reviewedAt);
}

class PracticeLogsCompanion extends UpdateCompanion<PracticeLogRow> {
  final Value<String> id;
  final Value<String> cardId;
  final Value<String> mode;
  final Value<int> reviewedAt;
  final Value<int> rowid;
  const PracticeLogsCompanion({
    this.id = const Value.absent(),
    this.cardId = const Value.absent(),
    this.mode = const Value.absent(),
    this.reviewedAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  PracticeLogsCompanion.insert({
    required String id,
    required String cardId,
    required String mode,
    required int reviewedAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       cardId = Value(cardId),
       mode = Value(mode),
       reviewedAt = Value(reviewedAt);
  static Insertable<PracticeLogRow> custom({
    Expression<String>? id,
    Expression<String>? cardId,
    Expression<String>? mode,
    Expression<int>? reviewedAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (cardId != null) 'card_id': cardId,
      if (mode != null) 'mode': mode,
      if (reviewedAt != null) 'reviewed_at': reviewedAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  PracticeLogsCompanion copyWith({
    Value<String>? id,
    Value<String>? cardId,
    Value<String>? mode,
    Value<int>? reviewedAt,
    Value<int>? rowid,
  }) {
    return PracticeLogsCompanion(
      id: id ?? this.id,
      cardId: cardId ?? this.cardId,
      mode: mode ?? this.mode,
      reviewedAt: reviewedAt ?? this.reviewedAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (cardId.present) {
      map['card_id'] = Variable<String>(cardId.value);
    }
    if (mode.present) {
      map['mode'] = Variable<String>(mode.value);
    }
    if (reviewedAt.present) {
      map['reviewed_at'] = Variable<int>(reviewedAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('PracticeLogsCompanion(')
          ..write('id: $id, ')
          ..write('cardId: $cardId, ')
          ..write('mode: $mode, ')
          ..write('reviewedAt: $reviewedAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $MediaTable extends Media with TableInfo<$MediaTable, MediaRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $MediaTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _cardIdMeta = const VerificationMeta('cardId');
  @override
  late final GeneratedColumn<String> cardId = GeneratedColumn<String>(
    'card_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pathMeta = const VerificationMeta('path');
  @override
  late final GeneratedColumn<String> path = GeneratedColumn<String>(
    'path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _mimeTypeMeta = const VerificationMeta(
    'mimeType',
  );
  @override
  late final GeneratedColumn<String> mimeType = GeneratedColumn<String>(
    'mime_type',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _sizeMeta = const VerificationMeta('size');
  @override
  late final GeneratedColumn<int> size = GeneratedColumn<int>(
    'size',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, cardId, path, mimeType, size];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'media';
  @override
  VerificationContext validateIntegrity(
    Insertable<MediaRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('card_id')) {
      context.handle(
        _cardIdMeta,
        cardId.isAcceptableOrUnknown(data['card_id']!, _cardIdMeta),
      );
    } else if (isInserting) {
      context.missing(_cardIdMeta);
    }
    if (data.containsKey('path')) {
      context.handle(
        _pathMeta,
        path.isAcceptableOrUnknown(data['path']!, _pathMeta),
      );
    } else if (isInserting) {
      context.missing(_pathMeta);
    }
    if (data.containsKey('mime_type')) {
      context.handle(
        _mimeTypeMeta,
        mimeType.isAcceptableOrUnknown(data['mime_type']!, _mimeTypeMeta),
      );
    } else if (isInserting) {
      context.missing(_mimeTypeMeta);
    }
    if (data.containsKey('size')) {
      context.handle(
        _sizeMeta,
        size.isAcceptableOrUnknown(data['size']!, _sizeMeta),
      );
    } else if (isInserting) {
      context.missing(_sizeMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  MediaRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return MediaRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      cardId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}card_id'],
      )!,
      path: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}path'],
      )!,
      mimeType: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}mime_type'],
      )!,
      size: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}size'],
      )!,
    );
  }

  @override
  $MediaTable createAlias(String alias) {
    return $MediaTable(attachedDatabase, alias);
  }
}

class MediaRow extends DataClass implements Insertable<MediaRow> {
  /// Уникальный идентификатор.
  final String id;

  /// Карточка-владелец.
  final String cardId;

  /// Путь к файлу в каталоге медиа.
  final String path;

  /// MIME-тип.
  final String mimeType;

  /// Размер файла, байт.
  final int size;
  const MediaRow({
    required this.id,
    required this.cardId,
    required this.path,
    required this.mimeType,
    required this.size,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['card_id'] = Variable<String>(cardId);
    map['path'] = Variable<String>(path);
    map['mime_type'] = Variable<String>(mimeType);
    map['size'] = Variable<int>(size);
    return map;
  }

  MediaCompanion toCompanion(bool nullToAbsent) {
    return MediaCompanion(
      id: Value(id),
      cardId: Value(cardId),
      path: Value(path),
      mimeType: Value(mimeType),
      size: Value(size),
    );
  }

  factory MediaRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return MediaRow(
      id: serializer.fromJson<String>(json['id']),
      cardId: serializer.fromJson<String>(json['cardId']),
      path: serializer.fromJson<String>(json['path']),
      mimeType: serializer.fromJson<String>(json['mimeType']),
      size: serializer.fromJson<int>(json['size']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'cardId': serializer.toJson<String>(cardId),
      'path': serializer.toJson<String>(path),
      'mimeType': serializer.toJson<String>(mimeType),
      'size': serializer.toJson<int>(size),
    };
  }

  MediaRow copyWith({
    String? id,
    String? cardId,
    String? path,
    String? mimeType,
    int? size,
  }) => MediaRow(
    id: id ?? this.id,
    cardId: cardId ?? this.cardId,
    path: path ?? this.path,
    mimeType: mimeType ?? this.mimeType,
    size: size ?? this.size,
  );
  MediaRow copyWithCompanion(MediaCompanion data) {
    return MediaRow(
      id: data.id.present ? data.id.value : this.id,
      cardId: data.cardId.present ? data.cardId.value : this.cardId,
      path: data.path.present ? data.path.value : this.path,
      mimeType: data.mimeType.present ? data.mimeType.value : this.mimeType,
      size: data.size.present ? data.size.value : this.size,
    );
  }

  @override
  String toString() {
    return (StringBuffer('MediaRow(')
          ..write('id: $id, ')
          ..write('cardId: $cardId, ')
          ..write('path: $path, ')
          ..write('mimeType: $mimeType, ')
          ..write('size: $size')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, cardId, path, mimeType, size);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is MediaRow &&
          other.id == this.id &&
          other.cardId == this.cardId &&
          other.path == this.path &&
          other.mimeType == this.mimeType &&
          other.size == this.size);
}

class MediaCompanion extends UpdateCompanion<MediaRow> {
  final Value<String> id;
  final Value<String> cardId;
  final Value<String> path;
  final Value<String> mimeType;
  final Value<int> size;
  final Value<int> rowid;
  const MediaCompanion({
    this.id = const Value.absent(),
    this.cardId = const Value.absent(),
    this.path = const Value.absent(),
    this.mimeType = const Value.absent(),
    this.size = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  MediaCompanion.insert({
    required String id,
    required String cardId,
    required String path,
    required String mimeType,
    required int size,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       cardId = Value(cardId),
       path = Value(path),
       mimeType = Value(mimeType),
       size = Value(size);
  static Insertable<MediaRow> custom({
    Expression<String>? id,
    Expression<String>? cardId,
    Expression<String>? path,
    Expression<String>? mimeType,
    Expression<int>? size,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (cardId != null) 'card_id': cardId,
      if (path != null) 'path': path,
      if (mimeType != null) 'mime_type': mimeType,
      if (size != null) 'size': size,
      if (rowid != null) 'rowid': rowid,
    });
  }

  MediaCompanion copyWith({
    Value<String>? id,
    Value<String>? cardId,
    Value<String>? path,
    Value<String>? mimeType,
    Value<int>? size,
    Value<int>? rowid,
  }) {
    return MediaCompanion(
      id: id ?? this.id,
      cardId: cardId ?? this.cardId,
      path: path ?? this.path,
      mimeType: mimeType ?? this.mimeType,
      size: size ?? this.size,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (cardId.present) {
      map['card_id'] = Variable<String>(cardId.value);
    }
    if (path.present) {
      map['path'] = Variable<String>(path.value);
    }
    if (mimeType.present) {
      map['mime_type'] = Variable<String>(mimeType.value);
    }
    if (size.present) {
      map['size'] = Variable<int>(size.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('MediaCompanion(')
          ..write('id: $id, ')
          ..write('cardId: $cardId, ')
          ..write('path: $path, ')
          ..write('mimeType: $mimeType, ')
          ..write('size: $size, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SourceDocsTable extends SourceDocs
    with TableInfo<$SourceDocsTable, SourceDocRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SourceDocsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _deckIdMeta = const VerificationMeta('deckId');
  @override
  late final GeneratedColumn<String> deckId = GeneratedColumn<String>(
    'deck_id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _pathMeta = const VerificationMeta('path');
  @override
  late final GeneratedColumn<String> path = GeneratedColumn<String>(
    'path',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _titleMeta = const VerificationMeta('title');
  @override
  late final GeneratedColumn<String> title = GeneratedColumn<String>(
    'title',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, deckId, path, title];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'source_docs';
  @override
  VerificationContext validateIntegrity(
    Insertable<SourceDocRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('deck_id')) {
      context.handle(
        _deckIdMeta,
        deckId.isAcceptableOrUnknown(data['deck_id']!, _deckIdMeta),
      );
    } else if (isInserting) {
      context.missing(_deckIdMeta);
    }
    if (data.containsKey('path')) {
      context.handle(
        _pathMeta,
        path.isAcceptableOrUnknown(data['path']!, _pathMeta),
      );
    } else if (isInserting) {
      context.missing(_pathMeta);
    }
    if (data.containsKey('title')) {
      context.handle(
        _titleMeta,
        title.isAcceptableOrUnknown(data['title']!, _titleMeta),
      );
    } else if (isInserting) {
      context.missing(_titleMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SourceDocRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SourceDocRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      deckId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}deck_id'],
      )!,
      path: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}path'],
      )!,
      title: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}title'],
      )!,
    );
  }

  @override
  $SourceDocsTable createAlias(String alias) {
    return $SourceDocsTable(attachedDatabase, alias);
  }
}

class SourceDocRow extends DataClass implements Insertable<SourceDocRow> {
  /// Уникальный идентификатор.
  final String id;

  /// Колода, к которой привязан документ.
  final String deckId;

  /// Путь к файлу.
  final String path;

  /// Отображаемое название.
  final String title;
  const SourceDocRow({
    required this.id,
    required this.deckId,
    required this.path,
    required this.title,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['deck_id'] = Variable<String>(deckId);
    map['path'] = Variable<String>(path);
    map['title'] = Variable<String>(title);
    return map;
  }

  SourceDocsCompanion toCompanion(bool nullToAbsent) {
    return SourceDocsCompanion(
      id: Value(id),
      deckId: Value(deckId),
      path: Value(path),
      title: Value(title),
    );
  }

  factory SourceDocRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SourceDocRow(
      id: serializer.fromJson<String>(json['id']),
      deckId: serializer.fromJson<String>(json['deckId']),
      path: serializer.fromJson<String>(json['path']),
      title: serializer.fromJson<String>(json['title']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'deckId': serializer.toJson<String>(deckId),
      'path': serializer.toJson<String>(path),
      'title': serializer.toJson<String>(title),
    };
  }

  SourceDocRow copyWith({
    String? id,
    String? deckId,
    String? path,
    String? title,
  }) => SourceDocRow(
    id: id ?? this.id,
    deckId: deckId ?? this.deckId,
    path: path ?? this.path,
    title: title ?? this.title,
  );
  SourceDocRow copyWithCompanion(SourceDocsCompanion data) {
    return SourceDocRow(
      id: data.id.present ? data.id.value : this.id,
      deckId: data.deckId.present ? data.deckId.value : this.deckId,
      path: data.path.present ? data.path.value : this.path,
      title: data.title.present ? data.title.value : this.title,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SourceDocRow(')
          ..write('id: $id, ')
          ..write('deckId: $deckId, ')
          ..write('path: $path, ')
          ..write('title: $title')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, deckId, path, title);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SourceDocRow &&
          other.id == this.id &&
          other.deckId == this.deckId &&
          other.path == this.path &&
          other.title == this.title);
}

class SourceDocsCompanion extends UpdateCompanion<SourceDocRow> {
  final Value<String> id;
  final Value<String> deckId;
  final Value<String> path;
  final Value<String> title;
  final Value<int> rowid;
  const SourceDocsCompanion({
    this.id = const Value.absent(),
    this.deckId = const Value.absent(),
    this.path = const Value.absent(),
    this.title = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SourceDocsCompanion.insert({
    required String id,
    required String deckId,
    required String path,
    required String title,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       deckId = Value(deckId),
       path = Value(path),
       title = Value(title);
  static Insertable<SourceDocRow> custom({
    Expression<String>? id,
    Expression<String>? deckId,
    Expression<String>? path,
    Expression<String>? title,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (deckId != null) 'deck_id': deckId,
      if (path != null) 'path': path,
      if (title != null) 'title': title,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SourceDocsCompanion copyWith({
    Value<String>? id,
    Value<String>? deckId,
    Value<String>? path,
    Value<String>? title,
    Value<int>? rowid,
  }) {
    return SourceDocsCompanion(
      id: id ?? this.id,
      deckId: deckId ?? this.deckId,
      path: path ?? this.path,
      title: title ?? this.title,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (deckId.present) {
      map['deck_id'] = Variable<String>(deckId.value);
    }
    if (path.present) {
      map['path'] = Variable<String>(path.value);
    }
    if (title.present) {
      map['title'] = Variable<String>(title.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SourceDocsCompanion(')
          ..write('id: $id, ')
          ..write('deckId: $deckId, ')
          ..write('path: $path, ')
          ..write('title: $title, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SyncMetaTable extends SyncMeta
    with TableInfo<$SyncMetaTable, SyncMetaRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SyncMetaTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _deviceIdMeta = const VerificationMeta(
    'deviceId',
  );
  @override
  late final GeneratedColumn<String> deviceId = GeneratedColumn<String>(
    'device_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _lastSyncHlcMeta = const VerificationMeta(
    'lastSyncHlc',
  );
  @override
  late final GeneratedColumn<String> lastSyncHlc = GeneratedColumn<String>(
    'last_sync_hlc',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [deviceId, lastSyncHlc];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'sync_meta';
  @override
  VerificationContext validateIntegrity(
    Insertable<SyncMetaRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('device_id')) {
      context.handle(
        _deviceIdMeta,
        deviceId.isAcceptableOrUnknown(data['device_id']!, _deviceIdMeta),
      );
    }
    if (data.containsKey('last_sync_hlc')) {
      context.handle(
        _lastSyncHlcMeta,
        lastSyncHlc.isAcceptableOrUnknown(
          data['last_sync_hlc']!,
          _lastSyncHlcMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => const {};
  @override
  SyncMetaRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SyncMetaRow(
      deviceId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}device_id'],
      ),
      lastSyncHlc: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}last_sync_hlc'],
      ),
    );
  }

  @override
  $SyncMetaTable createAlias(String alias) {
    return $SyncMetaTable(attachedDatabase, alias);
  }
}

class SyncMetaRow extends DataClass implements Insertable<SyncMetaRow> {
  /// Идентификатор устройства.
  final String? deviceId;

  /// Последняя синхронизация в HLC (Hybrid Logical Clock).
  final String? lastSyncHlc;
  const SyncMetaRow({this.deviceId, this.lastSyncHlc});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (!nullToAbsent || deviceId != null) {
      map['device_id'] = Variable<String>(deviceId);
    }
    if (!nullToAbsent || lastSyncHlc != null) {
      map['last_sync_hlc'] = Variable<String>(lastSyncHlc);
    }
    return map;
  }

  SyncMetaCompanion toCompanion(bool nullToAbsent) {
    return SyncMetaCompanion(
      deviceId: deviceId == null && nullToAbsent
          ? const Value.absent()
          : Value(deviceId),
      lastSyncHlc: lastSyncHlc == null && nullToAbsent
          ? const Value.absent()
          : Value(lastSyncHlc),
    );
  }

  factory SyncMetaRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SyncMetaRow(
      deviceId: serializer.fromJson<String?>(json['deviceId']),
      lastSyncHlc: serializer.fromJson<String?>(json['lastSyncHlc']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'deviceId': serializer.toJson<String?>(deviceId),
      'lastSyncHlc': serializer.toJson<String?>(lastSyncHlc),
    };
  }

  SyncMetaRow copyWith({
    Value<String?> deviceId = const Value.absent(),
    Value<String?> lastSyncHlc = const Value.absent(),
  }) => SyncMetaRow(
    deviceId: deviceId.present ? deviceId.value : this.deviceId,
    lastSyncHlc: lastSyncHlc.present ? lastSyncHlc.value : this.lastSyncHlc,
  );
  SyncMetaRow copyWithCompanion(SyncMetaCompanion data) {
    return SyncMetaRow(
      deviceId: data.deviceId.present ? data.deviceId.value : this.deviceId,
      lastSyncHlc: data.lastSyncHlc.present
          ? data.lastSyncHlc.value
          : this.lastSyncHlc,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SyncMetaRow(')
          ..write('deviceId: $deviceId, ')
          ..write('lastSyncHlc: $lastSyncHlc')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(deviceId, lastSyncHlc);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SyncMetaRow &&
          other.deviceId == this.deviceId &&
          other.lastSyncHlc == this.lastSyncHlc);
}

class SyncMetaCompanion extends UpdateCompanion<SyncMetaRow> {
  final Value<String?> deviceId;
  final Value<String?> lastSyncHlc;
  final Value<int> rowid;
  const SyncMetaCompanion({
    this.deviceId = const Value.absent(),
    this.lastSyncHlc = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SyncMetaCompanion.insert({
    this.deviceId = const Value.absent(),
    this.lastSyncHlc = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  static Insertable<SyncMetaRow> custom({
    Expression<String>? deviceId,
    Expression<String>? lastSyncHlc,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (deviceId != null) 'device_id': deviceId,
      if (lastSyncHlc != null) 'last_sync_hlc': lastSyncHlc,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SyncMetaCompanion copyWith({
    Value<String?>? deviceId,
    Value<String?>? lastSyncHlc,
    Value<int>? rowid,
  }) {
    return SyncMetaCompanion(
      deviceId: deviceId ?? this.deviceId,
      lastSyncHlc: lastSyncHlc ?? this.lastSyncHlc,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (deviceId.present) {
      map['device_id'] = Variable<String>(deviceId.value);
    }
    if (lastSyncHlc.present) {
      map['last_sync_hlc'] = Variable<String>(lastSyncHlc.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SyncMetaCompanion(')
          ..write('deviceId: $deviceId, ')
          ..write('lastSyncHlc: $lastSyncHlc, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $GenerationJobsTable extends GenerationJobs
    with TableInfo<$GenerationJobsTable, GenerationJobRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $GenerationJobsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _statusMeta = const VerificationMeta('status');
  @override
  late final GeneratedColumn<String> status = GeneratedColumn<String>(
    'status',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _providerMeta = const VerificationMeta(
    'provider',
  );
  @override
  late final GeneratedColumn<String> provider = GeneratedColumn<String>(
    'provider',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _modelMeta = const VerificationMeta('model');
  @override
  late final GeneratedColumn<String> model = GeneratedColumn<String>(
    'model',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _tokensUsedMeta = const VerificationMeta(
    'tokensUsed',
  );
  @override
  late final GeneratedColumn<int> tokensUsed = GeneratedColumn<int>(
    'tokens_used',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _promptVersionMeta = const VerificationMeta(
    'promptVersion',
  );
  @override
  late final GeneratedColumn<String> promptVersion = GeneratedColumn<String>(
    'prompt_version',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _errorCodeMeta = const VerificationMeta(
    'errorCode',
  );
  @override
  late final GeneratedColumn<String> errorCode = GeneratedColumn<String>(
    'error_code',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _cardsCountMeta = const VerificationMeta(
    'cardsCount',
  );
  @override
  late final GeneratedColumn<int> cardsCount = GeneratedColumn<int>(
    'cards_count',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _chunkCountMeta = const VerificationMeta(
    'chunkCount',
  );
  @override
  late final GeneratedColumn<int> chunkCount = GeneratedColumn<int>(
    'chunk_count',
    aliasedName,
    true,
    type: DriftSqlType.int,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _filesJsonMeta = const VerificationMeta(
    'filesJson',
  );
  @override
  late final GeneratedColumn<String> filesJson = GeneratedColumn<String>(
    'files_json',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  static const VerificationMeta _resultDeckIdMeta = const VerificationMeta(
    'resultDeckId',
  );
  @override
  late final GeneratedColumn<String> resultDeckId = GeneratedColumn<String>(
    'result_deck_id',
    aliasedName,
    true,
    type: DriftSqlType.string,
    requiredDuringInsert: false,
  );
  @override
  List<GeneratedColumn> get $columns => [
    id,
    status,
    createdAt,
    provider,
    model,
    tokensUsed,
    promptVersion,
    errorCode,
    cardsCount,
    chunkCount,
    filesJson,
    resultDeckId,
  ];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'generation_jobs';
  @override
  VerificationContext validateIntegrity(
    Insertable<GenerationJobRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('status')) {
      context.handle(
        _statusMeta,
        status.isAcceptableOrUnknown(data['status']!, _statusMeta),
      );
    } else if (isInserting) {
      context.missing(_statusMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    if (data.containsKey('provider')) {
      context.handle(
        _providerMeta,
        provider.isAcceptableOrUnknown(data['provider']!, _providerMeta),
      );
    }
    if (data.containsKey('model')) {
      context.handle(
        _modelMeta,
        model.isAcceptableOrUnknown(data['model']!, _modelMeta),
      );
    }
    if (data.containsKey('tokens_used')) {
      context.handle(
        _tokensUsedMeta,
        tokensUsed.isAcceptableOrUnknown(data['tokens_used']!, _tokensUsedMeta),
      );
    }
    if (data.containsKey('prompt_version')) {
      context.handle(
        _promptVersionMeta,
        promptVersion.isAcceptableOrUnknown(
          data['prompt_version']!,
          _promptVersionMeta,
        ),
      );
    }
    if (data.containsKey('error_code')) {
      context.handle(
        _errorCodeMeta,
        errorCode.isAcceptableOrUnknown(data['error_code']!, _errorCodeMeta),
      );
    }
    if (data.containsKey('cards_count')) {
      context.handle(
        _cardsCountMeta,
        cardsCount.isAcceptableOrUnknown(data['cards_count']!, _cardsCountMeta),
      );
    }
    if (data.containsKey('chunk_count')) {
      context.handle(
        _chunkCountMeta,
        chunkCount.isAcceptableOrUnknown(data['chunk_count']!, _chunkCountMeta),
      );
    }
    if (data.containsKey('files_json')) {
      context.handle(
        _filesJsonMeta,
        filesJson.isAcceptableOrUnknown(data['files_json']!, _filesJsonMeta),
      );
    }
    if (data.containsKey('result_deck_id')) {
      context.handle(
        _resultDeckIdMeta,
        resultDeckId.isAcceptableOrUnknown(
          data['result_deck_id']!,
          _resultDeckIdMeta,
        ),
      );
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  GenerationJobRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return GenerationJobRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      status: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}status'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
      provider: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}provider'],
      ),
      model: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}model'],
      ),
      tokensUsed: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}tokens_used'],
      ),
      promptVersion: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}prompt_version'],
      ),
      errorCode: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}error_code'],
      ),
      cardsCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}cards_count'],
      ),
      chunkCount: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}chunk_count'],
      ),
      filesJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}files_json'],
      ),
      resultDeckId: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}result_deck_id'],
      ),
    );
  }

  @override
  $GenerationJobsTable createAlias(String alias) {
    return $GenerationJobsTable(attachedDatabase, alias);
  }
}

class GenerationJobRow extends DataClass
    implements Insertable<GenerationJobRow> {
  /// Уникальный идентификатор.
  final String id;

  /// Статус: `running | done | partial | error | cancelled`.
  final String status;

  /// Момент создания (epoch ms).
  final int createdAt;

  /// Провайдер API.
  final String? provider;

  /// Модель провайдера.
  final String? model;

  /// Израсходовано токенов.
  final int? tokensUsed;

  /// Версия встроенного системного промпта.
  final String? promptVersion;

  /// Машинный код ошибки для retry-логики.
  final String? errorCode;

  /// Сколько карточек получено.
  final int? cardsCount;

  /// Сколько фрагментов обработано.
  final int? chunkCount;

  /// JSON со списком файлов.
  final String? filesJson;

  /// Колода, куда импортированы карточки.
  final String? resultDeckId;
  const GenerationJobRow({
    required this.id,
    required this.status,
    required this.createdAt,
    this.provider,
    this.model,
    this.tokensUsed,
    this.promptVersion,
    this.errorCode,
    this.cardsCount,
    this.chunkCount,
    this.filesJson,
    this.resultDeckId,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['status'] = Variable<String>(status);
    map['created_at'] = Variable<int>(createdAt);
    if (!nullToAbsent || provider != null) {
      map['provider'] = Variable<String>(provider);
    }
    if (!nullToAbsent || model != null) {
      map['model'] = Variable<String>(model);
    }
    if (!nullToAbsent || tokensUsed != null) {
      map['tokens_used'] = Variable<int>(tokensUsed);
    }
    if (!nullToAbsent || promptVersion != null) {
      map['prompt_version'] = Variable<String>(promptVersion);
    }
    if (!nullToAbsent || errorCode != null) {
      map['error_code'] = Variable<String>(errorCode);
    }
    if (!nullToAbsent || cardsCount != null) {
      map['cards_count'] = Variable<int>(cardsCount);
    }
    if (!nullToAbsent || chunkCount != null) {
      map['chunk_count'] = Variable<int>(chunkCount);
    }
    if (!nullToAbsent || filesJson != null) {
      map['files_json'] = Variable<String>(filesJson);
    }
    if (!nullToAbsent || resultDeckId != null) {
      map['result_deck_id'] = Variable<String>(resultDeckId);
    }
    return map;
  }

  GenerationJobsCompanion toCompanion(bool nullToAbsent) {
    return GenerationJobsCompanion(
      id: Value(id),
      status: Value(status),
      createdAt: Value(createdAt),
      provider: provider == null && nullToAbsent
          ? const Value.absent()
          : Value(provider),
      model: model == null && nullToAbsent
          ? const Value.absent()
          : Value(model),
      tokensUsed: tokensUsed == null && nullToAbsent
          ? const Value.absent()
          : Value(tokensUsed),
      promptVersion: promptVersion == null && nullToAbsent
          ? const Value.absent()
          : Value(promptVersion),
      errorCode: errorCode == null && nullToAbsent
          ? const Value.absent()
          : Value(errorCode),
      cardsCount: cardsCount == null && nullToAbsent
          ? const Value.absent()
          : Value(cardsCount),
      chunkCount: chunkCount == null && nullToAbsent
          ? const Value.absent()
          : Value(chunkCount),
      filesJson: filesJson == null && nullToAbsent
          ? const Value.absent()
          : Value(filesJson),
      resultDeckId: resultDeckId == null && nullToAbsent
          ? const Value.absent()
          : Value(resultDeckId),
    );
  }

  factory GenerationJobRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return GenerationJobRow(
      id: serializer.fromJson<String>(json['id']),
      status: serializer.fromJson<String>(json['status']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
      provider: serializer.fromJson<String?>(json['provider']),
      model: serializer.fromJson<String?>(json['model']),
      tokensUsed: serializer.fromJson<int?>(json['tokensUsed']),
      promptVersion: serializer.fromJson<String?>(json['promptVersion']),
      errorCode: serializer.fromJson<String?>(json['errorCode']),
      cardsCount: serializer.fromJson<int?>(json['cardsCount']),
      chunkCount: serializer.fromJson<int?>(json['chunkCount']),
      filesJson: serializer.fromJson<String?>(json['filesJson']),
      resultDeckId: serializer.fromJson<String?>(json['resultDeckId']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'status': serializer.toJson<String>(status),
      'createdAt': serializer.toJson<int>(createdAt),
      'provider': serializer.toJson<String?>(provider),
      'model': serializer.toJson<String?>(model),
      'tokensUsed': serializer.toJson<int?>(tokensUsed),
      'promptVersion': serializer.toJson<String?>(promptVersion),
      'errorCode': serializer.toJson<String?>(errorCode),
      'cardsCount': serializer.toJson<int?>(cardsCount),
      'chunkCount': serializer.toJson<int?>(chunkCount),
      'filesJson': serializer.toJson<String?>(filesJson),
      'resultDeckId': serializer.toJson<String?>(resultDeckId),
    };
  }

  GenerationJobRow copyWith({
    String? id,
    String? status,
    int? createdAt,
    Value<String?> provider = const Value.absent(),
    Value<String?> model = const Value.absent(),
    Value<int?> tokensUsed = const Value.absent(),
    Value<String?> promptVersion = const Value.absent(),
    Value<String?> errorCode = const Value.absent(),
    Value<int?> cardsCount = const Value.absent(),
    Value<int?> chunkCount = const Value.absent(),
    Value<String?> filesJson = const Value.absent(),
    Value<String?> resultDeckId = const Value.absent(),
  }) => GenerationJobRow(
    id: id ?? this.id,
    status: status ?? this.status,
    createdAt: createdAt ?? this.createdAt,
    provider: provider.present ? provider.value : this.provider,
    model: model.present ? model.value : this.model,
    tokensUsed: tokensUsed.present ? tokensUsed.value : this.tokensUsed,
    promptVersion: promptVersion.present
        ? promptVersion.value
        : this.promptVersion,
    errorCode: errorCode.present ? errorCode.value : this.errorCode,
    cardsCount: cardsCount.present ? cardsCount.value : this.cardsCount,
    chunkCount: chunkCount.present ? chunkCount.value : this.chunkCount,
    filesJson: filesJson.present ? filesJson.value : this.filesJson,
    resultDeckId: resultDeckId.present ? resultDeckId.value : this.resultDeckId,
  );
  GenerationJobRow copyWithCompanion(GenerationJobsCompanion data) {
    return GenerationJobRow(
      id: data.id.present ? data.id.value : this.id,
      status: data.status.present ? data.status.value : this.status,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
      provider: data.provider.present ? data.provider.value : this.provider,
      model: data.model.present ? data.model.value : this.model,
      tokensUsed: data.tokensUsed.present
          ? data.tokensUsed.value
          : this.tokensUsed,
      promptVersion: data.promptVersion.present
          ? data.promptVersion.value
          : this.promptVersion,
      errorCode: data.errorCode.present ? data.errorCode.value : this.errorCode,
      cardsCount: data.cardsCount.present
          ? data.cardsCount.value
          : this.cardsCount,
      chunkCount: data.chunkCount.present
          ? data.chunkCount.value
          : this.chunkCount,
      filesJson: data.filesJson.present ? data.filesJson.value : this.filesJson,
      resultDeckId: data.resultDeckId.present
          ? data.resultDeckId.value
          : this.resultDeckId,
    );
  }

  @override
  String toString() {
    return (StringBuffer('GenerationJobRow(')
          ..write('id: $id, ')
          ..write('status: $status, ')
          ..write('createdAt: $createdAt, ')
          ..write('provider: $provider, ')
          ..write('model: $model, ')
          ..write('tokensUsed: $tokensUsed, ')
          ..write('promptVersion: $promptVersion, ')
          ..write('errorCode: $errorCode, ')
          ..write('cardsCount: $cardsCount, ')
          ..write('chunkCount: $chunkCount, ')
          ..write('filesJson: $filesJson, ')
          ..write('resultDeckId: $resultDeckId')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(
    id,
    status,
    createdAt,
    provider,
    model,
    tokensUsed,
    promptVersion,
    errorCode,
    cardsCount,
    chunkCount,
    filesJson,
    resultDeckId,
  );
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is GenerationJobRow &&
          other.id == this.id &&
          other.status == this.status &&
          other.createdAt == this.createdAt &&
          other.provider == this.provider &&
          other.model == this.model &&
          other.tokensUsed == this.tokensUsed &&
          other.promptVersion == this.promptVersion &&
          other.errorCode == this.errorCode &&
          other.cardsCount == this.cardsCount &&
          other.chunkCount == this.chunkCount &&
          other.filesJson == this.filesJson &&
          other.resultDeckId == this.resultDeckId);
}

class GenerationJobsCompanion extends UpdateCompanion<GenerationJobRow> {
  final Value<String> id;
  final Value<String> status;
  final Value<int> createdAt;
  final Value<String?> provider;
  final Value<String?> model;
  final Value<int?> tokensUsed;
  final Value<String?> promptVersion;
  final Value<String?> errorCode;
  final Value<int?> cardsCount;
  final Value<int?> chunkCount;
  final Value<String?> filesJson;
  final Value<String?> resultDeckId;
  final Value<int> rowid;
  const GenerationJobsCompanion({
    this.id = const Value.absent(),
    this.status = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.provider = const Value.absent(),
    this.model = const Value.absent(),
    this.tokensUsed = const Value.absent(),
    this.promptVersion = const Value.absent(),
    this.errorCode = const Value.absent(),
    this.cardsCount = const Value.absent(),
    this.chunkCount = const Value.absent(),
    this.filesJson = const Value.absent(),
    this.resultDeckId = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  GenerationJobsCompanion.insert({
    required String id,
    required String status,
    required int createdAt,
    this.provider = const Value.absent(),
    this.model = const Value.absent(),
    this.tokensUsed = const Value.absent(),
    this.promptVersion = const Value.absent(),
    this.errorCode = const Value.absent(),
    this.cardsCount = const Value.absent(),
    this.chunkCount = const Value.absent(),
    this.filesJson = const Value.absent(),
    this.resultDeckId = const Value.absent(),
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       status = Value(status),
       createdAt = Value(createdAt);
  static Insertable<GenerationJobRow> custom({
    Expression<String>? id,
    Expression<String>? status,
    Expression<int>? createdAt,
    Expression<String>? provider,
    Expression<String>? model,
    Expression<int>? tokensUsed,
    Expression<String>? promptVersion,
    Expression<String>? errorCode,
    Expression<int>? cardsCount,
    Expression<int>? chunkCount,
    Expression<String>? filesJson,
    Expression<String>? resultDeckId,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (status != null) 'status': status,
      if (createdAt != null) 'created_at': createdAt,
      if (provider != null) 'provider': provider,
      if (model != null) 'model': model,
      if (tokensUsed != null) 'tokens_used': tokensUsed,
      if (promptVersion != null) 'prompt_version': promptVersion,
      if (errorCode != null) 'error_code': errorCode,
      if (cardsCount != null) 'cards_count': cardsCount,
      if (chunkCount != null) 'chunk_count': chunkCount,
      if (filesJson != null) 'files_json': filesJson,
      if (resultDeckId != null) 'result_deck_id': resultDeckId,
      if (rowid != null) 'rowid': rowid,
    });
  }

  GenerationJobsCompanion copyWith({
    Value<String>? id,
    Value<String>? status,
    Value<int>? createdAt,
    Value<String?>? provider,
    Value<String?>? model,
    Value<int?>? tokensUsed,
    Value<String?>? promptVersion,
    Value<String?>? errorCode,
    Value<int?>? cardsCount,
    Value<int?>? chunkCount,
    Value<String?>? filesJson,
    Value<String?>? resultDeckId,
    Value<int>? rowid,
  }) {
    return GenerationJobsCompanion(
      id: id ?? this.id,
      status: status ?? this.status,
      createdAt: createdAt ?? this.createdAt,
      provider: provider ?? this.provider,
      model: model ?? this.model,
      tokensUsed: tokensUsed ?? this.tokensUsed,
      promptVersion: promptVersion ?? this.promptVersion,
      errorCode: errorCode ?? this.errorCode,
      cardsCount: cardsCount ?? this.cardsCount,
      chunkCount: chunkCount ?? this.chunkCount,
      filesJson: filesJson ?? this.filesJson,
      resultDeckId: resultDeckId ?? this.resultDeckId,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (status.present) {
      map['status'] = Variable<String>(status.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (provider.present) {
      map['provider'] = Variable<String>(provider.value);
    }
    if (model.present) {
      map['model'] = Variable<String>(model.value);
    }
    if (tokensUsed.present) {
      map['tokens_used'] = Variable<int>(tokensUsed.value);
    }
    if (promptVersion.present) {
      map['prompt_version'] = Variable<String>(promptVersion.value);
    }
    if (errorCode.present) {
      map['error_code'] = Variable<String>(errorCode.value);
    }
    if (cardsCount.present) {
      map['cards_count'] = Variable<int>(cardsCount.value);
    }
    if (chunkCount.present) {
      map['chunk_count'] = Variable<int>(chunkCount.value);
    }
    if (filesJson.present) {
      map['files_json'] = Variable<String>(filesJson.value);
    }
    if (resultDeckId.present) {
      map['result_deck_id'] = Variable<String>(resultDeckId.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('GenerationJobsCompanion(')
          ..write('id: $id, ')
          ..write('status: $status, ')
          ..write('createdAt: $createdAt, ')
          ..write('provider: $provider, ')
          ..write('model: $model, ')
          ..write('tokensUsed: $tokensUsed, ')
          ..write('promptVersion: $promptVersion, ')
          ..write('errorCode: $errorCode, ')
          ..write('cardsCount: $cardsCount, ')
          ..write('chunkCount: $chunkCount, ')
          ..write('filesJson: $filesJson, ')
          ..write('resultDeckId: $resultDeckId, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $AppSettingsTable extends AppSettings
    with TableInfo<$AppSettingsTable, AppSettingRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $AppSettingsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _keyMeta = const VerificationMeta('key');
  @override
  late final GeneratedColumn<String> key = GeneratedColumn<String>(
    'key',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _valueJsonMeta = const VerificationMeta(
    'valueJson',
  );
  @override
  late final GeneratedColumn<String> valueJson = GeneratedColumn<String>(
    'value_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [key, valueJson];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'app_settings';
  @override
  VerificationContext validateIntegrity(
    Insertable<AppSettingRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('key')) {
      context.handle(
        _keyMeta,
        key.isAcceptableOrUnknown(data['key']!, _keyMeta),
      );
    } else if (isInserting) {
      context.missing(_keyMeta);
    }
    if (data.containsKey('value_json')) {
      context.handle(
        _valueJsonMeta,
        valueJson.isAcceptableOrUnknown(data['value_json']!, _valueJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_valueJsonMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {key};
  @override
  AppSettingRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return AppSettingRow(
      key: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}key'],
      )!,
      valueJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}value_json'],
      )!,
    );
  }

  @override
  $AppSettingsTable createAlias(String alias) {
    return $AppSettingsTable(attachedDatabase, alias);
  }
}

class AppSettingRow extends DataClass implements Insertable<AppSettingRow> {
  /// Ключ настройки.
  final String key;

  /// Значение, JSON.
  final String valueJson;
  const AppSettingRow({required this.key, required this.valueJson});
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['key'] = Variable<String>(key);
    map['value_json'] = Variable<String>(valueJson);
    return map;
  }

  AppSettingsCompanion toCompanion(bool nullToAbsent) {
    return AppSettingsCompanion(key: Value(key), valueJson: Value(valueJson));
  }

  factory AppSettingRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return AppSettingRow(
      key: serializer.fromJson<String>(json['key']),
      valueJson: serializer.fromJson<String>(json['valueJson']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'key': serializer.toJson<String>(key),
      'valueJson': serializer.toJson<String>(valueJson),
    };
  }

  AppSettingRow copyWith({String? key, String? valueJson}) => AppSettingRow(
    key: key ?? this.key,
    valueJson: valueJson ?? this.valueJson,
  );
  AppSettingRow copyWithCompanion(AppSettingsCompanion data) {
    return AppSettingRow(
      key: data.key.present ? data.key.value : this.key,
      valueJson: data.valueJson.present ? data.valueJson.value : this.valueJson,
    );
  }

  @override
  String toString() {
    return (StringBuffer('AppSettingRow(')
          ..write('key: $key, ')
          ..write('valueJson: $valueJson')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(key, valueJson);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is AppSettingRow &&
          other.key == this.key &&
          other.valueJson == this.valueJson);
}

class AppSettingsCompanion extends UpdateCompanion<AppSettingRow> {
  final Value<String> key;
  final Value<String> valueJson;
  final Value<int> rowid;
  const AppSettingsCompanion({
    this.key = const Value.absent(),
    this.valueJson = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  AppSettingsCompanion.insert({
    required String key,
    required String valueJson,
    this.rowid = const Value.absent(),
  }) : key = Value(key),
       valueJson = Value(valueJson);
  static Insertable<AppSettingRow> custom({
    Expression<String>? key,
    Expression<String>? valueJson,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (key != null) 'key': key,
      if (valueJson != null) 'value_json': valueJson,
      if (rowid != null) 'rowid': rowid,
    });
  }

  AppSettingsCompanion copyWith({
    Value<String>? key,
    Value<String>? valueJson,
    Value<int>? rowid,
  }) {
    return AppSettingsCompanion(
      key: key ?? this.key,
      valueJson: valueJson ?? this.valueJson,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (key.present) {
      map['key'] = Variable<String>(key.value);
    }
    if (valueJson.present) {
      map['value_json'] = Variable<String>(valueJson.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('AppSettingsCompanion(')
          ..write('key: $key, ')
          ..write('valueJson: $valueJson, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

class $SessionPresetsTable extends SessionPresets
    with TableInfo<$SessionPresetsTable, SessionPresetRow> {
  @override
  final GeneratedDatabase attachedDatabase;
  final String? _alias;
  $SessionPresetsTable(this.attachedDatabase, [this._alias]);
  static const VerificationMeta _idMeta = const VerificationMeta('id');
  @override
  late final GeneratedColumn<String> id = GeneratedColumn<String>(
    'id',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _nameMeta = const VerificationMeta('name');
  @override
  late final GeneratedColumn<String> name = GeneratedColumn<String>(
    'name',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _configJsonMeta = const VerificationMeta(
    'configJson',
  );
  @override
  late final GeneratedColumn<String> configJson = GeneratedColumn<String>(
    'config_json',
    aliasedName,
    false,
    type: DriftSqlType.string,
    requiredDuringInsert: true,
  );
  static const VerificationMeta _createdAtMeta = const VerificationMeta(
    'createdAt',
  );
  @override
  late final GeneratedColumn<int> createdAt = GeneratedColumn<int>(
    'created_at',
    aliasedName,
    false,
    type: DriftSqlType.int,
    requiredDuringInsert: true,
  );
  @override
  List<GeneratedColumn> get $columns => [id, name, configJson, createdAt];
  @override
  String get aliasedName => _alias ?? actualTableName;
  @override
  String get actualTableName => $name;
  static const String $name = 'session_presets';
  @override
  VerificationContext validateIntegrity(
    Insertable<SessionPresetRow> instance, {
    bool isInserting = false,
  }) {
    final context = VerificationContext();
    final data = instance.toColumns(true);
    if (data.containsKey('id')) {
      context.handle(_idMeta, id.isAcceptableOrUnknown(data['id']!, _idMeta));
    } else if (isInserting) {
      context.missing(_idMeta);
    }
    if (data.containsKey('name')) {
      context.handle(
        _nameMeta,
        name.isAcceptableOrUnknown(data['name']!, _nameMeta),
      );
    } else if (isInserting) {
      context.missing(_nameMeta);
    }
    if (data.containsKey('config_json')) {
      context.handle(
        _configJsonMeta,
        configJson.isAcceptableOrUnknown(data['config_json']!, _configJsonMeta),
      );
    } else if (isInserting) {
      context.missing(_configJsonMeta);
    }
    if (data.containsKey('created_at')) {
      context.handle(
        _createdAtMeta,
        createdAt.isAcceptableOrUnknown(data['created_at']!, _createdAtMeta),
      );
    } else if (isInserting) {
      context.missing(_createdAtMeta);
    }
    return context;
  }

  @override
  Set<GeneratedColumn> get $primaryKey => {id};
  @override
  SessionPresetRow map(Map<String, dynamic> data, {String? tablePrefix}) {
    final effectivePrefix = tablePrefix != null ? '$tablePrefix.' : '';
    return SessionPresetRow(
      id: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}id'],
      )!,
      name: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}name'],
      )!,
      configJson: attachedDatabase.typeMapping.read(
        DriftSqlType.string,
        data['${effectivePrefix}config_json'],
      )!,
      createdAt: attachedDatabase.typeMapping.read(
        DriftSqlType.int,
        data['${effectivePrefix}created_at'],
      )!,
    );
  }

  @override
  $SessionPresetsTable createAlias(String alias) {
    return $SessionPresetsTable(attachedDatabase, alias);
  }
}

class SessionPresetRow extends DataClass
    implements Insertable<SessionPresetRow> {
  /// Уникальный идентификатор.
  final String id;

  /// Название пресета.
  final String name;

  /// Конфигурация сессии, JSON.
  final String configJson;

  /// Момент создания (epoch ms).
  final int createdAt;
  const SessionPresetRow({
    required this.id,
    required this.name,
    required this.configJson,
    required this.createdAt,
  });
  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    map['id'] = Variable<String>(id);
    map['name'] = Variable<String>(name);
    map['config_json'] = Variable<String>(configJson);
    map['created_at'] = Variable<int>(createdAt);
    return map;
  }

  SessionPresetsCompanion toCompanion(bool nullToAbsent) {
    return SessionPresetsCompanion(
      id: Value(id),
      name: Value(name),
      configJson: Value(configJson),
      createdAt: Value(createdAt),
    );
  }

  factory SessionPresetRow.fromJson(
    Map<String, dynamic> json, {
    ValueSerializer? serializer,
  }) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return SessionPresetRow(
      id: serializer.fromJson<String>(json['id']),
      name: serializer.fromJson<String>(json['name']),
      configJson: serializer.fromJson<String>(json['configJson']),
      createdAt: serializer.fromJson<int>(json['createdAt']),
    );
  }
  @override
  Map<String, dynamic> toJson({ValueSerializer? serializer}) {
    serializer ??= driftRuntimeOptions.defaultSerializer;
    return <String, dynamic>{
      'id': serializer.toJson<String>(id),
      'name': serializer.toJson<String>(name),
      'configJson': serializer.toJson<String>(configJson),
      'createdAt': serializer.toJson<int>(createdAt),
    };
  }

  SessionPresetRow copyWith({
    String? id,
    String? name,
    String? configJson,
    int? createdAt,
  }) => SessionPresetRow(
    id: id ?? this.id,
    name: name ?? this.name,
    configJson: configJson ?? this.configJson,
    createdAt: createdAt ?? this.createdAt,
  );
  SessionPresetRow copyWithCompanion(SessionPresetsCompanion data) {
    return SessionPresetRow(
      id: data.id.present ? data.id.value : this.id,
      name: data.name.present ? data.name.value : this.name,
      configJson: data.configJson.present
          ? data.configJson.value
          : this.configJson,
      createdAt: data.createdAt.present ? data.createdAt.value : this.createdAt,
    );
  }

  @override
  String toString() {
    return (StringBuffer('SessionPresetRow(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('configJson: $configJson, ')
          ..write('createdAt: $createdAt')
          ..write(')'))
        .toString();
  }

  @override
  int get hashCode => Object.hash(id, name, configJson, createdAt);
  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      (other is SessionPresetRow &&
          other.id == this.id &&
          other.name == this.name &&
          other.configJson == this.configJson &&
          other.createdAt == this.createdAt);
}

class SessionPresetsCompanion extends UpdateCompanion<SessionPresetRow> {
  final Value<String> id;
  final Value<String> name;
  final Value<String> configJson;
  final Value<int> createdAt;
  final Value<int> rowid;
  const SessionPresetsCompanion({
    this.id = const Value.absent(),
    this.name = const Value.absent(),
    this.configJson = const Value.absent(),
    this.createdAt = const Value.absent(),
    this.rowid = const Value.absent(),
  });
  SessionPresetsCompanion.insert({
    required String id,
    required String name,
    required String configJson,
    required int createdAt,
    this.rowid = const Value.absent(),
  }) : id = Value(id),
       name = Value(name),
       configJson = Value(configJson),
       createdAt = Value(createdAt);
  static Insertable<SessionPresetRow> custom({
    Expression<String>? id,
    Expression<String>? name,
    Expression<String>? configJson,
    Expression<int>? createdAt,
    Expression<int>? rowid,
  }) {
    return RawValuesInsertable({
      if (id != null) 'id': id,
      if (name != null) 'name': name,
      if (configJson != null) 'config_json': configJson,
      if (createdAt != null) 'created_at': createdAt,
      if (rowid != null) 'rowid': rowid,
    });
  }

  SessionPresetsCompanion copyWith({
    Value<String>? id,
    Value<String>? name,
    Value<String>? configJson,
    Value<int>? createdAt,
    Value<int>? rowid,
  }) {
    return SessionPresetsCompanion(
      id: id ?? this.id,
      name: name ?? this.name,
      configJson: configJson ?? this.configJson,
      createdAt: createdAt ?? this.createdAt,
      rowid: rowid ?? this.rowid,
    );
  }

  @override
  Map<String, Expression> toColumns(bool nullToAbsent) {
    final map = <String, Expression>{};
    if (id.present) {
      map['id'] = Variable<String>(id.value);
    }
    if (name.present) {
      map['name'] = Variable<String>(name.value);
    }
    if (configJson.present) {
      map['config_json'] = Variable<String>(configJson.value);
    }
    if (createdAt.present) {
      map['created_at'] = Variable<int>(createdAt.value);
    }
    if (rowid.present) {
      map['rowid'] = Variable<int>(rowid.value);
    }
    return map;
  }

  @override
  String toString() {
    return (StringBuffer('SessionPresetsCompanion(')
          ..write('id: $id, ')
          ..write('name: $name, ')
          ..write('configJson: $configJson, ')
          ..write('createdAt: $createdAt, ')
          ..write('rowid: $rowid')
          ..write(')'))
        .toString();
  }
}

abstract class _$AppDatabase extends GeneratedDatabase {
  _$AppDatabase(QueryExecutor e) : super(e);
  $AppDatabaseManager get managers => $AppDatabaseManager(this);
  late final $DecksTable decks = $DecksTable(this);
  late final $CardsTable cards = $CardsTable(this);
  late final $ReviewLogsTable reviewLogs = $ReviewLogsTable(this);
  late final $PracticeLogsTable practiceLogs = $PracticeLogsTable(this);
  late final $MediaTable media = $MediaTable(this);
  late final $SourceDocsTable sourceDocs = $SourceDocsTable(this);
  late final $SyncMetaTable syncMeta = $SyncMetaTable(this);
  late final $GenerationJobsTable generationJobs = $GenerationJobsTable(this);
  late final $AppSettingsTable appSettings = $AppSettingsTable(this);
  late final $SessionPresetsTable sessionPresets = $SessionPresetsTable(this);
  late final Index idxCardsDeckDue = Index(
    'idx_cards_deck_due',
    'CREATE INDEX idx_cards_deck_due ON cards (deck_id, due)',
  );
  late final Index idxCardsHash = Index(
    'idx_cards_hash',
    'CREATE INDEX idx_cards_hash ON cards (deck_id, content_hash)',
  );
  late final Index idxReviewLogsCard = Index(
    'idx_review_logs_card',
    'CREATE INDEX idx_review_logs_card ON review_logs (card_id)',
  );
  @override
  Iterable<TableInfo<Table, Object?>> get allTables =>
      allSchemaEntities.whereType<TableInfo<Table, Object?>>();
  @override
  List<DatabaseSchemaEntity> get allSchemaEntities => [
    decks,
    cards,
    reviewLogs,
    practiceLogs,
    media,
    sourceDocs,
    syncMeta,
    generationJobs,
    appSettings,
    sessionPresets,
    idxCardsDeckDue,
    idxCardsHash,
    idxReviewLogsCard,
  ];
  @override
  StreamQueryUpdateRules get streamUpdateRules => const StreamQueryUpdateRules([
    WritePropagation(
      on: TableUpdateQuery.onTableName(
        'decks',
        limitUpdateKind: UpdateKind.delete,
      ),
      result: [TableUpdate('cards', kind: UpdateKind.delete)],
    ),
  ]);
}

typedef $$DecksTableCreateCompanionBuilder = DecksCompanion Function({
  required String id,
  required String name,
  Value<String> settingsJson,
  Value<int?> archivedAt,
  required int createdAt,
  required int updatedAt,
  Value<int> rowid,
});
typedef $$DecksTableUpdateCompanionBuilder = DecksCompanion Function({
  Value<String> id,
  Value<String> name,
  Value<String> settingsJson,
  Value<int?> archivedAt,
  Value<int> createdAt,
  Value<int> updatedAt,
  Value<int> rowid,
});

final class $$DecksTableReferences
    extends BaseReferences<_$AppDatabase, $DecksTable, DeckRow> {
  $$DecksTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static MultiTypedResultKey<$CardsTable, List<CardRow>> _cardsRefsTable(
    _$AppDatabase db,
  ) => MultiTypedResultKey.fromTable(
    db.cards,
    aliasName: 'decks__id__cards__deck_id',
  );

  $$CardsTableProcessedTableManager get cardsRefs {
    final manager = $$CardsTableTableManager(
      $_db,
      $_db.cards,
    ).filter((f) => f.deckId.id.sqlEquals($_itemColumn<String>('id')!));

    final cache = $_typedResult.readTableOrNull(_cardsRefsTable($_db));
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: cache),
    );
  }
}

class $$DecksTableFilterComposer extends Composer<_$AppDatabase, $DecksTable> {
  $$DecksTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get settingsJson => $composableBuilder(
    column: $table.settingsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get archivedAt => $composableBuilder(
    column: $table.archivedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  Expression<bool> cardsRefs(
    Expression<bool> Function($$CardsTableFilterComposer f) f,
  ) {
    final $$CardsTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.cards,
      getReferencedColumn: (t) => t.deckId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CardsTableFilterComposer(
            $db: $db,
            $table: $db.cards,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$DecksTableOrderingComposer
    extends Composer<_$AppDatabase, $DecksTable> {
  $$DecksTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get settingsJson => $composableBuilder(
    column: $table.settingsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get archivedAt => $composableBuilder(
    column: $table.archivedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$DecksTableAnnotationComposer
    extends Composer<_$AppDatabase, $DecksTable> {
  $$DecksTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get settingsJson => $composableBuilder(
    column: $table.settingsJson,
    builder: (column) => column,
  );

  GeneratedColumn<int> get archivedAt => $composableBuilder(
    column: $table.archivedAt,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  Expression<T> cardsRefs<T extends Object>(
    Expression<T> Function($$CardsTableAnnotationComposer a) f,
  ) {
    final $$CardsTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.id,
      referencedTable: $db.cards,
      getReferencedColumn: (t) => t.deckId,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$CardsTableAnnotationComposer(
            $db: $db,
            $table: $db.cards,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return f(composer);
  }
}

class $$DecksTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $DecksTable,
          DeckRow,
          $$DecksTableFilterComposer,
          $$DecksTableOrderingComposer,
          $$DecksTableAnnotationComposer,
          $$DecksTableCreateCompanionBuilder,
          $$DecksTableUpdateCompanionBuilder,
          (DeckRow, $$DecksTableReferences),
          DeckRow,
          PrefetchHooks Function({bool cardsRefs})
        > {
  $$DecksTableTableManager(_$AppDatabase db, $DecksTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$DecksTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$DecksTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$DecksTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> settingsJson = const Value.absent(),
                Value<int?> archivedAt = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => DecksCompanion(
                id: id,
                name: name,
                settingsJson: settingsJson,
                archivedAt: archivedAt,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                Value<String> settingsJson = const Value.absent(),
                Value<int?> archivedAt = const Value.absent(),
                required int createdAt,
                required int updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => DecksCompanion.insert(
                id: id,
                name: name,
                settingsJson: settingsJson,
                archivedAt: archivedAt,
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$DecksTable, DeckRow>(table),
                  $$DecksTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({cardsRefs = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [if (cardsRefs) db.cards],
              addJoins: null,
              getPrefetchedDataCallback: (items) async {
                return [
                  if (cardsRefs)
                    await $_getPrefetchedDataByColumns<
                      DeckRow,
                      $DecksTable,
                      CardRow,
                      $CardsTable
                    >(
                      currentTable: table,
                      referencedTable: $$DecksTableReferences._cardsRefsTable(
                        db,
                      ),
                      managerFromTypedResult: (p0) =>
                          $$DecksTableReferences(db, table, p0).cardsRefs,
                      currentColumn: 'id',
                      referencedColumn: 'deck_id',
                      typedResults: items,
                    ),
                ];
              },
            );
          },
        ),
      );
}

typedef $$DecksTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $DecksTable,
      DeckRow,
      $$DecksTableFilterComposer,
      $$DecksTableOrderingComposer,
      $$DecksTableAnnotationComposer,
      $$DecksTableCreateCompanionBuilder,
      $$DecksTableUpdateCompanionBuilder,
      (DeckRow, $$DecksTableReferences),
      DeckRow,
      PrefetchHooks Function({bool cardsRefs})
    >;
typedef $$CardsTableCreateCompanionBuilder = CardsCompanion Function({
  required String id,
  required String deckId,
  required String front,
  required String back,
  Value<String?> hint,
  required String cardType,
  Value<String> tagsJson,
  Value<String> mediaJson,
  Value<String?> latex,
  Value<String?> occlusionJson,
  Value<String?> sourceDocId,
  Value<String?> sourceExcerpt,
  required String state,
  Value<String?> fsrsJson,
  Value<int?> due,
  Value<int> suspended,
  Value<int?> buriedUntil,
  Value<int> flagged,
  Value<String?> siblingId,
  Value<String?> contentHash,
  required int createdAt,
  required int updatedAt,
  Value<int> rowid,
});
typedef $$CardsTableUpdateCompanionBuilder = CardsCompanion Function({
  Value<String> id,
  Value<String> deckId,
  Value<String> front,
  Value<String> back,
  Value<String?> hint,
  Value<String> cardType,
  Value<String> tagsJson,
  Value<String> mediaJson,
  Value<String?> latex,
  Value<String?> occlusionJson,
  Value<String?> sourceDocId,
  Value<String?> sourceExcerpt,
  Value<String> state,
  Value<String?> fsrsJson,
  Value<int?> due,
  Value<int> suspended,
  Value<int?> buriedUntil,
  Value<int> flagged,
  Value<String?> siblingId,
  Value<String?> contentHash,
  Value<int> createdAt,
  Value<int> updatedAt,
  Value<int> rowid,
});

final class $$CardsTableReferences
    extends BaseReferences<_$AppDatabase, $CardsTable, CardRow> {
  $$CardsTableReferences(super.$_db, super.$_table, super.$_typedResult);

  static $DecksTable _deckIdTable(_$AppDatabase db) =>
      db.decks.createAlias('cards__deck_id__decks__id');

  $$DecksTableProcessedTableManager get deckId {
    final $_column = $_itemColumn<String>('deck_id')!;

    final manager = $$DecksTableTableManager(
      $_db,
      $_db.decks,
    ).filter((f) => f.id.sqlEquals($_column));
    final item = $_typedResult.readTableOrNull(_deckIdTable($_db));
    if (item == null) return manager;
    return ProcessedTableManager(
      manager.$state.copyWith(prefetchedData: [item]),
    );
  }
}

class $$CardsTableFilterComposer extends Composer<_$AppDatabase, $CardsTable> {
  $$CardsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get front => $composableBuilder(
    column: $table.front,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get back => $composableBuilder(
    column: $table.back,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get hint => $composableBuilder(
    column: $table.hint,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cardType => $composableBuilder(
    column: $table.cardType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get tagsJson => $composableBuilder(
    column: $table.tagsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mediaJson => $composableBuilder(
    column: $table.mediaJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get latex => $composableBuilder(
    column: $table.latex,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get occlusionJson => $composableBuilder(
    column: $table.occlusionJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceDocId => $composableBuilder(
    column: $table.sourceDocId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get sourceExcerpt => $composableBuilder(
    column: $table.sourceExcerpt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get fsrsJson => $composableBuilder(
    column: $table.fsrsJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get due => $composableBuilder(
    column: $table.due,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get suspended => $composableBuilder(
    column: $table.suspended,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get buriedUntil => $composableBuilder(
    column: $table.buriedUntil,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get flagged => $composableBuilder(
    column: $table.flagged,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get siblingId => $composableBuilder(
    column: $table.siblingId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get contentHash => $composableBuilder(
    column: $table.contentHash,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnFilters(column),
  );

  $$DecksTableFilterComposer get deckId {
    final $$DecksTableFilterComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.deckId,
      referencedTable: $db.decks,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DecksTableFilterComposer(
            $db: $db,
            $table: $db.decks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CardsTableOrderingComposer
    extends Composer<_$AppDatabase, $CardsTable> {
  $$CardsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get front => $composableBuilder(
    column: $table.front,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get back => $composableBuilder(
    column: $table.back,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get hint => $composableBuilder(
    column: $table.hint,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cardType => $composableBuilder(
    column: $table.cardType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get tagsJson => $composableBuilder(
    column: $table.tagsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mediaJson => $composableBuilder(
    column: $table.mediaJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get latex => $composableBuilder(
    column: $table.latex,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get occlusionJson => $composableBuilder(
    column: $table.occlusionJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceDocId => $composableBuilder(
    column: $table.sourceDocId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get sourceExcerpt => $composableBuilder(
    column: $table.sourceExcerpt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get state => $composableBuilder(
    column: $table.state,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get fsrsJson => $composableBuilder(
    column: $table.fsrsJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get due => $composableBuilder(
    column: $table.due,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get suspended => $composableBuilder(
    column: $table.suspended,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get buriedUntil => $composableBuilder(
    column: $table.buriedUntil,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get flagged => $composableBuilder(
    column: $table.flagged,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get siblingId => $composableBuilder(
    column: $table.siblingId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get contentHash => $composableBuilder(
    column: $table.contentHash,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get updatedAt => $composableBuilder(
    column: $table.updatedAt,
    builder: (column) => ColumnOrderings(column),
  );

  $$DecksTableOrderingComposer get deckId {
    final $$DecksTableOrderingComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.deckId,
      referencedTable: $db.decks,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DecksTableOrderingComposer(
            $db: $db,
            $table: $db.decks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CardsTableAnnotationComposer
    extends Composer<_$AppDatabase, $CardsTable> {
  $$CardsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get front =>
      $composableBuilder(column: $table.front, builder: (column) => column);

  GeneratedColumn<String> get back =>
      $composableBuilder(column: $table.back, builder: (column) => column);

  GeneratedColumn<String> get hint =>
      $composableBuilder(column: $table.hint, builder: (column) => column);

  GeneratedColumn<String> get cardType =>
      $composableBuilder(column: $table.cardType, builder: (column) => column);

  GeneratedColumn<String> get tagsJson =>
      $composableBuilder(column: $table.tagsJson, builder: (column) => column);

  GeneratedColumn<String> get mediaJson =>
      $composableBuilder(column: $table.mediaJson, builder: (column) => column);

  GeneratedColumn<String> get latex =>
      $composableBuilder(column: $table.latex, builder: (column) => column);

  GeneratedColumn<String> get occlusionJson => $composableBuilder(
    column: $table.occlusionJson,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sourceDocId => $composableBuilder(
    column: $table.sourceDocId,
    builder: (column) => column,
  );

  GeneratedColumn<String> get sourceExcerpt => $composableBuilder(
    column: $table.sourceExcerpt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get state =>
      $composableBuilder(column: $table.state, builder: (column) => column);

  GeneratedColumn<String> get fsrsJson =>
      $composableBuilder(column: $table.fsrsJson, builder: (column) => column);

  GeneratedColumn<int> get due =>
      $composableBuilder(column: $table.due, builder: (column) => column);

  GeneratedColumn<int> get suspended =>
      $composableBuilder(column: $table.suspended, builder: (column) => column);

  GeneratedColumn<int> get buriedUntil => $composableBuilder(
    column: $table.buriedUntil,
    builder: (column) => column,
  );

  GeneratedColumn<int> get flagged =>
      $composableBuilder(column: $table.flagged, builder: (column) => column);

  GeneratedColumn<String> get siblingId =>
      $composableBuilder(column: $table.siblingId, builder: (column) => column);

  GeneratedColumn<String> get contentHash => $composableBuilder(
    column: $table.contentHash,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<int> get updatedAt =>
      $composableBuilder(column: $table.updatedAt, builder: (column) => column);

  $$DecksTableAnnotationComposer get deckId {
    final $$DecksTableAnnotationComposer composer = $composerBuilder(
      composer: this,
      getCurrentColumn: (t) => t.deckId,
      referencedTable: $db.decks,
      getReferencedColumn: (t) => t.id,
      builder:
          (
            joinBuilder, {
            $addJoinBuilderToRootComposer,
            $removeJoinBuilderFromRootComposer,
          }) => $$DecksTableAnnotationComposer(
            $db: $db,
            $table: $db.decks,
            $addJoinBuilderToRootComposer: $addJoinBuilderToRootComposer,
            joinBuilder: joinBuilder,
            $removeJoinBuilderFromRootComposer:
                $removeJoinBuilderFromRootComposer,
          ),
    );
    return composer;
  }
}

class $$CardsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $CardsTable,
          CardRow,
          $$CardsTableFilterComposer,
          $$CardsTableOrderingComposer,
          $$CardsTableAnnotationComposer,
          $$CardsTableCreateCompanionBuilder,
          $$CardsTableUpdateCompanionBuilder,
          (CardRow, $$CardsTableReferences),
          CardRow,
          PrefetchHooks Function({bool deckId})
        > {
  $$CardsTableTableManager(_$AppDatabase db, $CardsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$CardsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$CardsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$CardsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> deckId = const Value.absent(),
                Value<String> front = const Value.absent(),
                Value<String> back = const Value.absent(),
                Value<String?> hint = const Value.absent(),
                Value<String> cardType = const Value.absent(),
                Value<String> tagsJson = const Value.absent(),
                Value<String> mediaJson = const Value.absent(),
                Value<String?> latex = const Value.absent(),
                Value<String?> occlusionJson = const Value.absent(),
                Value<String?> sourceDocId = const Value.absent(),
                Value<String?> sourceExcerpt = const Value.absent(),
                Value<String> state = const Value.absent(),
                Value<String?> fsrsJson = const Value.absent(),
                Value<int?> due = const Value.absent(),
                Value<int> suspended = const Value.absent(),
                Value<int?> buriedUntil = const Value.absent(),
                Value<int> flagged = const Value.absent(),
                Value<String?> siblingId = const Value.absent(),
                Value<String?> contentHash = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> updatedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => CardsCompanion(
                id: id,
                deckId: deckId,
                front: front,
                back: back,
                hint: hint,
                cardType: cardType,
                tagsJson: tagsJson,
                mediaJson: mediaJson,
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
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String deckId,
                required String front,
                required String back,
                Value<String?> hint = const Value.absent(),
                required String cardType,
                Value<String> tagsJson = const Value.absent(),
                Value<String> mediaJson = const Value.absent(),
                Value<String?> latex = const Value.absent(),
                Value<String?> occlusionJson = const Value.absent(),
                Value<String?> sourceDocId = const Value.absent(),
                Value<String?> sourceExcerpt = const Value.absent(),
                required String state,
                Value<String?> fsrsJson = const Value.absent(),
                Value<int?> due = const Value.absent(),
                Value<int> suspended = const Value.absent(),
                Value<int?> buriedUntil = const Value.absent(),
                Value<int> flagged = const Value.absent(),
                Value<String?> siblingId = const Value.absent(),
                Value<String?> contentHash = const Value.absent(),
                required int createdAt,
                required int updatedAt,
                Value<int> rowid = const Value.absent(),
              }) => CardsCompanion.insert(
                id: id,
                deckId: deckId,
                front: front,
                back: back,
                hint: hint,
                cardType: cardType,
                tagsJson: tagsJson,
                mediaJson: mediaJson,
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
                createdAt: createdAt,
                updatedAt: updatedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$CardsTable, CardRow>(table),
                  $$CardsTableReferences(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: ({deckId = false}) {
            return PrefetchHooks(
              db: db,
              explicitlyWatchedTables: [],
              addJoins:
                  <
                    T extends TableManagerState<
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic,
                      dynamic
                    >
                  >(state) {
                    if (deckId) {
                      state = state.withJoin(
                        currentTable: table,
                        currentColumn: table.deckId,
                        referencedTable: $$CardsTableReferences._deckIdTable(
                          db,
                        ),
                        referencedColumn: $$CardsTableReferences
                            ._deckIdTable(db)
                            .id,
                      ) as T;
                    }

                    return state;
                  },
              getPrefetchedDataCallback: (items) async {
                return [];
              },
            );
          },
        ),
      );
}

typedef $$CardsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $CardsTable,
      CardRow,
      $$CardsTableFilterComposer,
      $$CardsTableOrderingComposer,
      $$CardsTableAnnotationComposer,
      $$CardsTableCreateCompanionBuilder,
      $$CardsTableUpdateCompanionBuilder,
      (CardRow, $$CardsTableReferences),
      CardRow,
      PrefetchHooks Function({bool deckId})
    >;
typedef $$ReviewLogsTableCreateCompanionBuilder = ReviewLogsCompanion Function({
  required String id,
  required String cardId,
  required int rating,
  required int reviewedAt,
  required String mode,
  Value<int> recognitionFlag,
  Value<double?> scheduledDays,
  Value<double?> actualDays,
  Value<int?> elapsedMs,
  Value<int> rowid,
});
typedef $$ReviewLogsTableUpdateCompanionBuilder = ReviewLogsCompanion Function({
  Value<String> id,
  Value<String> cardId,
  Value<int> rating,
  Value<int> reviewedAt,
  Value<String> mode,
  Value<int> recognitionFlag,
  Value<double?> scheduledDays,
  Value<double?> actualDays,
  Value<int?> elapsedMs,
  Value<int> rowid,
});

class $$ReviewLogsTableFilterComposer
    extends Composer<_$AppDatabase, $ReviewLogsTable> {
  $$ReviewLogsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cardId => $composableBuilder(
    column: $table.cardId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get rating => $composableBuilder(
    column: $table.rating,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get reviewedAt => $composableBuilder(
    column: $table.reviewedAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mode => $composableBuilder(
    column: $table.mode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get recognitionFlag => $composableBuilder(
    column: $table.recognitionFlag,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get scheduledDays => $composableBuilder(
    column: $table.scheduledDays,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<double> get actualDays => $composableBuilder(
    column: $table.actualDays,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get elapsedMs => $composableBuilder(
    column: $table.elapsedMs,
    builder: (column) => ColumnFilters(column),
  );
}

class $$ReviewLogsTableOrderingComposer
    extends Composer<_$AppDatabase, $ReviewLogsTable> {
  $$ReviewLogsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cardId => $composableBuilder(
    column: $table.cardId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get rating => $composableBuilder(
    column: $table.rating,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get reviewedAt => $composableBuilder(
    column: $table.reviewedAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mode => $composableBuilder(
    column: $table.mode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get recognitionFlag => $composableBuilder(
    column: $table.recognitionFlag,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get scheduledDays => $composableBuilder(
    column: $table.scheduledDays,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<double> get actualDays => $composableBuilder(
    column: $table.actualDays,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get elapsedMs => $composableBuilder(
    column: $table.elapsedMs,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$ReviewLogsTableAnnotationComposer
    extends Composer<_$AppDatabase, $ReviewLogsTable> {
  $$ReviewLogsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get cardId =>
      $composableBuilder(column: $table.cardId, builder: (column) => column);

  GeneratedColumn<int> get rating =>
      $composableBuilder(column: $table.rating, builder: (column) => column);

  GeneratedColumn<int> get reviewedAt => $composableBuilder(
    column: $table.reviewedAt,
    builder: (column) => column,
  );

  GeneratedColumn<String> get mode =>
      $composableBuilder(column: $table.mode, builder: (column) => column);

  GeneratedColumn<int> get recognitionFlag => $composableBuilder(
    column: $table.recognitionFlag,
    builder: (column) => column,
  );

  GeneratedColumn<double> get scheduledDays => $composableBuilder(
    column: $table.scheduledDays,
    builder: (column) => column,
  );

  GeneratedColumn<double> get actualDays => $composableBuilder(
    column: $table.actualDays,
    builder: (column) => column,
  );

  GeneratedColumn<int> get elapsedMs =>
      $composableBuilder(column: $table.elapsedMs, builder: (column) => column);
}

class $$ReviewLogsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $ReviewLogsTable,
          ReviewLogRow,
          $$ReviewLogsTableFilterComposer,
          $$ReviewLogsTableOrderingComposer,
          $$ReviewLogsTableAnnotationComposer,
          $$ReviewLogsTableCreateCompanionBuilder,
          $$ReviewLogsTableUpdateCompanionBuilder,
          (
            ReviewLogRow,
            BaseReferences<_$AppDatabase, $ReviewLogsTable, ReviewLogRow>,
          ),
          ReviewLogRow,
          PrefetchHooks Function()
        > {
  $$ReviewLogsTableTableManager(_$AppDatabase db, $ReviewLogsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$ReviewLogsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$ReviewLogsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$ReviewLogsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> cardId = const Value.absent(),
                Value<int> rating = const Value.absent(),
                Value<int> reviewedAt = const Value.absent(),
                Value<String> mode = const Value.absent(),
                Value<int> recognitionFlag = const Value.absent(),
                Value<double?> scheduledDays = const Value.absent(),
                Value<double?> actualDays = const Value.absent(),
                Value<int?> elapsedMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ReviewLogsCompanion(
                id: id,
                cardId: cardId,
                rating: rating,
                reviewedAt: reviewedAt,
                mode: mode,
                recognitionFlag: recognitionFlag,
                scheduledDays: scheduledDays,
                actualDays: actualDays,
                elapsedMs: elapsedMs,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String cardId,
                required int rating,
                required int reviewedAt,
                required String mode,
                Value<int> recognitionFlag = const Value.absent(),
                Value<double?> scheduledDays = const Value.absent(),
                Value<double?> actualDays = const Value.absent(),
                Value<int?> elapsedMs = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => ReviewLogsCompanion.insert(
                id: id,
                cardId: cardId,
                rating: rating,
                reviewedAt: reviewedAt,
                mode: mode,
                recognitionFlag: recognitionFlag,
                scheduledDays: scheduledDays,
                actualDays: actualDays,
                elapsedMs: elapsedMs,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$ReviewLogsTable, ReviewLogRow>(table),
                  BaseReferences<_$AppDatabase, $ReviewLogsTable, ReviewLogRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$ReviewLogsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $ReviewLogsTable,
      ReviewLogRow,
      $$ReviewLogsTableFilterComposer,
      $$ReviewLogsTableOrderingComposer,
      $$ReviewLogsTableAnnotationComposer,
      $$ReviewLogsTableCreateCompanionBuilder,
      $$ReviewLogsTableUpdateCompanionBuilder,
      (
        ReviewLogRow,
        BaseReferences<_$AppDatabase, $ReviewLogsTable, ReviewLogRow>,
      ),
      ReviewLogRow,
      PrefetchHooks Function()
    >;
typedef $$PracticeLogsTableCreateCompanionBuilder =
    PracticeLogsCompanion Function({
      required String id,
      required String cardId,
      required String mode,
      required int reviewedAt,
      Value<int> rowid,
    });
typedef $$PracticeLogsTableUpdateCompanionBuilder =
    PracticeLogsCompanion Function({
      Value<String> id,
      Value<String> cardId,
      Value<String> mode,
      Value<int> reviewedAt,
      Value<int> rowid,
    });

class $$PracticeLogsTableFilterComposer
    extends Composer<_$AppDatabase, $PracticeLogsTable> {
  $$PracticeLogsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cardId => $composableBuilder(
    column: $table.cardId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mode => $composableBuilder(
    column: $table.mode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get reviewedAt => $composableBuilder(
    column: $table.reviewedAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$PracticeLogsTableOrderingComposer
    extends Composer<_$AppDatabase, $PracticeLogsTable> {
  $$PracticeLogsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cardId => $composableBuilder(
    column: $table.cardId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mode => $composableBuilder(
    column: $table.mode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get reviewedAt => $composableBuilder(
    column: $table.reviewedAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$PracticeLogsTableAnnotationComposer
    extends Composer<_$AppDatabase, $PracticeLogsTable> {
  $$PracticeLogsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get cardId =>
      $composableBuilder(column: $table.cardId, builder: (column) => column);

  GeneratedColumn<String> get mode =>
      $composableBuilder(column: $table.mode, builder: (column) => column);

  GeneratedColumn<int> get reviewedAt => $composableBuilder(
    column: $table.reviewedAt,
    builder: (column) => column,
  );
}

class $$PracticeLogsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $PracticeLogsTable,
          PracticeLogRow,
          $$PracticeLogsTableFilterComposer,
          $$PracticeLogsTableOrderingComposer,
          $$PracticeLogsTableAnnotationComposer,
          $$PracticeLogsTableCreateCompanionBuilder,
          $$PracticeLogsTableUpdateCompanionBuilder,
          (
            PracticeLogRow,
            BaseReferences<_$AppDatabase, $PracticeLogsTable, PracticeLogRow>,
          ),
          PracticeLogRow,
          PrefetchHooks Function()
        > {
  $$PracticeLogsTableTableManager(_$AppDatabase db, $PracticeLogsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$PracticeLogsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$PracticeLogsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$PracticeLogsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> cardId = const Value.absent(),
                Value<String> mode = const Value.absent(),
                Value<int> reviewedAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => PracticeLogsCompanion(
                id: id,
                cardId: cardId,
                mode: mode,
                reviewedAt: reviewedAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String cardId,
                required String mode,
                required int reviewedAt,
                Value<int> rowid = const Value.absent(),
              }) => PracticeLogsCompanion.insert(
                id: id,
                cardId: cardId,
                mode: mode,
                reviewedAt: reviewedAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$PracticeLogsTable, PracticeLogRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $PracticeLogsTable,
                    PracticeLogRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$PracticeLogsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $PracticeLogsTable,
      PracticeLogRow,
      $$PracticeLogsTableFilterComposer,
      $$PracticeLogsTableOrderingComposer,
      $$PracticeLogsTableAnnotationComposer,
      $$PracticeLogsTableCreateCompanionBuilder,
      $$PracticeLogsTableUpdateCompanionBuilder,
      (
        PracticeLogRow,
        BaseReferences<_$AppDatabase, $PracticeLogsTable, PracticeLogRow>,
      ),
      PracticeLogRow,
      PrefetchHooks Function()
    >;
typedef $$MediaTableCreateCompanionBuilder = MediaCompanion Function({
  required String id,
  required String cardId,
  required String path,
  required String mimeType,
  required int size,
  Value<int> rowid,
});
typedef $$MediaTableUpdateCompanionBuilder = MediaCompanion Function({
  Value<String> id,
  Value<String> cardId,
  Value<String> path,
  Value<String> mimeType,
  Value<int> size,
  Value<int> rowid,
});

class $$MediaTableFilterComposer extends Composer<_$AppDatabase, $MediaTable> {
  $$MediaTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get cardId => $composableBuilder(
    column: $table.cardId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get mimeType => $composableBuilder(
    column: $table.mimeType,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get size => $composableBuilder(
    column: $table.size,
    builder: (column) => ColumnFilters(column),
  );
}

class $$MediaTableOrderingComposer
    extends Composer<_$AppDatabase, $MediaTable> {
  $$MediaTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get cardId => $composableBuilder(
    column: $table.cardId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get mimeType => $composableBuilder(
    column: $table.mimeType,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get size => $composableBuilder(
    column: $table.size,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$MediaTableAnnotationComposer
    extends Composer<_$AppDatabase, $MediaTable> {
  $$MediaTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get cardId =>
      $composableBuilder(column: $table.cardId, builder: (column) => column);

  GeneratedColumn<String> get path =>
      $composableBuilder(column: $table.path, builder: (column) => column);

  GeneratedColumn<String> get mimeType =>
      $composableBuilder(column: $table.mimeType, builder: (column) => column);

  GeneratedColumn<int> get size =>
      $composableBuilder(column: $table.size, builder: (column) => column);
}

class $$MediaTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $MediaTable,
          MediaRow,
          $$MediaTableFilterComposer,
          $$MediaTableOrderingComposer,
          $$MediaTableAnnotationComposer,
          $$MediaTableCreateCompanionBuilder,
          $$MediaTableUpdateCompanionBuilder,
          (MediaRow, BaseReferences<_$AppDatabase, $MediaTable, MediaRow>),
          MediaRow,
          PrefetchHooks Function()
        > {
  $$MediaTableTableManager(_$AppDatabase db, $MediaTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$MediaTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$MediaTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$MediaTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> cardId = const Value.absent(),
                Value<String> path = const Value.absent(),
                Value<String> mimeType = const Value.absent(),
                Value<int> size = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => MediaCompanion(
                id: id,
                cardId: cardId,
                path: path,
                mimeType: mimeType,
                size: size,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String cardId,
                required String path,
                required String mimeType,
                required int size,
                Value<int> rowid = const Value.absent(),
              }) => MediaCompanion.insert(
                id: id,
                cardId: cardId,
                path: path,
                mimeType: mimeType,
                size: size,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$MediaTable, MediaRow>(table),
                  BaseReferences<_$AppDatabase, $MediaTable, MediaRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$MediaTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $MediaTable,
      MediaRow,
      $$MediaTableFilterComposer,
      $$MediaTableOrderingComposer,
      $$MediaTableAnnotationComposer,
      $$MediaTableCreateCompanionBuilder,
      $$MediaTableUpdateCompanionBuilder,
      (MediaRow, BaseReferences<_$AppDatabase, $MediaTable, MediaRow>),
      MediaRow,
      PrefetchHooks Function()
    >;
typedef $$SourceDocsTableCreateCompanionBuilder = SourceDocsCompanion Function({
  required String id,
  required String deckId,
  required String path,
  required String title,
  Value<int> rowid,
});
typedef $$SourceDocsTableUpdateCompanionBuilder = SourceDocsCompanion Function({
  Value<String> id,
  Value<String> deckId,
  Value<String> path,
  Value<String> title,
  Value<int> rowid,
});

class $$SourceDocsTableFilterComposer
    extends Composer<_$AppDatabase, $SourceDocsTable> {
  $$SourceDocsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get deckId => $composableBuilder(
    column: $table.deckId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SourceDocsTableOrderingComposer
    extends Composer<_$AppDatabase, $SourceDocsTable> {
  $$SourceDocsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get deckId => $composableBuilder(
    column: $table.deckId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get path => $composableBuilder(
    column: $table.path,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get title => $composableBuilder(
    column: $table.title,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SourceDocsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SourceDocsTable> {
  $$SourceDocsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get deckId =>
      $composableBuilder(column: $table.deckId, builder: (column) => column);

  GeneratedColumn<String> get path =>
      $composableBuilder(column: $table.path, builder: (column) => column);

  GeneratedColumn<String> get title =>
      $composableBuilder(column: $table.title, builder: (column) => column);
}

class $$SourceDocsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SourceDocsTable,
          SourceDocRow,
          $$SourceDocsTableFilterComposer,
          $$SourceDocsTableOrderingComposer,
          $$SourceDocsTableAnnotationComposer,
          $$SourceDocsTableCreateCompanionBuilder,
          $$SourceDocsTableUpdateCompanionBuilder,
          (
            SourceDocRow,
            BaseReferences<_$AppDatabase, $SourceDocsTable, SourceDocRow>,
          ),
          SourceDocRow,
          PrefetchHooks Function()
        > {
  $$SourceDocsTableTableManager(_$AppDatabase db, $SourceDocsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SourceDocsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SourceDocsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SourceDocsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> deckId = const Value.absent(),
                Value<String> path = const Value.absent(),
                Value<String> title = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SourceDocsCompanion(
                id: id,
                deckId: deckId,
                path: path,
                title: title,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String deckId,
                required String path,
                required String title,
                Value<int> rowid = const Value.absent(),
              }) => SourceDocsCompanion.insert(
                id: id,
                deckId: deckId,
                path: path,
                title: title,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SourceDocsTable, SourceDocRow>(table),
                  BaseReferences<_$AppDatabase, $SourceDocsTable, SourceDocRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SourceDocsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SourceDocsTable,
      SourceDocRow,
      $$SourceDocsTableFilterComposer,
      $$SourceDocsTableOrderingComposer,
      $$SourceDocsTableAnnotationComposer,
      $$SourceDocsTableCreateCompanionBuilder,
      $$SourceDocsTableUpdateCompanionBuilder,
      (
        SourceDocRow,
        BaseReferences<_$AppDatabase, $SourceDocsTable, SourceDocRow>,
      ),
      SourceDocRow,
      PrefetchHooks Function()
    >;
typedef $$SyncMetaTableCreateCompanionBuilder = SyncMetaCompanion Function({
  Value<String?> deviceId,
  Value<String?> lastSyncHlc,
  Value<int> rowid,
});
typedef $$SyncMetaTableUpdateCompanionBuilder = SyncMetaCompanion Function({
  Value<String?> deviceId,
  Value<String?> lastSyncHlc,
  Value<int> rowid,
});

class $$SyncMetaTableFilterComposer
    extends Composer<_$AppDatabase, $SyncMetaTable> {
  $$SyncMetaTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get lastSyncHlc => $composableBuilder(
    column: $table.lastSyncHlc,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SyncMetaTableOrderingComposer
    extends Composer<_$AppDatabase, $SyncMetaTable> {
  $$SyncMetaTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get deviceId => $composableBuilder(
    column: $table.deviceId,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get lastSyncHlc => $composableBuilder(
    column: $table.lastSyncHlc,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SyncMetaTableAnnotationComposer
    extends Composer<_$AppDatabase, $SyncMetaTable> {
  $$SyncMetaTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get deviceId =>
      $composableBuilder(column: $table.deviceId, builder: (column) => column);

  GeneratedColumn<String> get lastSyncHlc => $composableBuilder(
    column: $table.lastSyncHlc,
    builder: (column) => column,
  );
}

class $$SyncMetaTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SyncMetaTable,
          SyncMetaRow,
          $$SyncMetaTableFilterComposer,
          $$SyncMetaTableOrderingComposer,
          $$SyncMetaTableAnnotationComposer,
          $$SyncMetaTableCreateCompanionBuilder,
          $$SyncMetaTableUpdateCompanionBuilder,
          (
            SyncMetaRow,
            BaseReferences<_$AppDatabase, $SyncMetaTable, SyncMetaRow>,
          ),
          SyncMetaRow,
          PrefetchHooks Function()
        > {
  $$SyncMetaTableTableManager(_$AppDatabase db, $SyncMetaTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SyncMetaTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SyncMetaTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SyncMetaTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String?> deviceId = const Value.absent(),
                Value<String?> lastSyncHlc = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncMetaCompanion(
                deviceId: deviceId,
                lastSyncHlc: lastSyncHlc,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                Value<String?> deviceId = const Value.absent(),
                Value<String?> lastSyncHlc = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SyncMetaCompanion.insert(
                deviceId: deviceId,
                lastSyncHlc: lastSyncHlc,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SyncMetaTable, SyncMetaRow>(table),
                  BaseReferences<_$AppDatabase, $SyncMetaTable, SyncMetaRow>(
                    db,
                    table,
                    e,
                  ),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SyncMetaTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SyncMetaTable,
      SyncMetaRow,
      $$SyncMetaTableFilterComposer,
      $$SyncMetaTableOrderingComposer,
      $$SyncMetaTableAnnotationComposer,
      $$SyncMetaTableCreateCompanionBuilder,
      $$SyncMetaTableUpdateCompanionBuilder,
      (SyncMetaRow, BaseReferences<_$AppDatabase, $SyncMetaTable, SyncMetaRow>),
      SyncMetaRow,
      PrefetchHooks Function()
    >;
typedef $$GenerationJobsTableCreateCompanionBuilder =
    GenerationJobsCompanion Function({
      required String id,
      required String status,
      required int createdAt,
      Value<String?> provider,
      Value<String?> model,
      Value<int?> tokensUsed,
      Value<String?> promptVersion,
      Value<String?> errorCode,
      Value<int?> cardsCount,
      Value<int?> chunkCount,
      Value<String?> filesJson,
      Value<String?> resultDeckId,
      Value<int> rowid,
    });
typedef $$GenerationJobsTableUpdateCompanionBuilder =
    GenerationJobsCompanion Function({
      Value<String> id,
      Value<String> status,
      Value<int> createdAt,
      Value<String?> provider,
      Value<String?> model,
      Value<int?> tokensUsed,
      Value<String?> promptVersion,
      Value<String?> errorCode,
      Value<int?> cardsCount,
      Value<int?> chunkCount,
      Value<String?> filesJson,
      Value<String?> resultDeckId,
      Value<int> rowid,
    });

class $$GenerationJobsTableFilterComposer
    extends Composer<_$AppDatabase, $GenerationJobsTable> {
  $$GenerationJobsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get provider => $composableBuilder(
    column: $table.provider,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get model => $composableBuilder(
    column: $table.model,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get tokensUsed => $composableBuilder(
    column: $table.tokensUsed,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get promptVersion => $composableBuilder(
    column: $table.promptVersion,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get errorCode => $composableBuilder(
    column: $table.errorCode,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get cardsCount => $composableBuilder(
    column: $table.cardsCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get chunkCount => $composableBuilder(
    column: $table.chunkCount,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get filesJson => $composableBuilder(
    column: $table.filesJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get resultDeckId => $composableBuilder(
    column: $table.resultDeckId,
    builder: (column) => ColumnFilters(column),
  );
}

class $$GenerationJobsTableOrderingComposer
    extends Composer<_$AppDatabase, $GenerationJobsTable> {
  $$GenerationJobsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get status => $composableBuilder(
    column: $table.status,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get provider => $composableBuilder(
    column: $table.provider,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get model => $composableBuilder(
    column: $table.model,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get tokensUsed => $composableBuilder(
    column: $table.tokensUsed,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get promptVersion => $composableBuilder(
    column: $table.promptVersion,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get errorCode => $composableBuilder(
    column: $table.errorCode,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get cardsCount => $composableBuilder(
    column: $table.cardsCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get chunkCount => $composableBuilder(
    column: $table.chunkCount,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get filesJson => $composableBuilder(
    column: $table.filesJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get resultDeckId => $composableBuilder(
    column: $table.resultDeckId,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$GenerationJobsTableAnnotationComposer
    extends Composer<_$AppDatabase, $GenerationJobsTable> {
  $$GenerationJobsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get status =>
      $composableBuilder(column: $table.status, builder: (column) => column);

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);

  GeneratedColumn<String> get provider =>
      $composableBuilder(column: $table.provider, builder: (column) => column);

  GeneratedColumn<String> get model =>
      $composableBuilder(column: $table.model, builder: (column) => column);

  GeneratedColumn<int> get tokensUsed => $composableBuilder(
    column: $table.tokensUsed,
    builder: (column) => column,
  );

  GeneratedColumn<String> get promptVersion => $composableBuilder(
    column: $table.promptVersion,
    builder: (column) => column,
  );

  GeneratedColumn<String> get errorCode =>
      $composableBuilder(column: $table.errorCode, builder: (column) => column);

  GeneratedColumn<int> get cardsCount => $composableBuilder(
    column: $table.cardsCount,
    builder: (column) => column,
  );

  GeneratedColumn<int> get chunkCount => $composableBuilder(
    column: $table.chunkCount,
    builder: (column) => column,
  );

  GeneratedColumn<String> get filesJson =>
      $composableBuilder(column: $table.filesJson, builder: (column) => column);

  GeneratedColumn<String> get resultDeckId => $composableBuilder(
    column: $table.resultDeckId,
    builder: (column) => column,
  );
}

class $$GenerationJobsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $GenerationJobsTable,
          GenerationJobRow,
          $$GenerationJobsTableFilterComposer,
          $$GenerationJobsTableOrderingComposer,
          $$GenerationJobsTableAnnotationComposer,
          $$GenerationJobsTableCreateCompanionBuilder,
          $$GenerationJobsTableUpdateCompanionBuilder,
          (
            GenerationJobRow,
            BaseReferences<
              _$AppDatabase,
              $GenerationJobsTable,
              GenerationJobRow
            >,
          ),
          GenerationJobRow,
          PrefetchHooks Function()
        > {
  $$GenerationJobsTableTableManager(
    _$AppDatabase db,
    $GenerationJobsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$GenerationJobsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$GenerationJobsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$GenerationJobsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> status = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<String?> provider = const Value.absent(),
                Value<String?> model = const Value.absent(),
                Value<int?> tokensUsed = const Value.absent(),
                Value<String?> promptVersion = const Value.absent(),
                Value<String?> errorCode = const Value.absent(),
                Value<int?> cardsCount = const Value.absent(),
                Value<int?> chunkCount = const Value.absent(),
                Value<String?> filesJson = const Value.absent(),
                Value<String?> resultDeckId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => GenerationJobsCompanion(
                id: id,
                status: status,
                createdAt: createdAt,
                provider: provider,
                model: model,
                tokensUsed: tokensUsed,
                promptVersion: promptVersion,
                errorCode: errorCode,
                cardsCount: cardsCount,
                chunkCount: chunkCount,
                filesJson: filesJson,
                resultDeckId: resultDeckId,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String status,
                required int createdAt,
                Value<String?> provider = const Value.absent(),
                Value<String?> model = const Value.absent(),
                Value<int?> tokensUsed = const Value.absent(),
                Value<String?> promptVersion = const Value.absent(),
                Value<String?> errorCode = const Value.absent(),
                Value<int?> cardsCount = const Value.absent(),
                Value<int?> chunkCount = const Value.absent(),
                Value<String?> filesJson = const Value.absent(),
                Value<String?> resultDeckId = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => GenerationJobsCompanion.insert(
                id: id,
                status: status,
                createdAt: createdAt,
                provider: provider,
                model: model,
                tokensUsed: tokensUsed,
                promptVersion: promptVersion,
                errorCode: errorCode,
                cardsCount: cardsCount,
                chunkCount: chunkCount,
                filesJson: filesJson,
                resultDeckId: resultDeckId,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$GenerationJobsTable, GenerationJobRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $GenerationJobsTable,
                    GenerationJobRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$GenerationJobsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $GenerationJobsTable,
      GenerationJobRow,
      $$GenerationJobsTableFilterComposer,
      $$GenerationJobsTableOrderingComposer,
      $$GenerationJobsTableAnnotationComposer,
      $$GenerationJobsTableCreateCompanionBuilder,
      $$GenerationJobsTableUpdateCompanionBuilder,
      (
        GenerationJobRow,
        BaseReferences<_$AppDatabase, $GenerationJobsTable, GenerationJobRow>,
      ),
      GenerationJobRow,
      PrefetchHooks Function()
    >;
typedef $$AppSettingsTableCreateCompanionBuilder =
    AppSettingsCompanion Function({
      required String key,
      required String valueJson,
      Value<int> rowid,
    });
typedef $$AppSettingsTableUpdateCompanionBuilder =
    AppSettingsCompanion Function({
      Value<String> key,
      Value<String> valueJson,
      Value<int> rowid,
    });

class $$AppSettingsTableFilterComposer
    extends Composer<_$AppDatabase, $AppSettingsTable> {
  $$AppSettingsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get valueJson => $composableBuilder(
    column: $table.valueJson,
    builder: (column) => ColumnFilters(column),
  );
}

class $$AppSettingsTableOrderingComposer
    extends Composer<_$AppDatabase, $AppSettingsTable> {
  $$AppSettingsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get key => $composableBuilder(
    column: $table.key,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get valueJson => $composableBuilder(
    column: $table.valueJson,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$AppSettingsTableAnnotationComposer
    extends Composer<_$AppDatabase, $AppSettingsTable> {
  $$AppSettingsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get key =>
      $composableBuilder(column: $table.key, builder: (column) => column);

  GeneratedColumn<String> get valueJson =>
      $composableBuilder(column: $table.valueJson, builder: (column) => column);
}

class $$AppSettingsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $AppSettingsTable,
          AppSettingRow,
          $$AppSettingsTableFilterComposer,
          $$AppSettingsTableOrderingComposer,
          $$AppSettingsTableAnnotationComposer,
          $$AppSettingsTableCreateCompanionBuilder,
          $$AppSettingsTableUpdateCompanionBuilder,
          (
            AppSettingRow,
            BaseReferences<_$AppDatabase, $AppSettingsTable, AppSettingRow>,
          ),
          AppSettingRow,
          PrefetchHooks Function()
        > {
  $$AppSettingsTableTableManager(_$AppDatabase db, $AppSettingsTable table)
    : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$AppSettingsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$AppSettingsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$AppSettingsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> key = const Value.absent(),
                Value<String> valueJson = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => AppSettingsCompanion(
                key: key,
                valueJson: valueJson,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String key,
                required String valueJson,
                Value<int> rowid = const Value.absent(),
              }) => AppSettingsCompanion.insert(
                key: key,
                valueJson: valueJson,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$AppSettingsTable, AppSettingRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $AppSettingsTable,
                    AppSettingRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$AppSettingsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $AppSettingsTable,
      AppSettingRow,
      $$AppSettingsTableFilterComposer,
      $$AppSettingsTableOrderingComposer,
      $$AppSettingsTableAnnotationComposer,
      $$AppSettingsTableCreateCompanionBuilder,
      $$AppSettingsTableUpdateCompanionBuilder,
      (
        AppSettingRow,
        BaseReferences<_$AppDatabase, $AppSettingsTable, AppSettingRow>,
      ),
      AppSettingRow,
      PrefetchHooks Function()
    >;
typedef $$SessionPresetsTableCreateCompanionBuilder =
    SessionPresetsCompanion Function({
      required String id,
      required String name,
      required String configJson,
      required int createdAt,
      Value<int> rowid,
    });
typedef $$SessionPresetsTableUpdateCompanionBuilder =
    SessionPresetsCompanion Function({
      Value<String> id,
      Value<String> name,
      Value<String> configJson,
      Value<int> createdAt,
      Value<int> rowid,
    });

class $$SessionPresetsTableFilterComposer
    extends Composer<_$AppDatabase, $SessionPresetsTable> {
  $$SessionPresetsTableFilterComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnFilters<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<String> get configJson => $composableBuilder(
    column: $table.configJson,
    builder: (column) => ColumnFilters(column),
  );

  ColumnFilters<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnFilters(column),
  );
}

class $$SessionPresetsTableOrderingComposer
    extends Composer<_$AppDatabase, $SessionPresetsTable> {
  $$SessionPresetsTableOrderingComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  ColumnOrderings<String> get id => $composableBuilder(
    column: $table.id,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get name => $composableBuilder(
    column: $table.name,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<String> get configJson => $composableBuilder(
    column: $table.configJson,
    builder: (column) => ColumnOrderings(column),
  );

  ColumnOrderings<int> get createdAt => $composableBuilder(
    column: $table.createdAt,
    builder: (column) => ColumnOrderings(column),
  );
}

class $$SessionPresetsTableAnnotationComposer
    extends Composer<_$AppDatabase, $SessionPresetsTable> {
  $$SessionPresetsTableAnnotationComposer({
    required super.$db,
    required super.$table,
    super.joinBuilder,
    super.$addJoinBuilderToRootComposer,
    super.$removeJoinBuilderFromRootComposer,
  });
  GeneratedColumn<String> get id =>
      $composableBuilder(column: $table.id, builder: (column) => column);

  GeneratedColumn<String> get name =>
      $composableBuilder(column: $table.name, builder: (column) => column);

  GeneratedColumn<String> get configJson => $composableBuilder(
    column: $table.configJson,
    builder: (column) => column,
  );

  GeneratedColumn<int> get createdAt =>
      $composableBuilder(column: $table.createdAt, builder: (column) => column);
}

class $$SessionPresetsTableTableManager
    extends
        RootTableManager<
          _$AppDatabase,
          $SessionPresetsTable,
          SessionPresetRow,
          $$SessionPresetsTableFilterComposer,
          $$SessionPresetsTableOrderingComposer,
          $$SessionPresetsTableAnnotationComposer,
          $$SessionPresetsTableCreateCompanionBuilder,
          $$SessionPresetsTableUpdateCompanionBuilder,
          (
            SessionPresetRow,
            BaseReferences<
              _$AppDatabase,
              $SessionPresetsTable,
              SessionPresetRow
            >,
          ),
          SessionPresetRow,
          PrefetchHooks Function()
        > {
  $$SessionPresetsTableTableManager(
    _$AppDatabase db,
    $SessionPresetsTable table,
  ) : super(
        TableManagerState(
          db: db,
          table: table,
          createFilteringComposer: () =>
              $$SessionPresetsTableFilterComposer($db: db, $table: table),
          createOrderingComposer: () =>
              $$SessionPresetsTableOrderingComposer($db: db, $table: table),
          createComputedFieldComposer: () =>
              $$SessionPresetsTableAnnotationComposer($db: db, $table: table),
          updateCompanionCallback:
              ({
                Value<String> id = const Value.absent(),
                Value<String> name = const Value.absent(),
                Value<String> configJson = const Value.absent(),
                Value<int> createdAt = const Value.absent(),
                Value<int> rowid = const Value.absent(),
              }) => SessionPresetsCompanion(
                id: id,
                name: name,
                configJson: configJson,
                createdAt: createdAt,
                rowid: rowid,
              ),
          createCompanionCallback:
              ({
                required String id,
                required String name,
                required String configJson,
                required int createdAt,
                Value<int> rowid = const Value.absent(),
              }) => SessionPresetsCompanion.insert(
                id: id,
                name: name,
                configJson: configJson,
                createdAt: createdAt,
                rowid: rowid,
              ),
          withReferenceMapper: (p0) => p0
              .map(
                (e) => (
                  e.readTable<$SessionPresetsTable, SessionPresetRow>(table),
                  BaseReferences<
                    _$AppDatabase,
                    $SessionPresetsTable,
                    SessionPresetRow
                  >(db, table, e),
                ),
              )
              .toList(),
          prefetchHooksCallback: null,
        ),
      );
}

typedef $$SessionPresetsTableProcessedTableManager =
    ProcessedTableManager<
      _$AppDatabase,
      $SessionPresetsTable,
      SessionPresetRow,
      $$SessionPresetsTableFilterComposer,
      $$SessionPresetsTableOrderingComposer,
      $$SessionPresetsTableAnnotationComposer,
      $$SessionPresetsTableCreateCompanionBuilder,
      $$SessionPresetsTableUpdateCompanionBuilder,
      (
        SessionPresetRow,
        BaseReferences<_$AppDatabase, $SessionPresetsTable, SessionPresetRow>,
      ),
      SessionPresetRow,
      PrefetchHooks Function()
    >;

class $AppDatabaseManager {
  final _$AppDatabase _db;
  $AppDatabaseManager(this._db);
  $$DecksTableTableManager get decks =>
      $$DecksTableTableManager(_db, _db.decks);
  $$CardsTableTableManager get cards =>
      $$CardsTableTableManager(_db, _db.cards);
  $$ReviewLogsTableTableManager get reviewLogs =>
      $$ReviewLogsTableTableManager(_db, _db.reviewLogs);
  $$PracticeLogsTableTableManager get practiceLogs =>
      $$PracticeLogsTableTableManager(_db, _db.practiceLogs);
  $$MediaTableTableManager get media =>
      $$MediaTableTableManager(_db, _db.media);
  $$SourceDocsTableTableManager get sourceDocs =>
      $$SourceDocsTableTableManager(_db, _db.sourceDocs);
  $$SyncMetaTableTableManager get syncMeta =>
      $$SyncMetaTableTableManager(_db, _db.syncMeta);
  $$GenerationJobsTableTableManager get generationJobs =>
      $$GenerationJobsTableTableManager(_db, _db.generationJobs);
  $$AppSettingsTableTableManager get appSettings =>
      $$AppSettingsTableTableManager(_db, _db.appSettings);
  $$SessionPresetsTableTableManager get sessionPresets =>
      $$SessionPresetsTableTableManager(_db, _db.sessionPresets);
}
