/// Пресет конструктора сессии (SPEC A5 `session_presets`, A6.7, ADR-018).
library;

import 'package:cardflow/domain/session/session_config.dart';

/// Сохранённый набор параметров сессии.
class SessionPreset {
  /// Создаёт пресет.
  const SessionPreset({
    required this.id,
    required this.name,
    required this.config,
    required this.createdAt,
  });

  /// Идентификатор строки `session_presets.id`.
  final String id;

  /// Имя пресета.
  final String name;

  /// Параметры сессии.
  final SessionConfig config;

  /// Момент создания.
  final DateTime createdAt;

  @override
  bool operator ==(Object other) =>
      other is SessionPreset &&
      other.id == id &&
      other.name == name &&
      other.config == config &&
      other.createdAt == createdAt;

  @override
  int get hashCode => Object.hash(id, name, config, createdAt);

  @override
  String toString() => 'SessionPreset($id: $name)';
}
