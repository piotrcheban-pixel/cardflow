import 'package:cardflow/domain/settings/app_settings.dart';
import 'package:cardflow/domain/settings/app_settings_store.dart';
import 'package:cardflow/domain/statistics/statistics.dart';
import 'package:cardflow/domain/statistics/statistics_repository.dart';
import 'package:cardflow/ui/settings/external_link_launcher.dart';

/// In-memory store настроек приложения для widget-тестов (без drift).
class FakeAppSettingsStore implements AppSettingsStore {
  /// Создаёт store с настройками [settings] (по умолчанию — дефолты).
  FakeAppSettingsStore({AppSettings? settings})
    : settings = settings ?? AppSettings.defaults;

  /// Текущие настройки.
  AppSettings settings;

  /// Сколько раз настройки записывались.
  int writeCount = 0;

  /// Если `true`, запись бросает исключение (проверка ошибки сохранения).
  bool failWrites = false;

  /// Если задано — запись бросает именно это исключение (ADR-047).
  Object? writeError;

  @override
  Future<AppSettings> read() async => settings;

  @override
  Future<void> write(AppSettings settings) async {
    final Object? failure = writeError;
    if (failure != null) throw failure;
    if (failWrites) {
      throw StateError('Запись настроек недоступна (тест)');
    }
    this.settings = settings;
    writeCount++;
  }
}

/// In-memory статистика для widget-тестов.
class FakeStatisticsRepository implements StatisticsRepository {
  /// Создаёт репозиторий со снимком [snapshot].
  FakeStatisticsRepository({StatisticsSnapshot? snapshot, this.tokens = 0})
    : snapshot = snapshot ?? emptyStatisticsSnapshot();

  /// Снимок, который вернёт [load].
  StatisticsSnapshot snapshot;

  /// Сумма токенов за неделю.
  int tokens;

  /// Если задано — [load] бросает это исключение.
  Object? error;

  @override
  Future<StatisticsSnapshot> load({required DateTime now}) async {
    final Object? failure = error;
    if (failure != null) throw failure;
    return snapshot;
  }

  @override
  Future<int> tokensUsedSince(DateTime since) async => tokens;
}

/// Пустой снимок статистики на текущий момент.
StatisticsSnapshot emptyStatisticsSnapshot({DateTime? now}) {
  return StatisticsCalculator.build(
    reviews: const <ReviewSample>[],
    tagsByCard: const <String, List<String>>{},
    dueDates: const <DateTime>[],
    now: now ?? DateTime.now(),
  );
}

/// Фейковый запуск внешних ссылок (без браузера и плагина).
class FakeExternalLinkLauncher implements ExternalLinkLauncher {
  /// Последний открытый адрес.
  Uri? lastUri;

  /// Результат [open].
  bool result = true;

  @override
  Future<bool> open(Uri uri) async {
    lastUri = uri;
    return result;
  }
}
