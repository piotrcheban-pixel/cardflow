/// Инициализация PDFium (pdfrx) с явным каталогом кэша.
///
/// TASK 04 (импорт файлов на Android): `pdfrxInitialize()` без `tmpPath` на
/// не-Windows платформах вычисляет каталог кэша через
/// `Platform.environment['HOME']!` (`pdfrx_initialize_dart.dart`). В процессе
/// Android-приложения переменная `HOME` не задана, поэтому разыменование `null`
/// бросало исключение **до** открытия документа, а `PdfParser` переводил его в
/// `ParserErrorCode.unreadableFile` — пользователь видел «Не удалось прочитать
/// файл» на любом корректном PDF. На Windows/CI дефект не воспроизводился:
/// там ветка HOME не выполняется (каталог берётся из `LOCALAPPDATA`).
///
/// Каталог передаётся **явно** из main-изолята (`path_provider` →
/// `getTemporaryDirectory()`), потому что вызовы платформенных каналов из
/// фонового изолята невозможны (`MissingPluginException`). Значение — просто
/// строка, поэтому оно безопасно передаётся в `Isolate.run`.
library;

import 'dart:io';

import 'package:pdfrx/pdfrx.dart';

/// Каталог кэша PDFium по умолчанию, если приложение не передало свой.
///
/// `Directory.systemTemp` — единственный путь, который guaranteed существует и
/// не зависит от переменных окружения (`HOME`, `LOCALAPPDATA`). Раньше здесь
/// был неявный `HOME` из pdfrx, из-за чего Android не мог инициализировать
/// PDFium.
String defaultPdfiumCacheDirectory() =>
    '${Directory.systemTemp.path}${Platform.pathSeparator}cardflow-pdf';

/// Действующий каталог кэша PDFium для переданного значения.
///
/// Чистая функция (без ввода-вывода и без `Platform.environment`): пустая
/// строка и `null` дают [defaultPdfiumCacheDirectory]. Вынесена отдельно,
/// потому что именно ветка «нет явного каталога» и была дефектом Android.
String pdfiumCacheDirectoryFor(String? cacheDirectory) {
  final String? trimmed = cacheDirectory?.trim();
  if (trimmed != null && trimmed.isNotEmpty) return trimmed;
  return defaultPdfiumCacheDirectory();
}

/// Готовит каталог кэша PDFium и инициализирует библиотеку.
///
/// Идемпотентна: повторный вызов в том же изоляте ничего не делает.
/// Ошибки создания каталога не фатальны — pdfrx создаёт файлы сам, а
/// недоступный каталог не должен превращать читаемый PDF в ошибку.
Future<void> ensurePdfiumInitialized({String? cacheDirectory}) async {
  final String path = pdfiumCacheDirectoryFor(cacheDirectory);
  // `Pdfrx.cacheDirectoryPath` — статическое поле, а статика у каждого
  // изолята своя: в фоновом изоляте его обязательно нужно задать заново,
  // иначе pdfrx уйдёт в ветку HOME.
  Pdfrx.cacheDirectoryPath = path;
  try {
    await Directory(path).create(recursive: true);
  } on Object {
    // Каталог только для кэша: инициализацию не блокируем.
  }
  await pdfrxInitialize(tmpPath: path);
}
