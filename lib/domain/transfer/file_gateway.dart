import 'dart:typed_data';

/// Абстракция файловых операций для импорта/экспорта `.zip`.
///
/// UI вызывает её через `fileGatewayProvider`; в widget-тестах подменяется
/// фейком (плагин `file_picker` в тестах не поднимается). Реализация —
/// `FilePickerGateway` в `lib/data/transfer/`.
///
/// Контракт сохранения спроектирован под `file_picker` 13.3.3: на мобильных
/// платформах `saveFile` сам записывает байты и возвращает `content://`-URI
/// (dart:io с ним не работает), на desktop — путь к файлу. Поэтому «выбрать
/// путь» и «записать» объединены в один вызов [saveZipFile] (ADR-006).
abstract interface class FileGateway {
  /// Открывает системный пикер и возвращает путь к выбранному `.zip`
  /// (или `null`, если пользователь отменил выбор).
  ///
  /// [dialogTitle] — локализованный заголовок системного диалога (находка F12
  /// аудита: на Windows диалог показывал английский «Select File»).
  Future<String?> pickZipToImport({String? dialogTitle});

  /// Предлагает сохранить zip под именем [suggestedFileName] с содержимым
  /// [bytes]; возвращает `true`, если файл сохранён, `false` — при отмене.
  ///
  /// [dialogTitle] — локализованный заголовок системного диалога (ADR-047:
  /// диалог показывал английский «Save File»). Если запись в выбранную папку
  /// запрещена ОС — [ArchiveException] с кодом
  /// `ArchiveErrorCode.writeDenied` (не сырое `FileSystemException`).
  Future<bool> saveZipFile({
    required String suggestedFileName,
    required Uint8List bytes,
    String? dialogTitle,
  });

  /// Читает файл целиком (для пути, полученного из [pickZipToImport]).
  ///
  /// Обязан проверить размер файла ДО чтения в память: файл больше
  /// [DeckArchiveLimits.maxImportBytes] → [ArchiveException] с кодом
  /// `tooLarge` (защита от OOM на больших архивах).
  Future<Uint8List> readFile(String path);
}
