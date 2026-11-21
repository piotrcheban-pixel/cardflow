// Диагностический отчёт по изображениям карточек (итерация 7.19, §0.2).
//
// Запуск (из корня проекта, при закрытом приложении):
//   fvm dart run tool/media_integrity_report.dart <путь к cardflow.sqlite> [media]
//
// Второй аргумент — каталог данных приложения с подкаталогом `media/`
// (по умолчанию — рядом с файлом БД). Печатает markdown-таблицу
// «этап / image id / source / размер / MIME / результат» и сводку.
//
// Бинарные данные изображений в вывод НЕ попадают: только SHA-256, размер,
// MIME, провайдер и id.
import 'dart:io';

import 'package:drift/native.dart';

import 'package:cardflow/data/cards/media_integrity_checker.dart';
import 'package:cardflow/data/db/app_database.dart';
import 'package:cardflow/data/transfer/media_store.dart';

Future<void> main(List<String> args) async {
  if (args.isEmpty) {
    stderr.writeln(
      'Использование: dart run tool/media_integrity_report.dart '
      '<cardflow.sqlite> [каталог данных с media/]',
    );
    exitCode = 64;
    return;
  }
  final File databaseFile = File(args[0]);
  if (!databaseFile.existsSync()) {
    stderr.writeln('Файл БД не найден: ${databaseFile.path}');
    exitCode = 66;
    return;
  }
  final Directory dataDirectory = args.length > 1
      ? Directory(args[1])
      : databaseFile.parent;
  final AppDatabase database = AppDatabase(NativeDatabase(databaseFile));
  try {
    final MediaIntegrityReport report = await MediaIntegrityChecker(
      database,
      MediaStore(dataDirectory),
    ).check();
    stdout.writeln(report.toMarkdownTable());
    stdout.writeln(
      'Всего связей: ${report.entries.length}; '
      'проблем: ${report.problems.length}; '
      'чисто: ${report.isClean}.',
    );
    if (report.problems.isNotEmpty) {
      stdout.writeln('\nПроблемы:');
      for (final MediaIntegrityEntry entry in report.problems) {
        stdout.writeln(
          '- ${entry.cardId.length > 8 ? entry.cardId.substring(0, 8) : entry.cardId}'
          ' / ${entry.mediaId.length > 8 ? entry.mediaId.substring(0, 8) : entry.mediaId}'
          ' / ${entry.side?.wireName ?? '-'} / ${entry.status.name}',
        );
      }
    }
  } finally {
    await database.close();
  }
}
