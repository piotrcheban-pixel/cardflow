import 'dart:io';

import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show Override;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'data/db/app_database.dart';
import 'data/db/database_opener.dart';
import 'data/transfer/media_store.dart';
import 'ui/app.dart';
import 'ui/state/app_providers.dart';

/// Точка входа CardFlow.
///
/// Открывает файловую БД (ADR-005) и медиа-хранилище, передаёт их в граф
/// провайдеров через `ProviderScope.overrides`, затем запускает приложение.
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  final baseDirectory = await getApplicationSupportDirectory();
  final AppDatabase database = await openAppDatabase(
    baseDirectory: baseDirectory,
  );
  final mediaStore = MediaStore(
    Directory(p.join(baseDirectory.path, appDataDirectoryName, 'media')),
  );

  runApp(
    ProviderScope(
      overrides: <Override>[
        appDatabaseProvider.overrideWithValue(database),
        mediaStoreProvider.overrideWithValue(mediaStore),
      ],
      child: const CardFlowApp(),
    ),
  );
}
