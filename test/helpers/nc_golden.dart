import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'nc_harness.dart';

/// Golden-тесты компонентов Nocturne (тег `golden`, REDESIGN-SPEC §8).
///
/// Каждый компонент снимается в 8 вариантах: dark/light × обычный/high-contrast
/// × textScale 1,0/2,0. Шрифты Onest/Literata/JetBrainsMono и MaterialIcons
/// подкладываются явно (AGENTS.md: golden с кириллицей), иначе CI-машина
/// рисует текст системным шрифтом и снимок нестабилен.

/// Каталог эталонов (путь относительно `test/golden/<файл>_test.dart`:
/// `matchesGoldenFile` разрешает относительный путь от каталога теста).
const String ncGoldenFolder = 'goldens';

/// Один вариант golden-снимка.
@immutable
class NcGoldenVariant {
  /// Создаёт вариант.
  const NcGoldenVariant({
    required this.id,
    required this.brightness,
    this.highContrast = false,
    this.textScale = 1,
  });

  /// Суффикс имени файла.
  final String id;

  /// Тема.
  final Brightness brightness;

  /// Повышенный контраст.
  final bool highContrast;

  /// Масштаб текста.
  final double textScale;

  /// Конфигурация стенда для варианта.
  NcTestConfig config(Size size) => NcTestConfig(
    brightness: brightness,
    highContrast: highContrast,
    textScale: textScale,
    size: size,
    reduceMotion: true,
  );
}

/// Восемь обязательных вариантов (§8): тема × контраст × textScale.
const List<NcGoldenVariant> ncGoldenVariants = <NcGoldenVariant>[
  NcGoldenVariant(id: 'dark', brightness: Brightness.dark),
  NcGoldenVariant(
    id: 'dark_hc',
    brightness: Brightness.dark,
    highContrast: true,
  ),
  NcGoldenVariant(id: 'light', brightness: Brightness.light),
  NcGoldenVariant(
    id: 'light_hc',
    brightness: Brightness.light,
    highContrast: true,
  ),
  NcGoldenVariant(id: 'dark_ts2', brightness: Brightness.dark, textScale: 2),
  NcGoldenVariant(
    id: 'dark_hc_ts2',
    brightness: Brightness.dark,
    highContrast: true,
    textScale: 2,
  ),
  NcGoldenVariant(id: 'light_ts2', brightness: Brightness.light, textScale: 2),
  NcGoldenVariant(
    id: 'light_hc_ts2',
    brightness: Brightness.light,
    highContrast: true,
    textScale: 2,
  ),
];

/// Загружает реальные шрифты Nocturne и MaterialIcons для golden-снимков.
Future<void> loadNcFonts() async {
  const Map<String, String> families = <String, String>{
    'Onest': 'assets/fonts/Onest/Onest-Variable.ttf',
    'Literata': 'assets/fonts/Literata/Literata-Variable.ttf',
    'JetBrainsMono': 'assets/fonts/JetBrainsMono/JetBrainsMono-Variable.ttf',
    'OpenDyslexic': 'assets/fonts/OpenDyslexic-Regular.otf',
  };
  for (final MapEntry<String, String> entry in families.entries) {
    final File file = File(entry.value);
    if (!file.existsSync()) continue;
    final FontLoader loader = FontLoader(entry.key);
    loader.addFont(
      Future<ByteData>.value(ByteData.sublistView(file.readAsBytesSync())),
    );
    await loader.load();
  }
  final File? icons = _materialIconsFile();
  if (icons != null) {
    final FontLoader iconLoader = FontLoader('MaterialIcons');
    iconLoader.addFont(
      Future<ByteData>.value(ByteData.sublistView(icons.readAsBytesSync())),
    );
    await iconLoader.load();
  }
}

/// Ищет `materialicons-regular.otf` в кэше Flutter (несколько кандидатов).
File? _materialIconsFile() {
  final List<String> roots = <String>[
    if (Platform.environment['FLUTTER_ROOT'] != null)
      Platform.environment['FLUTTER_ROOT']!,
    // flutter_tester лежит в <flutter>/bin/cache/artifacts/engine/<os>/.
    File(Platform.resolvedExecutable).parent.parent.parent.parent.path,
  ];
  for (final String root in roots) {
    final File file = File(
      '$root${Platform.pathSeparator}bin${Platform.pathSeparator}cache'
      '${Platform.pathSeparator}artifacts${Platform.pathSeparator}'
      'material_fonts${Platform.pathSeparator}materialicons-regular.otf',
    );
    if (file.existsSync()) return file;
  }
  return null;
}

/// Монтирует [child] в варианте [variant] и сравнивает с эталоном [name].
///
/// [settle] = false — для компонентов с повторяющейся анимацией
/// (`NcSpinner`, `NcSkeleton`, пульс): снимок делается на фиксированном
/// кадре после `pump(Duration)`, `pumpAndSettle` там зависает (§6.4).
Future<void> expectNcGolden(
  WidgetTester tester, {
  required String name,
  required NcGoldenVariant variant,
  required Widget child,
  Size size = const Size(420, 200),
  bool settle = true,
  Duration frame = const Duration(milliseconds: 300),
}) async {
  await pumpNc(tester, child, config: variant.config(size));
  if (settle) {
    await tester.pumpAndSettle();
  } else {
    await tester.pump(frame);
  }
  await expectLater(
    find.byType(MaterialApp),
    matchesGoldenFile('$ncGoldenFolder/${name}_${variant.id}.png'),
  );
}

/// Объявляет группу из 8 golden-тестов для одного компонента.
///
/// [builder] получает вариант — размеры при `textScale` 2,0 обычно больше.
void ncGoldenGroup(
  String name,
  Widget Function(NcGoldenVariant variant) builder, {
  Size Function(NcGoldenVariant variant)? size,
  bool settle = true,
  Duration frame = const Duration(milliseconds: 300),
}) {
  group(name, () {
    for (final NcGoldenVariant variant in ncGoldenVariants) {
      testWidgets('$name ${variant.id}', (WidgetTester tester) async {
        await expectNcGolden(
          tester,
          name: 'nc_$name',
          variant: variant,
          child: builder(variant),
          size: size?.call(variant) ?? const Size(420, 200),
          settle: settle,
          frame: frame,
        );
      });
    }
  });
}
