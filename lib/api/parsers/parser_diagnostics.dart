/// Debug-диагностика импорта документов (TASK 04, часть 8).
///
/// В TASK 04 нужно было понять, **что именно** пришло с устройства и какой
/// парсер это обрабатывал: имя файла, формат, MIME, выбранный парсер, число
/// страниц и найденных изображений. Без этих чисел «Не удалось прочитать
/// файл» на Android нельзя было отличить от «файл действительно битый».
///
/// Пишется только в debug/профиле (`kParserDiagnosticsEnabled`), только через
/// sink и без содержимого документа: имя файла и размеры — не секреты, текст
/// материалов не логируется. В release все методы — no-op.
library;

import 'dart:developer' as developer;

import 'package:cardflow/domain/text/document_format.dart';

/// Включена ли диагностика по умолчанию (выключена в release).
const bool kParserDiagnosticsEnabled = !bool.fromEnvironment('dart.vm.product');

/// Приёмник диагностических строк.
typedef ParserDiagnosticsSink = void Function(String message);

/// Диагностика импорта документов (debug-only).
class ParserDiagnostics {
  /// Создаёт диагностику.
  const ParserDiagnostics({
    this.enabled = kParserDiagnosticsEnabled,
    this.sink,
  });

  /// Включена ли запись (в release всегда `false`).
  final bool enabled;

  /// Приёмник сообщений; `null` — `dart:developer.log`.
  final ParserDiagnosticsSink? sink;

  /// Файл выбран в системном пикере.
  ///
  /// [source] — `file` (локальный путь), `content` (URI провайдера,
  /// материализован во временный файл), `memory` (только байты).
  void picked({
    required String fileName,
    required String source,
    int? sizeBytes,
    String? mimeType,
  }) {
    if (!enabled) return;
    _write(
      'Импорт: выбран "$fileName" (источник=$source, '
      'размер=${sizeBytes ?? '?'} Б, MIME=${mimeType ?? '?'})',
    );
  }

  /// Файл передан парсеру: формат, выбранный парсер и причина выбора.
  void dispatched({
    required String fileName,
    required DocumentFormat format,
    required String parser,
    required int bytes,
    String? cacheDirectory,
  }) {
    if (!enabled) return;
    _write(
      'Импорт: "$fileName" → формат=${format.extension}, парсер=$parser, '
      'байт=$bytes${cacheDirectory == null ? '' : ', pdf-кэш=$cacheDirectory'}',
    );
  }

  /// Файл разобран: страницы, разделы, изображения.
  void parsed({
    required String fileName,
    required DocumentFormat format,
    required int pages,
    required int sections,
    required int characters,
    required int images,
  }) {
    if (!enabled) return;
    _write(
      'Импорт: "$fileName" разобран (${format.extension}): '
      'страниц=$pages, разделов=$sections, символов=$characters, '
      'изображений=$images',
    );
  }

  /// Файл не разобран: код ошибки и техническая причина (если есть).
  void failed({
    required String fileName,
    required DocumentFormat? format,
    required String code,
    String? details,
  }) {
    if (!enabled) return;
    final String reason = details == null ? '' : ', причина=$details';
    _write(
      'Импорт: "$fileName" не разобран '
      '(формат=${format?.extension ?? '?'}, код=$code)$reason',
    );
  }

  /// Сообщение обрыва импорта до парсинга (нет доступа к URI, нет пути).
  void unavailable({required String fileName, required String reason}) {
    if (!enabled) return;
    _write('Импорт: "$fileName" недоступен: $reason');
  }

  void _write(String message) {
    final ParserDiagnosticsSink? target = sink;
    if (target != null) {
      target(message);
      return;
    }
    developer.log(message, name: 'cardflow.parsers');
  }
}
