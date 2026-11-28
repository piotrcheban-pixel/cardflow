import 'dart:async';
import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'data/cards/media_garbage_collector.dart';
import 'data/cards/placeholder_media_purger.dart';
import 'data/db/app_database.dart';
import 'data/db/database_opener.dart';
import 'data/transfer/media_store.dart';
import 'ui/app.dart';
import 'ui/state/app_providers.dart';

/// Точка входа CardFlow.
///
/// Открывает файловую БД (ADR-005) и медиа-хранилище, передаёт их в граф
/// провайдеров через `ProviderScope.overrides`, затем запускает приложение.
///
/// Если инициализация упала (несовместимый файл БД, нет прав, fail-fast
/// миграции по ADR-005) — показывается экран ошибки с сообщением из ARB,
/// без сырых исключений (SPEC A8.6). Повреждённый файл БД приложение не теряет:
/// он откладывается рядом (`cardflow.sqlite.corrupted_<дата>`), а запуск
/// продолжается с новой базой (ADR-057); об этом сообщает уведомление.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final AppDatabase database;
  final MediaStore mediaStore;
  final String? recoveredFileName;
  try {
    final Directory baseDirectory = await getApplicationSupportDirectory();
    final OpenedDatabase opened = await openAppDatabaseWithRecovery(
      baseDirectory: baseDirectory,
    );
    database = opened.database;
    recoveredFileName = opened.corruptedFile?.path;
    // Корень медиа-хранилища — каталог данных приложения: относительные пути
    // медиа имеют вид `media/<id>.<ext>` (ADR-006), без двойного вложения.
    mediaStore = MediaStore(
      Directory(p.join(baseDirectory.path, appDataDirectoryName)),
    );
  } on Object catch (error, stackTrace) {
    // В release — только тип сбоя (ни путей, ни данных пользователя); полный
    // текст и стек доступны в debug-сборке для диагностики.
    debugPrint('CardFlow: база данных не открыта (${error.runtimeType})');
    assert(() {
      debugPrint('$error\n$stackTrace');
      return true;
    }());
    runApp(StartupErrorApp(accessDenied: isDatabaseAccessFailure(error)));
    return;
  }

  final ProviderContainer container = ProviderContainer(
    overrides: <Override>[
      appDatabaseProvider.overrideWithValue(database),
      mediaStoreProvider.overrideWithValue(mediaStore),
    ],
  );

  // Итерация 7.19 (ADR-041): существующие нарисованные заглушки удаляются до
  // первого кадра, чтобы UI не показывал их как иллюстрации. Ошибка пуржа не
  // должна блокировать запуск — GC ниже доберёт сирот.
  try {
    await PlaceholderMediaPurger(database, mediaStore).purge();
  } on Object {
    // Пурж повторяется при следующем запуске.
  }

  unawaited(
    MediaGarbageCollector(database, mediaStore).collect().catchError((_) => 0),
  );

  runApp(
    UncontrolledProviderScope(
      container: container,
      child: CardFlowApp(recoveredDatabaseFileName: recoveredFileName),
    ),
  );
}
