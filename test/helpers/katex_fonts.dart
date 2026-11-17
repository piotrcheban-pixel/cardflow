import 'dart:io';

import 'package:flutter/services.dart';

/// Шрифты KaTeX из `flutter_math_fork` для golden-снимков и скриншотов.
///
/// `flutter_test` не загружает шрифты пакетов сам: без этого формулы в
/// снимках рисуются квадратами Ahem (L91). Семейства объявлены в pubspec
/// пакета (`KaTeX_Main`, `KaTeX_Math`, `KaTeX_Size1..4`, …); в рендере они
/// с префиксом пакета.
Future<void> loadKatexFonts() async {
  final Directory hosted = _pubHosted();
  if (!hosted.existsSync()) return;
  final Directory? package = hosted
      .listSync()
      .whereType<Directory>()
      .where(
        (Directory entry) => entry.path
            .split(Platform.pathSeparator)
            .last
            .startsWith('flutter_math_fork-'),
      )
      .firstOrNull;
  if (package == null) return;
  final Directory fonts = Directory('${package.path}\\lib\\katex_fonts\\fonts');
  if (!fonts.existsSync()) return;

  final Map<String, File> preferred = <String, File>{};
  for (final FileSystemEntity entry in fonts.listSync()) {
    if (entry is! File || !entry.path.endsWith('.ttf')) continue;
    final String name = entry.path.split(Platform.pathSeparator).last;
    final String family = name.substring(0, name.indexOf('-'));
    final bool isRegular = name.contains('Regular');
    final bool isItalic = name.contains('Italic');
    final int rank = isRegular ? 0 : (isItalic ? 1 : 2);
    final File? current = preferred[family];
    if (current == null) {
      preferred[family] = entry;
      continue;
    }
    final String currentName = current.path.split(Platform.pathSeparator).last;
    final int currentRank = currentName.contains('Regular')
        ? 0
        : (currentName.contains('Italic') ? 1 : 2);
    if (rank < currentRank) preferred[family] = entry;
  }

  for (final MapEntry<String, File> entry in preferred.entries) {
    final FontLoader loader = FontLoader(
      'packages/flutter_math_fork/${entry.key}',
    );
    loader.addFont(
      Future<ByteData>.value(
        ByteData.sublistView(await entry.value.readAsBytes()),
      ),
    );
    await loader.load();
  }
}

Directory _pubHosted() {
  final String? localAppData = Platform.environment['LOCALAPPDATA'];
  final String? pubCache = Platform.environment['PUB_CACHE'];
  return Directory(
    '${pubCache ?? '$localAppData\\Pub\\Cache'}\\hosted\\pub.dev',
  );
}
