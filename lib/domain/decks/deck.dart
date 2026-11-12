import 'package:collection/collection.dart';

/// Колода (SPEC A5) — набор карточек с настройками планировщика.
///
/// Доменная модель без зависимостей от Flutter/БД (`AGENTS.md`): репозитории
/// маппят строки БД в этот тип.
class Deck {
  /// Создаёт колоду.
  const Deck({
    required this.id,
    required this.name,
    required this.settings,
    required this.createdAt,
    required this.updatedAt,
    this.archivedAt,
  });

  /// Уникальный идентификатор (`TEXT PRIMARY KEY`).
  final String id;

  /// Отображаемое имя колоды.
  final String name;

  /// Настройки планировщика (`settings_json`; пустой объект по умолчанию).
  final Map<String, Object?> settings;

  /// Момент создания.
  final DateTime createdAt;

  /// Момент последнего изменения.
  final DateTime updatedAt;

  /// Момент архивации; `null` — колода активна.
  final DateTime? archivedAt;

  /// Признак архивной колоды (скрыта из основного списка).
  bool get isArchived => archivedAt != null;

  static const Object _unset = Object();

  /// Копия с заменой полей; для `archivedAt` используйте явный `null`.
  Deck copyWith({
    String? id,
    String? name,
    Map<String, Object?>? settings,
    DateTime? createdAt,
    DateTime? updatedAt,
    Object? archivedAt = _unset,
  }) {
    return Deck(
      id: id ?? this.id,
      name: name ?? this.name,
      settings: settings ?? this.settings,
      createdAt: createdAt ?? this.createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
      archivedAt: identical(archivedAt, _unset)
          ? this.archivedAt
          : archivedAt as DateTime?,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is Deck &&
        other.id == id &&
        other.name == name &&
        other.createdAt == createdAt &&
        other.updatedAt == updatedAt &&
        other.archivedAt == archivedAt &&
        const DeepCollectionEquality().equals(other.settings, settings);
  }

  @override
  int get hashCode => Object.hash(
    id,
    name,
    createdAt,
    updatedAt,
    archivedAt,
    const DeepCollectionEquality().hash(settings),
  );

  @override
  String toString() =>
      'Deck(id: $id, name: $name, archived: ${archivedAt != null})';
}
