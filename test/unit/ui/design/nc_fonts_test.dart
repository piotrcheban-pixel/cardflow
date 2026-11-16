import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import 'package:cardflow/ui/design/font_licenses.dart';

import '../../../guards/guard_utils.dart';

/// Шрифты Nocturne: ассеты, лицензии и кириллица (REDESIGN-SPEC §2.1).
///
/// Метод проверки кириллицы — **растровое сравнение** символа с `.notdef`
/// (`U+E000`): сравнение ширин негодно (у JetBrains Mono моноширинные глифы
/// имеют одинаковый advance, у Literata бывают совпадения с `.notdef`).
/// Спайк 1.0: `journal/redesign-1/spikes.md` §S4.
const Map<String, String> fontAssets = <String, String>{
  'Onest': 'assets/fonts/Onest/Onest-Variable.ttf',
  'Literata': 'assets/fonts/Literata/Literata-Variable.ttf',
  'JetBrainsMono': 'assets/fonts/JetBrainsMono/JetBrainsMono-Variable.ttf',
};

/// Символы, которыми заполнен русский интерфейс (включая ё/Ё, кавычки, тире,
/// №, многоточие, цифры, латиницу и «моно»-символы счётчиков).
const String requiredGlyphs =
    'АБВГДЕЁЖЗИЙКЛМНОПРСТУФХЦЧШЩЪЫЬЭЮЯ'
    'абвгдеёжзийклмнопрстуфхцчшщъыьэюя'
    '«»„“”–—№…0123456789'
    'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz'
    '%‰°₽\$€·•→←≈≠≤≥±×÷';

Future<void> _loadFamily(String family, String assetPath) async {
  final ByteData data = await rootBundle.load(assetPath);
  final FontLoader loader = FontLoader(family)
    ..addFont(Future<ByteData>.value(data));
  await loader.load();
}

/// Растеризует один символ и возвращает RGBA-байты.
Future<List<int>> _raster(String char, {required String family}) async {
  const Size size = Size(160, 160);
  final ui.PictureRecorder recorder = ui.PictureRecorder();
  final Canvas canvas = Canvas(recorder);
  final TextPainter painter = TextPainter(
    text: TextSpan(
      text: char,
      style: TextStyle(
        fontFamily: family,
        fontSize: 96,
        color: const Color(0xFFFFFFFF),
      ),
    ),
    textDirection: TextDirection.ltr,
  )..layout();
  painter.paint(canvas, Offset.zero);
  painter.dispose();
  final ui.Picture picture = recorder.endRecording();
  final ui.Image image = await picture.toImage(
    size.width.toInt(),
    size.height.toInt(),
  );
  final ByteData? bytes = await image.toByteData(
    format: ui.ImageByteFormat.rawRgba,
  );
  picture.dispose();
  image.dispose();
  return bytes!.buffer.asUint8List().toList(growable: false);
}

bool _sameRaster(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('nc_fonts: ассеты и pubspec', () {
    test('шрифты объявлены в pubspec с существующими файлами', () {
      final String pubspec = readRepoFile('pubspec.yaml');
      for (final MapEntry<String, String> font in fontAssets.entries) {
        expect(
          pubspec,
          contains('family: ${font.key}'),
          reason: 'В pubspec.yaml нет семейства ${font.key}',
        );
        expect(
          pubspec,
          contains(font.value),
          reason: 'В pubspec.yaml нет ассета ${font.value}',
        );
        final File file = repoFile(font.value);
        expect(file.existsSync(), isTrue, reason: 'Нет файла ${font.value}');
        expect(
          file.lengthSync(),
          greaterThan(100 * 1024),
          reason: 'Файл ${font.value} подозрительно мал',
        );
      }
    });

    test('шрифт дислексии остаётся (ADR-019)', () {
      expect(readRepoFile('pubspec.yaml'), contains('OpenDyslexic'));
      expect(
        repoFile('assets/fonts/OpenDyslexic-Regular.otf').existsSync(),
        isTrue,
      );
    });

    test(
      'лицензии OFL на месте и зарегистрированы в LicenseRegistry',
      () async {
        for (final MapEntry<String, String> entry in ncFontLicenses.entries) {
          final File license = repoFile(entry.value);
          expect(license.existsSync(), isTrue, reason: 'Нет ${entry.value}');
          expect(
            license.readAsStringSync(),
            contains('SIL Open Font License'),
            reason: '${entry.value} не OFL',
          );
        }

        registerNcFontLicenses();
        final List<LicenseEntry> entries = await LicenseRegistry.licenses
            .toList();
        final Set<String> packages = entries
            .expand((entry) => entry.packages)
            .toSet();
        for (final String family in ncFontLicenses.keys) {
          expect(
            packages,
            contains(family),
            reason: 'Лицензия $family не зарегистрирована',
          );
        }
      },
    );
  });

  group('nc_fonts: кириллица без tofu', () {
    setUpAll(() async {
      for (final MapEntry<String, String> font in fontAssets.entries) {
        await _loadFamily(font.key, font.value);
      }
    });

    for (final String family in fontAssets.keys) {
      test('$family: все символы интерфейса рисуются', () async {
        final List<int> notdef = await _raster('\uE000', family: family);
        expect(notdef, isNotEmpty);
        final List<String> tofu = <String>[];
        final List<String> blank = <String>[];
        for (final int rune in requiredGlyphs.runes) {
          final String char = String.fromCharCode(rune);
          final List<int> raster = await _raster(char, family: family);
          if (_sameRaster(raster, notdef)) tofu.add(char);
          if (raster.every((int byte) => byte == 0)) blank.add(char);
        }
        expect(
          tofu,
          isEmpty,
          reason: '$family: tofu для символов «${tofu.join()}»',
        );
        expect(
          blank,
          isEmpty,
          reason: '$family: пустой рендер для символов «${blank.join()}»',
        );
      });
    }

    test(
      'семьи отличаются друг от друга (шрифты действительно разные)',
      () async {
        final List<List<int>> rasters = <List<int>>[
          for (final String family in fontAssets.keys)
            await _raster('Щ', family: family),
        ];
        expect(_sameRaster(rasters[0], rasters[1]), isFalse);
        expect(_sameRaster(rasters[1], rasters[2]), isFalse);
        expect(_sameRaster(rasters[0], rasters[2]), isFalse);
      },
    );
  });
}
