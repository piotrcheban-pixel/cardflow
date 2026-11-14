import 'package:cardflow/domain/session/leech_repository.dart';
import 'package:cardflow/domain/session/session_config.dart';
import 'package:cardflow/domain/session/session_preset.dart';
import 'package:cardflow/domain/session/session_preset_repository.dart';

/// Фейковые реализации портов конструктора сессии (TEST A6.7, ADR-018).

/// In-memory пресеты: журнал сохранений/удалений и настраиваемые ошибки.
class FakeSessionPresetRepository implements SessionPresetRepository {
  /// Создаёт фейк с готовыми пресетами.
  FakeSessionPresetRepository({
    List<SessionPreset> presets = const <SessionPreset>[],
  }) : _presets = <SessionPreset>[...presets];

  final List<SessionPreset> _presets;
  int _counter = 0;

  /// Ошибка `presets()`.
  Object? presetsError;

  /// Ошибка `savePreset()`.
  Object? saveError;

  /// Ошибка `deletePreset()`.
  Object? deleteError;

  /// Имена сохранённых пресетов в порядке вызовов.
  final List<String> savedNames = <String>[];

  /// Конфиги сохранённых пресетов в порядке вызовов.
  final List<SessionConfig> savedConfigs = <SessionConfig>[];

  /// Id удалённых пресетов в порядке вызовов.
  final List<String> deletedIds = <String>[];

  /// Сколько раз запрашивали список.
  int presetsCalls = 0;

  /// Текущие пресеты.
  List<SessionPreset> get all => List<SessionPreset>.unmodifiable(_presets);

  @override
  Future<List<SessionPreset>> presets() async {
    presetsCalls++;
    if (presetsError != null) throw presetsError!;
    return List<SessionPreset>.unmodifiable(_presets);
  }

  @override
  Future<SessionPreset> savePreset({
    required String name,
    required SessionConfig config,
    required DateTime createdAt,
  }) async {
    if (saveError != null) throw saveError!;
    savedNames.add(name);
    savedConfigs.add(config);
    final SessionPreset preset = SessionPreset(
      id: 'preset-${++_counter}',
      name: name,
      config: config,
      createdAt: createdAt,
    );
    _presets.add(preset);
    return preset;
  }

  @override
  Future<void> deletePreset(String presetId) async {
    if (deleteError != null) throw deleteError!;
    deletedIds.add(presetId);
    _presets.removeWhere((SessionPreset preset) => preset.id == presetId);
  }
}

/// Фейковые счётчики провалов: карта id → число провалов.
class FakeLeechRepository implements LeechRepository {
  /// Создаёт фейк с заданными счётчиками.
  FakeLeechRepository({this.counts = const <String, int>{}});

  /// Счётчики провалов.
  Map<String, int> counts;

  /// Ошибка `failureCounts()`.
  Object? error;

  /// Колоды, запрошенные в `failureCounts` (в порядке вызовов).
  final List<List<String>> requestedDecks = <List<String>>[];

  @override
  Future<Map<String, int>> failureCounts({
    required Iterable<String> deckIds,
  }) async {
    requestedDecks.add(deckIds.toList(growable: false));
    if (error != null) throw error!;
    return Map<String, int>.of(counts);
  }
}
