/// Совместимый реэкспорт встроенного системного промпта (SPEC A8.1).
///
/// Начиная с итерации fix-gen текст и версия промпта хранятся в
/// `lib/api/prompts/system_prompt.dart` (`gen-ru-v5`); этот файл оставлен,
/// чтобы существующие импорты `api/generation/system_prompt.dart` работали.
library;

export 'package:cardflow/api/prompts/system_prompt.dart';
